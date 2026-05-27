"use client";

import { useMemo, useState } from "react";
import { Download } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Label, Select } from "@/components/ui/input";
import { Table, THead, TBody, TR, TH, TD } from "@/components/ui/table";
import { toCsv, type CsvColumn } from "@/lib/csv";
import { downloadText } from "@/lib/download";
import { fmtDate } from "@/lib/format";
import type { AcademyRow } from "@/lib/data/academies";
import type { TicketRow } from "@/lib/data/tickets";
import type { PlanRow } from "@/lib/data/plans";

type Field<T> = { key: string; header: string; value: (r: T) => string | number | null };

type Entity<T> = { label: string; rows: T[]; fields: Field<T>[] };

export function ReportBuilder({
  academies,
  tickets,
  plans,
}: {
  academies: AcademyRow[];
  tickets: TicketRow[];
  plans: PlanRow[];
}) {
  const entities = useMemo(
    () => ({
      academies: {
        label: "Academies",
        rows: academies,
        fields: [
          { key: "name", header: "Name", value: (r) => r.name },
          { key: "status", header: "Subscription", value: (r) => r.subscriptionStatus },
          { key: "active", header: "Active", value: (r) => (r.isActive ? "yes" : "no") },
          { key: "email", header: "Email", value: (r) => r.email },
          { key: "city", header: "City", value: (r) => r.city },
          { key: "joined", header: "Joined", value: (r) => fmtDate(r.createdAt) },
        ] as Field<AcademyRow>[],
      } as Entity<AcademyRow>,
      tickets: {
        label: "Tickets",
        rows: tickets,
        fields: [
          { key: "subject", header: "Subject", value: (r) => r.subject },
          { key: "academy", header: "Academy", value: (r) => r.academyName },
          { key: "priority", header: "Priority", value: (r) => r.priority },
          { key: "status", header: "Status", value: (r) => r.status },
          { key: "opened", header: "Opened", value: (r) => fmtDate(r.createdAt) },
        ] as Field<TicketRow>[],
      } as Entity<TicketRow>,
      plans: {
        label: "Plans",
        rows: plans,
        fields: [
          { key: "name", header: "Name", value: (r) => r.name },
          { key: "code", header: "Code", value: (r) => r.code },
          { key: "monthly", header: "Monthly (₹)", value: (r) => r.monthlyPrice },
          { key: "active", header: "Active", value: (r) => (r.isActive ? "yes" : "no") },
        ] as Field<PlanRow>[],
      } as Entity<PlanRow>,
    }),
    [academies, tickets, plans],
  );

  type Key = keyof typeof entities;
  const [entityKey, setEntityKey] = useState<Key>("academies");
  const entity = entities[entityKey] as Entity<unknown>;

  const [selected, setSelected] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(entity.fields.map((f) => [f.key, true])),
  );

  function pickEntity(k: Key) {
    setEntityKey(k);
    const e = entities[k] as Entity<unknown>;
    setSelected(Object.fromEntries(e.fields.map((f) => [f.key, true])));
  }

  const activeFields = entity.fields.filter((f) => selected[f.key]);

  function exportCsv() {
    const cols: CsvColumn<unknown>[] = activeFields.map((f) => ({
      header: f.header,
      value: f.value,
    }));
    downloadText(`${entityKey}-report.csv`, toCsv(entity.rows, cols));
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardContent className="flex flex-wrap items-end gap-4 py-4">
          <div className="w-48">
            <Label>Entity</Label>
            <Select
              value={entityKey}
              onChange={(e) => pickEntity(e.target.value as Key)}
            >
              {(Object.keys(entities) as Key[]).map((k) => (
                <option key={k} value={k}>
                  {entities[k].label}
                </option>
              ))}
            </Select>
          </div>
          <div className="flex flex-1 flex-wrap items-center gap-3">
            {entity.fields.map((f) => (
              <label key={f.key} className="flex items-center gap-1.5 text-xs">
                <input
                  type="checkbox"
                  checked={selected[f.key] ?? false}
                  onChange={(e) =>
                    setSelected((s) => ({ ...s, [f.key]: e.target.checked }))
                  }
                />
                {f.header}
              </label>
            ))}
          </div>
          <Button variant="outline" size="sm" onClick={exportCsv}>
            <Download size={14} /> Export CSV
          </Button>
        </CardContent>
      </Card>

      <div className="rounded-[var(--radius)] border border-[var(--color-border)] bg-[var(--color-surface)]">
        <Table>
          <THead>
            <tr>
              {activeFields.map((f) => (
                <TH key={f.key}>{f.header}</TH>
              ))}
            </tr>
          </THead>
          <TBody>
            {entity.rows.length === 0 ? (
              <TR>
                <TD colSpan={activeFields.length || 1} className="py-8 text-center text-[var(--color-muted)]">
                  No rows.
                </TD>
              </TR>
            ) : (
              entity.rows.map((row, i) => (
                <TR key={i}>
                  {activeFields.map((f) => (
                    <TD key={f.key}>{f.value(row) ?? "—"}</TD>
                  ))}
                </TR>
              ))
            )}
          </TBody>
        </Table>
      </div>
      <p className="text-xs text-[var(--color-muted)]">
        {entity.rows.length} rows · {activeFields.length} columns
      </p>
    </div>
  );
}
