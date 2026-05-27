"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input, Label, Select, Textarea } from "@/components/ui/input";
import { updateTicket, postStaffReply } from "@/lib/actions/tickets";
import type { TicketStatus } from "@/lib/data/tickets";

const STATUSES: TicketStatus[] = [
  "open",
  "in_progress",
  "waiting_on_user",
  "resolved",
  "closed",
];
const PRIORITIES = ["low", "normal", "high", "urgent"];

export function TicketActions({
  ticketId,
  academyId,
  status,
  priority,
  assignedTo,
  currentUserId,
}: {
  ticketId: string;
  academyId: string;
  status: TicketStatus;
  priority: string;
  assignedTo: string | null;
  currentUserId: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [reply, setReply] = useState("");
  const [error, setError] = useState<string | null>(null);

  const assignedToMe = assignedTo === currentUserId;

  function run(fn: () => Promise<{ ok: boolean; error?: string }>) {
    setError(null);
    startTransition(async () => {
      const res = await fn();
      if (!res.ok) setError(res.error ?? "Something went wrong.");
      else router.refresh();
    });
  }

  return (
    <Card className="mt-4">
      <CardHeader>
        <CardTitle>Manage ticket</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
          <div>
            <Label>Status</Label>
            <Select
              value={status}
              disabled={pending}
              onChange={(e) =>
                run(() =>
                  updateTicket(ticketId, {
                    status: e.target.value as TicketStatus,
                  }),
                )
              }
            >
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label>Priority</Label>
            <Select
              value={priority}
              disabled={pending}
              onChange={(e) =>
                run(() => updateTicket(ticketId, { priority: e.target.value }))
              }
            >
              {PRIORITIES.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </Select>
          </div>
          <div className="flex items-end">
            <Button
              variant="outline"
              disabled={pending}
              onClick={() =>
                run(() =>
                  updateTicket(ticketId, {
                    assignedTo: assignedToMe ? null : currentUserId,
                  }),
                )
              }
            >
              {assignedToMe ? "Unassign me" : "Assign to me"}
            </Button>
          </div>
        </div>

        <div>
          <Label>Reply as PlayHub staff</Label>
          <Textarea
            value={reply}
            placeholder="Write a reply…"
            onChange={(e) => setReply(e.target.value)}
          />
          <div className="mt-2 flex justify-end">
            <Button
              disabled={pending || !reply.trim()}
              onClick={() =>
                run(async () => {
                  const res = await postStaffReply(ticketId, academyId, reply);
                  if (res.ok) setReply("");
                  return res;
                })
              }
            >
              {pending ? "Sending…" : "Send reply"}
            </Button>
          </div>
        </div>

        {error && <p className="text-xs text-[var(--color-danger)]">{error}</p>}
      </CardContent>
    </Card>
  );
}
