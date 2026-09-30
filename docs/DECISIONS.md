# Decisions

Choices made while building, especially where SPEC §10 left something open or the spec had to bend.

## 2026-09-30 — Credit is on us, no payments

- **Starter credit:** $1,000 per account, granted once on first sign-in (`STARTER_CREDIT_USD`). Effectively unlimited for a household; still a hard ceiling per account.
- **No top-ups, no Stripe.** `POST /v1/credit/checkout` and `POST /v1/stripe/webhook` are not implemented. The ledger schema already has a `topup` row kind and a unique `external_ref`, so adding idempotent Stripe webhooks later needs no migration. `/v1/me` returns `payments.enabled: false` and Settings shows "on us" instead of a Top up button.
- **Margin:** 0 (`PRICE_MARGIN`). Users are charged exactly the model cost OpenRouter reports.
- **Guardrails kept**, because we pay the bill: reserve-then-settle per run (capped at each skill's `maxCostPerRunUSD`), a **$10/day per-user cap** (`DAILY_SPEND_CAP_USD`), 30 requests/minute per user, and a per-model kill switch (`DISABLED_MODELS`). All are config, not code.

## 2026-09-30 — Backend stack

Cloudflare Workers + D1 (SPEC default). Balances are integer micro-dollars. Session tokens are opaque random strings stored as SHA-256 hashes (access 1 h, refresh 60 days, rotating).

`POST /v1/auth/dev` (off unless `ALLOW_DEV_AUTH=true`) lets staging and Debug builds sign in with a per-Mac test account before Sign in with Apple is provisioned.

## 2026-09-30 — Model tiers

Picked from current low-cost OpenRouter models. They live in `cloud/config/tiers.json` (production) and `app/Knack/Resources/ModelTiers.json` (DEBUG direct provider only); a unit test keeps them in sync.

| Tier | Model |
|---|---|
| `text-fast` | `google/gemini-2.5-flash-lite` |
| `text-smart` | `anthropic/claude-haiku-4.5` |
| `vision-fast` | `google/gemini-2.5-flash` |

Model IDs and prices weren't verifiable from the build environment (no access to openrouter.ai). Check them against https://openrouter.ai/models before the first staging deploy. If OpenRouter omits `usage.cost`, the server falls back to the per-token prices in the config.

## 2026-09-30 — Project layout

- `app/KnackCore/` is a Swift package with everything that doesn't need AppKit/SwiftUI: manifests, `PermissionCatalog`, `SkillContext`, `ModelRouter`, both providers, the Knack Cloud client, usage log and structured-output decoding. It builds and tests on Linux too.
- Unit tests live in `app/KnackCore/Tests/KnackTests/` (CLAUDE.md asks for `KnackTests/`). The Xcode scheme's test action runs them.
- `app/project.yml` is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec; the `.xcodeproj` is generated, not committed. XcodeGen is a build tool, not an app dependency.
- Fridge Chef tiers: the manifest has one tier (`vision-fast`). The recipe (text-only) call uses the same tier, since `model.vision` also covers text-only calls. That avoids adding `model.text` to a skill that doesn't read your text.
- `skill.json` manifests stay in each skill's folder and are copied into `Knack.app/Contents/Resources/Skills/<Skill>/skill.json` by a build phase.
- Debug builds are ad-hoc signed without the Sign in with Apple entitlement so they run without a team; use "Use a test account". Release builds carry the entitlement.

## 2026-09-30 — M2–M6 build choices

- **Skill engines live in KnackCore** (`Sources/KnackCore/Skills/`, `Routing/`): prompt building, response parsing, the Fridge Chef pipeline and ⌘K routing are plain Swift so they're unit-tested. Each skill's UI stays in `app/Knack/Skills/<Skill>/`.
- **`Skill.handleRoute` takes an `AskRoute`** (skill ID, input, optional tone) instead of a bare string, so "make this nicer: …" can pre-select the tone.
- **Panel focus order:** the panel is shown without becoming key, the selection is read (so a ⌘C fallback reaches the source app), then the panel takes key. On Replace it hides first so ⌘V lands in the source app.
- **From ⌘K, Say It Better copies instead of replacing** — there's no selection to replace.
- **⌘K routing:** deterministic first (colon patterns, route-example overlap), then a tiny `text-fast` call as `com.knack.router` that may only pick an installed skill. It never answers the question.
- **"Sounds like you" is opt-in** (Settings ▸ Privacy), keeps up to 40 of the user's own originals on this Mac, and is never used for "Fix typos only".
- **Fridge Chef photos** are downsized to 1600 px and re-encoded as JPEG (drops EXIF/GPS) before sending. The recipe call sends only item names.
- **Continuity Camera** uses SwiftUI's `ImportFromDevicesCommands` + `importsItemProviders` (File ▸ Import from iPhone); there's no public API for a one-click in-window button.
- **Needs you / Tonight** are static in Phase 1, as the spec allows. "This week" counts come from the local usage log.
- **Menu bar icon** is an SF Symbol for now; swap in a template version of the logo glyph when design provides one.
- **Sample fridge photo** (`fridge.jpg`) is a generated illustration, not a real photo — the build environment couldn't download images. Replace it with a real one for a meaningful live vision test.
