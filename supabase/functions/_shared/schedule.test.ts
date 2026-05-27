import { assert, assertEquals, assertFalse } from "jsr:@std/assert@^1.0.0";
import { dowCode, isSessionOver, toIst } from "./schedule.ts";

Deno.test("dowCode is Mon-indexed", () => {
  assertEquals(dowCode(new Date(Date.UTC(2024, 0, 1))), "mon"); // 2024-01-01 was a Monday
  assertEquals(dowCode(new Date(Date.UTC(2024, 0, 7))), "sun"); // Sunday
});

Deno.test("toIst shifts UTC by +5:30", () => {
  const ist = toIst(new Date("2026-01-01T00:00:00Z"));
  assertEquals(ist.getUTCHours(), 5);
  assertEquals(ist.getUTCMinutes(), 30);
});

Deno.test("isSessionOver: scheduled today and past end_time", () => {
  const sched = { days: ["mon", "wed"], start_time: "16:00", end_time: "17:00" };
  assert(isSessionOver(sched, "mon", "18:00"));
  assertFalse(isSessionOver(sched, "mon", "16:30")); // still running
  assertFalse(isSessionOver(sched, "tue", "23:00")); // not scheduled today
});

Deno.test("isSessionOver: day codes are case-insensitive; missing end_time defaults to 23:59", () => {
  assert(isSessionOver({ days: ["MON"] }, "mon", "23:59"));
  assertFalse(isSessionOver({ days: ["MON"] }, "mon", "23:58"));
  assertFalse(isSessionOver(null, "mon", "23:59"));
});
