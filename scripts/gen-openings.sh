#!/usr/bin/env bash
# Regenerates Packages/ChessCore/Sources/ChessCore/Resources/openings.json from the
# CC0 lichess-org/chess-openings dataset. Fails if any line cannot be replayed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE=https://raw.githubusercontent.com/lichess-org/chess-openings/master
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for f in a b c d e; do
  curl -fsSL "$BASE/$f.tsv" -o "$TMP/$f.tsv"
done

cd "$ROOT/Packages/ChessCore"
swift run -c release GenOpenings "$TMP" "$ROOT/Packages/ChessCore/Sources/ChessCore/Resources/openings.json"
