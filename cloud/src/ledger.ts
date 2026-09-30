import { now, startOfUtcDay } from "./util";

// Append-only credit ledger. See migrations/0001_init.sql for row kinds.
// Amounts are integer micro-dollars. Nothing here ever UPDATEs or DELETEs a row.

export async function balanceMicros(db: D1Database, userId: string): Promise<number> {
  const row = await db
    .prepare("SELECT COALESCE(SUM(amount_micros), 0) AS b FROM ledger WHERE user_id = ?")
    .bind(userId)
    .first<{ b: number }>();
  return row?.b ?? 0;
}

/** Net debits (reserve + settle) since the start of the current UTC day, as a positive number. */
export async function spentTodayMicros(db: D1Database, userId: string, at = now()): Promise<number> {
  const row = await db
    .prepare(
      "SELECT COALESCE(-SUM(amount_micros), 0) AS s FROM ledger WHERE user_id = ? AND kind IN ('reserve', 'settle') AND created_at >= ?",
    )
    .bind(userId, startOfUtcDay(at))
    .first<{ s: number }>();
  return row?.s ?? 0;
}

/** Credits the user once per external reference (starter grant, payment event ID). Returns false if already applied. */
export async function credit(
  db: D1Database,
  userId: string,
  kind: "grant" | "topup",
  amountMicros: number,
  externalRef: string,
): Promise<boolean> {
  if (amountMicros <= 0) throw new Error("credit amount must be positive");
  const res = await db
    .prepare(
      "INSERT OR IGNORE INTO ledger (user_id, kind, amount_micros, external_ref, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(userId, kind, amountMicros, externalRef, now())
    .run();
  return res.meta.changes === 1;
}

export type ReserveResult = { ok: true } | { ok: false; reason: "out_of_credit" | "daily_limit" };

/**
 * Pre-authorizes `amountMicros` for a request. The balance and daily-cap checks and the
 * insert happen in one statement, so concurrent requests can't overdraw.
 */
export async function reserve(
  db: D1Database,
  userId: string,
  requestId: string,
  amountMicros: number,
  dailyCapMicros: number,
  at = now(),
): Promise<ReserveResult> {
  const dayStart = startOfUtcDay(at);
  const res = await db
    .prepare(
      `INSERT OR IGNORE INTO ledger (user_id, kind, amount_micros, request_id, created_at)
       SELECT ?1, 'reserve', -?2, ?3, ?4
       WHERE (SELECT COALESCE(SUM(amount_micros), 0) FROM ledger WHERE user_id = ?1) >= ?2
         AND (SELECT COALESCE(-SUM(amount_micros), 0) FROM ledger
              WHERE user_id = ?1 AND kind IN ('reserve', 'settle') AND created_at >= ?5) + ?2 <= ?6`,
    )
    .bind(userId, amountMicros, requestId, at, dayStart, dailyCapMicros)
    .run();
  if (res.meta.changes === 1) return { ok: true };
  const balance = await balanceMicros(db, userId);
  return { ok: false, reason: balance < amountMicros ? "out_of_credit" : "daily_limit" };
}

/**
 * Settles a reservation to the actual charge by releasing the unused part.
 * Idempotent per request. The charge is capped at the reservation.
 * Returns the amount actually charged.
 */
export async function settle(
  db: D1Database,
  userId: string,
  requestId: string,
  chargedMicros: number,
): Promise<number> {
  const reserved = await db
    .prepare("SELECT -amount_micros AS r FROM ledger WHERE request_id = ? AND kind = 'reserve' AND user_id = ?")
    .bind(requestId, userId)
    .first<{ r: number }>();
  if (!reserved) throw new Error("no reservation for request");
  const charged = Math.max(0, Math.min(Math.round(chargedMicros), reserved.r));
  await db
    .prepare(
      "INSERT OR IGNORE INTO ledger (user_id, kind, amount_micros, request_id, created_at) VALUES (?, 'settle', ?, ?, ?)",
    )
    .bind(userId, reserved.r - charged, requestId, now())
    .run();
  return charged;
}
