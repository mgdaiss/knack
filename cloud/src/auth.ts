import { verifyAppleIdentityToken } from "./apple";
import { settings } from "./config";
import type { Env } from "./env";
import { ApiError, json } from "./errors";
import { credit } from "./ledger";
import { now, randomToken, sha256Hex } from "./util";

export const ACCESS_TTL_MS = 60 * 60 * 1000; // 1 hour
export const REFRESH_TTL_MS = 60 * 24 * 60 * 60 * 1000; // 60 days

export interface SessionTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

async function issueTokens(db: D1Database, userId: string): Promise<SessionTokens> {
  const accessToken = randomToken();
  const refreshToken = randomToken();
  const t = now();
  await db.batch([
    db
      .prepare("INSERT INTO sessions (token_hash, user_id, kind, expires_at, created_at) VALUES (?, ?, 'access', ?, ?)")
      .bind(await sha256Hex(accessToken), userId, t + ACCESS_TTL_MS, t),
    db
      .prepare("INSERT INTO sessions (token_hash, user_id, kind, expires_at, created_at) VALUES (?, ?, 'refresh', ?, ?)")
      .bind(await sha256Hex(refreshToken), userId, t + REFRESH_TTL_MS, t),
  ]);
  return { accessToken, refreshToken, expiresIn: Math.floor(ACCESS_TTL_MS / 1000) };
}

/** Finds or creates the user for an external subject and grants starter credit exactly once. */
async function upsertUser(env: Env, subject: string): Promise<{ id: string; isNew: boolean }> {
  const db = env.DB;
  const existing = await db.prepare("SELECT id FROM users WHERE apple_sub = ?").bind(subject).first<{ id: string }>();
  let id = existing?.id;
  let isNew = false;
  if (!id) {
    const candidate = crypto.randomUUID();
    await db
      .prepare("INSERT OR IGNORE INTO users (id, apple_sub, created_at) VALUES (?, ?, ?)")
      .bind(candidate, subject, now())
      .run();
    const row = await db.prepare("SELECT id FROM users WHERE apple_sub = ?").bind(subject).first<{ id: string }>();
    id = row!.id;
    isNew = id === candidate;
  }
  // Idempotent on the external ref, so a retry after a partial failure still grants once.
  await credit(db, id, "grant", settings(env).starterCreditMicros, `starter:${id}`);
  return { id, isNew };
}

async function readJson<T>(request: Request): Promise<T> {
  try {
    return (await request.json()) as T;
  } catch {
    throw new ApiError("bad_request");
  }
}

export async function handleAppleSignIn(request: Request, env: Env): Promise<Response> {
  const body = await readJson<{ identityToken?: string }>(request);
  if (!body.identityToken) throw new ApiError("bad_request", "identityToken is required.");
  const claims = await verifyAppleIdentityToken(body.identityToken, settings(env).appleAudiences);
  const user = await upsertUser(env, claims.sub);
  const tokens = await issueTokens(env.DB, user.id);
  return json({ ...tokens, user });
}

/** Development-only sign-in, for staging before Sign in with Apple is configured. */
export async function handleDevSignIn(request: Request, env: Env): Promise<Response> {
  if (!settings(env).allowDevAuth) throw new ApiError("not_found");
  const body = await readJson<{ deviceId?: string }>(request);
  if (!body.deviceId || !/^[A-Za-z0-9-]{8,64}$/.test(body.deviceId)) {
    throw new ApiError("bad_request", "deviceId is required.");
  }
  const user = await upsertUser(env, `dev:${body.deviceId}`);
  const tokens = await issueTokens(env.DB, user.id);
  return json({ ...tokens, user });
}

export async function handleRefresh(request: Request, env: Env): Promise<Response> {
  const body = await readJson<{ refreshToken?: string }>(request);
  if (!body.refreshToken) throw new ApiError("bad_request", "refreshToken is required.");
  const hash = await sha256Hex(body.refreshToken);
  const t = now();
  // Rotate: revoke the presented refresh token atomically; only one caller can win.
  const res = await env.DB
    .prepare(
      "UPDATE sessions SET revoked_at = ? WHERE token_hash = ? AND kind = 'refresh' AND revoked_at IS NULL AND expires_at > ?",
    )
    .bind(t, hash, t)
    .run();
  if (res.meta.changes !== 1) throw new ApiError("unauthorized");
  const row = await env.DB.prepare("SELECT user_id FROM sessions WHERE token_hash = ?").bind(hash).first<{ user_id: string }>();
  return json(await issueTokens(env.DB, row!.user_id));
}

/** Resolves the bearer access token to a user ID, or throws unauthorized. */
export async function authenticate(request: Request, env: Env): Promise<string> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer (.+)$/.exec(header);
  if (!match) throw new ApiError("unauthorized");
  const row = await env.DB
    .prepare(
      "SELECT user_id FROM sessions WHERE token_hash = ? AND kind = 'access' AND revoked_at IS NULL AND expires_at > ?",
    )
    .bind(await sha256Hex(match[1]), now())
    .first<{ user_id: string }>();
  if (!row) throw new ApiError("unauthorized");
  return row.user_id;
}
