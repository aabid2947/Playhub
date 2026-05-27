import * as React from "react";
import { cn } from "@/lib/utils";

export type BadgeTone =
  | "neutral"
  | "success"
  | "warning"
  | "danger"
  | "info";

const TONES: Record<BadgeTone, string> = {
  neutral:
    "bg-[var(--color-surface-2)] text-[var(--color-muted)] border-[var(--color-border)]",
  success: "bg-emerald-500/10 text-emerald-400 border-emerald-500/30",
  warning: "bg-amber-500/10 text-amber-400 border-amber-500/30",
  danger: "bg-red-500/10 text-red-400 border-red-500/30",
  info: "bg-blue-500/10 text-blue-400 border-blue-500/30",
};

export function Badge({
  tone = "neutral",
  className,
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { tone?: BadgeTone }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium",
        TONES[tone],
        className,
      )}
      {...props}
    />
  );
}

/** Maps PlayHub status enums to a sensible badge tone. */
export function statusTone(status: string): BadgeTone {
  switch (status) {
    case "active":
    case "paid":
    case "resolved":
    case "converted":
      return "success";
    case "trial":
    case "issued":
    case "open":
    case "in_progress":
    case "waiting_on_user":
      return "info";
    case "past_due":
    case "overdue":
      return "warning";
    case "suspended":
    case "cancelled":
    case "closed":
    case "lost":
      return "danger";
    default:
      return "neutral";
  }
}
