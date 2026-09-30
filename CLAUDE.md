# CLAUDE.md — working rules for this repo

## Context
- The product spec is in `SPEC.md`. It is the source of truth. Read it fully at the start of every session.
- Visual reference is in `design/`. The `.dc.html` files are HTML mockups (they don't render standalone), so read inline styles for exact colors, sizes and copy. Character art is in `design/characters/`.
- Target: native macOS app in SwiftUI, macOS 14+, non-sandboxed, Developer ID distribution, plus a small backend proxy ("Knack Cloud", SPEC §3.2).
- Repo layout: `app/` (Xcode project) and `cloud/` (backend). Keep them independent. They share only the API contract, documented in `cloud/API.md`.

## How to work
- Build one milestone at a time (SPEC §9). Before coding a milestone, write a short plan: the files you'll add or change and how you'll verify it. Then build.
- After each milestone: build, run, verify the acceptance criteria, then summarize what works, what doesn't, and anything you had to assume. Stop for review.
- Ask when the spec is ambiguous or when a decision is in SPEC §10. Don't silently pick.
- Prefer small, focused files. One skill per folder under `Knack/Skills/<SkillName>/`.

## Code conventions
- Swift + SwiftUI, `@Observable`, `async/await`. No Combine unless required by an API.
- All colors, fonts, radii and shadows come from `Theme.swift`. Never hardcode hex values in views.
- Skills get services only through `SkillContext`, and only the services their manifest permits. Don't reach around it.
- Model calls go through `ModelRouter` with an abstract tier. Never hardcode model IDs in skills.
- Secrets: the app keeps only the Knack session token, in the Keychain. The OpenRouter key and Stripe secrets live only in backend environment secrets, never in the repo or the app. Never log prompts containing user text at info level or above, in the app or the backend.
- Money: credit is an append-only ledger with reserve-then-settle debits and idempotent Stripe webhooks. Use Stripe test mode until told otherwise.
- Structured LLM output: decode into `Codable` types, validate, and retry once on a parse failure.

## Dependencies
- Allowed: `sindresorhus/KeyboardShortcuts`.
- Ask before adding anything else.

## Build & run
- Use `xcodebuild` for CI-style builds. Keep a `scripts/build.sh` that builds a Release archive.
- Unit tests go in `KnackTests/`. At minimum: manifest parsing, tier mapping, recipe JSON decoding, pasteboard save/restore.

## Don'ts
- No Mac App Store–only APIs or entitlements. We ship outside the store.
- No chat-box UI as a skill's main interface.
- Don't send more user data to the model than the task needs. For example, Say It Better sends only the selected text.
