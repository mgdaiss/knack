import { ApiError } from "./errors";
import { base64urlDecode } from "./util";

// Verifies a Sign in with Apple identity token (RS256 JWT) against Apple's published keys.

const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";

interface Jwk extends JsonWebKey {
  kid: string;
}

let cachedKeys: { keys: Jwk[]; fetchedAt: number } | null = null;
const KEY_TTL_MS = 60 * 60 * 1000;

export function resetAppleKeyCache() {
  cachedKeys = null;
}

async function appleKeys(forceRefresh = false): Promise<Jwk[]> {
  if (!forceRefresh && cachedKeys && Date.now() - cachedKeys.fetchedAt < KEY_TTL_MS) {
    return cachedKeys.keys;
  }
  const res = await fetch(APPLE_KEYS_URL);
  if (!res.ok) throw new ApiError("internal", "Couldn't reach Apple to verify sign-in.");
  const body = (await res.json()) as { keys: Jwk[] };
  cachedKeys = { keys: body.keys, fetchedAt: Date.now() };
  return body.keys;
}

export interface AppleClaims {
  sub: string;
  iss: string;
  aud: string;
  exp: number;
  iat: number;
}

export async function verifyAppleIdentityToken(token: string, audiences: string[]): Promise<AppleClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new ApiError("unauthorized", "That sign-in didn't work.");
  const [h, p, s] = parts;
  let header: { alg?: string; kid?: string };
  let claims: AppleClaims;
  try {
    header = JSON.parse(new TextDecoder().decode(base64urlDecode(h)));
    claims = JSON.parse(new TextDecoder().decode(base64urlDecode(p)));
  } catch {
    throw new ApiError("unauthorized", "That sign-in didn't work.");
  }
  if (header.alg !== "RS256" || !header.kid) throw new ApiError("unauthorized", "That sign-in didn't work.");

  let jwk = (await appleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) jwk = (await appleKeys(true)).find((k) => k.kid === header.kid);
  if (!jwk) throw new ApiError("unauthorized", "That sign-in didn't work.");

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64urlDecode(s),
    new TextEncoder().encode(`${h}.${p}`),
  );
  if (!valid) throw new ApiError("unauthorized", "That sign-in didn't work.");

  const nowSec = Math.floor(Date.now() / 1000);
  if (claims.iss !== APPLE_ISSUER) throw new ApiError("unauthorized", "That sign-in didn't work.");
  if (!audiences.includes(claims.aud)) throw new ApiError("unauthorized", "That sign-in didn't work.");
  if (typeof claims.exp !== "number" || claims.exp < nowSec - 60) {
    throw new ApiError("unauthorized", "That sign-in expired. Please try again.");
  }
  if (!claims.sub) throw new ApiError("unauthorized", "That sign-in didn't work.");
  return claims;
}
