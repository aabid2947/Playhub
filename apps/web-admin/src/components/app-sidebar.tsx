"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Activity,
  Building2,
  CreditCard,
  LifeBuoy,
  FileBarChart,
  Wrench,
  Menu,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils";

const NAV = [
  { href: "/health", label: "Health", icon: Activity },
  { href: "/academies", label: "Academies", icon: Building2 },
  { href: "/plans", label: "Plans", icon: CreditCard },
  { href: "/tickets", label: "Tickets", icon: LifeBuoy },
  { href: "/reports", label: "Reports", icon: FileBarChart },
  { href: "/ops", label: "Ops", icon: Wrench },
] as const;

function NavList({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  return (
    <nav className="flex flex-col gap-1 px-3 py-2">
      {NAV.map(({ href, label, icon: Icon }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
        return (
          <Link
            key={href}
            href={href}
            onClick={onNavigate}
            className={cn(
              "flex items-center gap-3 rounded-[var(--radius)] px-3 py-2 text-sm transition-colors",
              active
                ? "bg-[var(--color-surface-2)] text-[var(--color-fg)]"
                : "text-[var(--color-muted)] hover:bg-[var(--color-surface-2)]/60 hover:text-[var(--color-fg)]",
            )}
          >
            <Icon size={16} />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}

function SidebarBrand() {
  return (
    <div className="flex h-14 items-center gap-2 px-5 font-semibold">
      <span className="text-[var(--color-brand)]">PlayHub</span>
      <span className="text-xs text-[var(--color-muted)]">admin</span>
    </div>
  );
}

export function AppSidebar() {
  const [open, setOpen] = React.useState(false);
  const pathname = usePathname();

  // Close the mobile drawer on route change.
  React.useEffect(() => {
    setOpen(false);
  }, [pathname]);

  // Lock body scroll while drawer is open.
  React.useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  return (
    <>
      {/* Mobile hamburger — visible only <md */}
      <button
        type="button"
        aria-label="Open menu"
        aria-expanded={open}
        onClick={() => setOpen(true)}
        className={cn(
          "fixed left-3 top-3 z-40 inline-flex h-9 w-9 items-center justify-center rounded-[var(--radius)] border border-[var(--color-border)] bg-[var(--color-surface)] text-[var(--color-fg)] shadow-sm transition-colors hover:bg-[var(--color-surface-2)] md:hidden",
        )}
      >
        <Menu size={18} />
      </button>

      {/* Desktop sidebar — fixed 224px (w-56), unchanged layout */}
      <aside className="hidden w-56 shrink-0 flex-col border-r border-[var(--color-border)] bg-[var(--color-surface)] md:flex">
        <SidebarBrand />
        <NavList />
      </aside>

      {/* Mobile overlay drawer */}
      <div
        className={cn(
          "fixed inset-0 z-50 md:hidden",
          open ? "pointer-events-auto" : "pointer-events-none",
        )}
        aria-hidden={!open}
      >
        {/* Backdrop */}
        <div
          onClick={() => setOpen(false)}
          className={cn(
            "absolute inset-0 bg-black/60 transition-opacity duration-200",
            open ? "opacity-100" : "opacity-0",
          )}
        />
        {/* Panel */}
        <aside
          className={cn(
            "absolute left-0 top-0 flex h-full w-64 flex-col border-r border-[var(--color-border)] bg-[var(--color-surface)] shadow-xl transition-transform duration-200",
            open ? "translate-x-0" : "-translate-x-full",
          )}
          role="dialog"
          aria-modal="true"
          aria-label="Navigation"
        >
          <div className="flex items-center justify-between pr-2">
            <SidebarBrand />
            <button
              type="button"
              aria-label="Close menu"
              onClick={() => setOpen(false)}
              className="inline-flex h-8 w-8 items-center justify-center rounded-[var(--radius)] text-[var(--color-muted)] transition-colors hover:bg-[var(--color-surface-2)] hover:text-[var(--color-fg)]"
            >
              <X size={16} />
            </button>
          </div>
          <NavList onNavigate={() => setOpen(false)} />
        </aside>
      </div>
    </>
  );
}
