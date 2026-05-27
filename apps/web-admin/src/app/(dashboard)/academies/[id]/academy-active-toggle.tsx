"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { setAcademyActive } from "@/lib/actions/academies";

export function AcademyActiveToggle({
  id,
  isActive,
}: {
  id: string;
  isActive: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function toggle() {
    setError(null);
    startTransition(async () => {
      const res = await setAcademyActive(id, !isActive);
      if (!res.ok) setError(res.error);
      else router.refresh();
    });
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <Button
        variant={isActive ? "danger" : "primary"}
        size="sm"
        onClick={toggle}
        disabled={pending}
      >
        {pending ? "…" : isActive ? "Disable academy" : "Enable academy"}
      </Button>
      {error && <span className="text-xs text-[var(--color-danger)]">{error}</span>}
    </div>
  );
}
