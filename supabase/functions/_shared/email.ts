// Gmail SMTP sender (best-effort).
//
// v1 strategy per PLAN.md: Gmail SMTP, 500/day cap accepted. If SMTP_USER /
// SMTP_PASS aren't configured, sendEmail() logs and returns a stub success
// so callers can still record delivery without a hard failure.
//
// We avoid pulling a heavyweight SMTP client into Sprint-4 by speaking SMTP
// via a tiny TLS socket helper; for production, swap to denomailer or skip
// to the email provider sprint.
//
// SMTP_USER  — gmail address
// SMTP_PASS  — gmail app password (NOT the account password)
// SMTP_FROM  — display name + email, e.g. "PlayHub <noreply@playhub.in>"

export interface EmailMessage {
  to: string;
  subject: string;
  body_text: string;
  body_html?: string;
}

export async function sendEmail(msg: EmailMessage): Promise<boolean> {
  const user = Deno.env.get('SMTP_USER');
  const pass = Deno.env.get('SMTP_PASS');
  if (!user || !pass) {
    // Stub mode — log + succeed so the caller can mark "delivered" without
    // breaking the announcement fan-out. Real SMTP comes online once a
    // domain + Google Workspace app password is configured.
    console.log(`[email-stub] to=${msg.to} subject=${msg.subject}`);
    return true;
  }

  const from = Deno.env.get('SMTP_FROM') ?? `PlayHub <${user}>`;
  const conn = await Deno.connectTls({ hostname: 'smtp.gmail.com', port: 465 });
  const enc = new TextEncoder();
  const dec = new TextDecoder();

  async function read(): Promise<string> {
    const buf = new Uint8Array(4096);
    const n = await conn.read(buf);
    return n ? dec.decode(buf.subarray(0, n)) : '';
  }
  async function send(line: string): Promise<void> {
    await conn.write(enc.encode(line + '\r\n'));
  }
  async function expect(prefix: string): Promise<void> {
    const r = await read();
    if (!r.startsWith(prefix)) throw new Error(`SMTP unexpected: ${r}`);
  }

  try {
    await expect('220');
    await send(`EHLO playhub`);              await expect('250');
    await send(`AUTH LOGIN`);                await expect('334');
    await send(btoa(user));                  await expect('334');
    await send(btoa(pass));                  await expect('235');
    await send(`MAIL FROM:<${user}>`);       await expect('250');
    await send(`RCPT TO:<${msg.to}>`);       await expect('250');
    await send(`DATA`);                      await expect('354');

    const headers = [
      `From: ${from}`,
      `To: ${msg.to}`,
      `Subject: ${msg.subject}`,
      `MIME-Version: 1.0`,
      `Content-Type: text/${msg.body_html ? 'html' : 'plain'}; charset=utf-8`,
      ``,
      msg.body_html ?? msg.body_text,
      `.`,
    ].join('\r\n');
    await send(headers);
    await expect('250');
    await send(`QUIT`);
  } catch (err) {
    console.error('[email] send failed', err);
    return false;
  } finally {
    try { conn.close(); } catch { /* already closed */ }
  }
  return true;
}
