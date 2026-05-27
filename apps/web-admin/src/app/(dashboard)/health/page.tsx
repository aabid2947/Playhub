import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatCard } from "@/components/stat-card";
import { Badge, statusTone } from "@/components/ui/badge";
import { MonthAreaChart, MonthBarChart } from "@/components/charts";
import { humanize, inr } from "@/lib/format";
import {
  getGlobalKpi,
  getRevenueByMonth,
  getSignupsByMonth,
} from "@/lib/data/health";

export const dynamic = "force-dynamic";

export default async function HealthPage() {
  const [kpi, revenue, signups] = await Promise.all([
    getGlobalKpi(),
    getRevenueByMonth(),
    getSignupsByMonth(),
  ]);

  return (
    <>
      <PageHeader
        title="Platform health"
        description="Global KPIs across every academy on PlayHub."
      />

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          label="Academies"
          value={kpi.academiesTotal}
          hint={`${kpi.academiesActive} active`}
        />
        <StatCard
          label="Platform revenue"
          value={inr(kpi.platformRevenue)}
          hint="All SaaS payments"
        />
        <StatCard
          label="Outstanding"
          value={inr(kpi.outstanding)}
          hint="Unpaid SaaS invoices"
        />
        <StatCard label="Open tickets" value={kpi.openTickets} />
      </div>

      <Card className="mt-4">
        <CardHeader>
          <CardTitle>Academies by subscription status</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {(
            Object.entries(kpi.byStatus) as [
              keyof typeof kpi.byStatus,
              number,
            ][]
          ).map(([status, count]) => (
            <Badge key={status} tone={statusTone(status)}>
              {humanize(status)}: {count}
            </Badge>
          ))}
        </CardContent>
      </Card>

      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>SaaS revenue (last 12 months)</CardTitle>
          </CardHeader>
          <CardContent>
            <MonthAreaChart data={revenue} fmt="inr" />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>New academies (last 12 months)</CardTitle>
          </CardHeader>
          <CardContent>
            <MonthBarChart data={signups} fmt="int" />
          </CardContent>
        </Card>
      </div>
    </>
  );
}
