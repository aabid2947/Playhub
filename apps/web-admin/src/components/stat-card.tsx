import { ArrowDown, ArrowUp } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export type StatCardTone = "neutral" | "positive" | "negative";

export interface StatCardTrend {
  /** Signed percentage (e.g. 4.2 for +4.2%, -3.1 for -3.1%). */
  value: number;
  /** Optional label suffix, e.g. "vs last week". */
  label?: string;
}

export function StatCard({
  label,
  value,
  hint,
  trend,
  tone = "neutral",
  className,
}: {
  label: string;
  value: string | number;
  hint?: string;
  trend?: StatCardTrend;
  tone?: StatCardTone;
  className?: string;
}) {
  const trendDirection =
    trend === undefined ? null : trend.value > 0 ? "up" : trend.value < 0 ? "down" : "flat";

  // Tone applies to the value text. Trend has its own up/down color.
  const valueClass = cn(
    "mt-1.5 text-2xl font-semibold tracking-tight",
    tone === "positive" && "text-[var(--color-success)]",
    tone === "negative" && "text-[var(--color-danger)]",
  );

  const trendClass = cn(
    "inline-flex items-center gap-0.5 text-xs font-medium",
    trendDirection === "up" && "text-[var(--color-success)]",
    trendDirection === "down" && "text-[var(--color-danger)]",
    trendDirection === "flat" && "text-[var(--color-muted)]",
  );

  return (
    <Card className={className}>
      <CardContent className="p-5">
        <div className="text-xs font-medium uppercase tracking-wide text-[var(--color-muted)]">
          {label}
        </div>
        <div className={valueClass}>{value}</div>
        {(hint || trend) && (
          <div className="mt-1 flex items-center gap-2 text-xs text-[var(--color-muted)]">
            {trend && (
              <span className={trendClass}>
                {trendDirection === "up" && <ArrowUp size={12} />}
                {trendDirection === "down" && <ArrowDown size={12} />}
                {trend.value > 0 ? "+" : ""}
                {trend.value}%
              </span>
            )}
            {hint && <span>{hint}</span>}
            {!hint && trend?.label && <span>{trend.label}</span>}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
