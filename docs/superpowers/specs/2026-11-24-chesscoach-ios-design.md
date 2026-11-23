# ChessCoach for iOS — Design

Date: 2026-11-24
Status: approved by owner 2026-11-24
Source app: ChessCoach web (Next.js + Stockfish WASM), repo `Xusniddin-devv/xq-chesscoach` (GitHub copy ends 2026-07-19; later rules are written into this doc — see "Rules carried over").

## Intent

Rebuild ChessCoach as a native iPhone app (SwiftUI) and ship it on the App Store as a paid-subscription product. It is a chess tutor for true beginners: play bots, get told in plain words why a move was bad, review games, drill puzzles, take lessons. The web app proved the product; the iOS app is the version people will actually install and pay for.

Why native: App Store distribution, real on-device Stockfish 18 (stronger and faster than WASM, offline, no 7 MB download), native feel (Liquid Glass, haptics), subscriptions through Apple.

## Goals

- Every web feature except multiplayer and the LLM coach, rebuilt natively.
- Runs fully on the phone: $0 running cost (only RevenueCat's revenue share), works offline except chess.com import.
- Explanations in plain English for beginners (describe moves in words, not SAN, below ~1200).
- A distinct, crafted visual identity — clearly not a chess.com or Lichess clone, and no "AI slop".
- Subscription revenue via RevenueCat.

## Non-goals (v1)

- Multiplayer / live games / ratings ladder / profiles of other users.
- LLM coach, coach chat, OpenRouter, any server-side AI.
- Android, web, iPad-specific layouts (iPhone only; portrait only).
- Accounts / login. No backend of our own.
- Ads.

## Anti-goals (failure even if it works)

- Looks like chess.com (green/cream board, green 3D buttons) or Lichess (brown/blue board).
- AI-slop look: gradients, purple/neon, emoji used as icons, generic SF-Symbol grids, centered hero + three feature cards, glassy everything, filler copy ("Unlock your potential").
- Any feature that costs money per user (paid APIs, owner API keys).
- Notation-heavy text a beginner can't read.
- Closed source (see License).

## Constraints

- **License: GPLv3, public repo.** Stockfish is GPLv3; shipping it inside the app requires the app's source to be public under GPLv3 (the Lichess iOS model). App must show a licenses screen with a link to the source repo and Stockfish's license. Do not name the app or any feature "Stockfish"; "Powered by Stockfish" is fine. All dependencies must be GPL-compatible (RevenueCat SDK = MIT ✓, chesskit-swift = MIT ✓).
- **iOS 26 minimum** (owner's call: real system Liquid Glass). Swift 6, SwiftUI, Xcode 26.6 (installed).
- **Dark only in v1** (owner chose a dark theme; light mode is later work).
- **No secrets in the repo.** RevenueCat *public* SDK key is designed to be public and may be committed.
- Repo location: `~/dev/chesscoach-ios` (my call).

## Approaches considered (how to build)

1. **Native Swift + ChessKit packages** (`chesskit-swift` rules, `chesskit-engine` = Stockfish 17 wrapper). Fastest, but SF17 and a small (~40★) dependency for the engine.
2. **Native Swift + our own Stockfish 18 engine module.** Full control of the engine, newest Stockfish; more low-level work up front.
3. **SwiftUI shell running the existing TypeScript logic in JavaScriptCore.** Fastest parity, but the core becomes a JS blob — hard to debug, not native.

**Chosen (owner): native Swift with Stockfish 18** — approach 2 for the engine, while still using `chesskit-swift` (MIT) for chess rules/SAN/FEN/PGN instead of writing move generation. `chesskit-engine` may be read as a reference for the C++ bridge pattern.

## Architecture

```
ChessCoach (app target, SwiftUI)
 ├─ Features/   Home · Play · Review · Freeplay · Puzzles · Learn · Profile · Paywall · Settings
 ├─ DesignSystem/  tokens, components, board view, piece assets
 ├─ Core/  (pure Swift, no UI, fully unit-tested)
 │   ├─ Analysis/   classifier, motifs, explanations (templates), accuracy, eval-bar geometry
 │   ├─ Training/   SRS (SM-2), rating estimate, weaknesses, streak, daily puzzle
 │   ├─ Content/    lessons (openings/endgames/checkmates), openings ECO lookup, puzzle bank
 │   ├─ Import/     chess.com public API
 │   └─ Voice/      speech → move parser
 ├─ Persistence/  SwiftData models (+ CloudKit private sync)
 └─ Packages/
     └─ StockfishKit (local SPM package): SF18 C++ source + thin bridge, Swift `actor Engine` speaking UCI
```

### Engine (StockfishKit)

- Stockfish 18 compiled from source into a local Swift package; C++ ↔ Swift via a small C/ObjC++ shim or Swift C++ interop (builder's choice). UCI runs on its own thread; Swift side is an `actor` exposing `analyze(startFen:moves:depth:multiPV:) async -> AnalysisResult` and `bestMove(...)`.
- **Two roles:** Opponent (strength-limited) and Analyst (full strength, MultiPV 2).
- **NNUE:** prefer the standard SF18 nets (big + small) for analysis strength; app size ~120 MB is acceptable (<200 MB cellular limit). Builder must measure on a real device (iPhone 13-class) depth reached in a 300 ms / depth-16 search, big+small vs small-only, and pick by results; record numbers in the repo.
- **Threads:** measure single vs multi-thread on the *real access pattern* (warm engine, sequential related positions, many short searches). On the web, threads made it slower. Pick by measurement.
- Rules carried over (all bugs we already paid for):
  - UCI is strictly serial: one `go` at a time per engine; queue requests.
  - Always send `position startpos|fen <start> moves …` with the full move history (repetition awareness), never a bare FEN of the current position.
  - Depths: live grading 16, bulk full-game review 14, "deep" analysis toggle 20. MultiPV 2 for grading (needed by classifier); note MultiPV 2 at low depth can hide mates — mate scores must be carried as mate, never flattened into centipawns.
  - Search reuse: cache last result keyed by `depth|startFen|moves` — position-after move N is position-before move N+1, so grading costs one search per move.
  - Bot pacing: weak levels return instantly; enforce think-time floor ~450 ms (600 Elo) → ~1.7 s (2300) with ±30% jitter, padding only when search finished early.
  - Strength: `UCI_LimitStrength`+`UCI_Elo` for ≥1320; below that `Skill Level` + depth limits (web mapping in `src/lib/engine/levels.ts`).

### Move classification (rules carried over — single source of truth)

One pure function `classifyPlayed(engine results before/after, position, move) -> Verdict`; used by live grading, bulk review and freeplay alike. No engine calls inside it.

11 classes, precedence: **forced → miss → brilliant → book → great → best → blunder → mistake → inaccuracy → excellent → good**.
- forced `→`: only one legal move.
- miss `✗`: mover had mate or ≥85% win chance, dropped below 70%.
- brilliant `!!`: a sacrifice that is still best or within 30 cp of best, from a non-crushing position, still ≥50% after. **Sacrifice** = the moved piece is left en prise *and* is worth more than what it captured (en passant counted). An even recapture (QxQ recapturable) is NOT brilliant — this was a real shipped bug.
- book: position in ECO opening table.
- Others by win-percentage loss with severity thresholds scaled by level (web: `src/lib/moveClass.ts`, `src/lib/analysis/classify.ts`).
- **Caveat:** the GitHub copy predates the 11-class rewrite (`src/lib/analysis/classifyPlayed.ts`, 2026-07-29). It has 8 classes with fixed 5/10/20 win%-loss cuts in `moveClass.ts` and a separate level-scaled cp system in `classify.ts`. The exact July numbers (great gap, "non-crushing" cut, win% formula, accuracy formula, level scaling) must come from the newest source — see Open items. Until then the GitHub values plus the rules written above are the baseline, locked by golden tests so changing a number is a deliberate act.
- **Level used for thresholds** (my call): the player's current estimated rating (default 800 for new players), recorded in the saved analysis together with `analysisVersion`. Saved analyses are *not* redone when the rating moves; only a version bump re-analyzes. Freeplay and imported games use the same rule.
- **Words vs notation** (my call): a setting "Show moves as: Words / Notation", default Words while the estimated rating is below 1200.
- Negative classes: inaccuracy, mistake, blunder, miss. Severity mapping must not fall through (a Miss is never banked as an inaccuracy).
- Verdict text must never say "Best instead was X" when X is the move played.
- Accuracy % per game (chess.com-style from win% loss).
- `analysisVersion` stored with saved analysis; bump it when rules change so old games re-analyze once.

### Explanations (no LLM)

Engine facts (best move, eval before/after, best line, mate info) + deterministic motif detector (hanging piece, fork, pin, missed mate, allowed mate, trapped piece, etc. — port `src/lib/analysis/motifs.ts` and `src/lib/tactics.ts`) → sentence templates. Below 1200 Elo, describe moves in words ("move your bishop to c4"), never SAN. One short explanation per mistake (2–3 sentences), plus "Show best" arrow and best line.

### Features (parity list)

- **Play vs bots:** 8 personas (Pip 600 → top 2300; the web's top bot named "Stockfish" must be renamed; replace emoji avatars with proper art/illustrations). Training mode (interrupt on mistake: badge on board, explanation card, Take back / Show best / Continue; hints) and Silent mode (no interruptions, review after). Clocks optional. Promotion picker (never auto-queen). Premoves toggle. Captured-pieces tray. Game-over sheet + confetti on win. Opening name shown live.
- **Review:** bulk-analyze once and persist; classified move list (tap to seek), move-quality **colors on the board squares** plus badge on the piece (owner insisted), eval bar (light segment always = White; flipping moves it to the other end), accuracy, arrows, swipe/step navigation. **Branching:** moving a piece mid-review creates a temporary line with live grading; "Back to game" exits; never persisted.
- **Freeplay / analysis board:** move both colors, live grading, deep toggle, visual position editor (no raw FEN input shown), autosaved as owner-less records excluded from stats.
- **Guess-the-move** on own games, scored vs engine.
- **Puzzles:** own-blunder puzzles with SM-2 spaced repetition; bundled Lichess CC0 puzzle set (themes + rating bands, offline — build from the Lichess puzzle CSV dump, e.g. 20–50k puzzles into SQLite/JSON; size is builder's call); difficulty selector; streak; weakness-targeted selection.
- **Daily puzzle** (deterministic date pick) + streak.
- **Learn:** 34 lessons — 12 openings, 12 endgames, 10 checkmate patterns. Every FEN/SAN validated by tests, including legality (no side to move already giving check — four illegal positions were shipped on web once).
- **Profile / dashboard:** rating estimate + milestones, win-rate, accuracy trend, weaknesses from motif tags, game history, streak.
- **chess.com import** (public API, username only) → review with synthesized mistakes + puzzles.
- **Voice moves:** hold-to-talk using Apple on-device speech recognition (no Groq / no API key); port the voice-move parser (pieces, squares, captures, castling, homophones, number words) and its tests.
- **Sounds + haptics:** move/capture/check/castle/win/lose; settings toggles.
- **Settings:** sound, haptics, premoves, board coordinates, default mode, licenses/source link, restore purchases.

### Persistence

SwiftData on device; CloudKit private-database sync so games/progress follow the user to a new phone (my call — no account needed). Models: Game (PGN/moves, result, mode, bot, source, analysis blob + version), Mistake/Puzzle card (SRS state), LessonProgress, Settings, Streak. CloudKit forces optional/defaulted properties and no unique constraints — design models accordingly.

### Monetization

RevenueCat SDK, entitlement `pro`, monthly + yearly with free trial; RevenueCat paywall configured remotely but styled to match the design system (or a custom SwiftUI paywall reading RevenueCat offerings — builder's call, must not look templated). Restore purchases in Settings.

Free vs Pro (owner chose the generous free tier):
- **Free:** play all bots, Silent mode, basic review (result, move list, accuracy number), daily puzzle, a small daily puzzle allowance, first lesson of each track.
- **Pro:** Training-mode explanations, full review (on-board badges/colors, explanations, branching, best lines), unlimited puzzles + SRS, all lessons, chess.com import, guess-the-move, deep analysis.
- Exact free allowances (my call, tune later): 5 puzzles/day; first lesson in each of the 3 tracks.
- **Gating principle** (my call): the analysis pipeline always computes and stores everything for every user; Pro gates only the UI. Upgrading instantly unlocks the full history, and free users' saved data never needs to be redone.
- Placement of the in-between features (my call): Freeplay — free to move, live grading badges are Pro. Blunder puzzles — generated for everyone, playable with Pro (a locked count works as an upgrade prompt). Basic review — eval bar is free, arrows and best lines are Pro. Profile — accuracy trend free, weaknesses show the top one free and the rest Pro. Voice moves — free (accessibility).
- RevenueCat setup (my call): build against a local StoreKit configuration file first; the owner creates the RevenueCat project and App Store Connect products before TestFlight.

## Design

### Identity (owner-approved direction: "Charcoal & Signal Orange")

Flat, tool-like, confident — Teenage Engineering / Nothing energy. Solid surfaces, no gradients, one loud accent.

| Token | Value |
|---|---|
| background | `#131516` |
| surface / card | `#1D2022` |
| surface-2 / subtle | `#2A2E31` |
| text | `#ECEEEE` (secondary: ~60% opacity) |
| accent (Signal Orange) | `#FF6A1A`, pressed `#CC4F0C`, text on accent `#FFFFFF` |
| danger / blunder | `#FF3B46` |
| board light | neutral cool stone, start `#D6D9D8` |
| board dark | neutral cool stone, start `#7D8483` — **must not read green** (owner flagged the sea-stone variant as too close to chess.com) |

Move-class colors (brilliant, great, best, excellent, good, book, inaccuracy, mistake, blunder, miss, forced) must be re-picked to harmonize with this palette and stay distinguishable on both board square colors.

Reference mockup: `docs/design/references/theme-dark.html` (option B) and `dark-shot.png`.

### Pieces

Style **C: soft matte 3D** (rounded, chunky, matte vinyl look, cream white vs dark slate, no faces). Reference sheet: `docs/design/references/pieces-c.png` (Higgsfield job `597af496-dd5c-4438-bd7e-9541ad21333f`, model `gpt_image_2_6`).
Production pass: generate each of the 12 pieces with Higgsfield using the reference sheet for consistency (same lighting, scale, camera angle), remove background, normalize scale (king tallest, shared baseline), export transparent PNG @1x/2x/3x with each piece ≥ 300 px tall at @3x; review all 12 side by side on both square colors before committing. Knights may face a consistent direction. Budget: owner's Higgsfield credits (~0.75 credits per image at time of writing).

### Navigation

`TabView` with system **Liquid Glass** tab bar: Home · Puzzles · Learn · Profile. Play / Freeplay / Review are pushed or presented full-screen from Home and game lists. Sheets and toolbars use system glass. Use Liquid Glass where Apple's design does (bars, floating controls, sheets) — not on content cards.

### Design process (hard requirement: no AI slop)

For every screen, before building it:
1. Collect references: Mobbin (iOS screens + flows — e.g. Duolingo Chess board/feedback, Speak/Babbel/Numo streaks, Brilliant progress), Dribbble shots, Apple HIG Liquid Glass examples.
2. Save them under `docs/design/references/<screen>/` with a short note: what we take, what we reject.
3. Build, then screenshot in the Simulator and compare against references and the anti-slop list above; fix before moving on.
Banned list: gradients, purple, neon, emoji as icons, default SF-Symbol icon grids, centered hero + 3 cards, filler marketing copy, glass on content cards.

## What's left to the builder

- C++ bridge mechanism; package layout details; threading model inside the actor.
- NNUE choice and thread count — by on-device measurement (record results).
- Puzzle-set size and storage format.
- Paywall implementation route (RevenueCat Paywalls vs custom SwiftUI).
- Bot persona art approach (consistent with the piece style).
- Sound assets (synthesized or recorded), haptic patterns.
- Exact move-class palette within the identity.
- Order of feature work (the plan decides).

## Owner answers (2026-11-24)

1. **No newer web source exists** (not on GitHub, not on the Mac). The July 29–30 classifier numbers (great gap, non-crushing cut, win% and accuracy formulas, level scaling) must be **recovered from the live Netlify bundle** at https://xq-chesscoach.netlify.app (minified JS chunks) and written down with tests. This is the first task of the plan.
2. **Definition of done: TestFlight** (internal testing build with working subscription sandbox). App Store submission is out of scope.
3. Higgsfield budget approved: ~20–30 credits for 12 pieces + 8 bot avatars, including retries.
4. App Store name, bundle ID and test device were not given. Working values: display name "ChessCoach", bundle ID `uz.xq.chesscoach` — both must be confirmed by the owner before the TestFlight upload. Engine measurements run on the owner's iPhone when available; until then use the standard SF18 big + small nets, single thread, and keep the measurement harness ready.

## Calls I made (owner can veto)

- iPhone only, portrait only, dark only in v1.
- CloudKit private sync, no accounts.
- Apple on-device speech for voice moves (replaces Groq).
- Free allowances: 5 puzzles/day, first lesson per track.
- Repo at `~/dev/chesscoach-ios`; board stone values above as a starting point.
