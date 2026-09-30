# Knack — Product & Build Spec

> Handoff for Claude Code. Read this whole file before writing code. Design references live in `design/`.
> When something here is ambiguous, ask before building. Don't guess.

## 1. What we're building

Knack is a **macOS app where skills are the product and the AI is plumbing.**

People don't install "an AI." They install **helpers**. Each helper is a small, friendly character that does one job, like Say It Better, Fridge Chef or Bedtime Stories. Each helper has its own purpose-built UI, not a chat box. The language model underneath is a commodity routed through OpenRouter. Users never pick a model.

**Audience:** non-technical consumers, especially busy households.
**Platform:** macOS 14+ (Sonoma), Apple Silicon first. Distributed **outside the Mac App Store** (Developer ID + notarization), because we need Accessibility APIs and, later, per-skill app shims.

### Product principles
1. **Skill first, agent second.** Every feature should make a skill better. The text agent only routes (⌘K) and never becomes the main UI.
2. **No prompting.** Each skill gets a user to a result in one or two taps or a hotkey. If a user has to write a prompt, the skill is unfinished.
3. **Scoped trust.** Each skill declares exactly what it can touch, and that's shown before install. Send the model only the minimum data the task needs.
4. **Characters, not icons.** First-party skills have a character. Long-tail skills get a "blob buddy" until they graduate.
5. **Cheap-model friendly.** Script deterministic steps in code. Call the LLM only at decision or generation points.

## 2. Scope by phase

### Phase 1 — MVP (build this first)
- Host app: window with **Home** and **Discover**, plus a **menu bar extra**.
- Skill runtime: manifest loading, permission display, a model router over OpenRouter, and usage/cost tracking.
- Three skills:
  - **Say It Better** (global hotkey ⌥Space, works in any app)
  - **Explain This** (global hotkey ⌥E, works in any app)
  - **Fridge Chef** (photo in, three dinner ideas out, then a step-by-step cook mode)
- ⌘K "Ask anything" bar that routes a sentence to the right installed skill with the input pre-filled. It does not answer freely.
- **Knack Cloud proxy (§3.2):** users never see an API key. They sign in, get starter credit, and top up prepaid credit.
- Onboarding: Sign in with Apple → starter credit granted → Accessibility permission walkthrough → hotkey setup.

### Phase 2
- **Bedtime Stories** (text generation, then on-device TTS via AVSpeechSynthesizer first and a premium voice later; illustrations via an image model later)
- **The Decider**, **Form Filler** (fillable PDFs via PDFKit), **Paperwork Filer**, **Tidy My Mac**
- Per-skill **app shims** in `~/Applications/Knack Apps/` (see §6)
- Home dashboard cards published by skills ("Needs you", "Tonight")

### Phase 3
- Third-party and user-made skills (sandboxed, see §4.3), the skill maker agent, and the blob buddy tier

**Out of scope for now:** subscriptions (prepaid credit only), sync, family sharing, and an iOS companion.

## 3. Architecture

```
Knack.app (SwiftUI, non-sandboxed, Developer ID)
├── App shell        Home, Discover, Settings, onboarding, MenuBarExtra
├── SkillRegistry    loads manifests, install/uninstall state, permissions
├── SkillRuntime     runs a skill, provides services (below)
│   ├── ModelRouter      calls Knack Cloud with an abstract tier, streams results, local usage log
│   ├── HotkeyService    global shortcuts (use sindresorhus/KeyboardShortcuts)
│   ├── SelectionService read/replace selected text in the frontmost app (§5.1)
│   ├── ImageInput       drag-drop, file picker, Continuity Camera import
│   ├── Notifications    UNUserNotificationCenter
│   └── CardFeed         skills publish Home cards (Phase 2)
├── Skills/          first-party skills as Swift modules conforming to `Skill`
└── Storage          Application Support/Knack (JSON or SwiftData), session token in Keychain

Knack Cloud (backend proxy, §3.2)
├── Auth             Sign in with Apple → short-lived session tokens
├── Credit ledger    prepaid balance per user, starter grant, top-ups via Stripe Checkout
├── Model gateway    tier → OpenRouter model, holds the OpenRouter key, streams back, meters cost
└── Guardrails       per-run cost caps, per-user rate limits, abuse flags
```

### 3.1 Tech choices
- Swift 5.10+ / Swift 6 where practical, SwiftUI, Observation (`@Observable`).
- Swift Package Manager dependencies, kept minimal: `KeyboardShortcuts` (hotkeys) and nothing else without asking.
- Networking: `URLSession` + `async/await`. The app talks **only to Knack Cloud**, never to OpenRouter directly in production.
- The Knack session token is stored in the **Keychain**, never in UserDefaults or logs. The app never holds the OpenRouter key.
- `ModelRouter` sits behind a `ModelProvider` protocol with two implementations: `KnackCloudProvider` (default, all builds) and `DirectOpenRouterProvider` (**DEBUG builds only**, reads a developer key from the Keychain, for local development before the backend exists).
- Fonts: **Nunito** (SIL OFL), bundled in the app. Register it via `ATSApplicationFontsPath` or at runtime.

### 3.2 Knack Cloud (backend proxy), the default for all users

**Why:** non-technical consumers won't create an OpenRouter account or paste API keys. They get starter credit and top up like a prepaid phone plan. The proxy also lets us change models, enforce cost caps and stop abuse without shipping an app update.

**Endpoints (v1)**

| Endpoint | Purpose |
|---|---|
| `POST /v1/auth/apple` | Exchange a Sign in with Apple identity token for a Knack session token (refreshable). Grant starter credit on first sign-in. |
| `GET /v1/me` | Account, credit balance, and this month's usage. |
| `POST /v1/generate` | Body: `{ skillId, tier, messages, responseFormat?, stream }`. Checks balance and the skill's `maxCostPerRunUSD`, maps tier → model, calls OpenRouter, streams via SSE, then debits the actual cost. |
| `POST /v1/credit/checkout` | Create a Stripe Checkout session for a top-up amount and return its URL (opened in the browser). |
| `POST /v1/stripe/webhook` | On successful payment, credit the ledger (idempotent on the Stripe event ID). |

**Rules**
- **Ledger, not a balance field.** Credits and debits are append-only rows. The balance is their sum, and each debit is tied to a `generate` request ID.
- **Pre-authorize, then settle.** Before calling the model, reserve the skill's `maxCostPerRunUSD`. After the call, settle to actual cost and release the rest. Reject with a friendly "out of credit" error if the reservation fails.
- **Pricing:** users pay the model cost plus a margin. The margin and top-up amounts are config values, not code. Show balances in dollars, and show the per-run cost estimate on install screens.
- **Tier → model mapping lives on the server** in config, so models can change without an app release. Skills and the app only know tiers.
- **Privacy:** don't store prompt or response content. Log only metadata: user, skill, tier, model, tokens, cost, latency and status.
- **Guardrails:** per-user rate limits, a daily spend cap per user (configurable), and a global kill switch per model.
- **Stack:** default is a small TypeScript service on **Cloudflare Workers + D1** (or Postgres) with Stripe. If you already run infrastructure elsewhere, confirm before starting (see §10).

**App side**
- Settings shows the balance, a "Top up" button (opens Stripe Checkout in the browser, then refreshes `/v1/me` on return via the `knack://` URL scheme), and usage by helper.
- Low balance (< $1) shows a friendly Home card: "Running low on credit. Top up to keep your helpers going."
- Error states are in character voice, and the app never shows raw HTTP errors.

### 3.3 The `Skill` protocol (first-party)

```swift
protocol Skill: Identifiable {
    static var manifest: SkillManifest { get }      // mirrors skill.json
    @MainActor func makeMainView(context: SkillContext) -> AnyView   // the applet window
    func handleHotkey(context: SkillContext) async   // optional, for hotkey skills
    func handleRoute(input: String, context: SkillContext) async  // from ⌘K
}
```

`SkillContext` gives a skill **only** the services its manifest declares. For example, Fridge Chef gets `ImageInput` and `ModelRouter`, not `SelectionService`. Enforce this in the runtime, not by convention.

## 4. Skill package format

### 4.1 Manifest (`skill.json`)

```json
{
  "id": "com.knack.fridge-chef",
  "name": "Fridge Chef",
  "tagline": "Snap your fridge. Three dinners you can make tonight.",
  "character": { "asset": "fridge-chef", "color": "#E06A4E", "tint": "#FBE0D8" },
  "category": "home",
  "permissions": ["image.input", "model.vision", "notifications"],
  "never": ["files.read", "email.read", "network.other"],
  "triggers": [{ "type": "window" }, { "type": "route", "examples": ["what's for dinner", "what can I cook"] }],
  "model": { "tier": "vision-fast", "maxCostPerRunUSD": 0.02 },
  "version": "1.0.0"
}
```

- `permissions` / `never` are shown verbatim, in friendly words, on the install screen (see `design/Skill-Detail.dc.html`).
- `model.tier` is an **abstract tier** (`text-fast`, `text-smart`, `vision-fast`). `ModelRouter` maps tiers to concrete OpenRouter model IDs from one config file, so models can change without touching skills. Pick current low-cost models at build time and put them in config. Don't hardcode model IDs in skills.

### 4.2 Permission vocabulary (Phase 1)
`selection.read`, `selection.replace`, `image.input`, `model.text`, `model.vision`, `notifications`. Add new ones only in `PermissionCatalog.swift`, each with a user-facing sentence.

### 4.3 Third-party skills (Phase 3, design only for now)
The plan is declarative manifest + prompt templates + an HTML/JS UI running in a `WKWebView` with a narrow message bridge to the runtime services. No arbitrary native code. Don't build this in Phase 1, but keep `SkillContext` service-shaped so the bridge can wrap it later.

## 5. Phase 1 skills in detail

### 5.1 Say It Better (⌥Space)
**Flow:** the user selects text in any app → presses ⌥Space → a floating panel appears near the cursor → tone chips (Firmer but friendly, Nicer, Shorter, Funnier, More formal, Fix typos only) → the rewrite appears → Replace (↵), Copy, or Try again. Esc closes the panel.

**Implementation notes**
- The panel is a borderless, non-activating `NSPanel` (`.nonactivatingPanel`, floating level) so the source app keeps focus for replacement.
- **Reading the selection:** try Accessibility first (`AXUIElementCopyAttributeValue` with `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`). If that fails (common in Electron and web apps), fall back to saving the pasteboard, synthesizing ⌘C, reading the text, then restoring the pasteboard.
- **Replacing:** try setting `kAXSelectedTextAttribute`. On failure, save the pasteboard, write the rewrite, synthesize ⌘V, then restore the pasteboard.
- Requires the Accessibility permission. Onboarding must walk the user through System Settings → Privacy & Security → Accessibility, then detect when it's granted (`AXIsProcessTrusted`).
- Only the selected text and the chosen tone are sent to the model.
- **Phase 1.5 (voice learning):** keep up to N of the user's own original texts locally as few-shot "style samples," with explicit opt-in. The panel footer then shows "Sounds like you: learned from N messages."

**Acceptance criteria**
- Works in at least Mail, Notes, Messages, Slack (Electron) and Safari text fields.
- Time from hotkey to panel visible is under 150 ms. The first rewrite streams, and text starts appearing in under 1.5 s on a fast tier.
- The pasteboard is always restored, including on error or cancel.

Design: `design/Say-It-Better.dc.html`

### 5.2 Explain This (⌥E)
Same selection pipeline as Say It Better. The panel shows a plain-English explanation, then "What this means for you" when relevant, then a follow-up field for one clarifying question. If there's no text selection, capture the region under the cursor instead. That's Phase 1.5 and needs the Screen Recording permission, so text selection comes first.

### 5.3 Fridge Chef
**Flow:** Home or window → add a photo (drag-drop, file picker, or "Take photo with iPhone" via Continuity Camera) → a **vision call** detects items and returns structured JSON → the user can fix items (chips) and add pantry staples → a **text call** generates three recipes as structured JSON → filters (Under 30 min, Kid friendly, Vegetarian, Use it up first, Serves N) → **Cook mode**: one large step at a time with built-in timers.

**Structured outputs:** define Swift `Codable` types (`DetectedItem`, `Recipe`, `RecipeStep`) and request JSON matching them. Validate the response, and retry once on a parse failure. Dish photos are Phase 2, so use a character-illustrated placeholder card for now.

Design: `design/Fridge-Chef.dc.html`

## 6. Per-skill app shims (Phase 2)
On install, write `~/Applications/Knack Apps/<Skill Name>.app`, a tiny launcher bundle with the skill's character as its icon. Opening it calls `knack://open/<skill-id>`, which brings up that skill's window with its own Dock and ⌘-Tab presence. The bundle is created locally and ad-hoc signed (`codesign -s -`). Uninstalling the skill deletes the shim. This is the same pattern Chrome and Safari use for web apps. **Spike this early in Phase 2** to confirm Gatekeeper and Launchpad behavior on current macOS.

## 7. Design system: "Little Characters" (direction E)

Source of truth: `design/Home.dc.html`, `design/Main.dc.html` (Discover), `design/Visual-Directions.dc.html` (column E). The canvas files are HTML mockups, so read their inline styles for exact values. They won't render standalone.

**Tokens**

| Token | Value |
|---|---|
| bg | `#FDF3E7` (cream) |
| sidebar | `#F7E8D6` |
| surface | `#FFFFFF` |
| ink | `#1B1A17` |
| muted | `#6B6259` |
| hairline | `#F3E6D6` |
| accent-indigo | `#5B61C9` / pressed `#4A4FB0` |
| accent-coral | `#E06A4E` |
| danger badge | `#E0463A` |
| font | Nunito 600/700/800/900 |
| radius | cards 24, big cards 26, hero 30, character tiles 22–24 (64–72 pt), pills fully round |
| shadow | `0 6 16 rgba(120,80,40,0.08)`; character tiles `0 6 14 rgba(120,80,40,0.16)` |

**Character colors** (tile background / light tint for cards)

| Skill | Tile | Tint |
|---|---|---|
| Say It Better | `#5B61C9` | `#EEF0FB` |
| Explain This | `#1E7A74` | `#D8EFEC` |
| Fridge Chef | `#E06A4E` | `#FBE0D8` |
| Bedtime Stories | `#3A2F5C` | `#E6E1F2` |
| The Decider | `#2F8F6B` | `#DCEFE5` |
| Form Filler | `#D99A2B` | `#FBEBD0` |
| Paperwork | `#4F8FC0` | `#DDEBF6` |
| Tidy My Mac | `#E8839B` | `#FBE1E8` |

- Character art is in `design/characters/*.svg` (64×64 viewBox, including the tile). Import it into the asset catalog as vector assets and preserve the vector data.
- **Blob buddies** (long-tail skills) are a 32 pt circle in a pastel color with two 5 pt ink eyes. Generate them in code from the skill's color.
- Copy voice: warm and short. "Your helpers," "Meet more," "Fridge Chef says…," "Someone new to meet." Characters speak in first person on cards.
- Accessibility: every character image gets an accessibility label (the skill name). Keep text contrast at 4.5:1 or better, and don't put muted text on tinted cards without checking contrast.

## 8. Screens (Phase 1)

1. **Home** (`design/Home.dc.html`): greeting and ⌘K ask bar, a "Your helpers" launcher grid with badges, and three dashboard columns. In Phase 1, "Needs you" and "Tonight" can show static or empty states, and "This week" shows real counts from the usage log.
2. **Discover** (`design/Main.dc.html`): hero skill, "Start here" cards, and "More to try" blob pills. Phase 1 catalog is a bundled JSON file, and not-yet-built skills show "Coming soon."
3. **Skill detail / install** (`design/Skill-Detail.dc.html`, restyle to E): tagline, how it works, a permission card listing "can" and "never," AI cost, and an "Allow & install" button.
4. **Settings:** account, credit balance and Top up, hotkeys, per-skill enable/disable, usage by helper, and privacy (clear style samples, clear history).
5. **Menu bar extra:** installed helpers, hotkey hints, open Home, and quit.

The life-admin mockups (`Form-Filler`, `Paperwork-Filer`, `Tidy-My-Mac`) use the old visual style. Use them for layout and flow only, and restyle them in Phase 2.

## 9. Milestones & acceptance

| # | Milestone | Done when |
|---|---|---|
| M0 | Project skeleton | Xcode project builds and runs. App shell with sidebar (Home, Discover, Settings), design tokens in `Theme.swift`, Nunito loaded, characters in assets |
| M1 | Runtime | `SkillRegistry` loads bundled manifests. `ModelRouter` streams through `DirectOpenRouterProvider` (DEBUG) and logs usage per run. Unit tests for manifest parsing and the `ModelProvider` contract |
| M1b | Knack Cloud | Backend deployed to a staging environment. Sign in with Apple → starter credit → `/v1/generate` streams with reserve/settle debits → Stripe test-mode top-up credits the ledger. The app uses `KnackCloudProvider` by default and shows balance and Top up in Settings. Tests for ledger math, idempotent webhooks and out-of-credit handling |
| M2 | Say It Better | Meets the §5.1 acceptance criteria. Onboarding covers Accessibility |
| M3 | Explain This | Selection-based flow works in the same apps as M2 |
| M4 | Fridge Chef | Photo to three recipes to cook mode, end to end, with structured JSON and a retry. Works with a sample fridge photo in `Tests/Fixtures` |
| M5 | Home + Discover + ⌘K | Screens match the design within reason. ⌘K routes "what's for dinner" to Fridge Chef and "make this nicer: …" to Say It Better |
| M6 | Polish | Menu bar extra, empty states, errors in character voice, notarized build script |

Work milestone by milestone. At the end of each one, run the app, list what was verified, and stop for review.

## 10. Open questions (ask before deciding)
1. **Decided:** Knack Cloud proxy with prepaid credit is the default for all users (§3.2). Direct OpenRouter keys exist only in DEBUG builds. Still open: starter credit amount, top-up amounts, margin, and the backend stack (default Cloudflare Workers + D1 + Stripe).
   - **Decided (2026-09-30):** no payments for now — Knack foots the bill. Every account gets a large starter grant ($1,000, `STARTER_CREDIT_USD`), margin is 0, and Stripe checkout/webhooks are deferred (the ledger keeps a `topup` kind so they can be added later). Guardrails stay on: per-run reservation, a $10/day per-user cap (`DAILY_SPEND_CAP_USD`) and rate limits. Stack: Cloudflare Workers + D1. See `docs/DECISIONS.md`.
2. Final app name and bundle ID. "Knack" is a working name.
3. Minimum macOS version: 14 assumed.
4. Analytics: none in the MVP unless decided otherwise.
