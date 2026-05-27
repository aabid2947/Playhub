"use client";

import { useState, useTransition } from "react";
import { RefreshCw, Search } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";
import { Table, THead, TBody, TR, TH, TD } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { fmtDateTime, humanize } from "@/lib/format";
import type { FoundUser } from "@/app/api/ops/find-user/route";

export function OpsConsole() {
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <RefreshAnalyticsCard />
      <FindUserCard />
    </div>
  );
}

function RefreshAnalyticsCard() {
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  function run() {
    setMsg(null);
    start(async () => {
      const res = await fetch("/api/ops/refresh-analytics", { method: "POST" });
      const json = await res.json();
      setMsg(
        json.ok
          ? { ok: true, text: "Analytics materialized views refreshed." }
          : { ok: false, text: json.error ?? "Failed." },
      );
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Refresh analytics</CardTitle>
        <CardDescription>
          Runs refresh_analytics() via the service role (revoked for normal
          sessions). Rebuilds the five reporting materialized views.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <Button onClick={run} disabled={pending}>
          <RefreshCw size={16} className={pending ? "animate-spin" : undefined} />
          {pending ? "Refreshing…" : "Refresh now"}
        </Button>
        {msg && (
          <p
            className={
              msg.ok
                ? "text-xs text-[var(--color-success)]"
                : "text-xs text-[var(--color-danger)]"
            }
          >
            {msg.text}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

function FindUserCard() {
  const [email, setEmail] = useState("");
  const [pending, start] = useTransition();
  const [users, setUsers] = useState<FoundUser[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  function run() {
    setError(null);
    setUsers(null);
    start(async () => {
      const res = await fetch("/api/ops/find-user", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const json = await res.json();
      if (!json.ok) setError(json.error ?? "Lookup failed.");
      else setUsers(json.users as FoundUser[]);
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Find user (cross-tenant)</CardTitle>
        <CardDescription>
          Looks up any user by email across all academies, including auth
          metadata (last sign-in) via the service role.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex items-end gap-2">
          <div className="flex-1">
            <Label>Email</Label>
            <Input
              value={email}
              placeholder="owner@example.com"
              onChange={(e) => setEmail(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && run()}
            />
          </div>
          <Button onClick={run} disabled={pending || !email.trim()}>
            <Search size={16} /> {pending ? "…" : "Search"}
          </Button>
        </div>
        {error && <p className="text-xs text-[var(--color-danger)]">{error}</p>}
        {users && users.length === 0 && (
          <p className="text-xs text-[var(--color-muted)]">No matches.</p>
        )}
        {users && users.length > 0 && (
          <Table>
            <THead>
              <tr>
                <TH>Email</TH>
                <TH>Role</TH>
                <TH>Academy</TH>
                <TH>Last sign-in</TH>
              </tr>
            </THead>
            <TBody>
              {users.map((u) => (
                <TR key={u.id}>
                  <TD>{u.email ?? "—"}</TD>
                  <TD>
                    <Badge>{humanize(u.role)}</Badge>
                  </TD>
                  <TD>{u.academyName ?? "—"}</TD>
                  <TD>{u.lastSignInAt ? fmtDateTime(u.lastSignInAt) : "—"}</TD>
                </TR>
              ))}
            </TBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
