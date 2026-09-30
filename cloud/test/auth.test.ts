import { afterEach, describe, expect, it, vi } from "vitest";
import { APPLE_KEYS_URL, resetAppleKeyCache } from "../src/apple";
import { base64url } from "../src/util";
import { call, devSignIn } from "./helpers";

async function appleKeypair() {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  return { pair, jwk: { ...jwk, kid: "test-kid", alg: "RS256", use: "sig" } };
}

async function signToken(key: CryptoKey, claims: Record<string, unknown>, kid = "test-kid") {
  const enc = (o: unknown) => base64url(new TextEncoder().encode(JSON.stringify(o)));
  const head = enc({ alg: "RS256", kid });
  const body = enc(claims);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${base64url(new Uint8Array(sig))}`;
}

function mockAppleKeys(jwk: unknown) {
  const real = globalThis.fetch;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url === APPLE_KEYS_URL) return Response.json({ keys: [jwk] });
    return real(input, init);
  });
}

afterEach(() => {
  vi.restoreAllMocks();
  resetAppleKeyCache();
});

describe("auth", () => {
  it("Sign in with Apple creates a user with starter credit once", async () => {
    const { pair, jwk } = await appleKeypair();
    mockAppleKeys(jwk);
    const claims = {
      iss: "https://appleid.apple.com",
      aud: "com.knack.app",
      sub: `apple-${crypto.randomUUID()}`,
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 600,
    };
    const token = await signToken(pair.privateKey, claims);

    const first = await call("POST", "/v1/auth/apple", { identityToken: token });
    expect(first.status).toBe(200);
    const a = (await first.json()) as any;
    expect(a.user.isNew).toBe(true);

    const second = await call("POST", "/v1/auth/apple", { identityToken: token });
    const b = (await second.json()) as any;
    expect(b.user).toEqual({ id: a.user.id, isNew: false });

    const me = (await (await call("GET", "/v1/me", undefined, b.accessToken)).json()) as any;
    expect(me.balanceUSD).toBe(1000);
    expect(me.payments.enabled).toBe(false);
  });

  it("rejects tokens with the wrong audience, a bad signature or an expiry in the past", async () => {
    const { pair, jwk } = await appleKeypair();
    const other = await appleKeypair();
    mockAppleKeys(jwk);
    const base = {
      iss: "https://appleid.apple.com",
      aud: "com.knack.app",
      sub: "apple-x",
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 600,
    };
    for (const token of [
      await signToken(pair.privateKey, { ...base, aud: "com.evil.app" }),
      await signToken(other.pair.privateKey, base),
      await signToken(pair.privateKey, { ...base, exp: Math.floor(Date.now() / 1000) - 3600 }),
      "not-a-jwt",
    ]) {
      const res = await call("POST", "/v1/auth/apple", { identityToken: token });
      expect(res.status).toBe(401);
      expect(((await res.json()) as any).error.code).toBe("unauthorized");
    }
  });

  it("refresh rotates the refresh token", async () => {
    const s = await devSignIn();
    const r1 = await call("POST", "/v1/auth/refresh", { refreshToken: s.refreshToken });
    expect(r1.status).toBe(200);
    const t = (await r1.json()) as any;
    expect((await call("GET", "/v1/me", undefined, t.accessToken)).status).toBe(200);
    // The old refresh token is now spent.
    expect((await call("POST", "/v1/auth/refresh", { refreshToken: s.refreshToken })).status).toBe(401);
  });

  it("requires a valid bearer token", async () => {
    expect((await call("GET", "/v1/me")).status).toBe(401);
    expect((await call("GET", "/v1/me", undefined, "nope")).status).toBe(401);
  });
});
