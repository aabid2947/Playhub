import * as React from "react";
import { cn } from "@/lib/utils";

type Variant = "primary" | "secondary" | "ghost" | "danger" | "outline";
type Size = "sm" | "md" | "icon";

const VARIANTS: Record<Variant, string> = {
  primary:
    "bg-[var(--color-brand)] text-[var(--color-brand-fg)] hover:opacity-90",
  secondary:
    "bg-[var(--color-surface-2)] text-[var(--color-fg)] hover:bg-[var(--color-border)]",
  ghost: "bg-transparent text-[var(--color-fg)] hover:bg-[var(--color-surface-2)]",
  danger: "bg-[var(--color-danger)] text-white hover:opacity-90",
  outline:
    "border border-[var(--color-border)] bg-transparent text-[var(--color-fg)] hover:bg-[var(--color-surface-2)]",
};

const SIZES: Record<Size, string> = {
  sm: "h-8 px-3 text-xs",
  md: "h-9 px-4 text-sm",
  icon: "h-9 w-9",
};

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = "primary", size = "md", ...props }, ref) => (
    <button
      ref={ref}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-[var(--radius)] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-brand)] disabled:pointer-events-none disabled:opacity-50",
        VARIANTS[variant],
        SIZES[size],
        className,
      )}
      {...props}
    />
  ),
);
Button.displayName = "Button";
