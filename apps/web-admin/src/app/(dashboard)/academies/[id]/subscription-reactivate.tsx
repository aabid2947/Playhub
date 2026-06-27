"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { reactivateSubscription } from "@/lib/actions/billing";

/**
 * Manual recovery lever for a suspended academy — sets the subscription back to
 * 'active' + is_active=true. Used for trial-expired academies (no invoice to pay
 * against) or to override; a paid invoice auto-reactivates via DB trigger.
 */
export function ReactivateSubscription({ id }: { id: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function run() {
    setError(null);
    startTransition(async () => {
      const res = await reactivateSubscription(id);
      if (!res.ok) setError(res.error);
      else router.refresh();
    });
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <Button variant="primary" size="sm" onClick={run} disabled={pending}>
        {pending ? "…" : "Reactivate subscription"}
      </Button>
      {error && <span className="text-xs text-[var(--color-danger)]">{error}</span>}
    </div>
  );
}
