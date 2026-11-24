#!/usr/bin/env bash
# Regenerates Packages/ChessCore/Sources/ChessCore/Resources/puzzles.json from the CC0
# Lichess puzzle database. Streams the dump (~300 MB compressed) through zstd into the
# filter; the full CSV is never written to disk. Needs curl, zstd, python3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Packages/ChessCore/Sources/ChessCore/Resources/puzzles.json"
URL=https://database.lichess.org/lichess_db_puzzle.csv.zst

curl -fsSL "$URL" | zstd -dc | python3 -I "$ROOT/scripts/filter-puzzles.py" > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
ls -l "$OUT"
