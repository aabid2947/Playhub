import { assert, assertEquals } from "jsr:@std/assert@^1.0.0";
import { authoriseCron, preflight } from "./cors.ts";

const req = (method: string, headers: Record<string, string> = {}) =>
  new Request("http://localhost/fn", { method, headers });

Deno.test("preflight: OPTIONS returns a CORS response, others pass through", () => {
  assert(preflight(req("OPTIONS")) instanceof Response);
  assertEquals(preflight(req("POST")), null);
});

Deno.test("authoriseCron: matching x-cron-secret is authorised", () => {
  Deno.env.set("CRON_SECRET", "s3cr3t");
  assertEquals(authoriseCron(req("POST", { "x-cron-secret": "s3cr3t" })), null);
});

Deno.test("authoriseCron: any Bearer token is authorised (service-role ad-hoc)", () => {
  Deno.env.set("CRON_SECRET", "s3cr3t");
  assertEquals(authoriseCron(req("POST", { authorization: "Bearer abc.def.ghi" })), null);
});

Deno.test("authoriseCron: wrong secret + no bearer is 401", () => {
  Deno.env.set("CRON_SECRET", "s3cr3t");
  const denied = authoriseCron(req("POST", { "x-cron-secret": "nope" }));
  assert(denied instanceof Response);
  assertEquals(denied!.status, 401);
});

Deno.test("authoriseCron: no headers at all is 401", () => {
  Deno.env.set("CRON_SECRET", "s3cr3t");
  const denied = authoriseCron(req("POST"));
  assertEquals(denied!.status, 401);
});
