import { Card, CardContent } from "@/components/ui/card";

export function StatCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: string | number;
  hint?: string;
}) {
  return (
    <Card>
      <CardContent className="p-5">
        <div className="text-xs font-medium uppercase tracking-wide text-[var(--color-muted)]">
          {label}
        </div>
        <div className="mt-1.5 text-2xl font-semibold tracking-tight">
          {value}
        </div>
        {hint && (
          <div className="mt-1 text-xs text-[var(--color-muted)]">{hint}</div>
        )}
      </CardContent>
    </Card>
  );
}
