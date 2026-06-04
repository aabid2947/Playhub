import * as React from "react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

export interface EmptyStateProps {
  icon: LucideIcon;
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}

/**
 * Server-component empty/zero state for tables, lists, and pages.
 * Renders a large lucide icon, title, optional description, and optional action.
 */
export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center gap-3 rounded-[var(--radius)] border border-dashed border-[var(--color-border)] bg-[var(--color-surface)]/40 px-6 py-12 text-center",
        className,
      )}
    >
      <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[var(--color-surface-2)] text-[var(--color-muted)]">
        <Icon size={24} />
      </div>
      <div className="text-lg font-semibold tracking-tight text-[var(--color-fg)]">
        {title}
      </div>
      {description && (
        <p className="max-w-sm text-sm text-[var(--color-muted)]">
          {description}
        </p>
      )}
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}
