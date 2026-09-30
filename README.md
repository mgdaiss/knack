# Knack

A macOS app where skills are the product and the AI is plumbing. Read [SPEC.md](SPEC.md) first; working rules are in [CLAUDE.md](CLAUDE.md), decisions in [docs/DECISIONS.md](docs/DECISIONS.md).

```
app/        native macOS app (SwiftUI, macOS 14+)
  KnackCore/  platform-independent core + unit tests (Swift package)
  Knack/      app target: shell, screens, skills, assets
  project.yml XcodeGen spec for Knack.xcodeproj
cloud/      Knack Cloud: Cloudflare Worker + D1 (API contract: cloud/API.md)
design/     mockups and character art
scripts/    build.sh (Release archive)
```

## Status

| Milestone | State |
|---|---|
| M0 Project skeleton | Written. Not yet compiled on a Mac. |
| M1 Runtime | Built; core unit-tested on Linux (manifests, tiers, `ModelProvider` contract, usage log). |
| M1b Knack Cloud | Built and tested locally. Payments off: $1,000 starter credit per account. Not deployed. |
| M2 Say It Better | Written: ⌥Space panel, tones, Replace/Copy/Try again, AX + pasteboard fallback, opt-in "sounds like you". Engine and pasteboard restore unit-tested. |
| M3 Explain This | Written: ⌥E panel, "What this means for you", one follow-up. Engine unit-tested. |
| M4 Fridge Chef | Written: photo (drop / picker / iPhone), editable items, pantry, filters, three recipes, cook mode with timers. Pipeline tested with `Tests/KnackTests/Fixtures/fridge.jpg`. |
| M5 Home + Discover + ⌘K | Written: dashboard columns, catalog-driven Discover, skill detail/install, ⌘K routing (tested). |
| M6 Polish | Written: menu bar extra, empty states, character-voice errors, notarizing `scripts/build.sh`. |

Everything under `app/Knack/` (the SwiftUI/AppKit layer) has never been compiled: there was no Mac in the build environment. Expect a round of compile fixes on first open in Xcode.

## Knack Cloud

```sh
cd cloud
npm install --legacy-peer-deps
npm test                         # ledger, auth, generate (runs in workerd via Miniflare)
cp .dev.vars.example .dev.vars   # add your OpenRouter key
npm run db:migrate:local
npm run dev                      # http://localhost:8787
```

Deploy to staging:

```sh
npx wrangler d1 create knack-staging          # put the ID in wrangler.toml [env.staging]
npm run db:migrate:staging
npx wrangler secret put OPENROUTER_API_KEY --env staging
npm run deploy:staging
```

## App

Needs Xcode 16+ and XcodeGen (`brew install xcodegen`).

```sh
cd app
xcodegen generate
open Knack.xcodeproj    # run the Knack scheme (Debug talks to http://localhost:8787)
```

Debug builds show **Use a test account** on the sign-in screen, and Settings has a **Developer** card to test streaming (optionally straight to OpenRouter with your own key). Core tests run anywhere:

```sh
cd app/KnackCore && swift test
```
