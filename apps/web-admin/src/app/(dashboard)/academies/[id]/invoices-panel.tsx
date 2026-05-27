"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, THead, TBody, TR, TH, TD } from "@/components/ui/table";
import { Badge, statusTone } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { Input, Label, Select } from "@/components/ui/input";
import { inrPrecise, fmtDate, humanize } from "@/lib/format";
import { recordSaasPayment } from "@/lib/actions/billing";
import type { SaasInvoiceRow } from "@/lib/data/billing";

export function InvoicesPanel({
  academyId,
  invoices,
}: {
  academyId: string;
  invoices: SaasInvoiceRow[];
}) {
  const [active, setActive] = useState<SaasInvoiceRow | null>(null);

  return (
    <Card className="mt-4">
      <CardHeader>
        <CardTitle>SaaS invoices</CardTitle>
      </CardHeader>
      <CardContent>
        {invoices.length === 0 ? (
          <p className="text-sm text-[var(--color-muted)]">No invoices yet.</p>
        ) : (
          <Table>
            <THead>
              <tr>
                <TH>Invoice</TH>
                <TH>Status</TH>
                <TH>Total</TH>
                <TH>Paid</TH>
                <TH>Outstanding</TH>
                <TH>Due</TH>
                <TH />
              </tr>
            </THead>
            <TBody>
              {invoices.map((inv) => (
                <TR key={inv.id}>
                  <TD className="font-medium">{inv.invoiceNumber}</TD>
                  <TD>
                    <Badge tone={statusTone(inv.status)}>
                      {humanize(inv.status)}
                    </Badge>
                  </TD>
                  <TD>{inrPrecise(inv.totalAmount)}</TD>
                  <TD>{inrPrecise(inv.amountPaid)}</TD>
                  <TD>{inrPrecise(inv.outstanding)}</TD>
                  <TD>{fmtDate(inv.dueDate)}</TD>
                  <TD>
                    {inv.outstanding > 0 && inv.status !== "cancelled" && (
                      <Button size="sm" variant="outline" onClick={() => setActive(inv)}>
                        Record payment
                      </Button>
                    )}
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        )}
      </CardContent>

      {active && (
        <PaymentModal
          academyId={academyId}
          invoice={active}
          onClose={() => setActive(null)}
        />
      )}
    </Card>
  );
}

function PaymentModal({
  academyId,
  invoice,
  onClose,
}: {
  academyId: string;
  invoice: SaasInvoiceRow;
  onClose: () => void;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [amount, setAmount] = useState(invoice.outstanding.toFixed(2));
  const [method, setMethod] = useState("manual");
  const [reference, setReference] = useState("");
  const [error, setError] = useState<string | null>(null);

  function submit() {
    setError(null);
    startTransition(async () => {
      const res = await recordSaasPayment({
        invoiceId: invoice.id,
        academyId,
        amount: Number(amount),
        method: method as "razorpay" | "bank_transfer" | "manual" | "free",
        reference,
      });
      if (!res.ok) setError(res.error);
      else {
        onClose();
        router.refresh();
      }
    });
  }

  return (
    <Modal open onClose={onClose} title={`Record payment · ${invoice.invoiceNumber}`}>
      <div className="flex flex-col gap-4">
        <div>
          <Label>Amount (₹)</Label>
          <Input
            type="number"
            step="0.01"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>
        <div>
          <Label>Method</Label>
          <Select value={method} onChange={(e) => setMethod(e.target.value)}>
            <option value="manual">Manual</option>
            <option value="bank_transfer">Bank transfer</option>
            <option value="razorpay">Razorpay</option>
            <option value="free">Free / waived</option>
          </Select>
        </div>
        <div>
          <Label>Reference (optional)</Label>
          <Input value={reference} onChange={(e) => setReference(e.target.value)} />
        </div>
        {error && <p className="text-xs text-[var(--color-danger)]">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={pending}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={pending}>
            {pending ? "Recording…" : "Record payment"}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
