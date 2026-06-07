import { describe, it, expect, beforeAll, afterAll } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";
import { Fixture, HAS_ENV, type FullAcademy, type Role } from "./_helpers";

/**
 * The role × capability matrix, exercised through the SAME authenticated
 * supabase-js path the apps use. Encodes the contract from the role-capability
 * migrations (20260527000000 / …0100) and the center-narrowed read policies
 * (20260509000400). Every assertion mirrors a real RLS policy, so a regression
 * in any policy fails a named test here.
 *
 * Convention:
 *   - INSERT denied by RLS  → supabase-js returns an error (WITH CHECK violation)
 *   - UPDATE denied by RLS  → 0 rows affected, no error (USING filters the row out)
 *   - SELECT denied by RLS  → 0 rows, no error
 *
 * Skips automatically when local Supabase env vars are absent.
 */
const ALL_ROLES: Role[] = [
  "super_admin", "academy_owner", "academy_admin", "center_admin",
  "head_coach", "coach", "trainer", "parent", "student",
];

type Client = SupabaseClient<Database>;
type Expect = Record<Role, boolean>;

describe.skipIf(!HAS_ENV)("role × capability matrix", () => {
  const fx = new Fixture();
  let A: FullAcademy;
  const c: Partial<Record<Role, Client>> = {};

  // a separate tenant, to prove cross-academy isolation
  let otherAcademyId: string;
  let otherStudentId: string;

  beforeAll(async () => {
    A = await fx.createFullAcademy("mtx");
    for (const r of ALL_ROLES) c[r] = (await fx.signIn(A.emails[r])) as Client;

    const other = await fx.createAcademyWithOwner("iso");
    otherAcademyId = other.academyId;
    const admin = (await fx.signIn(A.emails.super_admin)) as Client; // super can write anywhere
    const { data } = await admin
      .from("students")
      .insert({ academy_id: otherAcademyId, first_name: "Other", last_name: "Tenant", parent_name: "P" })
      .select("id")
      .single();
    otherStudentId = data!.id;
  }, 90_000);

  afterAll(async () => {
    await fx.teardown();
  });

  /** Assert an INSERT outcome against the expected allow/deny. */
  function expectInsert(allowed: boolean, error: unknown, label: string) {
    if (allowed) expect(error, `${label}: expected ALLOWED`).toBeNull();
    else expect(error, `${label}: expected DENIED by RLS`).not.toBeNull();
  }

  // ── INSERT matrices ───────────────────────────────────────────────────────

  describe("students.insert @ center A", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: false, coach: false, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { error } = await c[r]!
          .from("students")
          .insert({ academy_id: A.academyId, center_id: A.centerA, first_name: "T", last_name: "T", parent_name: "P" })
          .select("id");
        expectInsert(exp[r], error, `students/${r}`);
      });
    }
  });

  it("center_admin: CANNOT create a student in another center (B)", async () => {
    const { error } = await c.center_admin!
      .from("students")
      .insert({ academy_id: A.academyId, center_id: A.centerB, first_name: "T", last_name: "T", parent_name: "P" })
      .select("id");
    expect(error, "center_admin write outside its center must be denied").not.toBeNull();
  });

  describe("coaches.insert @ center A", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: false, coach: false, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { error } = await c[r]!
          .from("coaches")
          .insert({ academy_id: A.academyId, center_id: A.centerA, first_name: "C", last_name: "C" })
          .select("id");
        expectInsert(exp[r], error, `coaches/${r}`);
      });
    }
  });

  describe("batches.insert @ center A + head_coach's sport (head_coach gains this)", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: true, coach: false, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        // sportA is the head_coach's qualified sport — Phase 2 scopes head_coach
        // to their sport, so the batch must carry it for head_coach to pass.
        const { error } = await c[r]!
          .from("batches")
          .insert({ academy_id: A.academyId, center_id: A.centerA, sport_id: A.sportA, name: `B ${r}` })
          .select("id");
        expectInsert(exp[r], error, `batches/${r}`);
      });
    }
  });

  describe("batches.insert @ center A, a sport the head_coach does NOT coach", () => {
    it("head_coach → denied (own-sport scope)", async () => {
      // No sport_id → not one of the head_coach's sports → denied (Phase 2).
      const { error } = await c.head_coach!
        .from("batches")
        .insert({ academy_id: A.academyId, center_id: A.centerA, name: "B no-sport" })
        .select("id");
      expect(error, "head_coach must not create a batch outside their sport").not.toBeNull();
    });
  });

  describe("attendance.insert @ batchA / centerA (coach owns batchA; trainer does NOT)", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: true, coach: true, trainer: false, parent: false, student: false,
    };
    ALL_ROLES.forEach((r, i) => {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { error } = await c[r]!
          .from("attendance_records")
          .insert({ academy_id: A.academyId, batch_id: A.batchA, student_id: A.studentA1, date: `2030-02-${String(i + 1).padStart(2, "0")}`, status: "present" })
          .select("id");
        expectInsert(exp[r], error, `attendance/${r}`);
      });
    });
  });

  describe("attendance.insert @ batchB / centerB (own-batch + center scoping)", () => {
    it("trainer (owns batchB) → allowed", async () => {
      const { error } = await c.trainer!
        .from("attendance_records")
        .insert({ academy_id: A.academyId, batch_id: A.batchB, student_id: A.studentB1, date: "2030-03-01", status: "present" })
        .select("id");
      expect(error).toBeNull();
    });
    it("coach (owns batchA, not batchB) → denied", async () => {
      const { error } = await c.coach!
        .from("attendance_records")
        .insert({ academy_id: A.academyId, batch_id: A.batchB, student_id: A.studentB1, date: "2030-03-02", status: "present" })
        .select("id");
      expect(error).not.toBeNull();
    });
    it("head_coach (centerA, batchB is centerB) → denied", async () => {
      const { error } = await c.head_coach!
        .from("attendance_records")
        .insert({ academy_id: A.academyId, batch_id: A.batchB, student_id: A.studentB1, date: "2030-03-03", status: "present" })
        .select("id");
      expect(error).not.toBeNull();
    });
    it("center_admin (centerA) → denied for centerB batch", async () => {
      const { error } = await c.center_admin!
        .from("attendance_records")
        .insert({ academy_id: A.academyId, batch_id: A.batchB, student_id: A.studentB1, date: "2030-03-04", status: "present" })
        .select("id");
      expect(error).not.toBeNull();
    });
  });

  describe("performance.insert @ batchA (staff-on-batch; trainer is not on batchA)", () => {
    // Since Phase 3 trainers CAN record performance, but only on batches they
    // staff — they don't staff batchA, so trainer is still denied here.
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: true, coach: true, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { error } = await c[r]!
          .from("performance_assessments")
          .insert({ academy_id: A.academyId, student_id: A.studentA1, batch_id: A.batchA, assessment_date: "2030-02-15" })
          .select("id");
        expectInsert(exp[r], error, `performance/${r}`);
      });
    }
  });

  describe("performance.insert @ batchB (trainer staffs batchB — Phase 3)", () => {
    it("trainer (owns batchB) → allowed", async () => {
      const { error } = await c.trainer!
        .from("performance_assessments")
        .insert({ academy_id: A.academyId, student_id: A.studentB1, batch_id: A.batchB, assessment_date: "2030-03-10" })
        .select("id");
      expect(error, "trainer should record performance on their own batch").toBeNull();
    });
  });

  describe("leads.insert (admin tier + center_admin only)", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: false, coach: false, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { error } = await c[r]!
          .from("leads")
          .insert({ academy_id: A.academyId, first_name: "Lead", phone: "+919000000000", preferred_center_id: A.centerA })
          .select("id");
        expectInsert(exp[r], error, `leads/${r}`);
      });
    }
  });

  describe("events.insert @ center A (admin tier + center_admin + head_coach)", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: true, coach: false, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { error } = await c[r]!
          .from("events")
          .insert({ academy_id: A.academyId, center_id: A.centerA, title: `E ${r}`, starts_at: "2030-06-01T10:00:00Z" })
          .select("id");
        expectInsert(exp[r], error, `events/${r}`);
      });
    }
  });

  describe("inventory_items.insert @ center A (admin tier + center_admin)", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: true, center_admin: true,
      head_coach: false, coach: false, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { error } = await c[r]!
          .from("inventory_items")
          .insert({ academy_id: A.academyId, center_id: A.centerA, name: `Item ${r}` })
          .select("id");
        expectInsert(exp[r], error, `inventory_items/${r}`);
      });
    }
  });

  describe("academies.update — academy settings are OWNER-only", () => {
    const exp: Expect = {
      super_admin: true, academy_owner: true, academy_admin: false, center_admin: false,
      head_coach: false, coach: false, trainer: false, parent: false, student: false,
    };
    for (const r of ALL_ROLES) {
      it(`${r} → ${exp[r] ? "allowed" : "denied"}`, async () => {
        const { data, error } = await c[r]!
          .from("academies")
          .update({ phone: "+919111111111" })
          .eq("id", A.academyId)
          .select("id");
        // denied = filtered to 0 rows (no error); allowed = the row comes back
        expect(error).toBeNull();
        expect((data ?? []).length, `academies.update/${r}`).toBe(exp[r] ? 1 : 0);
      });
    }
  });

  // ── READ / tenant-isolation matrix ────────────────────────────────────────

  describe("tenant isolation + read scoping", () => {
    async function canSeeStudent(role: Role, studentId: string): Promise<boolean> {
      const { data } = await c[role]!.from("students").select("id").eq("id", studentId);
      return (data ?? []).length === 1;
    }

    it("every academy role is BLIND to another tenant's student", async () => {
      for (const r of ALL_ROLES.filter((x) => x !== "super_admin")) {
        expect(await canSeeStudent(r, otherStudentId), `${r} must not see other tenant`).toBe(false);
      }
    });
    it("super_admin CAN read across tenants", async () => {
      expect(await canSeeStudent("super_admin", otherStudentId)).toBe(true);
    });
    it("center_admin sees own-center student (A) but NOT other-center (B)", async () => {
      expect(await canSeeStudent("center_admin", A.studentA1)).toBe(true);
      expect(await canSeeStudent("center_admin", A.studentB1)).toBe(false);
    });
    it("coach is NOT center-narrowed — sees academy-wide students (A and B)", async () => {
      expect(await canSeeStudent("coach", A.studentA1)).toBe(true);
      expect(await canSeeStudent("coach", A.studentB1)).toBe(true);
    });
    it("parent sees only their linked child (A1), not an unlinked student", async () => {
      expect(await canSeeStudent("parent", A.studentA1)).toBe(true);
      expect(await canSeeStudent("parent", A.studentB1)).toBe(false);
    });
    it("student sees only themselves (A1), not another student", async () => {
      expect(await canSeeStudent("student", A.studentA1)).toBe(true);
      expect(await canSeeStudent("student", A.studentB1)).toBe(false);
    });
  });
});
