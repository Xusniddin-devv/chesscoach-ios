#!/usr/bin/env bash
# Vendors Stockfish source (GPLv3) into the StockfishKit package.
# Usage: scripts/vendor-stockfish.sh [tag]   (default tag: sf_18)
set -euo pipefail

TAG="${1:-sf_18}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Packages/StockfishKit/Sources/StockfishCore/stockfish"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" https://github.com/official-stockfish/Stockfish "$WORK/Stockfish"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$WORK/Stockfish/src/." "$DEST/"
rm -f "$DEST/main.cpp" "$DEST/Makefile"
cp "$WORK/Stockfish/Copying.txt" "$DEST/Copying.txt"

echo "Vendored Stockfish $TAG into $DEST"
