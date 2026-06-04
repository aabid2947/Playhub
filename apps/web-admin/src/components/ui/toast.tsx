"use client";

import * as React from "react";
import { CheckCircle2, AlertCircle, Info, X } from "lucide-react";
import { cn } from "@/lib/utils";

export type ToastTone = "success" | "error" | "info";

export interface ToastInput {
  message: string;
  tone?: ToastTone;
  /** Auto-dismiss after this many ms. Defaults to 4000. Pass 0 to disable. */
  duration?: number;
}

interface ToastItem extends Required<Pick<ToastInput, "message" | "tone">> {
  id: number;
  duration: number;
}

interface ToastContextValue {
  toast: (input: ToastInput | string) => void;
  dismiss: (id: number) => void;
}

const ToastContext = React.createContext<ToastContextValue | null>(null);

const TONE_STYLES: Record<ToastTone, { border: string; icon: React.ReactNode }> = {
  success: {
    border: "border-l-[var(--color-success)]",
    icon: (
      <CheckCircle2 size={18} className="text-[var(--color-success)]" />
    ),
  },
  error: {
    border: "border-l-[var(--color-danger)]",
    icon: <AlertCircle size={18} className="text-[var(--color-danger)]" />,
  },
  info: {
    border: "border-l-[var(--color-brand)]",
    icon: <Info size={18} className="text-[var(--color-brand)]" />,
  },
};

function ToastViewport({
  toasts,
  onDismiss,
}: {
  toasts: ToastItem[];
  onDismiss: (id: number) => void;
}) {
  return (
    <div
      role="region"
      aria-label="Notifications"
      className="pointer-events-none fixed bottom-4 right-4 z-50 flex w-full max-w-sm flex-col gap-2"
    >
      {toasts.map((t) => {
        const tone = TONE_STYLES[t.tone];
        return (
          <div
            key={t.id}
            role="status"
            className={cn(
              "pointer-events-auto flex items-start gap-3 rounded-[var(--radius)] border border-[var(--color-border)] border-l-4 bg-[var(--color-surface)] p-3 text-sm text-[var(--color-fg)] shadow-lg",
              tone.border,
            )}
          >
            <div className="mt-0.5 shrink-0">{tone.icon}</div>
            <div className="flex-1 leading-snug">{t.message}</div>
            <button
              type="button"
              aria-label="Dismiss"
              onClick={() => onDismiss(t.id)}
              className="shrink-0 rounded p-0.5 text-[var(--color-muted)] transition-colors hover:text-[var(--color-fg)]"
            >
              <X size={14} />
            </button>
          </div>
        );
      })}
    </div>
  );
}

/**
 * Toaster — place ONCE near the root (e.g. dashboard layout).
 * Hosts the ToastProvider and renders the viewport.
 */
export function Toaster({ children }: { children?: React.ReactNode }) {
  const [toasts, setToasts] = React.useState<ToastItem[]>([]);
  const idRef = React.useRef(0);
  const timers = React.useRef<Map<number, ReturnType<typeof setTimeout>>>(
    new Map(),
  );

  const dismiss = React.useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
    const timer = timers.current.get(id);
    if (timer) {
      clearTimeout(timer);
      timers.current.delete(id);
    }
  }, []);

  const toast = React.useCallback(
    (input: ToastInput | string) => {
      const normalized: ToastInput =
        typeof input === "string" ? { message: input } : input;
      const id = ++idRef.current;
      const item: ToastItem = {
        id,
        message: normalized.message,
        tone: normalized.tone ?? "info",
        duration: normalized.duration ?? 4000,
      };
      setToasts((prev) => [...prev, item]);
      if (item.duration > 0) {
        const timer = setTimeout(() => dismiss(id), item.duration);
        timers.current.set(id, timer);
      }
    },
    [dismiss],
  );

  React.useEffect(() => {
    const map = timers.current;
    return () => {
      map.forEach((t) => clearTimeout(t));
      map.clear();
    };
  }, []);

  const value = React.useMemo(() => ({ toast, dismiss }), [toast, dismiss]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <ToastViewport toasts={toasts} onDismiss={dismiss} />
    </ToastContext.Provider>
  );
}

/**
 * useToast — fire a toast from any client component.
 * Throws if used outside <Toaster /> to surface wiring mistakes early.
 */
export function useToast(): ToastContextValue {
  const ctx = React.useContext(ToastContext);
  if (!ctx) {
    throw new Error(
      "useToast must be used within <Toaster />. Mount <Toaster /> in the layout.",
    );
  }
  return ctx;
}
