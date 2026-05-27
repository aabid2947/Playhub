import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";
import { invoiceOutstanding } from "@/lib/aggregate";

export type SaasInvoiceStatus =
  Database["public"]["Enums"]["saas_invoice_status"];

export type SaasInvoiceRow = {
  id: string;
  invoiceNumber: string;
  status: SaasInvoiceStatus;
  amount: number;
  taxAmount: number;
  totalAmount: number;
  amountPaid: number;
  outstanding: number;
  dueDate: string;
  issuedAt: string;
};

export async function listAcademyInvoices(
  academyId: string,
): Promise<SaasInvoiceRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("saas_invoices")
    .select(
      "id, invoice_number, status, amount, tax_amount, total_amount, amount_paid, due_date, issued_at",
    )
    .eq("academy_id", academyId)
    .order("issued_at", { ascending: false });
  if (error) throw error;

  return (data ?? []).map((m) => ({
    id: m.id,
    invoiceNumber: m.invoice_number,
    status: m.status,
    amount: m.amount,
    taxAmount: m.tax_amount,
    totalAmount: m.total_amount ?? m.amount + m.tax_amount,
    amountPaid: m.amount_paid,
    outstanding: invoiceOutstanding(m),
    dueDate: m.due_date,
    issuedAt: m.issued_at,
  }));
}
