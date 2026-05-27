import { PageHeader } from "@/components/page-header";
import { listTickets } from "@/lib/data/tickets";
import { TicketsTable } from "./tickets-table";

export const dynamic = "force-dynamic";

export default async function TicketsPage() {
  const tickets = await listTickets();
  const open = tickets.filter((t) =>
    ["open", "in_progress", "waiting_on_user"].includes(t.status),
  ).length;
  return (
    <>
      <PageHeader
        title="Support tickets"
        description={`${open} open · ${tickets.length} total`}
      />
      <TicketsTable data={tickets} />
    </>
  );
}
