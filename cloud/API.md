# Knack Cloud API (v1)

The only contract shared between `app/` and `cloud/`. All bodies are JSON unless noted.
Money is always US dollars as a JSON number.

## Errors

Every non-2xx response has this shape:

```json
{ "error": { "code": "out_of_credit", "message": "You're out of credit." } }
```

| code | HTTP | When |
|---|---|---|
| `bad_request` | 400 | Malformed body |
| `unauthorized` | 401 | Missing, expired or revoked access token, or a bad sign-in token |
| `not_found` | 404 | Unknown route (also `/v1/auth/dev` when dev auth is off) |
| `unknown_skill` | 400 | `skillId` isn't in the server's skill config |
| `tier_not_allowed` | 403 | The skill can't use that tier, or images were sent to a text tier |
| `out_of_credit` | 402 | Balance can't cover the skill's `maxCostPerRunUSD` |
| `daily_limit` | 429 | The per-user daily spend cap would be exceeded |
| `rate_limited` | 429 | Too many requests in the last minute |
| `model_unavailable` | 503 | Model disabled by kill switch, or the provider failed |
| `internal` | 500 | Anything else |

The app maps `code` to a message in the helper's own voice. It never shows `message` or HTTP details raw.

## Auth

Access tokens live 1 hour. Refresh tokens live 60 days and rotate on every use.

### `POST /v1/auth/apple`
```json
{ "identityToken": "<Sign in with Apple JWT>" }
```
→ `200`
```json
{ "accessToken": "…", "refreshToken": "…", "expiresIn": 3600, "user": { "id": "uuid", "isNew": true } }
```
Starter credit is granted exactly once per account, on first sign-in.

### `POST /v1/auth/dev` (staging only, when `ALLOW_DEV_AUTH=true`)
```json
{ "deviceId": "8–64 chars of [A-Za-z0-9-]" }
```
→ same as `/v1/auth/apple`.

### `POST /v1/auth/refresh`
```json
{ "refreshToken": "…" }
```
→ `200 { "accessToken", "refreshToken", "expiresIn" }`. The presented refresh token is revoked.

All other endpoints need `Authorization: Bearer <accessToken>`.

## `GET /v1/me`
```json
{
  "user": { "id": "uuid" },
  "balanceUSD": 999.87,
  "month": {
    "runs": 42,
    "spentUSD": 0.13,
    "bySkill": [{ "skillId": "com.knack.say-it-better", "runs": 40, "spentUSD": 0.11 }]
  },
  "limits": { "dailyCapUSD": 10, "dailySpentUSD": 0.02 },
  "payments": { "enabled": false }
}
```

## `POST /v1/generate`
```json
{
  "skillId": "com.knack.say-it-better",
  "tier": "text-fast",
  "messages": [
    { "role": "system", "content": "…" },
    { "role": "user", "content": "…" }
  ],
  "responseFormat": { "type": "json_object" },
  "stream": true
}
```
- `tier` is one of `text-fast`, `text-smart`, `vision-fast`. The server maps it to a model (`config/tiers.json`).
- `content` is a string, or an array of `{ "type": "text", "text" }` and `{ "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,…" } }` parts. Images need a vision tier.
- `responseFormat` is passed through to the model (OpenAI-style `json_object` / `json_schema`).
- The server reserves the skill's `maxCostPerRunUSD` (`config/skills.json`) before calling the model, then settles to the actual cost.

**`stream: false`** → `200`
```json
{
  "requestId": "uuid",
  "text": "…",
  "usage": { "promptTokens": 30, "completionTokens": 12 },
  "costUSD": 0.000123,
  "balanceUSD": 999.99
}
```

**`stream: true`** → `200 text/event-stream`, header `x-request-id`. Events:
```
event: delta
data: {"text":"Could you "}

event: done
data: {"requestId":"uuid","costUSD":0.0005,"balanceUSD":999.99,"usage":{"promptTokens":30,"completionTokens":6}}
```
or, if the model fails mid-stream, a final
```
event: error
data: {"error":{"code":"model_unavailable","message":"…"}}
```
Errors detected before the stream starts use the normal JSON error response.

## Payments

Off for now: every account starts with a large prepaid grant (`STARTER_CREDIT_USD`, default $1,000) and there is no top-up. The ledger already has a `topup` row kind, so `POST /v1/credit/checkout` and `POST /v1/stripe/webhook` (SPEC §3.2) can be added later without a schema change.

## `GET /v1/health`
→ `200 { "ok": true }`
