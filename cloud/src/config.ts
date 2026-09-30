import tiersJson from "../config/tiers.json";
import skillsJson from "../config/skills.json";
import type { Env } from "./env";

export type Tier = "text-fast" | "text-smart" | "vision-fast";

export interface TierConfig {
  model: string;
  maxTokens: number;
  usdPerMTokIn: number;
  usdPerMTokOut: number;
  vision?: boolean;
}

export interface SkillConfig {
  tiers: Tier[];
  maxCostPerRunUSD: number;
}

export const TIERS: Record<string, TierConfig> = tiersJson;
export const SKILLS: Record<string, SkillConfig> = skillsJson as Record<string, SkillConfig>;

export const MICROS_PER_USD = 1_000_000;

export function usdToMicros(usd: number): number {
  return Math.round(usd * MICROS_PER_USD);
}

export function microsToUsd(micros: number): number {
  return micros / MICROS_PER_USD;
}

export interface Settings {
  appleAudiences: string[];
  starterCreditMicros: number;
  dailyCapMicros: number;
  margin: number;
  rateLimitPerMinute: number;
  disabledModels: Set<string>;
  allowDevAuth: boolean;
}

function num(value: string | undefined, fallback: number): number {
  const n = Number(value);
  return value !== undefined && value !== "" && Number.isFinite(n) ? n : fallback;
}

function list(value: string | undefined): string[] {
  return (value ?? "").split(",").map((s) => s.trim()).filter(Boolean);
}

export function settings(env: Env): Settings {
  return {
    appleAudiences: list(env.APPLE_AUDIENCES),
    starterCreditMicros: usdToMicros(num(env.STARTER_CREDIT_USD, 1000)),
    dailyCapMicros: usdToMicros(num(env.DAILY_SPEND_CAP_USD, 10)),
    margin: num(env.PRICE_MARGIN, 0),
    rateLimitPerMinute: num(env.RATE_LIMIT_PER_MINUTE, 30),
    disabledModels: new Set(list(env.DISABLED_MODELS)),
    allowDevAuth: env.ALLOW_DEV_AUTH === "true",
  };
}
