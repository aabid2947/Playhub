import { PageHeader } from "@/components/page-header";
import { listAcademies } from "@/lib/data/academies";
import { AcademiesTable } from "./academies-table";

export const dynamic = "force-dynamic";

export default async function AcademiesPage() {
  const academies = await listAcademies();
  return (
    <>
      <PageHeader
        title="Academies"
        description={`${academies.length} academ${academies.length === 1 ? "y" : "ies"} on the platform.`}
      />
      <AcademiesTable data={academies} />
    </>
  );
}
