"""Selects the bundled puzzle set from the Lichess puzzle CSV on stdin.

Columns: PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
Keeps Popularity >= 80, NbPlays >= 500, Rating 400-2399, then picks PER_BAND puzzles per
100-point band, spread round-robin over theme buckets (a puzzle's bucket is the first
priority theme it carries). Reservoir sampling with a fixed seed: same dump, same output.
Output (stdout): compact JSON array of [id, fen, "uci uci ...", rating, "theme theme ..."].
"""
import csv
import json
import random
import sys

PER_BAND = 300
RESERVOIR = 80
BANDS = range(400, 2400, 100)
# Rarer, more teachable themes first so they win the bucket.
PRIORITY = [
    "mateIn1", "mateIn2", "mateIn3", "fork", "pin", "skewer", "hangingPiece",
    "discoveredAttack", "backRankMate", "capturingDefender", "trappedPiece",
    "promotion", "deflection", "attraction", "endgame", "opening",
]
BUCKETS = PRIORITY + ["other"]

rng = random.Random(20261124)
reservoirs = {(b, k): [] for b in BANDS for k in BUCKETS}
seen = {key: 0 for key in reservoirs}
kept = 0

reader = csv.reader(sys.stdin)
next(reader, None)
for row in reader:
    if len(row) < 8:
        continue
    try:
        rating, popularity, plays = int(row[3]), int(row[5]), int(row[6])
    except ValueError:
        continue
    if popularity < 80 or plays < 500 or not (400 <= rating < 2400):
        continue
    themes = row[7].split()
    bucket = next((t for t in PRIORITY if t in themes), "other")
    key = (rating // 100 * 100, bucket)
    kept += 1
    seen[key] += 1
    res = reservoirs[key]
    item = [row[0], row[1], row[2], rating, row[7]]
    if len(res) < RESERVOIR:
        res.append(item)
    else:
        j = rng.randrange(seen[key])
        if j < RESERVOIR:
            res[j] = item

out = []
for band in BANDS:
    pools = [sorted(reservoirs[(band, k)]) for k in BUCKETS]
    for pool in pools:
        rng.shuffle(pool)
    picked = []
    while len(picked) < PER_BAND and any(pools):
        for pool in pools:
            if pool and len(picked) < PER_BAND:
                picked.append(pool.pop())
    out.extend(sorted(picked, key=lambda p: p[0]))
    print(f"band {band}: {len(picked)}", file=sys.stderr)

print(f"eligible {kept}, selected {len(out)}", file=sys.stderr)
json.dump(out, sys.stdout, separators=(",", ":"))
