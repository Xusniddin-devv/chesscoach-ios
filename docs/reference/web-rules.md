# Rules recovered from the live web app

Source: minified production bundle of https://xq-chesscoach.netlify.app, downloaded 2026-11-24 (chunks `5142-c95fd325a4c75258.js`, `1668-092efd5923c1c058.js`, `app/play/page-77015c930dfdaa93.js`). This is the July 29–30 code that never reached GitHub. The Swift port must reproduce these exactly; golden tests pin them.

Notation: `mover` = side that played the move, `w`/`b`. Scores are UCI scores `{cp, mate}` from the side to move's view, as Stockfish reports them.

## Score → centipawns (from a given side's view)

```
toCp(score, side):  v = score.mate != nil ? sign(mate) * (10000 - 10*|mate|) : (score.cp ?? 0)
                    return side == "w" ? v : -v          // "side" = side to move in that position
```
(i.e. result is White-relative cp; mates map to ±(10000 − 10·N)).

## Win percentage (White-relative cp → White win %)

```
winPercent(cp) = 50 + 50 * (2 / (1 + exp(-0.00368208 * clamp(cp, -1500, 1500))) - 1)
```

## Per-move inputs (classifyPlayed)

```
sideToMoveAfter = fenAfter field 2
s = toCp(before.lines[0].score, mover)           // White cp before
c = toCp(after.lines[0].score, sideToMoveAfter)  // White cp after
u = mover == w ? 1 : -1
cpLoss      = max(0, u * (s - c))
wasBest     = before.bestMove == playedUci || cpLoss <= 5
gapToSecond = before.lines.count >= 2 ? max(0, u * (toCp(lines[0], mover) - toCp(lines[1], mover))) : 0
winBefore   = mover == w ? winPercent(s) : 100 - winPercent(s)        // mover's win %
winDrop     = max(0, winBefore - (mover == w ? winPercent(c) : 100 - winPercent(c)))
mateBefore  = before.lines[0].score.mate > 0 ? that : nil     // "hadMate"
mateAfter   = after.lines[0].score.mate  > 0 ? that : nil     // mate for the opponent (side to move after)
legalMoveCount = legal moves in fenBefore (30 if FEN fails to parse)
isBook      = ply <= 8 && cpLoss <= 35                         // heuristic, not the ECO table
isSacrifice = see below
```

## Classification (precedence order)

```
if legalMoveCount <= 1                                         → forced
winAfter = winBefore - winDrop
if (hadMate || winBefore >= 85) && winAfter < 70               → miss
if isSacrifice && (wasBest || cpLoss <= 30) && winBefore < 90 && winAfter >= 50 → brilliant
if isBook                                                       → book
if wasBest && gapToSecond >= 150                                → great
if wasBest                                                      → best
if winDrop >= 20 → blunder;  >= 10 → mistake;  >= 5 → inaccuracy
if cpLoss <= 20 → excellent  else → good
```
Negative classes (get motifs + explanation): `inaccuracy, mistake, miss, blunder`.

Display table (web colors — to be re-picked for the iOS palette; glyphs stay):

| class | label | glyph | web color |
|---|---|---|---|
| book | Book | B | #a88865 |
| brilliant | Brilliant | !! | #26c2a3 |
| great | Great | ! | #5c8bb0 |
| best | Best | ★ | #95bb4a |
| excellent | Excellent | ✓ | #96bc4b |
| good | Good | ✓ | #96af8b |
| forced | Forced | → | #9a9a94 |
| inaccuracy | Inaccuracy | ?! | #f0c15c |
| mistake | Mistake | ? | #e58f2a |
| miss | Miss | ✗ | #ff7769 |
| blunder | Blunder | ?? | #ca3431 |

## Piece values, en prise, sacrifice

`value = {p:1, n:3, b:3, r:5, q:9, k:100}`

```
isEnPrise(fenAfter, playedUci, mover):
  piece = pieceAt(fenAfter, to); require piece.color == mover
  attackers = attackers(to, by: opponent); if none → false
  defenders = attackers(to, by: mover)
  return defenders.isEmpty || min(value of attackers) < value(piece)

capturedValue(fenBefore, uci):
  target = pieceAt(fenBefore, to); if target → value(target)
  if pieceAt(fenBefore, from) is pawn && from.file != to.file → 1   // en passant
  return 0

isSacrifice(fenBefore, fenAfter, uci, mover) =
  isEnPrise(fenAfter, uci, mover) && value(pieceAt(fenAfter, to)) > capturedValue(fenBefore, uci)
```

## Motifs (only for negative classes), in this order

Facts: `fenBefore, fenAfter, playedUci, playedSan, bestUci (= before.bestMove or playedUci), bestPv, bestReplyUci (= after.bestMove), cpLoss (rounded), evalAfterWhiteCp (rounded c), mateForMoverBefore, mateAgainstMoverAfter, moveNumber (FEN field 6), mover`.

1. `allowed-mate`: mateAgainstMoverAfter != nil
2. `missed-mate`: mateForMoverBefore != nil && mateAgainstMoverAfter == nil && cpLoss > 200
3. `hanging-piece`: isEnPrise(fenAfter, playedUci, mover)
4. `allowed-fork`: bestReplyUci exists && cpLoss >= 150; play bestReplyUci on fenAfter; count mover's pieces of value >= 3 attacked by the replying piece from its destination; >= 2 → true
5. `missed-capture`: cpLoss >= 100 && bestUci on fenBefore is a capture (incl. en passant)
6. `opening-principle`: moveNumber <= 10 && cpLoss >= 50 && moved piece is a queen && moveNumber <= 5

## Explanation template (no LLM)

```
names = {p:pawn, n:knight, b:bishop, r:rook, q:queen, k:king}
motifText = {
  hanging-piece:     "your piece can simply be captured there",
  missed-mate:       "you had a forced checkmate available",
  allowed-mate:      "this allows a forced checkmate against you",
  allowed-fork:      "this lets the opponent fork two of your pieces",
  missed-capture:    "you missed a capture that wins material",
  opening-principle: "this breaks an opening principle (develop minor pieces before the queen)" }

explain(facts, motifs, label, level = 1200):
  bestSan = SAN of bestUci in fenBefore (fallback: the uci)
  why = motifs.first.map(motifText) ??
        "it gives up about \(cpLoss/100, 1 decimal) pawns of advantage"
        + (level < 1200 ? " (chess engines measure positions in pawn-units: +1.0 means being one pawn ahead)" : "")
  better = level < 1200 ? "\(bestSan) — \(words(bestUci))" : bestSan
  words(uci) = target piece ? "your <piece> on <from> takes the <target> on <to>" : "your <piece> moves from <from> to <to>"
  return "\(playedSan) is a \(label): \(why). Better was \(better)."
```
The iOS app may rewrite this copy to be warmer (spec: describe moves in words for beginners) but must keep the same inputs and branches.

## Training-mode interrupt severity (play page, cp-loss based, by level)

```
level < 1000:  inaccuracy 120, mistake 250, blunder 450
level < 1600:  inaccuracy  80, mistake 180, blunder 350
else:          inaccuracy  50, mistake 120, blunder 250
cpLoss >= blunder → blunder; >= mistake → mistake; >= inaccuracy → inaccuracy; else good
```
Web used the bot's Elo as `level`; the iOS spec uses the player's estimated rating.

## Accuracy (per game, per color)

```
win[i] = White win % at position i (i = 0...N, from toCp of each position's best line)
window = clamp(round(N/10), 2, 8)
for each move i by color c:
  winC(i) = c == w ? win[i] : 100 - win[i]
  acc = clamp(103.1668 * exp(-0.04354 * max(0, winC(i) - winC(i+1))) - 3.1669, 0, 100)
  weight = clamp(stddev(win[max(0, i+1-window) ... i+1]), 0.5, 12)     // population stddev of the slice
accuracy(c) = moves of c empty ? 100 :
  round( ( Σ acc·w / Σ w  +  Σ w / Σ (w / max(acc, 1)) ) / 2 , 1 decimal )   // mean of weighted arithmetic and weighted harmonic
```
`ANALYSIS_VERSION` on web = 3.

## Engine strength + pacing

Levels (web): 600 Beginner I, 800 Beginner II, 1000 Novice I, 1200 Novice II, 1320 Club I, 1500 Club II, 1700 Strong I, 1900 Strong II, 2100 Advanced, 2300 Expert.

```
t = clamp((elo - 600) / 1700, 0, 1)
skillLevel = round(20 * t);  depth = round(4 + 11 * t)
opponent: setoption UCI_LimitStrength false; setoption Skill Level <skillLevel>; go depth <depth> movetime 2500
thinkTimeMs(elo, jitter∈[0,1)) = round((450 + 1250 * t) * (0.7 + 0.6 * jitter))
```
(Shipped code did NOT use UCI_Elo; Skill Level + depth for all levels.)

Always `position fen <startFen> moves <uci…>` when history exists. Default `go depth 14` if none given.
Analysis cache key: `"\(depth)|\(startFen ?? fen)|\(moves.joined(" "))"`.

## Bot personas

| id | name | elo | blurb |
|---|---|---|---|
| pip | Pip | 600 | Just learning — will hang pieces right alongside you. |
| ron | Rookie Ron | 800 | Knows the rules but misses most tactics. |
| cadet | Cadet | 1000 | Solid basics. Punishes obvious blunders. |
| blaze | Blaze | 1300 | Aggressive attacker — keep your king safe. |
| wall | The Wall | 1600 | Patient and defensive. Hard to break down. |
| maestro | Maestro | 1900 | Strong positional understanding. |
| vera | Vera | 2100 | Sharp, precise, and quick to pounce. |
| engine | Stockfish → **rename** (trademark) | 2300 | Full strength. Good luck. |
