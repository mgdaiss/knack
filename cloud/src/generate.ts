import { authenticate } from "./auth";
import { SKILLS, TIERS, settings, microsToUsd, usdToMicros, type TierConfig } from "./config";
import type { Env } from "./env";
import { ApiError, errorBody, json, type ErrorCode } from "./errors";
import { balanceMicros, reserve, settle } from "./ledger";
import { now } from "./util";

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

const MAX_BODY_BYTES = 12 * 1024 * 1024; // room for one or two photos as data URLs
const MAX_MESSAGES = 40;

type ContentPart = { type: "text"; text: string } | { type: "image_url"; image_url: { url: string } };

interface Message {
  role: "system" | "user" | "assistant";
  content: string | ContentPart[];
}

interface GenerateBody {
  skillId: string;
  tier: string;
  messages: Message[];
  responseFormat?: unknown;
  stream?: boolean;
}

interface Usage {
  prompt_tokens?: number;
  completion_tokens?: number;
  cost?: number;
}

function validate(body: unknown): GenerateBody {
  const b = body as Partial<GenerateBody> | null;
  if (!b || typeof b !== "object") throw new ApiError("bad_request");
  if (typeof b.skillId !== "string" || typeof b.tier !== "string") {
    throw new ApiError("bad_request", "skillId and tier are required.");
  }
  if (!Array.isArray(b.messages) || b.messages.length === 0 || b.messages.length > MAX_MESSAGES) {
    throw new ApiError("bad_request", "messages must be a non-empty array.");
  }
  for (const m of b.messages) {
    if (!m || !["system", "user", "assistant"].includes(m.role)) throw new ApiError("bad_request", "Invalid message role.");
    if (typeof m.content === "string") continue;
    if (!Array.isArray(m.content)) throw new ApiError("bad_request", "Invalid message content.");
    for (const part of m.content) {
      const ok =
        (part?.type === "text" && typeof part.text === "string") ||
        (part?.type === "image_url" && typeof part.image_url?.url === "string");
      if (!ok) throw new ApiError("bad_request", "Invalid message content part.");
    }
  }
  if (b.responseFormat !== undefined && (typeof b.responseFormat !== "object" || b.responseFormat === null)) {
    throw new ApiError("bad_request", "responseFormat must be an object.");
  }
  return b as GenerateBody;
}

function hasImages(messages: Message[]): boolean {
  return messages.some((m) => Array.isArray(m.content) && m.content.some((p) => p.type === "image_url"));
}

/** Rough token estimate (≈4 chars per token) for when the provider doesn't report usage. */
function estimateTokens(messages: Message[]): number {
  let chars = 0;
  for (const m of messages) {
    if (typeof m.content === "string") chars += m.content.length;
    else for (const p of m.content) chars += p.type === "text" ? p.text.length : 4000; // ~1k tokens per image
  }
  return Math.ceil(chars / 4);
}

function costMicros(tier: TierConfig, usage: Usage, fallbackPromptTokens: number, fallbackCompletionChars: number, margin: number): number {
  let usd: number;
  if (typeof usage.cost === "number") {
    usd = usage.cost;
  } else {
    const pin = usage.prompt_tokens ?? fallbackPromptTokens;
    const pout = usage.completion_tokens ?? Math.ceil(fallbackCompletionChars / 4);
    usd = (pin * tier.usdPerMTokIn + pout * tier.usdPerMTokOut) / 1_000_000;
  }
  return usdToMicros(usd * (1 + margin));
}

async function rateLimited(db: D1Database, userId: string, limit: number): Promise<boolean> {
  const row = await db
    .prepare("SELECT COUNT(*) AS n FROM requests WHERE user_id = ? AND created_at >= ?")
    .bind(userId, now() - 60_000)
    .first<{ n: number }>();
  return (row?.n ?? 0) >= limit;
}

async function finishRequest(
  db: D1Database,
  requestId: string,
  fields: { status: string; usage?: Usage; costMicros?: number; chargedMicros?: number; errorCode?: string; startedAt: number },
) {
  await db
    .prepare(
      `UPDATE requests SET status = ?, prompt_tokens = ?, completion_tokens = ?, cost_micros = ?, charged_micros = ?,
       latency_ms = ?, error_code = ?, finished_at = ? WHERE id = ?`,
    )
    .bind(
      fields.status,
      fields.usage?.prompt_tokens ?? null,
      fields.usage?.completion_tokens ?? null,
      fields.costMicros ?? null,
      fields.chargedMicros ?? 0,
      now() - fields.startedAt,
      fields.errorCode ?? null,
      now(),
      requestId,
    )
    .run();
}

export async function handleGenerate(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const userId = await authenticate(request, env);
  const cfg = settings(env);

  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY_BYTES) throw new ApiError("bad_request", "That's too much to send at once.");
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    throw new ApiError("bad_request");
  }
  const body = validate(raw);

  const skill = SKILLS[body.skillId];
  if (!skill) throw new ApiError("unknown_skill");
  if (!skill.tiers.includes(body.tier as never)) throw new ApiError("tier_not_allowed");
  const tier = TIERS[body.tier];
  if (!tier) throw new ApiError("tier_not_allowed");
  if (hasImages(body.messages) && !tier.vision) throw new ApiError("tier_not_allowed", "That helper can't look at pictures.");
  if (cfg.disabledModels.has(tier.model)) throw new ApiError("model_unavailable");

  if (await rateLimited(env.DB, userId, cfg.rateLimitPerMinute)) throw new ApiError("rate_limited");

  const requestId = crypto.randomUUID();
  const startedAt = now();
  await env.DB
    .prepare(
      "INSERT INTO requests (id, user_id, skill_id, tier, model, status, created_at) VALUES (?, ?, ?, ?, ?, 'pending', ?)",
    )
    .bind(requestId, userId, body.skillId, body.tier, tier.model, startedAt)
    .run();

  const reservedMicros = usdToMicros(skill.maxCostPerRunUSD);
  const reservation = await reserve(env.DB, userId, requestId, reservedMicros, cfg.dailyCapMicros);
  if (!reservation.ok) {
    await finishRequest(env.DB, requestId, { status: "rejected", errorCode: reservation.reason, startedAt });
    throw new ApiError(reservation.reason);
  }

  const promptEstimate = estimateTokens(body.messages);
  const upstreamBody: Record<string, unknown> = {
    model: tier.model,
    messages: body.messages,
    max_tokens: tier.maxTokens,
    stream: !!body.stream,
    usage: { include: true },
  };
  if (body.responseFormat) upstreamBody.response_format = body.responseFormat;

  let upstream: Response;
  try {
    upstream = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
        "content-type": "application/json",
        "http-referer": "https://knack.app",
        "x-title": "Knack",
      },
      body: JSON.stringify(upstreamBody),
    });
  } catch {
    upstream = new Response(null, { status: 599 });
  }

  if (!upstream.ok) {
    await settle(env.DB, userId, requestId, 0);
    await finishRequest(env.DB, requestId, { status: "error", errorCode: `upstream_${upstream.status}`, startedAt });
    console.warn("upstream error", { requestId, status: upstream.status, model: tier.model });
    throw new ApiError("model_unavailable");
  }

  const finalize = async (status: "ok" | "cancelled" | "error", usage: Usage, completionChars: number, errorCode?: string) => {
    const cost = costMicros(tier, usage, promptEstimate, completionChars, cfg.margin);
    const charged = await settle(env.DB, userId, requestId, cost);
    await finishRequest(env.DB, requestId, { status, usage, costMicros: cost, chargedMicros: charged, errorCode, startedAt });
    return charged;
  };

  if (!body.stream) {
    const data = (await upstream.json()) as { choices?: { message?: { content?: string } }[]; usage?: Usage };
    const text = data.choices?.[0]?.message?.content ?? "";
    const charged = await finalize("ok", data.usage ?? {}, text.length);
    return json({
      requestId,
      text,
      usage: { promptTokens: data.usage?.prompt_tokens ?? null, completionTokens: data.usage?.completion_tokens ?? null },
      costUSD: microsToUsd(charged),
      balanceUSD: microsToUsd(await balanceMicros(env.DB, userId)),
    });
  }

  return streamResponse(upstream, requestId, finalize, async () => microsToUsd(await balanceMicros(env.DB, userId)), ctx);
}

/**
 * Re-encodes OpenRouter's SSE stream into Knack's own events (see API.md):
 *   event: delta  data: {"text": "..."}
 *   event: done   data: {"requestId", "costUSD", "balanceUSD", "usage"}
 *   event: error  data: {"error": {"code", "message"}}
 */
function streamResponse(
  upstream: Response,
  requestId: string,
  finalize: (status: "ok" | "cancelled" | "error", usage: Usage, completionChars: number, errorCode?: string) => Promise<number>,
  balance: () => Promise<number>,
  ctx: ExecutionContext,
): Response {
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();
  let clientGone = false;

  const send = async (event: string, data: unknown) => {
    if (clientGone) return;
    try {
      await writer.write(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
    } catch {
      clientGone = true;
    }
  };

  const pump = async () => {
    const reader = upstream.body!.pipeThrough(new TextDecoderStream()).getReader();
    let buffer = "";
    let usage: Usage = {};
    let chars = 0;
    let upstreamError: ErrorCode | null = null;
    let done = false;
    try {
      while (!done && !clientGone) {
        const { value, done: eof } = await reader.read();
        if (eof) break;
        buffer += value;
        let nl: number;
        while ((nl = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, nl).replace(/\r$/, "");
          buffer = buffer.slice(nl + 1);
          if (!line.startsWith("data:")) continue; // comments (": OPENROUTER PROCESSING") and blanks
          const payload = line.slice(5).trim();
          if (payload === "[DONE]") {
            done = true;
            break;
          }
          let chunk: { choices?: { delta?: { content?: string } }[]; usage?: Usage; error?: unknown };
          try {
            chunk = JSON.parse(payload);
          } catch {
            continue;
          }
          if (chunk.error) {
            upstreamError = "model_unavailable";
            done = true;
            break;
          }
          if (chunk.usage) usage = chunk.usage;
          const text = chunk.choices?.[0]?.delta?.content;
          if (text) {
            chars += text.length;
            await send("delta", { text });
          }
        }
      }
    } catch {
      upstreamError = "model_unavailable";
    } finally {
      if (clientGone || upstreamError) reader.cancel().catch(() => {});
    }

    const status = clientGone ? "cancelled" : upstreamError ? "error" : "ok";
    const charged = await finalize(status, usage, chars, upstreamError ?? undefined);
    if (upstreamError) {
      await send("error", errorBody(upstreamError));
    } else {
      await send("done", {
        requestId,
        costUSD: microsToUsd(charged),
        balanceUSD: await balance(),
        usage: { promptTokens: usage.prompt_tokens ?? null, completionTokens: usage.completion_tokens ?? null },
      });
    }
    if (!clientGone) await writer.close().catch(() => {});
  };

  ctx.waitUntil(pump());
  return new Response(readable, {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache",
      "x-request-id": requestId,
    },
  });
}
