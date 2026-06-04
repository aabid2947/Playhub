"use client";

import { Building2 } from "lucide-react";
import { DataTable, type ColumnDef } from "@/components/data-table";
import { Badge, statusTone } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { fmtDate, humanize } from "@/lib/format";
import type { AcademyRow } from "@/lib/data/academies";

const columns: ColumnDef<AcademyRow, unknown>[] = [
  {
    accessorKey: "name",
    header: "Academy",
    cell: ({ row }) => (
      <div className="font-medium text-[var(--color-fg)]">
        {row.original.name}
      </div>
    ),
  },
  {
    accessorKey: "subscriptionStatus",
    header: "Subscription",
    cell: ({ row }) => (
      <Badge tone={statusTone(row.original.subscriptionStatus)}>
        {humanize(row.original.subscriptionStatus)}
      </Badge>
    ),
  },
  {
    id: "active",
    accessorFn: (r) => (r.isActive ? "Active" : "Disabled"),
    header: "State",
    cell: ({ row }) => (
      <Badge tone={row.original.isActive ? "success" : "danger"}>
        {row.original.isActive ? "Active" : "Disabled"}
      </Badge>
    ),
  },
  {
    id: "location",
    accessorFn: (r) => [r.city, r.state].filter(Boolean).join(", "),
    header: "Location",
    cell: ({ row }) =>
      [row.original.city, row.original.state].filter(Boolean).join(", ") || "—",
  },
  {
    accessorKey: "email",
    header: "Contact",
    cell: ({ row }) => row.original.email ?? "—",
  },
  {
    accessorKey: "createdAt",
    header: "Joined",
    cell: ({ row }) => fmtDate(row.original.createdAt),
  },
];

export function AcademiesTable({ data }: { data: AcademyRow[] }) {
  if (data.length === 0) {
    return (
      <EmptyState
        icon={Building2}
        title="No academies yet"
        description="Academies that sign up on PlayHub will appear here."
      />
    );
  }
  return (
    <DataTable
      columns={columns}
      data={data}
      searchPlaceholder="Search academies…"
      rowHref={(r) => `/academies/${r.id}`}
      initialSorting={[{ id: "createdAt", desc: true }]}
      exportConfig={{
        filename: "academies.csv",
        columns: [
          { header: "Name", value: (r) => r.name },
          { header: "Subscription", value: (r) => r.subscriptionStatus },
          { header: "Active", value: (r) => (r.isActive ? "yes" : "no") },
          { header: "Email", value: (r) => r.email },
          { header: "Phone", value: (r) => r.phone },
          { header: "City", value: (r) => r.city },
          { header: "State", value: (r) => r.state },
          { header: "Joined", value: (r) => r.createdAt },
        ],
      }}
    />
  );
}
