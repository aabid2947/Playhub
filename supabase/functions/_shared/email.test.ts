import { assertEquals, assertMatch } from "jsr:@std/assert@^1.0.0";
import {
  base64,
  bareAddress,
  encodeBody,
  encodeHeader,
  headerSafe,
  rfc5322Date,
} from "./email.ts";

// --- header injection -------------------------------------------------------
// Announcement subjects are composed by coach/head_coach/center_admin users,
// so a CRLF in a caller value must never reach the header block intact.

Deno.test("headerSafe strips CRLF so headers can't be injected", () => {
  assertEquals(
    headerSafe("Practice update\r\nBcc: leak@evil.com"),
    "Practice update Bcc: leak@evil.com",
  );
  assertEquals(headerSafe("bare\nnewline"), "bare newline");
  assertEquals(headerSafe("carriage\rreturn"), "carriage return");
  assertEquals(headerSafe("  padded  "), "padded");
});

Deno.test("headerSafe collapses a run of newlines into one space", () => {
  assertEquals(headerSafe("a\r\n\r\n\r\nb"), "a b");
});

// --- subject encoding -------------------------------------------------------

Deno.test("encodeHeader leaves pure ASCII untouched", () => {
  assertEquals(encodeHeader("Fees due for July"), "Fees due for July");
});

Deno.test("encodeHeader RFC-2047-encodes non-ASCII subjects", () => {
  const encoded = encodeHeader("शुल्क बाकी है");
  assertMatch(encoded, /^=\?UTF-8\?B\?[A-Za-z0-9+/]+=*\?=$/);
  // Round-trips back to the original.
  assertEquals(
    new TextDecoder().decode(
      Uint8Array.from(atob(encoded.slice(10, -2)), (c) => c.charCodeAt(0)),
    ),
    "शुल्क बाकी है",
  );
});

Deno.test("encodeHeader sanitises before encoding", () => {
  // A CRLF must not survive, encoded or not.
  assertEquals(encodeHeader("clean\r\nBcc: x@y.com").includes("\r"), false);
  assertEquals(encodeHeader("नाम\r\nBcc: x@y.com").includes("\n"), false);
});

// --- body encoding ----------------------------------------------------------

Deno.test("encodeBody wraps base64 at 76 chars", () => {
  for (const line of encodeBody("x".repeat(500)).split("\r\n")) {
    assertEquals(line.length <= 76, true);
  }
});

Deno.test("encodeBody neutralises a lone-dot line (SMTP early terminator)", () => {
  // A raw body line of "." would end the DATA stage; base64 has no ".".
  const out = encodeBody("line one\r\n.\r\nline two");
  assertEquals(out.includes("."), false);
  assertEquals(
    new TextDecoder().decode(
      Uint8Array.from(atob(out.replace(/\r\n/g, "")), (c) => c.charCodeAt(0)),
    ),
    "line one\r\n.\r\nline two",
  );
});

Deno.test("base64 round-trips multibyte UTF-8", () => {
  const s = "आज की क्लास रद्द है — 5:30 बजे";
  assertEquals(
    new TextDecoder().decode(
      Uint8Array.from(atob(base64(s)), (c) => c.charCodeAt(0)),
    ),
    s,
  );
});

// --- address + date --------------------------------------------------------

Deno.test("bareAddress pulls the address out of a display-name From", () => {
  assertEquals(bareAddress("PlayHub <noreply@playhub.in>"), "noreply@playhub.in");
  assertEquals(bareAddress("noreply@playhub.in"), "noreply@playhub.in");
  assertEquals(bareAddress("  spaced@playhub.in  "), "spaced@playhub.in");
});

Deno.test("rfc5322Date uses a numeric zone, not the obsolete GMT", () => {
  const d = rfc5322Date(new Date(Date.UTC(2026, 6, 29, 19, 15, 0)));
  assertEquals(d, "Wed, 29 Jul 2026 19:15:00 +0000");
  assertMatch(d, /^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} .* \+0000$/);
});
