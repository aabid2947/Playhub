"use client";

import { Inbox } from "lucide-react";
import { DataTable, type ColumnDef } from "@/components/data-table";
import { Badge, statusTone } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { fmtDate, humanize } from "@/lib/format";
import type { TicketRow } from "@/lib/data/tickets";

const PRIORITY_TONE: Record<string, "danger" | "warning" | "neutral"> = {
  urgent: "danger",
  high: "warning",
  normal: "neutral",
  low: "neutral",
};

const columns: ColumnDef<TicketRow, unknown>[] = [
  {
    accessorKey: "subject",
    header: "Subject",
    cell: ({ row }) => (
      <div className="font-medium text-[var(--color-fg)]">
        {row.original.subject}
      </div>
    ),
  },
  {
    accessorKey: "academyName",
    header: "Academy",
    cell: ({ row }) => row.original.academyName ?? "—",
  },
  {
    accessorKey: "priority",
    header: "Priority",
    cell: ({ row }) => (
      <Badge tone={PRIORITY_TONE[row.original.priority] ?? "neutral"}>
        {humanize(row.original.priority)}
      </Badge>
    ),
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => (
      <Badge tone={statusTone(row.original.status)}>
        {humanize(row.original.status)}
      </Badge>
    ),
  },
  {
    accessorKey: "createdAt",
    header: "Opened",
    cell: ({ row }) => fmtDate(row.original.createdAt),
  },
];

export function TicketsTable({ data }: { data: TicketRow[] }) {
  if (data.length === 0) {
    return (
      <EmptyState
        icon={Inbox}
        title="No tickets yet"
        description="When customers file support tickets they'll appear here."
      />
    );
  }
  return (
    <DataTable
      columns={columns}
      data={data}
      searchPlaceholder="Search tickets…"
      rowHref={(r) => `/tickets/${r.id}`}
      initialSorting={[{ id: "createdAt", desc: true }]}
      exportConfig={{
        filename: "tickets.csv",
        columns: [
          { header: "Subject", value: (r) => r.subject },
          { header: "Academy", value: (r) => r.academyName },
          { header: "Priority", value: (r) => r.priority },
          { header: "Status", value: (r) => r.status },
          { header: "Opened", value: (r) => r.createdAt },
        ],
      }}
    />
  );
}
