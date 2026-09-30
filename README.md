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
| M0 Project skeleton | Built. Needs a first run on a Mac (see below). |
| M1 Runtime | Built and unit-tested (manifests, tiers, `ModelProvider` contract, usage log). |
| M1b Knack Cloud | Built and tested locally. Payments intentionally off: $1,000 starter credit per account. Not yet deployed. |
| M2–M6 | Not started. |

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
