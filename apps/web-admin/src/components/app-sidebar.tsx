"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Activity,
  Building2,
  CreditCard,
  LifeBuoy,
  FileBarChart,
  Wrench,
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

export function AppSidebar() {
  const pathname = usePathname();

  return (
    <aside className="flex w-56 shrink-0 flex-col border-r border-[var(--color-border)] bg-[var(--color-surface)]">
      <div className="flex h-14 items-center gap-2 px-5 font-semibold">
        <span className="text-[var(--color-brand)]">PlayHub</span>
        <span className="text-xs text-[var(--color-muted)]">admin</span>
      </div>
      <nav className="flex flex-col gap-1 px-3 py-2">
        {NAV.map(({ href, label, icon: Icon }) => {
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={href}
              href={href}
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
    </aside>
  );
}
