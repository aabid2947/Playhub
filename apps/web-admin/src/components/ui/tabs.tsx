"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

interface TabsContextValue {
  value: string;
  setValue: (v: string) => void;
}

const TabsContext = React.createContext<TabsContextValue | null>(null);

function useTabs(component: string): TabsContextValue {
  const ctx = React.useContext(TabsContext);
  if (!ctx) {
    throw new Error(`${component} must be used inside <Tabs>`);
  }
  return ctx;
}

export interface TabsProps {
  /** Controlled active tab value. */
  value?: string;
  /** Default uncontrolled value. */
  defaultValue?: string;
  onValueChange?: (value: string) => void;
  className?: string;
  children: React.ReactNode;
}

export function Tabs({
  value: controlled,
  defaultValue,
  onValueChange,
  className,
  children,
}: TabsProps) {
  const [internal, setInternal] = React.useState(defaultValue ?? "");
  const isControlled = controlled !== undefined;
  const value = isControlled ? controlled : internal;

  const setValue = React.useCallback(
    (next: string) => {
      if (!isControlled) setInternal(next);
      onValueChange?.(next);
    },
    [isControlled, onValueChange],
  );

  const ctx = React.useMemo(() => ({ value, setValue }), [value, setValue]);

  return (
    <TabsContext.Provider value={ctx}>
      <div className={cn("flex flex-col gap-4", className)}>{children}</div>
    </TabsContext.Provider>
  );
}

export function TabsList({
  className,
  children,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      role="tablist"
      className={cn(
        "flex items-center gap-1 border-b border-[var(--color-border)]",
        className,
      )}
      {...props}
    >
      {children}
    </div>
  );
}

export interface TabsTriggerProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  value: string;
}

export function TabsTrigger({
  value,
  className,
  children,
  ...props
}: TabsTriggerProps) {
  const ctx = useTabs("TabsTrigger");
  const active = ctx.value === value;
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      data-state={active ? "active" : "inactive"}
      onClick={() => ctx.setValue(value)}
      className={cn(
        "-mb-px inline-flex h-9 items-center border-b-2 px-3 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-brand)]",
        active
          ? "border-[var(--color-brand)] text-[var(--color-fg)]"
          : "border-transparent text-[var(--color-muted)] hover:text-[var(--color-fg)]",
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}

export interface TabsContentProps
  extends React.HTMLAttributes<HTMLDivElement> {
  value: string;
}

export function TabsContent({
  value,
  className,
  children,
  ...props
}: TabsContentProps) {
  const ctx = useTabs("TabsContent");
  if (ctx.value !== value) return null;
  return (
    <div role="tabpanel" className={cn("focus-visible:outline-none", className)} {...props}>
      {children}
    </div>
  );
}
