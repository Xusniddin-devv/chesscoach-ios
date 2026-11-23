# Plan 1 follow-ups (from task and final reviews)

Deferred minor findings and parked items from the Plan 1 execution ledger, kept for Plan 2+ triage. Branch feat/plan1-foundation-play.

## Parked (final review)
- Final: parked — GameSnapshot defaults result/startFen/mode/sans when missing — Ruling: real but no writer omits them today; make them required (logged+skipped) at the start of Plan 2 before any format change — cost if wrong: a hand-edited/corrupt record could show as ongoing.
- Final: parked — prefetch handle overwritten / wasted prefetch when Silent grades back up / no prefetch after takeBack — Ruling: perf-only, revisit with Plan 2's engine priority lane + LRU cache.

## Deferred minors
- Task 1: minor (deferred): state() returns .active for unparseable FEN (hides error)
- Task 1: minor (deferred): repetitionKey includes EP square even when no EP capture possible
- Task 1: minor (deferred): thin tests — fiftyMove, insufficientMaterial, check/active, apply rejections, capture-promotion, fen() nil, black pawn/king attackers
- Task 1: minor (deferred): AppliedMove lacks public memberwise init
- Task 2: minor (deferred): LevelSettings not Sendable (carry: Task 4 may add Sendable when it uses it)
- Task 2: minor (deferred): manual Comparable on TrainingSeverity unnecessary
- Task 2: minor (deferred): no elo-clamp / jitter-edge tests; only Apex blurb asserted
- Task 3: minor (deferred): dotprod + LTO from SF apple-silicon target not enabled (perf later, Plan 4 measurements)
- Task 3: minor (deferred): header lacks callback rules (no sf_start/sf_quit from callback; don't block on quitting thread)
- Task 3: minor (deferred): sf_send before start/after quit dropped; caller-sent quit leaves engineThread set — undocumented
- Task 3: minor (deferred): no tests for quit-during-search / search-after-restart
- Task 3: minor (deferred): AUTHORS not vendored; vendoring not pinned to commit SHA; fetch-nnue no trap; measurements doc not reproducible / inconsistent
- Task 3: minor (deferred): swap replace_all("quit") before stop() in sf_quit to close tiny double-rule-break window
- Task 3: minor (deferred): harness quit timeout leaves lifecycleMutex held (suite can still freeze on failure path)
- Task 4: minor (deferred): UCIParser.info doesn't skip `info string`; bound scores accepted silently
- Task 4: minor (deferred): failed start retried in same call (long block on hung engine)
- Task 4: minor (deferred): no tests for 3+ queued requests / restart while queued / terminal line contents / timeout path (no injectable timeout)
- Task 4: minor (deferred): cached re-request waits behind in-flight search (UI note)
- Task 4: minor (deferred): two engine tests rely on short sleeps (50/20 ms) — theoretical flakiness
- Task 5: minor (deferred): test gaps (black-to-move mates, winPercent symmetry, isEnPrise false cases, promotion, malformed UCI)
- Task 6: minor (deferred): no boundary tests (cpLoss 20/21, gap 150, brilliant winBefore<90 / winAfter>=50)
- Task 6: minor (deferred): neverSuggestsPlayedMoveAsBetter accepts 3 classes; Verdict lacks public memberwise init
- Task 6: minor (deferred): missBeatsBook test name misleading
- Task 7: minor (deferred): pawns() rounding differs from JS toFixed(1) on x5 values (115→1.1 in JS, 1.2 Swift); comment overstates parity — fix by String(format:"%.1f") (binary-exact) in a later pass
- Task 7: minor (deferred): captureWording test mutates facts; no .notation pawn-unit / UCI-fallback tests
- Task 8: minor (deferred): accuracy only single-move tests (no multi-move JS-parity case); no precondition whiteWin.count == movers.count+1 (traps)
- Task 8: minor (deferred): geometry black-orientation square(at:) untested; tracker EP/castling/promo-capture coverage thin; init(fen:) invalid → empty silently
- Task 9: minor (deferred): GameResult/PlayMode raw strings not pinned by test; deterministic test weak; sample uses .ongoing
- Task 10: minor (deferred): missing tests — retry after failed grade (needs failNextAnalyze), bot move held during takeBack, .miss interrupt, game ending on bot's move, hint outside userTurn
- Task 10: minor (deferred): negative checks rely on settle() yields; no teardown/close() — discarded session keeps grading on shared engine; stray CancellationError could stick phase
- Task 10: minor (deferred): FakeEngine/test clocks only in ChessCore test target (Task 14 needs own copy)
- Task 10: minor (deferred): resign detected via ending.reason == nil — explicit resigned flag sturdier
- Task 11: minor (deferred): screenshot has "Hannim" back-link (retake in Task 14); GameRecord try? decode silent; GameRecord id/date mirror + bad data untested; LaunchTests only counts tabs
- Task 11: minor (deferred): configure() async in .task may race first session; check dead code hasEngineError/restart callers later; brief text stale re scenePhase
- Task 12: minor (deferred): slate avatars (Wall/Vera/Apex) dark-on-dark on surface2 tile — consider lighter tile/rim in Task 14; mistake orange #F59A2E near brand accent (ΔE 28.5)
- Task 12: review 1 — Important: Bots/ and Pieces/ asset folders lack provides-namespace → Image("Bots/pip") blank. Task 12: minor (deferred): moveClassGlyph ignores arg (add comment/test); MoveBadge now 26 pt — Task 13 overlay offset
- Task 13: minor (deferred): release after mid-gesture reset acts as tap; whole-board redraw per drag frame; Rules.legalTargets API would drop direct ChessKit dep + duplicated last-rank test; evalbar Equal check order
- Task 14: minor (deferred): FEN parsed per render in PlayModel (interactive/captured/materialLead); eval bar lags bot moves; Home compactMap drops undecodable records silently; picker uses onTapGesture not Button; confetti origin hard-coded; Done dismisses before save completes; UserAccuracy test lacks multi-move unsorted case; test comment mismatch
- Task 14: minor (deferred): rollback path in insertRecord untested (needs context.save seam); Retry tap during save loop runs concurrently (bounded)
- Task 15: minor (deferred): default 1/64 duplicated as literals (use EngineHub constants); movetime test doesn't assert go line; progress Tasks unordered vs "Done"; "probably noise" wording; doc comment "validated at startup"
- Task 15: minor (deferred): EngineBenchmarkTests not wrapped in #if DEBUG; re-entry race (new run while old drains); wait loop without timeout

## Rulings made during execution
- Ruling: replace checkmate test FEN everywhere with "7k/6Q1/6K1/8/8/8/8/8 b - - 0 1" (Qg7#, protected by Kg6) — plan FEN is not mate — cost if wrong: none, verified by hand.
- Ruling: T11 ships DS.Color.moveClass with the web palette from docs/reference/web-rules.md as placeholder; T12 replaces it — T11 needs a value to compile — cost: one small edit in T12.
- Ruling: add `startFen: String = Rules.startFen` param to Rules.state(fen:history:startFen:) + custom-start repetition test — spec requires freeplay/lessons from custom FENs — cost if wrong: one extra param.
- Task 3: implementer DONE_WITH_CONCERNS (5df48b3). Rulings on concerns:
- Ruling: arm64-only build accepted — Debug sim builds active arch only, devices are arm64; Task 11 sets EXCLUDED_ARCHS[sdk=iphonesimulator*]=x86_64 — cost: no Intel-Mac simulator support.
- Ruling: one engine per process (bridge owns std::cin/cout) — Task 4 makes StockfishEngine a process-wide singleton (`StockfishEngine.shared`), opponent mode switches options on the same engine; Task 4 tests use .serialized suite; Task 15 benchmark reconfigures the shared engine — cost: no parallel analyst+opponent search (web was serial anyway).
- Ruling: Task 4 must always send EvalFile + EvalFileSmall + isready before any `go` (SF calls exit() otherwise) — carry into Task 4 brief.
- Ruling (1): add observable `pendingGradeCount: Int` + `func finalSnapshot() async -> GameSnapshot` (awaits queue drain or engine error); Task 14 saves via finalSnapshot() when the user leaves the game-over sheet — snapshots must include all verdicts — cost: small API addition.
- Ruling (2): expose observable `hasEngineError`; retry() works whenever hasEngineError is set (incl. .over) and resumes the drain from the failed job.
- Ruling (3): hint is non-critical — `@discardableResult func hint() async -> Bool` returns false on engine failure (no phase change, no .engineError); UI shows "Hint unavailable" — cost: signature change from brief, ledgered.
- Ruling (minor 3 promoted, tied to saving): takeBack() is a no-op after resign(); still allowed after checkmate/draw in .over (training value) — cost: none.
- Ruling: EngineHub.configure uses threads 1, hash 64 ("until measured", Plan 4 decides). Remove scenePhase recovery from EngineHub — StockfishEngine already auto-restarts on every EngineError (Task 4) and GameSession.retry() re-runs the step — cost: none; one less untested path.
- Ruling: 3:1-vs-both-squares badge requirement is physically infeasible (no colour clears 3:1 on both #D6D9D8 and #7D8483 except near-black) — accept 2 pt #131516 ring + dark glyph ink on all fills (ring 12.9:1 / 4.8:1) — meets the intent (badge separable from either square) — cost: deviates from mockup's white "??"; flagged for owner.
- Ruling: design gate signed off by controller (owner-delegated); "Pending owner review" list stays in decisions.md for morning.
- Ruling: 1k generation accepted (≥300 px/piece @3x met within budget).
- Ruling (Task 14): Game-over accuracy for the user only, via gameAccuracy over a whiteWin array reconstructed from user verdicts (after = winPercent(evalWhiteCp); before(mover) = after(mover) + winDrop; improving moves have winDrop 0 → approximation) — Verdict stores no before-eval; adding one is a schema change deferred — cost: slight accuracy approximation on improving moves.
- Ruling (2): on leaving with hasEngineError, auto-call retry() up to 2 times while awaiting finalSnapshot; if still failing, save the partial snapshot (Plan 2 bulk review re-analyzes games anyway) — cost: rare partial grading in stats.
- Ruling (3): move the MODE and PLAY AS segmented controls into the pinned bottom bar above the Play button; retake plan1-botpicker.png.
- Ruling: eval bar hidden in Silent mode (Silent = no coaching hints during play) — cost: none.
- Ruling: accuracy follows device locale (iOS norm). Ruling: CoachCard text may grow (no lineLimit truncation). Ruling: update decisions.md for avatar tile #7D8483 and captured-piece 22 pt (owner to confirm in morning).
- Ruling: accept — SF18 already uses the small net internally for simple positions; an app-size "small-only" build would need an engine patch, deferred to Plan 4 if app size matters — cost: one fewer data point.
- Ruling: mate 0 = side to move is mated → toCp gives -10000 from the side to move's view (deliberate deviation from web, recorded in web-rules.md); golden test; analysisVersion stays 1 (no saved games in the wild) — cost: none.
- Ruling: when the bot's move lands, prefetch analyze(new position, depth analysisDepth, multiPV 2, full history) so the next grade's "before" is a cache hit; hint() uses multiPV 2 to share that entry; correct benchmark doc claim — cost: engine busy while user thinks (fine, serial queue).
- Ruling: GameSnapshot gets schemaVersion (1) + lenient decoding (decodeIfPresent with defaults for every field added later; verdicts decoded leniently); GameRecord logs decode failures; Home shows nothing silently but logs; raw values of GameResult/PlayMode pinned by tests — cost: small.
- Ruling: also in the wave — vendor AUTHORS + VENDORED note with tag/SHA; SuspendingClock for the 30 s engine timeout; no false "Hint unavailable" when the user moved meanwhile; XcodeGen pre-build check failing the build if nets missing; retake plan1-gameover.png after the mate fix.
