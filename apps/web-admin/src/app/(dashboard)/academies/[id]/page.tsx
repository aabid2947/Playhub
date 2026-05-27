import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge, statusTone } from "@/components/ui/badge";
import { StatCard } from "@/components/stat-card";
import { fmtDate, humanize } from "@/lib/format";
import { getAcademy } from "@/lib/data/academies";
import { listAcademyInvoices } from "@/lib/data/billing";
import { AcademyActiveToggle } from "./academy-active-toggle";
import { InvoicesPanel } from "./invoices-panel";

export const dynamic = "force-dynamic";

export default async function AcademyDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const academy = await getAcademy(id);
  if (!academy) notFound();
  const invoices = await listAcademyInvoices(id);

  return (
    <>
      <Link
        href="/academies"
        className="mb-4 inline-flex items-center gap-1 text-xs text-[var(--color-muted)] hover:text-[var(--color-fg)]"
      >
        <ArrowLeft size={14} /> Academies
      </Link>

      <PageHeader
        title={academy.name}
        description={academy.email ?? undefined}
        actions={
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2">
              <Badge tone={statusTone(academy.subscriptionStatus)}>
                {humanize(academy.subscriptionStatus)}
              </Badge>
              <Badge tone={academy.isActive ? "success" : "danger"}>
                {academy.isActive ? "Active" : "Disabled"}
              </Badge>
            </div>
            <AcademyActiveToggle id={academy.id} isActive={academy.isActive} />
          </div>
        }
      />

      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Members" value={academy.memberCount} />
        <StatCard label="Students" value={academy.studentCount} />
        <StatCard
          label="Trial ends"
          value={academy.trialEndsAt ? fmtDate(academy.trialEndsAt) : "—"}
        />
        <StatCard label="Joined" value={fmtDate(academy.createdAt)} />
      </div>

      <Card className="mt-4">
        <CardHeader>
          <CardTitle>Details</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-y-3 text-sm">
          <Field label="Owner" value={academy.ownerName} />
          <Field label="Owner email" value={academy.ownerEmail} />
          <Field label="Phone" value={academy.phone} />
          <Field
            label="Location"
            value={[academy.city, academy.state].filter(Boolean).join(", ")}
          />
        </CardContent>
      </Card>

      <InvoicesPanel academyId={academy.id} invoices={invoices} />
    </>
  );
}

function Field({ label, value }: { label: string; value: string | null }) {
  return (
    <div>
      <div className="text-xs text-[var(--color-muted)]">{label}</div>
      <div className="mt-0.5">{value || "—"}</div>
    </div>
  );
}
