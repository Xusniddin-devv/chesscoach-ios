# ChessCoach iOS — Plan 2: Play layout, Review, Profile, Opening names

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saved games open in a full Review screen (both-colour analysis, move badges on squares, eval bar, explanations, branching), the Profile tab shows rating estimate / accuracy trend / weaknesses / history, opening names appear live, and the Play screen gets a balanced chess.com-style layout with the board vertically centred.

**Architecture:** New pure logic in `ChessCore` (game analyzer, opening book, profile stats, snapshot v1.1 fields), tested with `swift test`. App gains a shared `GameBoardScaffold` layout used by Play and Review, a `ReviewView`/`ReviewModel`, and a `ProfileView`. Analysis runs on the shared `StockfishEngine` only while no game is being played.

**Tech Stack:** Swift 6.3, SwiftUI iOS 26, SwiftData, Swift Charts, ChessCore/StockfishKit packages, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-24-chesscoach-ios-design.md` (Review, Profile, opening names). Grading rules: `docs/reference/web-rules.md`. Plan 1 follow-ups: `docs/superpowers/plans/2026-11-24-plan1-followups.md`. Design: `docs/design/decisions.md`.

## Design addendum (owner request 2026-11-24, controller design)

Owner: "when playing, board is on top side, bottom is blank space — see how chess.com handles this, center the board, leave space on top and bottom." Layout for Play and Review (shared scaffold, top → bottom):
1. **Move strip** — horizontal, scrollable SAN list (`1.e4 e5 2.Nf3 …`), current ply highlighted (accent underline), each user move carries its small move-class glyph once graded; tapping a ply steps the view to that position (Play: read-only "viewing history" with a "Back to live" chip; Review: seeks).
2. **Opponent bar** — avatar, name, Elo, captured pieces + material lead.
3. **Board** (with eval bar on the left when shown) — vertically centred in the remaining space; free space splits evenly above/below.
4. **User bar** — "You", captured pieces + material lead.
5. **Status line** — one quiet line: opening name, or the last verdict ("Nf3 · Best ★"), or "Mira is thinking…".
6. **Action bar** — system glass bottom bar: Play = resign · hint (Training) · ‹ · › · flip; Review = ‹ · › · best-line toggle · flip.
The Training coach card becomes a sheet sliding up over the action bar (`.sheet` with medium detent / or overlay card with glass background), never pushing the board. Game-over sheet must not clip its stats rows (Plan 1 screenshot shows "Blunders" under the buttons).

## Global Constraints

- iOS 26.0, iPhone portrait, dark only; Swift 6 strict concurrency; GPLv3; no secrets.
- Tokens/anti-slop list unchanged from Plan 1 (`docs/design/decisions.md`): no gradients, purple, neon, emoji-as-icons, glass on content cards; SF Symbols only in bars/toolbars.
- Grading numbers only from `docs/reference/web-rules.md`; bulk review depth **14**, MultiPV 2, full move history, both colours.
- One engine per process (`StockfishEngine.shared`); never run bulk analysis while a `GameSession` is live (Review is only reachable from Home/Profile, not during play).
- GameSnapshot changes stay backward-compatible (lenient decoding, `schemaVersion` 1, new fields optional).
- Every UI task ends with Simulator screenshots in `docs/design/screens/plan2-*.png`, read and compared with references/anti-slop before commit.

## Review Focus

1. Review opened on a game with no saved analysis, then left mid-analysis → analysis cancels cleanly, partial results never persisted as complete, engine free for the next game.
2. Branching in Review: rapid moves in a branch are graded in order with their own history; leaving the branch discards in-flight grades.
3. Games with a custom start FEN or ending in mate/stalemate analyse without crashes (terminal positions, mate 0).
4. Profile with 0, 1, 2 games (rating estimate needs ≥ 3), with undecodable records, with only draws.
5. Small iPhone (375 × 667 pt, e.g. iPhone SE simulator if available, else preview at that size): Play/Review scaffold still fits without scrolling the board off-screen.

---

### Task 1: Snapshot hardening + analysis fields

**Files:** Modify `Packages/ChessCore/Sources/ChessCore/Persistence/GameSnapshot.swift`; Create `Packages/ChessCore/Sources/ChessCore/Analysis/GameAnalysis.swift`; Test `GameSnapshotTests.swift`.

**Interfaces — Produces:**
- `public struct GameAnalysis: Codable, Sendable, Equatable { version: Int /* GameAnalysis.currentVersion = 1 */; depth: Int; verdicts: [Verdict] /* every ply, both colours, ply order */; whiteWin: [Double] /* White win % per position, count = moves + 1 */; accuracyWhite: Double; accuracyBlack: Double }`
- `GameSnapshot` gains `public var analysis: GameAnalysis?` and `public var openingName: String?` (both optional, default nil, lenient decode).
- Parked Plan 1 item: `result`, `startFen`, `mode`, `moves` become **required** in `init(from:)` (missing → decode throws → record logged & skipped); keep lenient defaults for genuinely-later fields (`sans`, `verdicts`, `analysis`, `openingName`, `schemaVersion`, `analysisVersion`, `playerRatingUsed`).

- [ ] Step 1: failing tests — `missingResultFailsToDecode`, `missingStartFenFailsToDecode`, `analysisRoundTrips`, `oldBlobWithoutAnalysisDecodes` (nil analysis/openingName).
- [ ] Step 2: run `cd Packages/ChessCore && swift test --filter GameSnapshotTests` → FAIL. Step 3: implement. Step 4: PASS + full ChessCore suite.
- [ ] Step 5: commit `feat(core): game analysis model; required core snapshot fields`.

### Task 2: GameAnalyzer (bulk both-colour analysis)

**Files:** Create `Packages/ChessCore/Sources/ChessCore/Analysis/GameAnalyzer.swift`; Test `GameAnalyzerTests.swift` (uses the ChessCore test-target `FakeEngine`).

**Interfaces — Produces:** `public struct GameAnalyzer { public init(engine: any ChessEngine, depth: Int = 14); public func analyze(startFen: String, moves: [String], progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> GameAnalysis }`
- Positions 0…N analysed once each (`AnalysisRequest(startFen:, moves: prefix, depth:, multiPV: 2)`), ply k verdict = `classifyPlayed` with before = result k, after = result k+1; terminal final position allowed (bestmove "" + mate 0 per Plan 1 fix). `whiteWin[i] = winPercent(toCp(result_i.lines[0].score, sideToMove_i))`; accuracies from `gameAccuracy(whiteWin:movers:)`. Engine error on one position → throw (caller may retry); `CancellationError` propagates; progress(done, total) after each position.
- Port note: web `analyzeGame` substituted the previous eval on a failed position; we throw instead (simpler, the caller retries) — ruling recorded in the plan.

- [ ] Step 1: failing tests — `analyzesBothColoursInPlyOrder` (4-ply game, scripted scores → 4 verdicts, movers alternate, whiteWin count 5), `oneSearchPerPosition` (fake request log count == moves + 1, each with full history prefix), `finalMateIsBestNotMiss` (scholar's mate final ply → `.best`/`.great`), `customStartFen` (black to move first), `cancellationStops` (cancel mid-way → CancellationError, no further requests), `progressReportsEveryPosition`.
- [ ] Steps 2–4: RED → implement → GREEN (+ full suite). Step 5: commit `feat(core): bulk game analyzer`.

### Task 3: Opening book

**Files:** Create `scripts/gen-openings.sh` (downloads `a.tsv`…`e.tsv` from `https://raw.githubusercontent.com/lichess-org/chess-openings/master/` — CC0 — into a temp dir and runs the generator), `Packages/ChessCore/Sources/GenOpenings/main.swift` (executable target: replays each PGN line with `Rules`/chesskit SAN parsing, writes JSON `[{"key": "<FEN fields 1-4>", "eco": "C50", "name": "Italian Game"}]`, keeping the longest-line name per key), `Packages/ChessCore/Sources/ChessCore/Resources/openings.json` (committed output), `Packages/ChessCore/Sources/ChessCore/Analysis/OpeningBook.swift`; Test `OpeningBookTests.swift`.

**Interfaces — Produces:** `public struct Opening: Codable, Sendable, Equatable { eco: String; name: String }`; `public enum OpeningBook { public static func lookup(fen: String) -> Opening?; public static func deepest(startFen: String, moves: [String]) -> Opening? }` (loads the bundled JSON once, lazily, thread-safe; keys = FEN fields 1-4).
- [ ] Step 1: run the script, commit JSON (record entry count in the commit message; expect ~3.5k).
- [ ] Step 2: failing tests — `italianGame` (`e2e4 e7e5 g1f3 b8c6 f1c4` → name contains "Italian"), `frenchDefense` (`e2e4 e7e6` → "French Defense"), `deepestKeepsLastKnownAfterLeavingBook`, `unknownStartFenReturnsNil`.
- [ ] Steps 3–4: implement → GREEN. Step 5: commit `feat(core): opening book from lichess chess-openings (CC0)`.

### Task 4: Shared board scaffold + new Play layout

**Files:** Create `App/Features/Shared/GameBoardScaffold.swift`, `App/Features/Shared/MoveStrip.swift`, `App/Features/Shared/PlayerBar.swift`; Modify `App/Features/Play/PlayView.swift`, `PlayModel.swift`, `CoachCard.swift`, `GameOverSheet.swift`; Tests `AppTests/MoveStripTests.swift` (pure model: ply labels/grouping), `AppTests/PlayFlowTests.swift` (history viewing).

**Interfaces — Produces:** `struct GameBoardScaffold<Board: View, Actions: View>: View { init(moves: [MoveStripItem], currentPly: Int?, onSelectPly: (Int?) -> Void, top: PlayerBarModel, bottom: PlayerBarModel, status: String?, @ViewBuilder board: () -> Board, @ViewBuilder actions: () -> Actions) }`; `struct MoveStripItem: Identifiable, Equatable { ply: Int; san: String; moveClass: MoveClass? }`; `struct PlayerBarModel { name: String; elo: Int?; avatarAsset: String?; captured: [String] /* piece codes */; materialLead: Int }`.
- Play: viewing history (`PlayModel.viewedPly: Int?`) shows that position read-only (board non-interactive, "Back to live" chip in the status line); any new move or tap on the chip returns to live. Opening name from `OpeningBook.deepest` in the status line until move 12, then last verdict/thinking text.
- Coach card: presented as a bottom overlay card with glass background above the action bar (does not change board position); Take back / Show best / Continue unchanged.
- Game-over sheet: stats rows never clipped (scroll or detent large enough); retake screenshot.
- [ ] Step 1: failing tests (move-strip model; history view returns to live on move). Steps 2–4: RED → implement → GREEN (app suite).
- [ ] Step 5: Simulator screenshots `plan2-play-live.png`, `plan2-play-coach.png`, `plan2-play-history.png`, `plan2-gameover.png` (iPhone 17 Pro) + one small-screen check (iPhone SE-class simulator if installed, else `#Preview` at 375×667 rendered via ImageRenderer) → read, compare with decisions.md + Mobbin play refs; board must be vertically centred (equal free space above/below ±8 pt). Step 6: commit `feat(app): centred board scaffold, move strip, coach overlay`.

### Task 5: Review screen

**Files:** Create `App/Features/Review/ReviewView.swift`, `ReviewModel.swift`, `ReviewMoveList.swift`; Modify `App/Persistence/GameRecord.swift` (update snapshot data in place), `App/Features/Home/HomeView.swift` (tap recent game → Review); Tests `AppTests/ReviewModelTests.swift`.

**Interfaces — Consumes:** `GameAnalyzer`, `OpeningBook`, `GameBoardScaffold`, `explain(_:wording:)`, `BoardView`, `EvalBar`. **Produces:** `@MainActor @Observable final class ReviewModel { init(record: GameRecord, engine: any ChessEngine); var analysisProgress: Double?; var analysis: GameAnalysis?; var selectedPly: Int /* 0 = start */; var branch: [BranchMove]? ; func start() async; func select(ply: Int); func step(_ delta: Int); func playBranchMove(_ uci: String) -> Bool; func exitBranch(); func cancel() }`.
- Opening Review: if `snapshot.analysis` is nil or `version < GameAnalysis.currentVersion` → run `GameAnalyzer` with progress UI ("Analysing 12 / 48"); on success persist into the record (`snapshot.analysis`, `openingName`); leaving cancels (no persist of partial). Then instant on reopen.
- Header: accuracy White/Black, opening name. Board shows the selected ply's destination square tinted with its class colour + badge, best-move arrow (toggle) for negative moves, eval bar from `whiteWin`. Explanation card for negative classes (`explain`, words). Move list: full classified list (sheet or expandable panel), tap to seek; ‹ › in the action bar.
- Branching: a board move at the selected ply creates a temporary line graded live (sequential, own history, generation-guarded — reuse `GameSession`'s grading approach or a small `LineGrader` in ChessCore if cleaner; decide and document); shown in the move strip as an indented branch; "Back to game" exits; never persisted.
- [ ] Step 1: failing tests — analysis runs once and persists; cancel leaves record unchanged; select/step bounds; branch move graded with history = mainline prefix + branch; exitBranch discards late grades. Steps 2–4: RED → implement → GREEN.
- [ ] Step 5: screenshots `plan2-review-analysing.png`, `plan2-review-blunder.png` (selected blunder with tint, badge, arrow, explanation), `plan2-review-branch.png`; read & compare. Step 6: commit `feat(app): game review with analysis, badges, branching`.

### Task 6: Profile stats + Profile tab

**Files:** Create `Packages/ChessCore/Sources/ChessCore/Profile/ProfileStats.swift` (+ tests), `App/Features/Profile/ProfileView.swift`, `ProfileModel.swift`, `AccuracyTrendChart.swift`; Modify `App/AppShell/RootTabView.swift` (Profile tab real; keep DEBUG benchmark link inside Profile behind `#if DEBUG`), `App/EngineHub.swift`/`PlayModel` (Training level uses the estimate).

**Interfaces — Produces (ChessCore):** `public struct RatedGame: Sendable { botElo: Int; outcome: Outcome /* win, draw, loss from user's view */; accuracy: Double? }`; `public func estimateRating(_ games: [RatedGame]) -> Int?` (web rating.ts exactly: newest 15, ≥ 3 games, perf = elo + 400·(score−0.5)·0.9, accRating = 500 + (acc−60)/35·1400 clamped 300…2400 when accuracy present, 0.7·perf + 0.3·accRating, average, clamp 300…2400, round to 10); `public func nextMilestone(_ estimate: Int) -> (elo: Int, name: String)?` (web levels list in web-rules.md); `public struct WeaknessSummary { motif: Motif; count: Int; lastSeen: Date }`, `public func aggregateWeaknesses(_ items: [(motifs: [Motif], date: Date)]) -> [WeaknessSummary]` (count desc); `public extension Motif { var title: String; var advice: String }` (beginner wording, e.g. hangingPiece → "Leaving pieces undefended", advice one sentence).
- Profile screen: estimated rating (or "Play 3 games to get a rating"), next milestone with progress, tiles (games, win rate, average accuracy), accuracy trend (Swift Charts line, last 20 games, accent colour, no gradient fill), top weaknesses (from user's negative verdicts across games), full history list → Review.
- `PlayerProfile` rating source: Training thresholds and explanation wording use `estimateRating` when available, else 800 (spec ruling); computed in the app from saved records.
- [ ] Step 1: failing ChessCore tests (rating examples incl. <3 games → nil, clamping, accuracy nil path; milestone; weaknesses ordering). Steps 2–4: RED → implement → GREEN (+ app tests for ProfileModel with in-memory store, 0/1/3 games, undecodable record skipped).
- [ ] Step 5: screenshots `plan2-profile-empty.png`, `plan2-profile.png`; read & compare. Step 6: commit `feat: profile with rating estimate, trend, weaknesses, history`.

### Task 7: Plan 2 verification

- [ ] Run all suites (ChessCore, StockfishKit, app) and paste pass lines; play one Training game end-to-end in the Simulator via DEBUG autoplay, open it in Review, step through, branch once, open Profile — screenshots refreshed; update `CODEMAP.md` (create: feature → files map for the repo) and README run steps. Commit `chore: plan 2 verification, codemap`.
