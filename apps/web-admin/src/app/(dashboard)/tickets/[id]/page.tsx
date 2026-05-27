import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent } from "@/components/ui/card";
import { Badge, statusTone } from "@/components/ui/badge";
import { fmtDateTime, humanize } from "@/lib/format";
import { getTicket, listTicketMessages } from "@/lib/data/tickets";
import { getCurrentUser } from "@/lib/auth";
import { TicketActions } from "./ticket-actions";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function TicketThreadPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const ticket = await getTicket(id);
  if (!ticket) notFound();
  const [messages, user] = await Promise.all([
    listTicketMessages(id),
    getCurrentUser(),
  ]);

  return (
    <>
      <Link
        href="/tickets"
        className="mb-4 inline-flex items-center gap-1 text-xs text-[var(--color-muted)] hover:text-[var(--color-fg)]"
      >
        <ArrowLeft size={14} /> Tickets
      </Link>

      <PageHeader
        title={ticket.subject}
        description={`${ticket.academyName ?? "Unknown academy"} · opened ${fmtDateTime(ticket.createdAt)}`}
        actions={
          <Badge tone={statusTone(ticket.status)}>
            {humanize(ticket.status)}
          </Badge>
        }
      />

      <Card>
        <CardContent className="space-y-4 py-5">
          <Message body={ticket.body} when={ticket.createdAt} staff={false} opener />
          {messages.map((m) => (
            <Message
              key={m.id}
              body={m.body}
              when={m.createdAt}
              staff={m.isStaff}
            />
          ))}
        </CardContent>
      </Card>

      {user && (
        <TicketActions
          ticketId={ticket.id}
          academyId={ticket.academyId}
          status={ticket.status}
          priority={ticket.priority}
          assignedTo={ticket.assignedTo}
          currentUserId={user.id}
        />
      )}
    </>
  );
}

function Message({
  body,
  when,
  staff,
  opener = false,
}: {
  body: string;
  when: string;
  staff: boolean;
  opener?: boolean;
}) {
  return (
    <div className={cn("flex", staff ? "justify-end" : "justify-start")}>
      <div
        className={cn(
          "max-w-[75%] rounded-[var(--radius)] border px-4 py-2.5 text-sm",
          staff
            ? "border-blue-500/30 bg-blue-500/10"
            : "border-[var(--color-border)] bg-[var(--color-surface-2)]",
        )}
      >
        <div className="mb-1 text-xs text-[var(--color-muted)]">
          {staff ? "PlayHub staff" : opener ? "Academy (opening message)" : "Academy"}
          {" · "}
          {fmtDateTime(when)}
        </div>
        <div className="whitespace-pre-wrap">{body}</div>
      </div>
    </div>
  );
}
