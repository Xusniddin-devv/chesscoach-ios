#ifndef STOCKFISH_BRIDGE_H
#define STOCKFISH_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Receives one engine output line (no trailing newline). Called on engine threads.
typedef void (*sf_line_callback)(const char *line, void *ctx);

/// Starts the UCI loop on its own thread; every stdout line goes to `cb`.
/// Ignored if the engine is already running.
void sf_start(sf_line_callback cb, void *ctx);

/// Enqueues one UCI line to the engine's stdin. Commands run one at a time, in order.
///
/// While a search runs (after `go`, until `bestmove`), send only `stop`, `ponderhit`,
/// `isready` or `quit`. Any other command (`ucinewgame`, another `go`, `setoption Hash`
/// or `Threads`, ...) blocks the engine's command loop until the search ends, and every
/// command queued behind it waits too; after `go infinite` that is forever.
void sf_send(const char *command);

/// Stops any running search, drops commands not yet read, sends `quit` and joins the
/// engine thread; `sf_start` may be called again afterwards. Returns promptly even if the
/// command loop is blocked waiting for a search.
void sf_quit(void);

/// Engine name and version, e.g. "Stockfish 18".
const char *sf_version(void);

#ifdef __cplusplus
}
#endif

#endif
