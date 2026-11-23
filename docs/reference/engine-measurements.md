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
