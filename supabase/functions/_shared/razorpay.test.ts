import { assert, assertFalse } from "jsr:@std/assert@^1.0.0";
import { verifyWebhookSignature } from "./razorpay.ts";

const SECRET = "whsec_test_123";

/** Independently compute the HMAC-SHA256 hex so the test isn't tautological. */
async function sign(body: string, secret = SECRET): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(body));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const BODY = JSON.stringify({ event: "payment.captured", id: "evt_1" });

Deno.test("verifyWebhookSignature: accepts a correct signature", async () => {
  assert(await verifyWebhookSignature(BODY, await sign(BODY), SECRET));
});

Deno.test("verifyWebhookSignature: rejects a tampered signature", async () => {
  const good = await sign(BODY);
  const bad = (good[0] === "0" ? "1" : "0") + good.slice(1); // flip first hex char
  assertFalse(await verifyWebhookSignature(BODY, bad, SECRET));
});

Deno.test("verifyWebhookSignature: rejects a signature from a different secret", async () => {
  assertFalse(await verifyWebhookSignature(BODY, await sign(BODY, "wrong_secret"), SECRET));
});

Deno.test("verifyWebhookSignature: rejects a length mismatch (constant-time guard)", async () => {
  assertFalse(await verifyWebhookSignature(BODY, "deadbeef", SECRET));
});

Deno.test("verifyWebhookSignature: a changed body invalidates the old signature", async () => {
  const sig = await sign(BODY);
  assertFalse(await verifyWebhookSignature(BODY + " ", sig, SECRET));
});
