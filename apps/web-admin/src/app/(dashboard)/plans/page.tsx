import { PageHeader } from "@/components/page-header";
import { listPlans } from "@/lib/data/plans";
import { PlansManager } from "./plans-manager";

export const dynamic = "force-dynamic";

export default async function PlansPage() {
  const plans = await listPlans();
  return (
    <>
      <PageHeader
        title="Subscription plans"
        description="The SaaS plans academies subscribe to."
      />
      <PlansManager plans={plans} />
    </>
  );
}
