# CODEMAP — feature → files

Where things live, so a change starts in the right file. Paths are from the repo root.
`App/` is the iOS app (SwiftUI, generated project via `project.yml` + xcodegen); `Packages/ChessCore`
is the pure-Swift chess brain (no UI, no engine binary); `Packages/StockfishKit` wraps the
vendored Stockfish 18 build. Design rules: `docs/design/decisions.md`; grading numbers:
`docs/reference/web-rules.md`; plans/specs: `docs/superpowers/`.

## App shell

| Feature | Files |
|---|---|
| App entry, engine configure, Entitlements injection | `App/ChessCoachApp.swift` |
| SwiftData container (CloudKit-mirrored `cloud.store` when the build syncs, else `local.store`; legacy `default.store` moved once; `-debugEmptyStore`), the one model list | `App/Services/ModelStore.swift` (`ModelStore.models`; `DataReset.models` = same) |
| Failed saves: `ModelContext.saveReporting`, `SaveIssues`, inline `SaveNotice` (Retry) | `App/Persistence/SaveReporting.swift`, overlay in `RootTabView` |
| Privacy manifest (required-reason APIs, no tracking) | `App/PrivacyInfo.xcprivacy`; TestFlight owner checklist `docs/TESTFLIGHT.md` |
| Onboarding gate (local flag or a synced `UserProfile`, never cutting an onboarding in progress: `showsTabs`, `Step.isEngaged`), tabs (Home, Puzzles, Learn, Profile); player rating sync (`ProfileModel.rating`); auto-sync triggers (launch, foreground); sync-duplicate merge on launch / remote change | `App/AppShell/RootTabView.swift` |
| Shared engine access, sessions, review models, player rating + wording | `App/EngineHub.swift` |
| Design tokens (colours, type, spacing, radii) | `App/DesignSystem/Tokens.swift` |
| Buttons, labels, avatar tiles (bots, user tier piece), move badge, pill | `App/DesignSystem/Components/*` |
| Coach character (poses), speech bubble, chip-aware text (`[e4]`, `**bold**`, `CoachText.marked`) | `App/DesignSystem/Components/CoachBubble.swift`, assets `Coach/*` |
| Streak pill, done ring, mini board, chips, flow layout | `App/DesignSystem/Components/TrainingComponents.swift` |
| Icons (Icons8 iOS Filled, potrace SVG templates; brand logos the only exception) | `App/Resources/Assets.xcassets/Icons/`, lock `icons8.json` |
| Saved game record (SwiftData), in-place update (`revision`), decode cache (`GameCache`: snapshot, `finalFen`, `blunderPuzzles`), sync duplicates (`unique` on read; `mergeDuplicates` / `mergeCopies` keep the smallest immutable `rowID` and move the best content onto it; rules `ChessCore/Persistence/GameDedupe.swift`) | `App/Persistence/GameRecord.swift` |
| Puzzle / lesson progress, streak rows, `TrainingStore` | `App/Persistence/TrainingModels.swift` |
| User profile (platform, rating, goal; `platformRating` = an imported player's shown rating), training plan, imported games | `App/Persistence/ProfileModels.swift` (`ProfileStore`) |
| Sounds, haptics (`.gameFeedback`), voice input | `App/Services/Sound.swift`, `Haptics.swift`, `Voice.swift` |
| Pro status (RevenueCat or StoreKit, `-forcePro YES|NO`) | `App/Services/Purchases.swift` (`Entitlements`) |
| App icon | `App/Resources/Assets.xcassets/AppIcon.appiconset` |

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
| Small static board (filmstrip, weakness card) | `App/Features/Shared/MiniBoardView.swift` |

## Home

| Feature | Files |
|---|---|
| Header (streak, rating → goal), coach line from real data, sparring link, Continue strip (analysis board + recent games → Review; freeplay excluded: `recentGames`) | `App/Features/Home/HomeView.swift` (thumbs: `GameThumb` in `ProfileView.swift`) |
| Today's plan as a 3-token path (practice steps, bot as boss), Start, next week; `PlanPath` / `StepToken` shared with onboarding's week | `App/Features/Home/TodayPlanCard.swift`, `ChessCore/Onboarding/TrainingPlan.swift` |
| Background analysis (quick pass, full upgrades, plan rebuild), engine holds (`.holdsEngine()`) | `App/Services/BackgroundAnalysis.swift`, `ChessCore/Analysis/AnalysisQueue.swift`, `StockfishKit/StockfishEngine.swift` (`analyzeInBackground`) |
| Auto-sync of the linked account (Pro): new games since the newest stored, rating refresh, throttle / backoff, pull to refresh (`.autoSyncRefreshable()`), background app refresh (`ChessCoachApp`, `uz.xq.chessc.sync`), unlink | `App/Services/GameAutoSync.swift`; cursor / stop-at-known / `SyncSchedule`: `ChessCore/Import/GameSync.swift`, clients' `games(_:since:limit:isKnown:)` |
| Platform evals / accuracies (chess.com review, Lichess server analysis) | `ChessCore/Import/PlatformEvals.swift`, `GameSnapshot.platformAccuracy` |

## Analysis board (Freeplay) and position editor

| Feature | Files |
|---|---|
| Board screen: both colours, live grades, eval bar, best arrow, Deep (depth 20), take back, autosave (`source: freeplay`) | `App/Features/Freeplay/FreeplayView.swift`, `App/Features/Freeplay/FreeplayModel.swift` |
| Visual position editor (tray, castling, side to move, inline validation) | `App/Features/Freeplay/PositionEditorView.swift` |
| Editor position + FEN, castling availability; legality rules | `ChessCore/Setup/BoardSetup.swift`, `ChessCore/Setup/PositionValidator.swift` |

## Guess the move

| Feature | Files |
|---|---|
| Flow (pick side, guess, reveal, score screen), entry from Review's action bar | `App/Features/Guess/GuessModel.swift`, `App/Features/Guess/GuessView.swift`, `App/Features/Review/ReviewView.swift` |
| Scoring (best 3 / ≤50 cp 2 / ≤150 cp 1) from the saved analysis, engine search when needed | `ChessCore/Analysis/GuessScoring.swift` |

## Play

| Feature | Files |
|---|---|
| Bot picker = sparring ladder (bot, mode, colour); ladder rules (next skips bots `tooEasy` below the rating) | `App/Features/Play/BotPickerView.swift`, `ChessCore/Play/BotLadder.swift` |
| Game screen, flat action bar (incl. hold-to-talk mic cell), saving | `App/Features/Play/PlayView.swift`, `App/Features/Play/PlayModel.swift`, `App/Features/Voice/VoiceMicButton.swift` |
| Voice move parsing (spoken text → UCI) | `ChessCore/Voice/VoiceMove.swift` |
| Game logic: board, grading queue, bot moves, interrupts, take-back | `ChessCore/Play/GameSession.swift` |
| Bots, bot strength / pacing, Training thresholds | `ChessCore/Play/Bots.swift`, `ChessCore/Play/Levels.swift`, `ChessCore/Play/PlayerProfile.swift` |
| Coach card (Training interrupt; coach figure + chip text; explanation Pro-gated) | `App/Features/Play/CoachCard.swift` |
| Game-over result panel (players, accuracy, class chips, key moment), summary analysis, confetti | `App/Features/Play/GameOverSheet.swift`, `PlayModel.swift` (summary), `ConfettiBurst.swift`, `UserAccuracy.swift`, `ChessCore/Analysis/GameSummary.swift` |
| DEBUG autoplay / launch arguments | `App/Features/Play/DebugAutoplay.swift` |

## Review

| Feature | Files |
|---|---|
| Review screen (scaffold, comment card, action bar; free users: classes/comments/Best/branches → paywall) | `App/Features/Review/ReviewView.swift` |
| Analysis run + store, stepping, branches, comments | `App/Features/Review/ReviewModel.swift` |
| Move list sheet (accuracy, class counts, moves) | `App/Features/Review/ReviewMoveList.swift` |
| DEBUG launch arguments (-debugReview …) | `App/Features/Review/DebugReview.swift` |
| Bulk analysis of a finished game | `ChessCore/Analysis/GameAnalyzer.swift`, `ChessCore/Analysis/GameAnalysis.swift` |
| Live grading of a branch (ordered, generation-guarded) | `ChessCore/Analysis/LineGrader.swift` |

## Profile

| Feature | Files |
|---|---|
| Profile tab "You" (piece hero + goal line, last-games filmstrip, ribbon, habits, "Fix it", Settings gear) | `App/Features/Profile/ProfileView.swift` |
| Stats from saved games (bots + imports, never freeplay); `rating` = platform rating for imports, else `estimate` | `App/Features/Profile/ProfileModel.swift` |
| "Fix it" puzzles for a habit (own positions first, then bank) | `ChessCore/Puzzles/BlunderPuzzles.swift` (`fixIt`) |

## Puzzles

| Feature | Files |
|---|---|
| Puzzles tab (coach + streak hook, daily, own mistakes, rating ruler, theme rows, free allowance) | `App/Features/Puzzles/PuzzlesView.swift` (`RatingRuler`) |
| Solver screen + model (setup move, replies, verdict band naming the missed step's move `PuzzleSolver.expectedSan`, badges, SRS + streak + puzzle rating); unplayable puzzles dropped in `PuzzleSessionSetup.init` | `App/Features/Puzzles/PuzzleSessionView.swift`, `PuzzleSessionModel.swift` |
| Shared training frame (progress segments, coach narration, chunky buttons, verdict band, "Which move?" pills) | `App/Features/Shared/TrainingFrame.swift` |
| Solution explanation (chips), puzzle rating (Elo, first outcomes) | `ChessCore/Puzzles/PuzzleExplainer.swift`, `ChessCore/Puzzles/PuzzleRating.swift` |
| Puzzle format, playability guard (`Puzzle.isServable`), solver rules, bank (6,000 Lichess CC0), daily, own-mistake puzzles | `ChessCore/Puzzles/*`, `Resources/puzzles.json`, `scripts/gen-puzzles.sh` |
| Spaced repetition, day streak | `ChessCore/Training/SRS.swift`, `Streak.swift` |

## Learn

| Feature | Files |
|---|---|
| Learn tab (winding path: unit banners, lesson tokens, boss bots, popovers; Pro lock after the first lesson) | `App/Features/Learn/LearnView.swift` |
| Lesson player + model (scripted lines, mate patterns, endgames vs engine) | `App/Features/Learn/LessonView.swift`, `LessonModel.swift`, `ChessCore/Lessons/*`, `Resources/lessons.json` |

## Onboarding and import

| Feature | Files |
|---|---|
| Flow (welcome, chat-style account finder, ~10 s import + background, reveal, goal, week as a token path, new player) | `App/Features/Onboarding/*` (`OnboardingFlow`, `OnboardingModel`, `FindStep`, `ImportStep`, `QuestionStep`, `PlanStep`) |
| chess.com / Lichess clients, PGN → snapshot (`source: chesscom|lichess`) | `ChessCore/Import/*` |
| Onboarding analysis, coach lines, goal model, 7-day plan | `ChessCore/Onboarding/*` |

## Settings, paywall, licenses

| Feature | Files |
|---|---|
| Settings (pushed from Profile's gear): linked account (change, unlink), auto-sync toggle (Pro), play defaults, feedback, Pro, about, re-import (Pro), reset | `App/Features/Settings/SettingsView.swift`, `SettingsRows.swift`, `Preferences.swift` (`Pref`, `AppInfo`) |
| Paywall, `ProFeature`, `ProGate`, `UpgradeButton`, puzzle / lesson / habit allowances (`WeaknessAllowance`) | `App/Features/Paywall/PaywallView.swift`, `ProGate.swift` |
| Licenses (GPLv3, Stockfish, chesskit, RevenueCat, Lichess CC0, Icons8) | `App/Features/Licenses/LicensesView.swift`, `App/Resources/Licenses/*.txt` |
| Build config (RevenueCat key from gitignored `Config/Secrets.xcconfig`), StoreKit test file, entitlements | `Config/App.xcconfig`, `Config/ChessCoach.storekit`, `App/ChessCoach.entitlements`, `App/Info.plist` |
| Rating estimate, `playerRating(platform:games:)`, tiers (pieces), milestones, weaknesses, motif wording; goal picker window / clamp in `ChessCore/Onboarding/GoalModel.swift` | `ChessCore/Profile/ProfileStats.swift` |

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
| Saved game format (lenient decoding; `source` freeplay / chesscom / lichess, `isFreeplay`, `isImported`, opponent name / rating) | `ChessCore/Persistence/GameSnapshot.swift` |
| Engine protocol, requests, results | `ChessCore/Engine/EngineTypes.swift` |
| Stockfish process bridge, UCI, cache | `Packages/StockfishKit/Sources/StockfishKit/*`, `Sources/StockfishCore/bridge.cpp` |
| Engine benchmark (DEBUG, Profile tab) | `App/Debug/EngineBenchmarkView.swift` |
| Vendoring / nets | `scripts/vendor-stockfish.sh`, `scripts/fetch-nnue.sh` |

## Tests

| Area | Files |
|---|---|
| ChessCore (Swift Testing, `swift test`) | `Packages/ChessCore/Tests/ChessCoreTests/*` (fake engine: `Support/FakeEngine.swift`) |
| StockfishKit | `Packages/StockfishKit/Tests/StockfishKitTests/*` |
| App (simulator) | `AppTests/*` — Play flow, Review, Profile, Freeplay + Guess (`FreeplayTests.swift`: saving, freeplay exclusion), settings / paywall, training store, onboarding, launch, merge invariants (`MergeIntegrationTests.swift`), decode cache / sync duplicates / store files / privacy manifest (`SyncAndStoreTests.swift`), scaffold geometry, persistence (fake engine: `AppTests/Support/FakeEngine.swift`) |
