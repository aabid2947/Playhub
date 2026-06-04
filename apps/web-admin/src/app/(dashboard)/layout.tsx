import { AppSidebar } from "@/components/app-sidebar";
import { getCurrentUser } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { Toaster } from "@/components/ui/toast";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const user = await getCurrentUser();

  return (
    <Toaster>
      <div className="flex h-screen overflow-hidden">
        <AppSidebar />
        <div className="flex min-w-0 flex-1 flex-col">
          <header className="flex h-14 shrink-0 items-center justify-between border-b border-[var(--color-border)] px-6">
            <div className="text-sm text-[var(--color-muted)]">
              Platform operations
            </div>
            <div className="flex items-center gap-4">
              <span className="text-xs text-[var(--color-muted)]">
                {user?.name ?? user?.email ?? "—"}
              </span>
              <form action="/auth/signout" method="post">
                <Button type="submit" variant="ghost" size="sm">
                  Sign out
                </Button>
              </form>
            </div>
          </header>
          <main className="min-h-0 flex-1 overflow-auto p-6">{children}</main>
        </div>
      </div>
    </Toaster>
  );
}
