import { describe, expect, it } from "vitest";
import { balanceMicros, credit, reserve, settle, spentTodayMicros } from "../src/ledger";
import { env } from "./helpers";

async function newUser(): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare("INSERT INTO users (id, apple_sub, created_at) VALUES (?, ?, ?)").bind(id, `sub-${id}`, Date.now()).run();
  return id;
}

const CAP = 10_000_000; // $10

describe("ledger", () => {
  it("balance is the sum of rows and credits are idempotent per external ref", async () => {
    const u = await newUser();
    expect(await balanceMicros(env.DB, u)).toBe(0);
    expect(await credit(env.DB, u, "grant", 5_000_000, `starter:${u}`)).toBe(true);
    expect(await credit(env.DB, u, "grant", 5_000_000, `starter:${u}`)).toBe(false);
    expect(await balanceMicros(env.DB, u)).toBe(5_000_000);
  });

  it("reserves, then settles to the actual cost and releases the rest", async () => {
    const u = await newUser();
    await credit(env.DB, u, "grant", 1_000_000, `g:${u}`);
    expect(await reserve(env.DB, u, "req-1", 20_000, CAP)).toEqual({ ok: true });
    expect(await balanceMicros(env.DB, u)).toBe(980_000);
    expect(await settle(env.DB, u, "req-1", 1_234)).toBe(1_234);
    expect(await balanceMicros(env.DB, u)).toBe(1_000_000 - 1_234);
    expect(await spentTodayMicros(env.DB, u)).toBe(1_234);
  });

  it("settle is idempotent and caps the charge at the reservation", async () => {
    const u = await newUser();
    await credit(env.DB, u, "grant", 1_000_000, `g:${u}`);
    await reserve(env.DB, u, "req-cap", 20_000, CAP);
    expect(await settle(env.DB, u, "req-cap", 999_999)).toBe(20_000);
    await settle(env.DB, u, "req-cap", 0);
    expect(await balanceMicros(env.DB, u)).toBe(980_000);
  });

  it("a request can only be reserved once", async () => {
    const u = await newUser();
    await credit(env.DB, u, "grant", 1_000_000, `g:${u}`);
    await reserve(env.DB, u, "req-dup", 20_000, CAP);
    const again = await reserve(env.DB, u, "req-dup", 20_000, CAP);
    expect(again.ok).toBe(false);
    expect(await balanceMicros(env.DB, u)).toBe(980_000);
  });

  it("rejects a reservation larger than the balance as out_of_credit", async () => {
    const u = await newUser();
    await credit(env.DB, u, "grant", 10_000, `g:${u}`);
    expect(await reserve(env.DB, u, "req-big", 20_000, CAP)).toEqual({ ok: false, reason: "out_of_credit" });
    expect(await balanceMicros(env.DB, u)).toBe(10_000);
  });

  it("rejects a reservation past the daily cap as daily_limit", async () => {
    const u = await newUser();
    await credit(env.DB, u, "grant", 100_000_000, `g:${u}`);
    expect((await reserve(env.DB, u, "d1", 60_000, 100_000)).ok).toBe(true);
    expect(await reserve(env.DB, u, "d2", 60_000, 100_000)).toEqual({ ok: false, reason: "daily_limit" });
    // Settling d1 cheaply frees up room under the cap.
    await settle(env.DB, u, "d1", 10_000);
    expect((await reserve(env.DB, u, "d3", 60_000, 100_000)).ok).toBe(true);
  });
});
