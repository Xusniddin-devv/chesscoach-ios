#!/usr/bin/env bash
# Downloads the Stockfish 18 NNUE nets into StockfishKit's resources (gitignored).
# Nets are named by hash: the first 12 hex chars of each file's SHA-256 must match its name.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Packages/StockfishKit/Sources/StockfishKit/Resources/nnue"
NETS=(nn-c288c895ea92.nnue nn-37f18f62d772.nnue)
MIRRORS=(https://tests.stockfishchess.org/api/nn https://data.stockfishchess.org/nn)

mkdir -p "$DEST"

hash_matches() {
  local file="$1" name="$2"
  local expected="${name#nn-}"; expected="${expected%.nnue}"
  local actual; actual="$(shasum -a 256 "$file" | cut -c1-12)"
  [[ "$actual" == "$expected" ]]
}

for name in "${NETS[@]}"; do
  target="$DEST/$name"
  if [[ -f "$target" ]]; then
    if hash_matches "$target" "$name"; then
      echo "ok      $name (already present)"
      continue
    fi
    echo "stale   $name (hash mismatch, re-downloading)"
    rm -f "$target"
  fi

  for mirror in "${MIRRORS[@]}"; do
    echo "fetch   $mirror/$name"
    if curl -fsSL --retry 2 -o "$target.part" "$mirror/$name" && hash_matches "$target.part" "$name"; then
      mv "$target.part" "$target"
      break
    fi
    rm -f "$target.part"
  done

  if [[ ! -f "$target" ]]; then
    echo "error: could not download a valid $name" >&2
    exit 1
  fi
  echo "ok      $name"
done
