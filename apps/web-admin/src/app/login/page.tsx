"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Label } from "@/components/ui/input";

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const supabase = createClient();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  // Stays false until the component hydrates — prevents a native (non-JS)
  // form GET submission if the user clicks before React attaches handlers.
  const [ready, setReady] = useState(false);
  useEffect(() => setReady(true), []);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    const { data, error: signInError } = await supabase.auth.signInWithPassword(
      { email, password },
    );

    if (signInError) {
      setError(signInError.message);
      setLoading(false);
      return;
    }

    // Confirm this account is actually a platform super-admin before entering.
    const { data: isSuper } = await supabase.rpc("is_super_admin");
    if (!isSuper) {
      await supabase.auth.signOut();
      setError("This account is not a platform super-admin.");
      setLoading(false);
      return;
    }

    const next = params.get("next");
    router.replace(next && next.startsWith("/") ? next : "/health");
    router.refresh();
    void data;
  }

  return (
    <Card className="w-full max-w-sm bg-surface-elevated shadow-[var(--shadow-lg)]">
      <CardHeader className="items-center text-center">
        <div className="mb-1 text-sm font-semibold uppercase tracking-[0.18em] text-[var(--color-brand)]">
          PlayHub Admin
        </div>
        <CardTitle className="text-base">PlayHub · Super Admin</CardTitle>
        <p className="text-xs text-[var(--color-muted)]">
          Platform operations console
        </p>
      </CardHeader>
      <CardContent>
        <form onSubmit={onSubmit} className="flex flex-col gap-4">
          <div>
            <Label
              htmlFor="email"
              className="text-[11px] font-semibold uppercase tracking-wide text-[var(--color-fg)]"
            >
              Email
            </Label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="focus-ring"
            />
          </div>
          <div>
            <Label
              htmlFor="password"
              className="text-[11px] font-semibold uppercase tracking-wide text-[var(--color-fg)]"
            >
              Password
            </Label>
            <Input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="focus-ring"
            />
          </div>
          {error && (
            <p className="text-xs text-[var(--color-danger)]" role="alert">
              {error}
            </p>
          )}
          <Button type="submit" disabled={loading || !ready}>
            {loading ? "Signing in…" : "Sign in"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center p-6">
      <Suspense fallback={null}>
        <LoginForm />
      </Suspense>
    </main>
  );
}
