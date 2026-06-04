import * as React from "react";
import { PageHeader } from "@/components/page-header";
import { Skeleton, SkeletonCard } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

export interface BreadcrumbItem {
  label: string;
  href?: string;
}

export interface PageShellProps {
  title: string;
  description?: string;
  actions?: React.ReactNode;
  breadcrumbs?: BreadcrumbItem[];
  className?: string;
  children: React.ReactNode;
}

/**
 * PageShell — consistent wrapper for dashboard pages.
 * Composes PageHeader and applies max-width + spacing.
 * Optional, additive; existing pages using PageHeader directly continue to work.
 */
export function PageShell({
  title,
  description,
  actions,
  breadcrumbs,
  className,
  children,
}: PageShellProps) {
  return (
    <div className={cn("mx-auto w-full max-w-7xl", className)}>
      {breadcrumbs && breadcrumbs.length > 0 && (
        <nav
          aria-label="Breadcrumb"
          className="mb-2 flex items-center gap-1 text-xs text-[var(--color-muted)]"
        >
          {breadcrumbs.map((c, i) => (
            <span key={i} className="flex items-center gap-1">
              {c.href ? (
                <a
                  href={c.href}
                  className="hover:text-[var(--color-fg)] transition-colors"
                >
                  {c.label}
                </a>
              ) : (
                <span>{c.label}</span>
              )}
              {i < breadcrumbs.length - 1 && <span>/</span>}
            </span>
          ))}
        </nav>
      )}
      <PageHeader title={title} description={description} actions={actions} />
      {children}
    </div>
  );
}

/**
 * Full-page skeleton for Suspense fallbacks / loading.tsx files.
 * Header bar + stat-grid + chart placeholder.
 */
export function PageSkeleton() {
  return (
    <div className="mx-auto w-full max-w-7xl">
      <div className="mb-6 flex items-start justify-between gap-4">
        <div className="flex flex-col gap-2">
          <Skeleton className="h-5 w-40" />
          <Skeleton className="h-3 w-64" />
        </div>
        <Skeleton className="h-9 w-24" />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <SkeletonCard key={i} />
        ))}
      </div>
      <div className="mt-6">
        <Skeleton className="h-64 w-full" />
      </div>
    </div>
  );
}
