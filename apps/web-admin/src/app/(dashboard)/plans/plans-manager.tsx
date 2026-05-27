"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { Input, Label, Textarea } from "@/components/ui/input";
import { inr } from "@/lib/format";
import { savePlan, deletePlan, type PlanInput } from "@/lib/actions/plans";
import type { PlanRow } from "@/lib/data/plans";

export function PlansManager({ plans }: { plans: PlanRow[] }) {
  const router = useRouter();
  const [editing, setEditing] = useState<PlanRow | null>(null);
  const [creating, setCreating] = useState(false);
  const [pending, startTransition] = useTransition();

  function remove(p: PlanRow) {
    if (!confirm(`Delete plan "${p.name}"? This cannot be undone.`)) return;
    startTransition(async () => {
      const res = await deletePlan(p.id);
      if (!res.ok) alert(res.error);
      else router.refresh();
    });
  }

  return (
    <>
      <div className="mb-4 flex justify-end">
        <Button onClick={() => setCreating(true)}>
          <Plus size={16} /> New plan
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        {plans.map((p) => (
          <Card key={p.id}>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle className="text-base">{p.name}</CardTitle>
                <Badge tone={p.isActive ? "success" : "neutral"}>
                  {p.isActive ? "Active" : "Hidden"}
                </Badge>
              </div>
              <p className="font-mono text-xs text-[var(--color-muted)]">{p.code}</p>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="flex items-baseline gap-1">
                <span className="text-2xl font-semibold">{inr(p.monthlyPrice)}</span>
                <span className="text-xs text-[var(--color-muted)]">/mo</span>
              </div>
              <div className="space-y-1 text-xs text-[var(--color-muted)]">
                <Row label="Students" value={p.maxStudents} />
                <Row label="Coaches" value={p.maxCoaches} />
                <Row label="Centers" value={p.maxCenters} />
              </div>
              <div className="flex gap-2 pt-1">
                <Button size="sm" variant="outline" onClick={() => setEditing(p)}>
                  <Pencil size={14} /> Edit
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => remove(p)}
                  disabled={pending}
                >
                  <Trash2 size={14} /> Delete
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
        {plans.length === 0 && (
          <p className="text-sm text-[var(--color-muted)]">No plans defined.</p>
        )}
      </div>

      {(creating || editing) && (
        <PlanForm
          plan={editing}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
        />
      )}
    </>
  );
}

function Row({ label, value }: { label: string; value: number | null }) {
  return (
    <div className="flex justify-between">
      <span>{label}</span>
      <span className="text-[var(--color-fg)]">{value ?? "Unlimited"}</span>
    </div>
  );
}

function PlanForm({ plan, onClose }: { plan: PlanRow | null; onClose: () => void }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<PlanInput>({
    id: plan?.id,
    code: plan?.code ?? "",
    name: plan?.name ?? "",
    description: plan?.description ?? "",
    monthlyPrice: plan?.monthlyPrice ?? 0,
    yearlyPrice: plan?.yearlyPrice ?? null,
    maxStudents: plan?.maxStudents ?? null,
    maxCoaches: plan?.maxCoaches ?? null,
    maxCenters: plan?.maxCenters ?? null,
    isActive: plan?.isActive ?? true,
  });

  function set<K extends keyof PlanInput>(key: K, value: PlanInput[K]) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  function num(v: string): number | null {
    return v.trim() === "" ? null : Number(v);
  }

  function submit() {
    setError(null);
    startTransition(async () => {
      const res = await savePlan(form);
      if (!res.ok) setError(res.error);
      else {
        onClose();
        router.refresh();
      }
    });
  }

  return (
    <Modal open onClose={onClose} title={plan ? "Edit plan" : "New plan"}>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>Code</Label>
          <Input
            value={form.code}
            disabled={!!plan}
            onChange={(e) => set("code", e.target.value)}
          />
        </div>
        <div>
          <Label>Name</Label>
          <Input value={form.name} onChange={(e) => set("name", e.target.value)} />
        </div>
        <div className="col-span-2">
          <Label>Description</Label>
          <Textarea
            value={form.description ?? ""}
            onChange={(e) => set("description", e.target.value)}
          />
        </div>
        <div>
          <Label>Monthly price (₹)</Label>
          <Input
            type="number"
            value={form.monthlyPrice}
            onChange={(e) => set("monthlyPrice", Number(e.target.value))}
          />
        </div>
        <div>
          <Label>Yearly price (₹)</Label>
          <Input
            type="number"
            value={form.yearlyPrice ?? ""}
            onChange={(e) => set("yearlyPrice", num(e.target.value))}
          />
        </div>
        <div>
          <Label>Max students</Label>
          <Input
            type="number"
            value={form.maxStudents ?? ""}
            onChange={(e) => set("maxStudents", num(e.target.value))}
          />
        </div>
        <div>
          <Label>Max coaches</Label>
          <Input
            type="number"
            value={form.maxCoaches ?? ""}
            onChange={(e) => set("maxCoaches", num(e.target.value))}
          />
        </div>
        <div>
          <Label>Max centers</Label>
          <Input
            type="number"
            value={form.maxCenters ?? ""}
            onChange={(e) => set("maxCenters", num(e.target.value))}
          />
        </div>
        <label className="col-span-2 flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.isActive}
            onChange={(e) => set("isActive", e.target.checked)}
          />
          Active (visible to academies)
        </label>
      </div>

      {error && <p className="mt-3 text-xs text-[var(--color-danger)]">{error}</p>}

      <div className="mt-5 flex justify-end gap-2">
        <Button variant="ghost" onClick={onClose} disabled={pending}>
          Cancel
        </Button>
        <Button onClick={submit} disabled={pending}>
          {pending ? "Saving…" : "Save plan"}
        </Button>
      </div>
    </Modal>
  );
}
