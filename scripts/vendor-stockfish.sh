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
cp "$WORK/Stockfish/AUTHORS" "$DEST/AUTHORS"

SHA="$(git -C "$WORK/Stockfish" rev-parse HEAD)"
cat > "$DEST/VENDORED.md" <<EOF_NOTE
# Vendored Stockfish

- Upstream: https://github.com/official-stockfish/Stockfish
- Tag: $TAG
- Commit: $SHA
- Vendored on: $(date -u +%Y-%m-%d) (UTC)
- Copied: \`src/\` (without \`main.cpp\` and \`Makefile\`), \`Copying.txt\` (GPLv3), \`AUTHORS\`.
- Unmodified: the app's changes live outside this folder (\`../bridge.cpp\`).

Re-vendor with \`scripts/vendor-stockfish.sh $TAG\`.
EOF_NOTE

echo "Vendored Stockfish $TAG into $DEST"
