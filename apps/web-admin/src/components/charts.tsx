"use client";

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { fmtMonth, inr } from "@/lib/format";
import type { MonthPoint } from "@/lib/aggregate";

type Fmt = "inr" | "int";

function tickFmt(fmt: Fmt) {
  return (v: number) =>
    fmt === "inr"
      ? inr(v).replace("₹", "₹")
      : new Intl.NumberFormat("en-IN").format(v);
}

const AXIS = { stroke: "var(--color-muted)", fontSize: 11 };

function ChartTooltip({ fmt }: { fmt: Fmt }) {
  const f = tickFmt(fmt);
  return (
    <Tooltip
      cursor={{ fill: "var(--color-surface-2)", opacity: 0.4 }}
      contentStyle={{
        background: "var(--color-surface-2)",
        border: "1px solid var(--color-border)",
        borderRadius: 8,
        fontSize: 12,
      }}
      labelStyle={{ color: "var(--color-muted)" }}
      labelFormatter={(l) => fmtMonth(String(l))}
      formatter={(v: number) => [f(v), ""]}
    />
  );
}

export function MonthAreaChart({
  data,
  fmt = "inr",
}: {
  data: MonthPoint[];
  fmt?: Fmt;
}) {
  return (
    <div className="h-56 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
          <defs>
            <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-brand)" stopOpacity={0.5} />
              <stop offset="100%" stopColor="var(--color-brand)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke="var(--color-border)" strokeDasharray="3 3" vertical={false} />
          <XAxis dataKey="month" tickFormatter={fmtMonth} tickLine={false} axisLine={false} tick={AXIS} />
          <YAxis tickFormatter={tickFmt(fmt)} tickLine={false} axisLine={false} width={56} tick={AXIS} />
          <ChartTooltip fmt={fmt} />
          <Area
            type="monotone"
            dataKey="value"
            stroke="var(--color-brand)"
            strokeWidth={2}
            fill="url(#g)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

export function MonthBarChart({
  data,
  fmt = "int",
}: {
  data: MonthPoint[];
  fmt?: Fmt;
}) {
  return (
    <div className="h-56 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
          <CartesianGrid stroke="var(--color-border)" strokeDasharray="3 3" vertical={false} />
          <XAxis dataKey="month" tickFormatter={fmtMonth} tickLine={false} axisLine={false} tick={AXIS} />
          <YAxis tickFormatter={tickFmt(fmt)} tickLine={false} axisLine={false} width={40} tick={AXIS} allowDecimals={false} />
          <ChartTooltip fmt={fmt} />
          <Bar dataKey="value" fill="var(--color-brand)" radius={[4, 4, 0, 0]} maxBarSize={36} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
