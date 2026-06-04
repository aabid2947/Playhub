import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * Animated placeholder block for loading states.
 * Pure visual — no client runtime needed.
 */
export function Skeleton({
  className,
  width,
  height,
  style,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & {
  width?: number | string;
  height?: number | string;
}) {
  return (
    <div
      aria-hidden="true"
      className={cn(
        "animate-pulse rounded-[var(--radius)] bg-[var(--color-surface-2)]",
        className,
      )}
      style={{ width, height, ...style }}
      {...props}
    />
  );
}

/** Three short lines of skeleton text — for paragraphs / list rows. */
export function SkeletonText({
  lines = 3,
  className,
}: {
  lines?: number;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-2", className)}>
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton
          key={i}
          className={cn("h-3", i === lines - 1 ? "w-2/3" : "w-full")}
        />
      ))}
    </div>
  );
}

/** Card-shaped skeleton with header bar + body lines. */
export function SkeletonCard({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "rounded-[var(--radius)] border border-[var(--color-border)] bg-[var(--color-surface)] p-5",
        className,
      )}
    >
      <Skeleton className="h-4 w-1/3" />
      <div className="mt-4">
        <SkeletonText lines={3} />
      </div>
    </div>
  );
}
