import { afterEach, describe, expect, it, vi } from "vitest";
import { OPENROUTER_URL } from "../src/generate";
import { call, devSignIn, env, sse } from "./helpers";

type Captured = { body: any; headers: Headers };

function mockOpenRouter(respond: (body: any) => Response): Captured[] {
  const captured: Captured[] = [];
  const real = globalThis.fetch;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url !== OPENROUTER_URL) return real(input, init);
    const body = JSON.parse(String(init?.body));
    captured.push({ body, headers: new Headers(init?.headers) });
    return respond(body);
  });
  return captured;
}

function sseStream(lines: string[]): Response {
  const text = lines.map((l) => `${l}\n\n`).join("");
  return new Response(text, { headers: { "content-type": "text/event-stream" } });
}

const sayItBetter = (extra: Record<string, unknown> = {}) => ({
  skillId: "com.knack.say-it-better",
  tier: "text-fast",
  messages: [
    { role: "system", content: "Rewrite the user's text in the requested tone." },
    { role: "user", content: "Tone: Nicer\n\nsend me the file" },
  ],
  ...extra,
});

async function balance(token: string): Promise<number> {
  return ((await (await call("GET", "/v1/me", undefined, token)).json()) as any).balanceUSD;
}

afterEach(() => vi.restoreAllMocks());

describe("generate", () => {
  it("maps the tier to a server-side model and debits the actual cost (non-streaming)", async () => {
    const s = await devSignIn();
    const captured = mockOpenRouter(() =>
      Response.json({
        choices: [{ message: { content: "Could you send me the file when you get a chance?" } }],
        usage: { prompt_tokens: 30, completion_tokens: 12, cost: 0.000123 },
      }),
    );
    const res = await call("POST", "/v1/generate", sayItBetter(), s.accessToken);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.text).toContain("send me the file");
    expect(body.costUSD).toBeCloseTo(0.000123, 6);
    expect(body.balanceUSD).toBeCloseTo(1000 - 0.000123, 6);

    expect(captured[0].body.model).toBe("google/gemini-2.5-flash-lite");
    expect(captured[0].body.usage).toEqual({ include: true });
    expect(captured[0].headers.get("authorization")).toBe("Bearer test-key");

    const me = (await (await call("GET", "/v1/me", undefined, s.accessToken)).json()) as any;
    expect(me.month.bySkill).toEqual([{ skillId: "com.knack.say-it-better", runs: 1, spentUSD: 0.000123 }]);
  });

  it("streams deltas and a done event, then settles", async () => {
    const s = await devSignIn();
    mockOpenRouter(() =>
      sseStream([
        ": OPENROUTER PROCESSING",
        `data: ${JSON.stringify({ choices: [{ delta: { content: "Could you " } }] })}`,
        `data: ${JSON.stringify({ choices: [{ delta: { content: "send the file?" } }] })}`,
        `data: ${JSON.stringify({ choices: [{ delta: {} }], usage: { prompt_tokens: 30, completion_tokens: 6, cost: 0.0005 } })}`,
        "data: [DONE]",
      ]),
    );
    const res = await call("POST", "/v1/generate", sayItBetter({ stream: true }), s.accessToken);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/event-stream");
    const events = sse(await res.text());
    expect(events.filter((e) => e.event === "delta").map((e) => e.data.text).join("")).toBe("Could you send the file?");
    const done = events.at(-1)!;
    expect(done.event).toBe("done");
    expect(done.data.costUSD).toBeCloseTo(0.0005, 6);
    expect(await balance(s.accessToken)).toBeCloseTo(1000 - 0.0005, 6);
  });

  it("estimates cost from tokens when the provider doesn't report it", async () => {
    const s = await devSignIn();
    mockOpenRouter(() =>
      Response.json({ choices: [{ message: { content: "ok" } }], usage: { prompt_tokens: 1_000, completion_tokens: 1_000 } }),
    );
    const body = (await (await call("POST", "/v1/generate", sayItBetter(), s.accessToken)).json()) as any;
    // text-fast: $0.10 in + $0.40 out per million tokens.
    expect(body.costUSD).toBeCloseTo(0.0005, 6);
  });

  it("releases the whole reservation when the model call fails", async () => {
    const s = await devSignIn();
    mockOpenRouter(() => new Response("boom", { status: 502 }));
    const res = await call("POST", "/v1/generate", sayItBetter(), s.accessToken);
    expect(res.status).toBe(503);
    expect(((await res.json()) as any).error.code).toBe("model_unavailable");
    expect(await balance(s.accessToken)).toBe(1000);
  });

  it("returns out_of_credit when the reservation can't be covered", async () => {
    const s = await devSignIn();
    const captured = mockOpenRouter(() => Response.json({}));
    await env.DB.prepare("INSERT INTO ledger (user_id, kind, amount_micros, external_ref, created_at) VALUES (?, 'topup', ?, ?, ?)")
      .bind(s.user.id, -999_995_000, `drain:${s.user.id}`, Date.now())
      .run();
    const res = await call("POST", "/v1/generate", sayItBetter(), s.accessToken);
    expect(res.status).toBe(402);
    expect(((await res.json()) as any).error.code).toBe("out_of_credit");
    expect(captured).toHaveLength(0);
  });

  it("rejects unknown skills, disallowed tiers and images on text tiers", async () => {
    const s = await devSignIn();
    const captured = mockOpenRouter(() => Response.json({}));
    const cases: [unknown, string][] = [
      [sayItBetter({ skillId: "com.evil.skill" }), "unknown_skill"],
      [sayItBetter({ tier: "vision-fast" }), "tier_not_allowed"],
      [
        sayItBetter({
          messages: [{ role: "user", content: [{ type: "image_url", image_url: { url: "data:image/png;base64,AAAA" } }] }],
        }),
        "tier_not_allowed",
      ],
      [sayItBetter({ messages: [] }), "bad_request"],
      [sayItBetter({ messages: [{ role: "tool", content: "x" }] }), "bad_request"],
    ];
    for (const [body, code] of cases) {
      const res = await call("POST", "/v1/generate", body, s.accessToken);
      expect(((await res.json()) as any).error.code).toBe(code);
    }
    expect(captured).toHaveLength(0);
  });

  it("lets vision tiers take images", async () => {
    const s = await devSignIn();
    const captured = mockOpenRouter(() => Response.json({ choices: [{ message: { content: "[]" } }], usage: { cost: 0.001 } }));
    const res = await call(
      "POST",
      "/v1/generate",
      {
        skillId: "com.knack.fridge-chef",
        tier: "vision-fast",
        responseFormat: { type: "json_object" },
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: "List the food items." },
              { type: "image_url", image_url: { url: "data:image/jpeg;base64,AAAA" } },
            ],
          },
        ],
      },
      s.accessToken,
    );
    expect(res.status).toBe(200);
    expect(captured[0].body.model).toBe("google/gemini-2.5-flash");
    expect(captured[0].body.response_format).toEqual({ type: "json_object" });
  });

  it("stores only metadata about requests, never content", async () => {
    const s = await devSignIn();
    mockOpenRouter(() => Response.json({ choices: [{ message: { content: "secret reply" } }], usage: { cost: 0.0001 } }));
    await call("POST", "/v1/generate", sayItBetter(), s.accessToken);
    const rows = await env.DB.prepare("SELECT * FROM requests WHERE user_id = ?").bind(s.user.id).all();
    expect(rows.results).toHaveLength(1);
    expect(JSON.stringify(rows.results)).not.toContain("secret reply");
    expect(JSON.stringify(rows.results)).not.toContain("send me the file");
    expect(rows.results[0]).toMatchObject({ status: "ok", skill_id: "com.knack.say-it-better", tier: "text-fast" });
  });
});
