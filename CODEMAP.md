# CODEMAP — feature → files

Where things live, so a change starts in the right file. Paths are from the repo root.
`App/` is the iOS app (SwiftUI, generated project via `project.yml` + xcodegen); `Packages/ChessCore`
is the pure-Swift chess brain (no UI, no engine binary); `Packages/StockfishKit` wraps the
vendored Stockfish 18 build. Design rules: `docs/design/decisions.md`; grading numbers:
`docs/reference/web-rules.md`; plans/specs: `docs/superpowers/`.

## App shell

| Feature | Files |
|---|---|
| App entry, SwiftData container, engine configure | `App/ChessCoachApp.swift` |
| Tabs (Home, Puzzles, Learn, Profile); player rating sync from saved games | `App/AppShell/RootTabView.swift` |
| Shared engine access, sessions, review models, player rating + wording | `App/EngineHub.swift` |
| Design tokens (colours, type, spacing, radii) | `App/DesignSystem/Tokens.swift` |
| Buttons, labels, avatar tiles (bots, user tier piece), move badge, pill | `App/DesignSystem/Components/*` |
| Icons (Icons8 iOS Filled, potrace SVG templates) | `App/Resources/Assets.xcassets/Icons/`, lock `icons8.json` |
| Saved game record (SwiftData), in-place update | `App/Persistence/GameRecord.swift` |
| Puzzles / Learn placeholders | `App/Features/Placeholders/ComingSoonView.swift` |

## Board

| Feature | Files |
|---|---|
| Board drawing, pieces, highlights, tints, badges, arrows | `App/Board/BoardView.swift`, `App/Board/ArrowOverlay.swift` |
| Tap / drag move input, promotion | `App/Board/BoardInteraction.swift`, `App/Board/PromotionPicker.swift` |
| Eval bar | `App/Board/EvalBar.swift`, `Packages/ChessCore/Sources/ChessCore/Display/EvalBarLayout.swift` |
| Square geometry, piece identity across moves | `ChessCore/Display/BoardGeometry.swift`, `ChessCore/Display/PieceTracker.swift` |

## Board screens (Play and Review share these)

| Feature | Files |
|---|---|
| Centred stack: strip, bars, board, status line, flat action bar (`GameActionBar`, `GameAction`), bottom card | `App/Features/Shared/GameBoardScaffold.swift` (`BoardStackGeometry`) |
| Move strip (SAN, class glyphs, branch tiles) | `App/Features/Shared/MoveStrip.swift` |
| Player bars (avatar, Elo, captured, lead, accuracy) | `App/Features/Shared/PlayerBar.swift`, `App/Features/Shared/BoardMaterial.swift` |
| Saved-game row (Home) | `App/Features/Shared/GameRow.swift` |
| Small static board (filmstrip, weakness card) | `App/Features/Shared/MiniBoardView.swift` |

## Home

| Feature | Files |
|---|---|
| Greeting, Play card, recent games → Review | `App/Features/Home/HomeView.swift` |

## Play

| Feature | Files |
|---|---|
| Bot picker = sparring ladder (bot, mode, colour); ladder rules | `App/Features/Play/BotPickerView.swift`, `ChessCore/Play/BotLadder.swift` |
| Game screen, action bar, saving | `App/Features/Play/PlayView.swift`, `App/Features/Play/PlayModel.swift` |
| Game logic: board, grading queue, bot moves, interrupts, take-back | `ChessCore/Play/GameSession.swift` |
| Bots, bot strength / pacing, Training thresholds | `ChessCore/Play/Bots.swift`, `ChessCore/Play/Levels.swift`, `ChessCore/Play/PlayerProfile.swift` |
| Coach card (Training interrupt) | `App/Features/Play/CoachCard.swift` |
| Game-over result panel (players, accuracy, class chips, key moment), summary analysis, confetti | `App/Features/Play/GameOverSheet.swift`, `PlayModel.swift` (summary), `ConfettiBurst.swift`, `UserAccuracy.swift`, `ChessCore/Analysis/GameSummary.swift` |
| DEBUG autoplay / launch arguments | `App/Features/Play/DebugAutoplay.swift` |

## Review

| Feature | Files |
|---|---|
| Review screen (scaffold, comment card, action bar) | `App/Features/Review/ReviewView.swift` |
| Analysis run + store, stepping, branches, comments | `App/Features/Review/ReviewModel.swift` |
| Move list sheet (accuracy, class counts, moves) | `App/Features/Review/ReviewMoveList.swift` |
| DEBUG launch arguments (-debugReview …) | `App/Features/Review/DebugReview.swift` |
| Bulk analysis of a finished game | `ChessCore/Analysis/GameAnalyzer.swift`, `ChessCore/Analysis/GameAnalysis.swift` |
| Live grading of a branch (ordered, generation-guarded) | `ChessCore/Analysis/LineGrader.swift` |

## Profile

| Feature | Files |
|---|---|
| Profile tab "You" (piece hero, last-games filmstrip, move-quality ribbon, habits) | `App/Features/Profile/ProfileView.swift` |
| Stats from saved games | `App/Features/Profile/ProfileModel.swift` |
| Rating estimate, tiers (pieces), milestones, weaknesses, motif wording | `ChessCore/Profile/ProfileStats.swift` |

## Grading and explanations (ChessCore/Analysis)

| Feature | Files |
|---|---|
| Move classes, glyphs | `MoveClass.swift` |
| Classifying a played move (`Verdict`, `MoveFacts`) | `Classifier.swift` |
| Win %, centipawns, mates | `EvalMath.swift` |
| Game accuracy | `Accuracy.swift` |
| Motifs (why a move was bad), material, en prise | `Motifs.swift`, `Material.swift` |
| Explanation text (words / notation) | `Explainer.swift` |
| Opening names (lichess chess-openings, CC0) | `OpeningBook.swift`, `Resources/openings.json`, `Sources/GenOpenings/main.swift`, `scripts/gen-openings.sh` |

## Rules, persistence, engine

| Feature | Files |
|---|---|
| Legal moves, SAN, FEN, game state (via ChessKit) | `ChessCore/Rules/Rules.swift` |
| Saved game format (lenient decoding) | `ChessCore/Persistence/GameSnapshot.swift` |
| Engine protocol, requests, results | `ChessCore/Engine/EngineTypes.swift` |
| Stockfish process bridge, UCI, cache | `Packages/StockfishKit/Sources/StockfishKit/*`, `Sources/StockfishCore/bridge.cpp` |
| Engine benchmark (DEBUG, Profile tab) | `App/Debug/EngineBenchmarkView.swift` |
| Vendoring / nets | `scripts/vendor-stockfish.sh`, `scripts/fetch-nnue.sh` |

## Tests

| Area | Files |
|---|---|
| ChessCore (Swift Testing, `swift test`) | `Packages/ChessCore/Tests/ChessCoreTests/*` (fake engine: `Support/FakeEngine.swift`) |
| StockfishKit | `Packages/StockfishKit/Tests/StockfishKitTests/*` |
| App (simulator) | `AppTests/*` — Play flow, Review, Profile, scaffold geometry, persistence (fake engine: `AppTests/Support/FakeEngine.swift`) |
