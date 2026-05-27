// Pure schedule/day-of-week helpers shared by attendance cron functions.
// Extracted from auto-mark-absent so the session-eligibility logic is
// unit-testable without a DB.

export const DOW_CODES = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
export type DowCode = (typeof DOW_CODES)[number];

/** Asia/Kolkata is UTC+5:30; the apps are India-first. */
export function toIst(utc: Date): Date {
  return new Date(utc.getTime() + 5.5 * 60 * 60 * 1000);
}

/** Mon-indexed day code for a date (uses its UTC weekday). */
export function dowCode(d: Date): DowCode {
  return DOW_CODES[(d.getUTCDay() + 6) % 7];
}

export interface BatchSchedule {
  days?: string[];
  start_time?: string;
  end_time?: string;
}

/**
 * True when `schedule` runs on `dow` AND its end time is at/before `hhmm`
 * (i.e. today's session is over). Missing end_time defaults to 23:59.
 * Mirrors the eligibility filter in auto-mark-absent.
 */
export function isSessionOver(
  schedule: BatchSchedule | null | undefined,
  dow: string,
  hhmm: string,
): boolean {
  const days = (schedule?.days ?? []).map((d) => d.toLowerCase());
  if (!days.includes(dow)) return false;
  const end = schedule?.end_time ?? "23:59";
  return hhmm >= end;
}
