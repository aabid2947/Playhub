import { PageHeader } from "@/components/page-header";
import { OpsConsole } from "./ops-console";

export const dynamic = "force-dynamic";

export default function OpsPage() {
  return (
    <>
      <PageHeader
        title="Ops tools"
        description="Privileged platform operations. Each runs through the service role only after re-checking is_super_admin()."
      />
      <OpsConsole />
    </>
  );
}
