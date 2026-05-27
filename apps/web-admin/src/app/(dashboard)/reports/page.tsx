import { PageHeader } from "@/components/page-header";
import { listAcademies } from "@/lib/data/academies";
import { listTickets } from "@/lib/data/tickets";
import { listPlans } from "@/lib/data/plans";
import { ReportBuilder } from "./report-builder";

export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  const [academies, tickets, plans] = await Promise.all([
    listAcademies(),
    listTickets(),
    listPlans(),
  ]);
  return (
    <>
      <PageHeader
        title="Reports"
        description="Pick an entity and columns, preview, and export CSV."
      />
      <ReportBuilder academies={academies} tickets={tickets} plans={plans} />
    </>
  );
}
