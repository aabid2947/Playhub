import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";

export type TicketStatus = Database["public"]["Enums"]["support_ticket_status"];

export type TicketRow = {
  id: string;
  academyId: string;
  academyName: string | null;
  subject: string;
  category: string | null;
  priority: string;
  status: TicketStatus;
  createdAt: string;
};

export type TicketMessageRow = {
  id: string;
  body: string;
  isStaff: boolean;
  authorId: string | null;
  createdAt: string;
};

export async function listTickets(): Promise<TicketRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("support_tickets")
    .select("id, academy_id, subject, category, priority, status, created_at, academies(name)")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []).map((m) => ({
    id: m.id,
    academyId: m.academy_id,
    academyName: m.academies?.name ?? null,
    subject: m.subject,
    category: m.category,
    priority: m.priority,
    status: m.status,
    createdAt: m.created_at,
  }));
}

export type TicketDetail = TicketRow & { body: string; assignedTo: string | null };

export async function getTicket(id: string): Promise<TicketDetail | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("support_tickets")
    .select(
      "id, academy_id, subject, body, category, priority, status, assigned_to, created_at, academies(name)",
    )
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    id: data.id,
    academyId: data.academy_id,
    academyName: data.academies?.name ?? null,
    subject: data.subject,
    body: data.body,
    category: data.category,
    priority: data.priority,
    status: data.status,
    assignedTo: data.assigned_to,
    createdAt: data.created_at,
  };
}

export async function listTicketMessages(
  ticketId: string,
): Promise<TicketMessageRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("support_ticket_messages")
    .select("id, body, is_staff, author_id, created_at")
    .eq("ticket_id", ticketId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((m) => ({
    id: m.id,
    body: m.body,
    isStaff: m.is_staff,
    authorId: m.author_id,
    createdAt: m.created_at,
  }));
}
