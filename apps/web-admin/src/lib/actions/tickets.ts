"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/lib/actions/academies";
import type { Database } from "@/lib/database.types";

type TicketStatus = Database["public"]["Enums"]["support_ticket_status"];
type TicketUpdate = Database["public"]["Tables"]["support_tickets"]["Update"];

export async function updateTicket(
  ticketId: string,
  patch: { status?: TicketStatus; priority?: string; assignedTo?: string | null },
): Promise<ActionResult> {
  const supabase = await createClient();

  const update: TicketUpdate = {};
  if (patch.status !== undefined) {
    update.status = patch.status;
    if (patch.status === "resolved")
      update.resolved_at = new Date().toISOString();
    if (patch.status === "closed") update.closed_at = new Date().toISOString();
  }
  if (patch.priority !== undefined) update.priority = patch.priority;
  if (patch.assignedTo !== undefined) update.assigned_to = patch.assignedTo;

  const { error } = await supabase
    .from("support_tickets")
    .update(update)
    .eq("id", ticketId);
  if (error) return { ok: false, error: error.message };

  revalidatePath(`/tickets/${ticketId}`);
  revalidatePath("/tickets");
  return { ok: true };
}

export async function postStaffReply(
  ticketId: string,
  academyId: string,
  body: string,
): Promise<ActionResult> {
  if (!body.trim()) return { ok: false, error: "Reply cannot be empty." };

  const supabase = await createClient();
  const { error } = await supabase.from("support_ticket_messages").insert({
    ticket_id: ticketId,
    academy_id: academyId,
    is_staff: true,
    body: body.trim(),
  });
  if (error) return { ok: false, error: error.message };

  revalidatePath(`/tickets/${ticketId}`);
  return { ok: true };
}
