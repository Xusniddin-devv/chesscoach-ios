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

/// Enqueues one UCI line to the engine's stdin.
void sf_send(const char *command);

/// Sends `quit` and joins the engine thread; `sf_start` may be called again afterwards.
void sf_quit(void);

/// Engine name and version, e.g. "Stockfish 18".
const char *sf_version(void);

#ifdef __cplusplus
}
#endif

#endif
