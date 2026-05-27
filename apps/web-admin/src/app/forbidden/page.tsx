import { Button } from "@/components/ui/button";

export default function ForbiddenPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
      <h1 className="text-2xl font-semibold">403 · Not authorised</h1>
      <p className="max-w-md text-sm text-[var(--color-muted)]">
        This console is restricted to PlayHub platform super-admins. Your
        account is signed in but does not have super-admin privileges.
      </p>
      <form action="/auth/signout" method="post">
        <Button type="submit" variant="outline">
          Sign out
        </Button>
      </form>
    </main>
  );
}
