import { authenticate } from "./auth";
import { settings, microsToUsd } from "./config";
import type { Env } from "./env";
import { json } from "./errors";
import { balanceMicros, spentTodayMicros } from "./ledger";
import { now, startOfUtcMonth } from "./util";

export async function handleMe(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  const cfg = settings(env);
  const monthStart = startOfUtcMonth(now());
  const bySkill = await env.DB
    .prepare(
      `SELECT skill_id AS skillId, COUNT(*) AS runs, COALESCE(SUM(charged_micros), 0) AS charged
       FROM requests WHERE user_id = ? AND created_at >= ? AND status IN ('ok', 'cancelled')
       GROUP BY skill_id ORDER BY charged DESC`,
    )
    .bind(userId, monthStart)
    .all<{ skillId: string; runs: number; charged: number }>();
  const skills = bySkill.results.map((r) => ({ skillId: r.skillId, runs: r.runs, spentUSD: microsToUsd(r.charged) }));

  return json({
    user: { id: userId },
    balanceUSD: microsToUsd(await balanceMicros(env.DB, userId)),
    month: {
      runs: skills.reduce((n, s) => n + s.runs, 0),
      spentUSD: skills.reduce((n, s) => n + s.spentUSD, 0),
      bySkill: skills,
    },
    limits: {
      dailyCapUSD: microsToUsd(cfg.dailyCapMicros),
      dailySpentUSD: microsToUsd(await spentTodayMicros(env.DB, userId)),
    },
    payments: { enabled: false },
  });
}
