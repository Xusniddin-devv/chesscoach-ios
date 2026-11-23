# Design decisions — Plan 1 (Task 12 design gate)

Identity: "Charcoal & Signal Orange" (spec → Design). Approved mockup: `references/theme-dark.html` option B, `references/dark-shot.png`. Board is neutral stone `#D6D9D8` / `#7D8483`. References for each screen: `references/<screen>/notes.md`.

Status: **proposed, pending owner review** (see the last section). Nothing here is self-approved.

---

## Type

**Font: system only.** SF Pro for words, SF Mono (`design: .monospaced`) for numbers that change or must line up: clocks, Elo, accuracy, scores, move numbers. No bundled display face.

Why: SF gives Dynamic Type, every weight and correct iOS metrics for free. The tool-like Teenage Engineering / Nothing tone in the references (`home/dribbble-nothing-os-weather.jpg`, `play/dribbble-ko-ii-iphone.jpg`, `game-over/dribbble-football-dark-mono.jpg`) comes from mono numerals next to plain sans labels, not from a novelty display font. Space Grotesk / Inter / Poppins are not used.

Type scale (`DS.Font`, sizes at the default Dynamic Type size):

| Token | Style | Size / weight | Use |
|---|---|---|---|
| `largeTitle` | `.largeTitle` | 34 bold | Home greeting, Game-over result word |
| `title` | `.title2` | 22 bold | Screen titles inside content, card titles on the accent card |
| `headline` | `.headline` | 17 semibold | Row titles (bot name), buttons |
| `body` | `.body` | 17 regular | Coach explanation, body copy |
| `subheadline` | `.subheadline` | 15 regular | Bot blurb, secondary lines (60 % text) |
| `caption` | `.caption` | 12 regular | Dates, small meta |
| `label` | `.caption2` | 11 semibold, UPPERCASE, tracking 0.8 | Section labels ("RECENT GAMES", "ACCURACY", "MODE") |
| `numeralLarge` | `.largeTitle` mono | 34 semibold | Accuracy on Game over, streak count |
| `numeral` | `.headline` mono | 17 medium | Elo, stat values, score line "1 – 0" |
| `clock` | `.title3` mono | 20 semibold | Chess clocks (when timed games arrive) |
| `badgeGlyph` | fixed | 12 heavy | Move-class badge glyph (fixed: the badge is a fixed 22 pt disc) |

## Spacing (`DS.Spacing`, 4 pt grid)

`xs 4` · `s 8` · `sm 12` · `m 16` · `l 24` · `xl 32`.
Screen side margin = `m` (16). Card padding = `m`. Gap between cards = `sm` (12). Gap between sections = `l` (24). Row vertical padding = `sm`.

## Radii (`DS.Radius`, unchanged values, now with fixed roles)

| Token | Value | Use |
|---|---|---|
| `small` | 8 | Board outer corners, 32–40 pt avatar tiles, class pill |
| `medium` | 14 | Buttons, 64 pt avatar tiles |
| `large` | 20 | Content cards (Home cards, coach card, list containers) |
| Capsule | — | Streak pill, segmented controls (system) |

Reference: card radii of ~20 in `home/mobbin-apple-fitness-summary.jpg` and `home/dribbble-nothing-os-weather.jpg`; the approved mockup uses 18.

## Icons

SF Symbols **only where Apple uses them**: the tab bar (Home `house.fill`, Puzzles `puzzlepiece.fill`, Learn `book.fill`, Profile `person.fill`) and toolbar / navigation-bar buttons (close `xmark`, resign `flag`, flip board `arrow.up.arrow.down`, hint `lightbulb`). Everywhere else: text labels, numerals, move-class glyph badges and our own piece / avatar art. No icon grids, no icon per stat row, no emoji (the approved mockup's 🔥 in the streak pill is replaced by a numeral — see Home).

## Move-class palette

Each class colour is a badge **fill**; the glyph on it uses `DS.Color.moveClassGlyph` (ink `#131516` for every class in this palette); every badge has a 2 pt ring in `#131516` (`DS.Color.moveClassRing`).

**The brief's "≥ 3:1 against both #D6D9D8 and #7D8483" cannot be met by any usable hue.** Relative luminance: board light 0.68, board dark 0.225. A colour needs luminance ≤ 0.19 for 3:1 on the light square and either ≤ 0.04 or ≥ 0.78 for 3:1 on the dark square, so only near-black colours (luminance ≤ 0.04) pass both — and the fixed blunder red `#FF3B46` is 2.48:1 / 1.08:1. Even pure black only reaches 14.8:1 / 5.5:1. So the 3:1 separation from both squares is delivered by the **ring**: `#131516` is **12.89:1** on board light and **4.80:1** on board dark. The fills are chosen for mutual distinguishability and readable glyphs instead. See `references/move-class-badges.png` (all 11 at real size on both squares).

Computed with WCAG 2.x relative luminance (script in the Task 12 report):

| Class | Glyph | Fill | Fill vs `#D6D9D8` | Fill vs `#7D8483` | Glyph colour | Glyph contrast | Ring vs light / dark |
|---|---|---|---|---|---|---|---|
| brilliant | !! | `#22B3A6` | 1.83 | 1.47 | `#131516` | 7.04 | 12.89 / 4.80 |
| great | ! | `#4F8CE0` | 2.40 | 1.12 | `#131516` | 5.37 | 12.89 / 4.80 |
| best | ★ | `#6DAA3C` | 1.98 | 1.36 | `#131516` | 6.51 | 12.89 / 4.80 |
| excellent | ✓ | `#A4C766` | 1.35 | 1.99 | `#131516` | 9.54 | 12.89 / 4.80 |
| good | ✓ | `#93B07C` | 1.69 | 1.59 | `#131516` | 7.62 | 12.89 / 4.80 |
| book | B | `#B48A62` | 2.19 | 1.23 | `#131516` | 5.89 | 12.89 / 4.80 |
| forced | → | `#AEB2B1` | 1.51 | 1.78 | `#131516` | 8.55 | 12.89 / 4.80 |
| inaccuracy | ?! | `#F2C14E` | 1.18 | 2.28 | `#131516` | 10.91 | 12.89 / 4.80 |
| mistake | ? | `#F59A2E` | 1.55 | 1.74 | `#131516` | 8.32 | 12.89 / 4.80 |
| miss | ✗ | `#F2786B` | 1.93 | 1.40 | `#131516` | 6.69 | 12.89 / 4.80 |
| blunder | ?? | `#FF3B46` | 2.48 | 1.08 | `#131516` | 5.20 | 12.89 / 4.80 |

Glyph rule: of white and ink, use the one with the higher contrast on the fill (must be ≥ 4.5:1). Ink wins for all 11 (white on blunder red is only 3.52:1). This also fixes the Task 11 carry-forward (white glyph on pale classes).

Distinguishability (CIE76 ΔE between fills): closest pairs best/excellent 17.2 (also differ by glyph ★ vs ✓), inaccuracy/mistake 22.7, excellent/good 23.6; every other pair ≥ 29. Mistake vs brand accent `#FF6A1A`: ΔE 28.5. No purple, no neon: saturation is kept moderate, the only fully saturated fill is the spec's blunder red.

Other uses of the class colour: destination `squareTint` = class fill at 45 % opacity over the square; coach-card pill = class fill with ink text.

## Pieces (`App/Resources/Assets.xcassets/Pieces/{w,b}{k,q,r,b,n,p}`)

- Style C soft matte 3D, generated one piece per image with Higgsfield `gpt_image_2_6` (1k, high), references: approved sheet job `597af496-…` + our first king (job `33675b7a-…`) to lock camera, light and framing. The first black pawn came out slimmer than the white one and was regenerated from the white pawn (job `435ae713-…`).
- Cut out locally (flat-background flood fill with soft alpha and colour decontamination). Higgsfield `remove_background` was tried on the king and left a faint grey fringe on light squares; the local cut-out was cleaner.
- Normalised: shared baseline at 96 % of the canvas, king 92 % of canvas height, other pieces by fixed ratio of the king (from the approved reference sheet, nudged up for small-size legibility): Q 0.90, B 0.84, N 0.82, R 0.72, P 0.66. Centred on the base, so knights sit like the other pieces.
- Square transparent canvas, 180 pt (@1x 180, @2x 360, @3x 540 px). Smallest piece (pawn) is 327 px tall at @3x. `BoardView` draws each image aspect-fit into the square.
- Cream `#F1E6CF`-ish and dark slate. **Both knights face left** (no mirroring for black), as in the approved sheet.
- Review: `references/pieces-final-sheet.png` (all 12 on both square colours at 44 pt, a full position, and 22 / 30 pt sizes).

## Bot avatars (`App/Resources/Assets.xcassets/Bots/<id>`)

Piece-derived figures in the same matte material, no faces. Transparent square canvas 128 pt (@3x 384 px), figure fitted into the centre 80 %. Shown on a **board dark `#7D8483`** rounded tile (`Radius.medium` at 64 pt, `Radius.small` at 32–40 pt). Task 14 changed this from `surface2`: the slate figures (Wall, Vera, Apex) were dark-on-dark there, while on the board's dark-square colour all eight read (cream bright, orange vivid, slate separated) — each avatar is a piece on a dark square. The accent Play card on Home shows its avatar without a tile.

| id | Figure | Why |
|---|---|---|
| pip | small plump cream pawn with a sage leaf | "just learning" — sprout |
| ron | cream pawn in an orange cap | rookie |
| cadet | cream pawn in a slate cadet cap with orange band | disciplined basics |
| blaze | all-orange knight with a flame-like mane | aggressive attacker |
| wall | very wide slate rook, stone courses | defensive fortress |
| maestro | cream bishop with a slate scarf | positional, refined |
| vera | slim slate queen with orange crown tips | sharp, precise |
| apex | slate king with orange cross on a plinth | full strength |

Ladder reads cream → slate as strength rises. Review: `references/bots-final-sheet.png`.

---

## Home (refs: `references/home/`)

- **Header**: left-aligned `largeTitle` greeting ("Good evening") (Blinkist title row). Streak pill on the right **from Plan 3** (streak ships with Puzzles): capsule on `surface2`, numeral in `numeral` mono + accent colour, `label` "DAY STREAK" — no flame emoji (Speak orange numerals, pillowtalk numeral tiles). Plan 1 shows the title only.
- **Primary card**: full-width "Play a bot" card, the only accent-filled surface on the screen (CALC-1 "one orange key"; approved mockup). 132 pt tall, `Radius.large`, `title` in white, subline "Next up: Pip · 600" with Elo in mono, the next bot's avatar art bottom-right (64 pt). Tapping pushes the Bot picker.
- **Secondary tiles** (Daily puzzle, Review): 2-up opaque `surface` tiles with a `label` on top and a `title`/numeral value (Apple Fitness grid, Nothing OS tiles). **Not shown in Plan 1** — those features don't exist yet, and placeholder tiles would be filler.
- **Recent games**: `label` "RECENT GAMES", then one `surface` container (`Radius.large`) with up to 5 rows separated by hairlines: 32 pt avatar tile, "vs Pip" `headline` + date `caption` secondary, result on the right in `numeral` mono ("1–0", "0–1", "½–½") with a word under it in `caption` (Won / Lost / Draw). No colour coding beyond text; danger red is reserved for blunders. Empty state: one secondary line "Your games will show up here." — no illustration.
- Tab bar: system Liquid Glass. No glass on cards. No centred hero, no 3-card marketing row.

## Play (refs: `references/play/`)

- Full screen, tab bar hidden; navigation bar with glass toolbar buttons: close / resign (`xmark` → confirm resign), flip (`arrow.up.arrow.down`), hint (`lightbulb`, Training mode only).
- **Opponent row** (top) and **user row** (bottom), each 44 pt: 32 pt avatar tile (`surface2`, `Radius.small`; user = accent tile with initial), name `headline`, Elo `numeral` secondary, captured pieces on the right as a tight row of 22 pt piece images (same-kind pieces overlap) + material diff "+2" in mono (NICKELFOX rows, Duolingo clock rows).
- **Board**: full width minus 8 pt each side, `Radius.small` outer corners, no frame or shadow (think. shot, Duolingo edge-to-edge). Eval bar: 6 pt vertical bar at the board's left edge, white/ink split, inside the 8 pt margin budget. Coordinates inside edge squares in `label` size, colour = the opposite square colour. Legal-move dots: ink at 22 % opacity, 30 % of square; captures: 4 pt ring. Last move: accent at 30 % on from/to. Verdict: class `squareTint` on the destination + `MoveBadge` overlapping the destination's top-right corner by 6 pt (Duolingo ring-on-square). Best-move arrow: accent at 85 %.
- **Coach card** on a training interrupt: opaque `surface` card under the board, `Radius.large`, never covering the board (Duolingo feedback panel). Top: class pill (class fill, ink text, `label` style "?? BLUNDER"). Body: explanation in `body`, max 3 lines. Buttons: Take back (`SecondaryButton`) + Show best (`PrimaryButton`) side by side, Continue as a plain text button under them.
- Danger red appears only in the blunder pill/badge/tint — never as a screen background.

## Bot picker (refs: `references/bot-picker/`)

- Pushed from Home, large title "Choose a bot".
- **List**: one `surface` container (`Radius.large`) with 8 rows and hairline separators (Meta AI voice list, Character AI). Row: 40 pt avatar tile, name `headline` + Elo in `numeral` secondary on the same line, blurb in `subheadline` secondary, max 2 lines. Selected row: `surface2` background + 2 pt accent ring around the avatar tile; no checkmark icon. All 8 visible by scrolling — no carousel (rejects the Dribbble 3D carousel).
- Default selection: the bot whose Elo is closest to `PlayerProfile.defaultRating` (800 → Rookie Ron).
- **Settings** pinned in the bottom bar above the Play button, so they are always visible while the list scrolls (Apple Games setup rows): `label` "MODE" + system segmented picker Training / Silent with one one-line secondary sentence for the selected mode (Runna); `label` "PLAY AS" + segmented White / Black / Random.
- **Start**: `PrimaryButton` "Play Rookie Ron" at the bottom of that pinned bar.

## Game over (refs: `references/game-over/`)

- System sheet (glass, medium + large detents) over the final position, so the board stays visible above it.
- Top: result word in `largeTitle` ("You won" / "You lost" / "Draw"), reason in `subheadline` secondary ("Checkmate", "Resigned", "Stalemate"), score line "You 1 – 0 Pip" in `numeral` mono (football mono score).
- **Accuracy**: `numeralLarge` "87.4" with `label` "ACCURACY", inside a flat 270° accent arc (Acorns arc, score-ring shot) — stroke only, no gradient. While grades are still pending: `label` "ANALYSING 3 MOVES" + system progress, numeral shows "—".
- **Stats rows** (Uxcel label/value rows): Best / Mistakes / Blunders counts, label left, mono value right, no per-row icons.
- **Buttons**: Play again (`PrimaryButton`) + Done (`SecondaryButton`), stacked (Quizlet).
- Win only: a 1.2 s flat confetti burst (rectangles in accent, board light, board dark) drawn with SwiftUI `Canvas`. Loss and draw use the same layout without confetti (Duolingo loss screen — no shaming art).

---

## Pending owner review

Look at these first, in this order:

1. **`references/pieces-final-sheet.png`** — do the 12 pieces read as one set at 44 pt on both stone squares? Specifically: pawn size (66 % of king), cream pieces on the light square, both knights facing left.
2. **`references/move-class-badges.png`** — the 3:1-against-both-squares requirement is mathematically impossible for any hue (see Move-class palette); the proposal is a 2 pt dark ring on every badge plus **ink glyphs on all fills** (the approved mockup had a white "??" on red). Confirm or pick another treatment (e.g. dark disc with coloured glyph).
3. **`references/bots-final-sheet.png`** — avatar personas; the slate figures (Wall, Vera, Apex) are dark-on-dark on the `surface2` tile; Pip's sage leaf is the only colour outside the core palette.
4. Mistake orange `#F59A2E` vs brand accent `#FF6A1A` (ΔE 28.5) — distinct, but both orange.
5. Home in Plan 1 shows no Daily puzzle / Review tiles and no streak (those ship in Plan 3; no placeholders); when the streak arrives, the pill drops the mockup's 🔥 emoji for a numeral.
6. **Avatar tile colour** is board dark `#7D8483` (Task 14), not `surface2`: slate figures are legible; the cost is a mid-grey tile in every list row. See `screens/plan1-botpicker.png`, `screens/plan1-home.png`.
7. **Captured-piece size** in the Play rows is 22 pt (was 16 pt), so the matte pieces stay recognisable. See `screens/plan1-gameover.png` (opponent row).
8. Credits: pieces 17.25 (13 images × 1.25 + one background-removal trial 1.0), avatars 8.0 (8 × 1.0) — within the 20 / 10 budgets.
