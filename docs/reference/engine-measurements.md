# Engine measurements

Stockfish 18 through the StockfishKit C bridge (`Packages/StockfishKit`). Device numbers come in Plan 4.

## macOS baseline (2026-11-24)

- Machine: Apple M1 (8 cores), macOS 26.5.1, Swift 6.3.3 / Xcode 26.6.
- Build: `swift test -c release --filter BridgeTests`; StockfishCore compiled with `-O3`, `USE_NEON=8`, `USE_POPCNT`, `IS_64BIT`, `NNUE_EMBEDDING_OFF`, `NDEBUG` (no dotprod, no LTO).
- Engine defaults: Threads 1, Hash 16 MB.

| Step (startpos) | Wall time |
| --- | --- |
| Start + `uci` + load both nets (`EvalFile`, `EvalFileSmall`) + `isready` | 0.32–0.38 s |
| Whole `searchesWithNetsLoaded` session: start, load nets, `go depth 8` to `bestmove`, `quit` | the row above plus the 4–5 ms search, so ≈0.33–0.39 s of engine time; Swift Testing reports 0.47 s and 0.64 s for the test (two runs, 2026-11-24), the rest being test-process and harness overhead |
| `go depth 8` search alone (engine-reported `time`) | 4–5 ms, 3,260 nodes, ~0.8 Mnps |

Depth 8 result: `score cp 36`, `bestmove e2e4 ponder e7e5`.

Net loading (the 104 MB big net) dominates a session, so Task 4 should keep one engine running and load the nets once, not per search.

## iOS Simulator (Mac host), 2026-11-24

- Host: Apple M1 (8 cores), macOS 26.5.1, iPhone 17 Pro Simulator, Debug app build (StockfishCore still `-O3`). Host numbers, not device numbers.
- Harness: `App/Debug/EngineBenchmark` (DEBUG only). Warm engine, one discarded warm-up pass, then 20 graded moves of a Ruy Lopez (Chigorin) line, each `analyze(before)` + `analyze(after)` at depth 16, MultiPV 2, full history. The benchmark grades every ply, so the one-entry cache makes `before` of move N+1 free and a graded move costs one search. The app grades only the user's moves, so on its own the user's next `before` would be a second search; `GameSession` prefetches it when the bot's move lands (same request, so the grade hits the cache), which runs it while the user thinks. The wait for a grade after the user's move is therefore one search, which is what this number measures. Hash 64 MB. Also the depth reached by `go movetime 300` from the position after 10 plies.
- Run: launch with `-engineBenchmark` (headless, writes `Documents/engine-benchmark.md`), or Profile tab > "Engine benchmark (debug)" > Run, then "Copy as Markdown".
- Single run each, so expect a few percent of noise (the 2-thread row is probably noise or contention, not a trend).

| Threads | Nets | Avg ms per graded move (depth 16, MultiPV 2) | Depth in go movetime 300 |
| --- | --- | --- | --- |
| 1 | big+small | 648 | 17 |
| 2 | big+small | 868 | 16 |
| 4 | big+small | 612 | 17 |

- Small-only was not measured. The planned way (`EvalFile` = small net) does not work: the big and small nets have different architectures, so Stockfish 18 cannot load the small file as `EvalFile` and exits the process at the first `go` (`nnue/network.cpp`, "The engine will be terminated now"). Forcing small-only needs a patch to `Eval::use_smallnet` in the vendored engine (decision pending).
- Device numbers are pending (owner's iPhone). Until then the default stays big+small nets, 1 thread, 64 MB hash.

## Bot calibration (2026-11-25)

`BOT_CALIBRATION=1 swift test --filter BotCalibration` in `Packages/StockfishKit`: each bot plays
itself from 6 openings, 40 plies each, every move's loss measured at depth 12 (clamped ±1000).
Human reference ACPL (rough): 600 120+, 800 90, 1000 70, 1300 55, 1600 45, 1900 35, 2300 25.

| Bot | Old Skill Level mapping* | Run 1 (T 170/120/85/55, offset 150) | Run 2 (T 300/220/160/100, MultiPV 12, offset 250) |
|---|---|---|---|
| Pip 600 | — | 73 | 155 |
| Ron 800 | — | 54 | 107 |
| Cadet 1000 | — | 48 | 83 |
| Blaze 1300 | — | 39 | 71 |
| Wall 1600 | — | 39 | 55 |
| Maestro 1900 | — | 31 | 31 |
| Vera 2100 | — | 23 | 29 |
| Apex 2300 | — | 23 | 31 |

*Not measured; Stockfish's lowest calibrated strength is ~1320 CCRL, so every bot below it
played at 1300+. Shipped values (`BotTuning.builtIn`, gh-pages `config/bots.json`) sit between
run 1 and run 2. Run 2's limited bots shared the CPU with an archive build.
