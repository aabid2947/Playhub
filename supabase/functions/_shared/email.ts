// Gmail SMTP sender (best-effort).
//
// v1 strategy per PLAN.md: Gmail SMTP, 500/day cap accepted. If SMTP_USER /
// SMTP_PASS aren't configured, sendEmail() logs and returns a stub success
// so callers can still record delivery without a hard failure.
//
// We avoid pulling a heavyweight SMTP client into Sprint-4 by speaking SMTP
// via a tiny TLS socket helper; for production, swap to denomailer or skip
// to the email provider sprint.
//
// SMTP_USER  — gmail address
// SMTP_PASS  — gmail app password (NOT the account password)
// SMTP_FROM  — display name + email, e.g. "PlayHub <noreply@playhub.in>"
// SMTP_REPLY_TO — optional address for replies (defaults to the From address)
//
// DELIVERABILITY: the headers below (Date, Message-ID, a plaintext part
// alongside HTML, RFC-2047-encoded subjects) are the spam signals we can fix
// in code. The dominant one is NOT in code — SMTP_FROM's domain must be
// DKIM-signed by the sending Google Workspace account, or DMARC fails to align
// (SPF/DKIM authenticate the Gmail account's domain, the From: header claims
// yours) and receivers junk the mail on policy. Configure SPF
// (`include:_spf.google.com`) + Workspace DKIM for the SMTP_FROM domain.

export interface EmailMessage {
  to: string;
  subject: string;
  body_text: string;
  body_html?: string;
  /// When set, adds List-Unsubscribe headers. Set it for bulk/announcement
  /// mail — receivers penalise bulk sends that offer no unsubscribe path.
  unsubscribe_url?: string;
}

/// Strips CR/LF so a caller-supplied value can't inject extra headers (e.g. a
/// `Bcc:`) by embedding a newline. Announcement subjects are user-composed, so
/// every value interpolated into the header block goes through this.
export function headerSafe(value: string): string {
  return value.replace(/[\r\n]+/g, ' ').trim();
}

export function base64(input: string): string {
  const bytes = new TextEncoder().encode(input);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

/// RFC 2047 encoded-word. Raw non-ASCII in a header is invalid and trips spam
/// filters — relevant here because subjects carry Hindi/Marathi names.
export function encodeHeader(value: string): string {
  const safe = headerSafe(value);
  // deno-lint-ignore no-control-regex
  return /^[\x20-\x7E]*$/.test(safe) ? safe : `=?UTF-8?B?${base64(safe)}?=`;
}

/// RFC 5322 date. `toUTCString()` ends in "GMT" (an obsolete zone per the
/// spec); "+0000" is the modern form.
export function rfc5322Date(at: Date = new Date()): string {
  return at.toUTCString().replace(/GMT$/, '+0000');
}

/// Bare address out of "Name <addr>" (or the value itself if unadorned).
export function bareAddress(from: string): string {
  return from.match(/<([^>]+)>/)?.[1]?.trim() ?? from.trim();
}

/// Base64 body, wrapped at 76 chars. Encoding sidesteps two SMTP hazards at
/// once: the 998-octet line limit (long HTML lines otherwise violate it), and
/// dot-stuffing — a body line of "." would end the DATA stage early, but the
/// base64 alphabet contains no ".", so no line can start one.
export function encodeBody(body: string): string {
  return base64(body).replace(/(.{76})/g, '$1\r\n');
}

export async function sendEmail(msg: EmailMessage): Promise<boolean> {
  const user = Deno.env.get('SMTP_USER');
  const pass = Deno.env.get('SMTP_PASS');
  if (!user || !pass) {
    // Stub mode — log + succeed so the caller can mark "delivered" without
    // breaking the announcement fan-out. Real SMTP comes online once a
    // domain + Google Workspace app password is configured.
    console.log(`[email-stub] to=${msg.to} subject=${msg.subject}`);
    return true;
  }

  const from = headerSafe(Deno.env.get('SMTP_FROM') ?? `PlayHub <${user}>`);
  const fromAddress = bareAddress(from);
  const replyTo = headerSafe(Deno.env.get('SMTP_REPLY_TO') ?? fromAddress);
  // Message-ID's domain should match the From domain; fall back to the
  // authenticated account's if SMTP_FROM is malformed.
  const domain = (fromAddress.split('@')[1] ?? user.split('@')[1] ?? 'playhub')
    .replace(/[^A-Za-z0-9.\-]/g, '');
  const recipient = headerSafe(msg.to);

  const conn = await Deno.connectTls({ hostname: 'smtp.gmail.com', port: 465 });
  const enc = new TextEncoder();
  const dec = new TextDecoder();

  async function read(): Promise<string> {
    const buf = new Uint8Array(4096);
    const n = await conn.read(buf);
    return n ? dec.decode(buf.subarray(0, n)) : '';
  }
  async function send(line: string): Promise<void> {
    await conn.write(enc.encode(line + '\r\n'));
  }
  async function expect(prefix: string): Promise<void> {
    const r = await read();
    if (!r.startsWith(prefix)) throw new Error(`SMTP unexpected: ${r}`);
  }

  try {
    await expect('220');
    await send(`EHLO ${domain}`);             await expect('250');
    await send(`AUTH LOGIN`);                 await expect('334');
    await send(base64(user));                 await expect('334');
    await send(base64(pass));                 await expect('235');
    // Envelope sender stays the authenticated account — Gmail rejects a
    // MAIL FROM it hasn't verified as an alias.
    await send(`MAIL FROM:<${user}>`);        await expect('250');
    await send(`RCPT TO:<${recipient}>`);     await expect('250');
    await send(`DATA`);                       await expect('354');

    const headers = [
      `From: ${from}`,
      `To: ${recipient}`,
      `Reply-To: ${replyTo}`,
      `Subject: ${encodeHeader(msg.subject)}`,
      `Date: ${rfc5322Date()}`,
      `Message-ID: <${crypto.randomUUID()}@${domain}>`,
      `MIME-Version: 1.0`,
    ];
    if (msg.unsubscribe_url) {
      const url = headerSafe(msg.unsubscribe_url);
      headers.push(`List-Unsubscribe: <${url}>`);
      headers.push(`List-Unsubscribe-Post: List-Unsubscribe=One-Click`);
    }

    const lines: string[] = [];
    if (msg.body_html) {
      // multipart/alternative: HTML-only mail with no plaintext part is a
      // spam signal (and unreadable in text-only clients).
      const boundary = `ph-${crypto.randomUUID()}`;
      headers.push(`Content-Type: multipart/alternative; boundary="${boundary}"`);
      lines.push(
        ...headers,
        ``,
        `--${boundary}`,
        `Content-Type: text/plain; charset=utf-8`,
        `Content-Transfer-Encoding: base64`,
        ``,
        encodeBody(msg.body_text),
        `--${boundary}`,
        `Content-Type: text/html; charset=utf-8`,
        `Content-Transfer-Encoding: base64`,
        ``,
        encodeBody(msg.body_html),
        `--${boundary}--`,
      );
    } else {
      headers.push(`Content-Type: text/plain; charset=utf-8`);
      headers.push(`Content-Transfer-Encoding: base64`);
      lines.push(...headers, ``, encodeBody(msg.body_text));
    }
    lines.push(`.`);

    await send(lines.join('\r\n'));
    await expect('250');
    await send(`QUIT`);
  } catch (err) {
    console.error('[email] send failed', err);
    return false;
  } finally {
    try { conn.close(); } catch { /* already closed */ }
  }
  return true;
}
