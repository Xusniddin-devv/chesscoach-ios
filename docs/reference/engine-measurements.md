# Engine measurements

Stockfish 18 through the StockfishKit C bridge (`Packages/StockfishKit`). Device numbers come in Plan 4.

## macOS baseline (2026-11-24)

- Machine: Apple M1 (8 cores), macOS 26.5.1, Swift 6.3.3 / Xcode 26.6.
- Build: `swift test -c release --filter BridgeTests`; StockfishCore compiled with `-O3`, `USE_NEON=8`, `USE_POPCNT`, `IS_64BIT`, `NNUE_EMBEDDING_OFF`, `NDEBUG` (no dotprod, no LTO).
- Engine defaults: Threads 1, Hash 16 MB.

| Step (startpos) | Wall time |
| --- | --- |
| Start + `uci` + load both nets (`EvalFile`, `EvalFileSmall`) + `isready` | 0.32–0.38 s |
| Whole `searchesWithNetsLoaded` session: start, load nets, `go depth 8` to `bestmove`, `quit` | 0.32 s (test reports 0.47 s incl. harness) |
| `go depth 8` search alone (engine-reported `time`) | 4–5 ms, 3,260 nodes, ~0.8 Mnps |

Depth 8 result: `score cp 36`, `bestmove e2e4 ponder e7e5`.

Net loading (the 104 MB big net) dominates a session, so Task 4 should keep one engine running and load the nets once, not per search.

## iOS Simulator (Mac host), 2026-11-24

- Host: Apple M1 (8 cores), macOS 26.5.1, iPhone 17 Pro Simulator, Debug app build (StockfishCore still `-O3`). Host numbers, not device numbers.
- Harness: `App/Debug/EngineBenchmark` (DEBUG only). Warm engine, one discarded warm-up pass, then 20 graded moves of a Ruy Lopez (Chigorin) line, each `analyze(before)` + `analyze(after)` at depth 16, MultiPV 2, full history; the one-entry cache makes `before` of move N+1 free, as in the app. Hash 64 MB. Also the depth reached by `go movetime 300` from the position after 10 plies.
- Run: launch with `-engineBenchmark` (headless, writes `Documents/engine-benchmark.md`), or Profile tab > "Engine benchmark (debug)" > Run, then "Copy as Markdown".
- Single run each, so expect a few percent of noise (the 2-thread row is probably noise or contention, not a trend).

| Threads | Nets | Avg ms per graded move (depth 16, MultiPV 2) | Depth in go movetime 300 |
| --- | --- | --- | --- |
| 1 | big+small | 648 | 17 |
| 2 | big+small | 868 | 16 |
| 4 | big+small | 612 | 17 |

- Small-only was not measured. The planned way (`EvalFile` = small net) does not work: the big and small nets have different architectures, so Stockfish 18 cannot load the small file as `EvalFile` and exits the process at the first `go` (`nnue/network.cpp`, "The engine will be terminated now"). Forcing small-only needs a patch to `Eval::use_smallnet` in the vendored engine (decision pending).
- Device numbers are pending (owner's iPhone). Until then the default stays big+small nets, 1 thread, 64 MB hash.
