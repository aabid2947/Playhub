// Razorpay webhook receiver. Verifies HMAC-SHA256 signature, ignores
// duplicate events via the unique_event_id constraint on payments, and
// records payment.captured / payment.failed events.
//
// Configure on Razorpay Dashboard → Webhooks:
//   Platform account:
//     URL:    https://<project-ref>.supabase.co/functions/v1/razorpay-webhook
//   Per-academy merchant account (bring-your-own-gateway):
//     URL:    https://<project-ref>.supabase.co/functions/v1/razorpay-webhook?academy=<academy_id>
//   Events: payment.captured, payment.failed
//   Secret: the webhook secret the owner saved for that academy (platform URL
//           uses RAZORPAY_WEBHOOK_SECRET). The `academy` param is only a routing
//           hint — a forged one simply fails signature verification.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders, preflight } from '../_shared/cors.ts';
import { verifyWebhookSignature } from '../_shared/razorpay.ts';
import { resolveRazorpayWebhookSecret } from '../_shared/payment_gateway.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return j({ error: 'missing env' }, 500);

  const admin = createClient(url, serviceKey);

  // Per-academy webhooks include ?academy=<id>; the platform webhook omits it.
  // We pick the matching webhook secret BEFORE trusting the body — a wrong
  // academy id just yields a non-matching secret and fails verification.
  const academyParam = new URL(req.url).searchParams.get('academy');

  const rawBody = await req.text();
  const sig = req.headers.get('x-razorpay-signature') ?? '';
  let valid = false;
  try {
    const webhookSecret = await resolveRazorpayWebhookSecret(admin, academyParam);
    valid = await verifyWebhookSignature(rawBody, sig, webhookSecret);
  } catch (e) {
    return j({ error: (e as Error).message }, 500);
  }
  if (!valid) return j({ error: 'invalid signature' }, 401);

  let event: WebhookEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return j({ error: 'invalid json' }, 400);
  }

  const eventId = event.id;
  const payload = event.payload?.payment?.entity;
  if (!eventId || !payload) {
    return j({ ok: true, ignored: 'no payment payload' });
  }

  // Locate the matching invoice via order notes (we set them on creation).
  const invoiceId = payload.notes?.invoice_id;
  const academyId = payload.notes?.academy_id;
  const studentId = payload.notes?.student_id;
  const invoiceType = payload.notes?.invoice_type ?? 'student';

  // SaaS subscription payments (PlayHub billing the academy) record into
  // saas_payments — no student. The apply_saas_payment + reactivate triggers
  // then mark the invoice paid and activate the academy.
  if (invoiceType === 'saas') {
    if (!invoiceId || !academyId) {
      return j({ ok: true, ignored: 'missing saas notes' });
    }
    if (event.event !== 'payment.captured') {
      return j({ ok: true, ignored: event.event });
    }
    const { error } = await admin.from('saas_payments').insert({
      academy_id: academyId,
      saas_invoice_id: invoiceId,
      amount: (payload.amount ?? 0) / 100,
      method: 'razorpay',
      razorpay_order_id: payload.order_id,
      razorpay_payment_id: payload.id,
      unique_event_id: eventId,
    });
    // 23505 = unique_violation → duplicate webhook delivery, already recorded.
    if (error && error.code !== '23505') {
      return j({ error: error.message }, 500);
    }
    return j({ ok: true, event: 'payment.captured', saas_invoice_id: invoiceId });
  }

  if (!invoiceId || !academyId || !studentId) {
    return j({ ok: true, ignored: 'missing notes — likely external order' });
  }

  switch (event.event) {
    case 'payment.captured': {
      // Insert payment row — unique_event_id stops dup processing.
      const { error } = await admin.from('payments').insert({
        academy_id: academyId,
        invoice_id: invoiceId,
        student_id: studentId,
        amount: (payload.amount ?? 0) / 100,
        method: 'razorpay',
        status: 'completed',
        razorpay_order_id: payload.order_id,
        razorpay_payment_id: payload.id,
        unique_event_id: eventId,
      });
      // 23505 = unique_violation → duplicate webhook delivery, ignore.
      if (error && error.code !== '23505') {
        return j({ error: error.message }, 500);
      }
      // Mark the matching attempt as paid.
      if (payload.order_id) {
        await admin.from('payment_attempts')
          .update({ status: 'paid' })
          .eq('razorpay_order_id', payload.order_id);
      }
      return j({ ok: true, event: 'payment.captured', invoice_id: invoiceId });
    }
    case 'payment.failed': {
      if (payload.order_id) {
        await admin.from('payment_attempts')
          .update({
            status: 'failed',
            failure_reason: payload.error_description ?? null,
          })
          .eq('razorpay_order_id', payload.order_id);
      }
      return j({ ok: true, event: 'payment.failed', invoice_id: invoiceId });
    }
    default:
      return j({ ok: true, ignored: event.event });
  }
});

interface WebhookEvent {
  id: string;
  event: string;
  payload?: {
    payment?: {
      entity?: {
        id: string;
        order_id?: string;
        amount?: number;
        currency?: string;
        status?: string;
        error_description?: string;
        notes?: Record<string, string>;
      };
    };
  };
}

function j(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
