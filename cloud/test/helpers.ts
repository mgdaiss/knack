import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index";

export { env };

export async function call(method: string, path: string, body?: unknown, token?: string): Promise<Response> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  const request = new Request(`https://cloud.test${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const ctx = createExecutionContext();
  const res = await worker.fetch(request, env, ctx);
  // Buffer the body before draining waitUntil work, so streamed responses complete.
  const buffered = new Response(await res.arrayBuffer(), { status: res.status, headers: res.headers });
  await waitOnExecutionContext(ctx);
  return buffered;
}

let counter = 0;
export async function devSignIn(): Promise<{ accessToken: string; refreshToken: string; user: { id: string; isNew: boolean } }> {
  counter += 1;
  const res = await call("POST", "/v1/auth/dev", { deviceId: `test-device-${Date.now()}-${counter}` });
  if (res.status !== 200) throw new Error(`dev sign-in failed: ${res.status}`);
  return res.json();
}

export function sse(text: string): { event: string; data: any }[] {
  return text
    .split("\n\n")
    .filter((b) => b.trim())
    .map((block) => {
      const event = /^event: (.+)$/m.exec(block)?.[1] ?? "";
      const data = JSON.parse(/^data: (.+)$/m.exec(block)?.[1] ?? "null");
      return { event, data };
    });
}
