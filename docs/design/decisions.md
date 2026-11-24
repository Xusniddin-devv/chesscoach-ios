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

## Play (refs: `references/play/`, layout: `references/play-layout/`)

Plan 2 layout (owner: "the board is on the top side and the bottom is blank space — center the board"). Play and Review share `GameBoardScaffold` (`App/Features/Shared/`). Screens: `screens/plan2-play-live.png`, `-coach.png`, `-history.png`, `screens/plan2-gameover.png`.

- Full screen, tab bar and navigation bar hidden. Top → bottom, as **one centred stack**: move strip, opponent bar, board, user bar, status line. The stack is centred between the top safe area and the action bar, so the free space splits evenly above and below (`BoardStackGeometry`, measured, no fixed offsets).
- **Board**: as wide as the screen allows — full width minus 8 pt each side, the eval bar in the left margin — and only smaller when the height runs out (small phones). `Radius.small` outer corners, no frame or shadow. Eval bar: 6 pt vertical bar 1 pt left of the board's edge (it follows the board when it shrinks), white/ink split, Training only. Coordinates inside edge squares in `label` size, colour = the opposite square colour. Legal-move dots: ink at 22 % opacity, 30 % of square; captures: 4 pt ring. Last move: accent at 30 % on from/to. Verdict: class `squareTint` on the destination + `MoveBadge` overlapping the destination's top-right corner by 6 pt. Best-move arrow: accent at 85 %.
- **Move strip** (36 pt): one horizontal, scrollable line "1. e4 e5 2. Nf3 …", move numbers in mono secondary, SAN in `subheadline`; the current ply is semibold with a 2 pt accent underline and stays scrolled into view. A graded user move carries its class glyph in the class colour (Training; Silent shows grades only after the game). Before the first move: "No moves yet". Tapping a ply shows that position.
- **Player bars** (44 pt each, directly above and below the board): 32 pt avatar tile (bot: board-dark tile; user: accent tile with initial), name `headline`, Elo `numeral` secondary, captured pieces on the right as 22 pt piece images (same-kind pieces overlap) + material lead "+2" in mono.
- **Status line** (one quiet `subheadline` secondary line): the opening's name (lichess openings, `OpeningBook.deepest`) through move 12; then "Pip is thinking…", "Checking your move…" or the last grade "Nf3 · Best ★" (Training). Game over: the reason. Engine failure: "The engine stopped." with an accent "Retry" on the right.
- **History** (read-only): ‹ › or a tap in the strip shows an earlier position; the board is not interactive, the viewed move's grade is marked on the board, and a "Back to live" chip (`surface2` capsule) sits at the right of the status line. If the bot moves meanwhile the view stays where it is and the chip gets a 6 pt accent dot. The user's own move, a Training interrupt or the end of the game return to live.
- **Action bar**: system Liquid Glass capsules in a `safeAreaBar`, SF Symbols only, neutral glyphs: resign `flag` (close `xmark` before the first move and after the game) · hint `lightbulb` (Training) · `chevron.left` `chevron.right` sharing one capsule · flip `arrow.up.arrow.down`. Disabled buttons stay in place at 30 % (hint off the user's turn or while viewing history; ‹ at the start; › when live).
- **Coach card** on a training interrupt: slides up **in place of the action bar** (the bar fades out), opaque `surface` with a 1 pt `surface2` hairline, top corners `Radius.large`, bottom corners concentric with the screen's. It never covers the board: when it would, the board shrinks by up to 8 % in place, then the stack moves up into its free space, then the board shrinks the rest (animated); the user bar and status line under it fade out. Content unchanged: class pill (class fill, ink text, `label` style "?? BLUNDER"), explanation in `body`, Take back (`SecondaryButton`) + Show best (`PrimaryButton`) side by side, Continue as a plain text button under them. Not glass: it is content (anti-slop rule).
- Danger red appears only in the blunder pill/badge/tint/strip glyph — never as a screen background.

## Review (refs: `references/review/`)

Screens: `screens/plan2-review-analysing.png`, `-blunder.png`, `-branch.png`, `-moves.png`. Pushed from Home's recent games (and Profile's history); tab bar hidden, system back button, inline title "vs Rookie Ron" with the opening name as the subtitle.

- **Scaffold**: the Play layout (`GameBoardScaffold`). Action bar: move list `list.bullet` (inside a branch: back to the game `arrow.uturn.backward`) · best move `lightbulb` / `lightbulb.fill` when shown (enabled on negative moves) · `chevron.left` `chevron.right` · flip.
- **Analysis**: runs once per game (depth 14, MultiPV 2, both colours) the first time the game is opened, then stored in the record. Status line "Analysing 13 / 25" with a 96 pt accent progress capsule on the right; moves can be stepped meanwhile, the board is read-only. Error: "Analysis stopped" + accent "Retry", inline.
- **Player bars**: each side's accuracy at the trailing edge, `subheadline` mono semibold on a `surface2` tile (`Radius.small`).
- **Board**: the selected move's destination in its class tint + `MoveBadge`; best-move arrow (accent) when toggled on a negative move; eval bar from the analysis' win %.
- **Strip**: every move of both sides carries its class glyph.
- **Comment card** above the action bar for every graded move: class pill + one sentence ("Nf3 is the best move.", "Rookie Ron played Bxg5, a book move."); the user's own inaccuracy / mistake / miss / blunder gets the full `explain` text. Opaque `surface`, 1 pt `surface2` hairline, `Radius.large`. The stack keeps 146 pt for it at all times so the board never resizes while stepping (a taller card moves the stack up, it does not shrink the board); the status line sits in that room when there is no card (start position, analysing, checking a branch move).
- **Branches**: a move on the board that differs from the game starts a line from the shown position; its moves sit on `surface2` tiles in the strip, are graded live and in order (`LineGrader`), and are never saved. A move that equals the line's next move just steps forward.
- **Move list** (sheet, medium / large): ACCURACY (You / bot), class count rows per side (only classes that occur), then the moves in rows of two with class glyphs; the selected move on a `surface2` tile.

## Profile (concept: `concepts/profile-concept.png`, refs: `references/profile/`)

Screens: `screens/plan2-profile-empty.png`, `screens/plan2-profile.png`, `screens/plan2-profile-bottom.png`. The first version (rating card, three stat tiles, line chart, card list, all-caps tracked labels) was rejected by the owner as generic; this is the controller's concept. Tab "Profile", large title "You", 20 pt margins, sentence-case section titles (20 pt semibold, −0.3 tracking, 30 pt above). No all-caps labels and no stat tiles on this screen.

- **Your piece** (hero, 250 pt): rating tiers are pieces — `RatingTier` Pawn < 800, Knight 800–1199, Bishop 1200–1499, Rook 1500–1799, Queen 1800–2099, King ≥ 2100. "Your piece" (15 pt secondary), the estimate in 96 pt heavy with −4 tracking, the tier name 26 pt bold; the tier's cream piece art 250 pt bleeding off the right edge with a soft drop shadow. Progress to the next tier: 8 board-square cells (10 pt, radius 2, 3 pt gaps; filled cells alternate board light / dark, empty `surface2`) and the next tier's piece at 45 % at the end; "260 points to Bishop" (13 pt secondary). Goal line ("Goal 1200 by March · on track") comes with onboarding; hidden until a goal exists. Under 3 finished games: the Pawn, "Pawn" at 64 pt, three cells for the games played, "Play 3 games to find your piece" · "1 of 3 played".
- **Your last games**: horizontal filmstrip (to the screen edge) of 112 pt `MiniBoardView`s of the final position (the user's side at the bottom, real piece art), a result tag on the corner (`background` chip, 11 pt bold: Won in accent, Lost / Drawn / Unfinished muted); below: 20 pt bot avatar on board dark, name 13 pt, accuracy "91%" SF Mono 12 secondary. Tap → Review.
- **How you move**: the average accuracy of the last 10 games in 44 pt heavy, "accuracy, last 7 games", and the change on the 10 games before ("↑ 6" accent / "↓ 3" muted, hidden without earlier games). Move-quality ribbon: one stacked column per game (120 pt, radius 4), bottom → top good-or-better (best green), inaccuracy, mistake (+ miss), blunder in the move-class colours; legend with 8 pt squares, 12 pt secondary.
- **What keeps costing you**: the top habit as a `surface` card (radius 18, 14 pt padding): a 118 pt mini board of the real position after the user's move, destination tinted with the class colour and badged; the habit said to the player ("You leave pieces undefended", 17 pt semibold); one line from that move ("Like Bg5 here — Rookie Ron took it for free."); red pips = games with the habit out of graded games (7 max, scaled). "Fix it · 5 puzzles" (accent, 3 pt darker edge) appears once Puzzles is merged (`ProfileView.onFix`, nil on this branch). Other habits as rows: title 16 pt + 5 pips, `surface2` hairlines.
- Sections without data are left out (no placeholder chart or empty cards); an empty profile is the Pawn hero and "Play a bot and your games show up here."
- The estimate also sets the player's level (`EngineHub.playerRating`): Training thresholds and explanation wording (words below 1200), default 800 until 3 games.

## Bot picker (refs: `references/bot-picker/`)

- Pushed from Home, large title "Choose a bot".
- **List**: one `surface` container (`Radius.large`) with 8 rows and hairline separators (Meta AI voice list, Character AI). Row: 40 pt avatar tile, name `headline` + Elo in `numeral` secondary on the same line, blurb in `subheadline` secondary, max 2 lines. Selected row: `surface2` background + 2 pt accent ring around the avatar tile; no checkmark icon. All 8 visible by scrolling — no carousel (rejects the Dribbble 3D carousel).
- Default selection: the bot whose Elo is closest to `PlayerProfile.defaultRating` (800 → Rookie Ron).
- **Settings** pinned in the bottom bar above the Play button, so they are always visible while the list scrolls (Apple Games setup rows): `label` "MODE" + system segmented picker Training / Silent with one one-line secondary sentence for the selected mode (Runna); `label` "PLAY AS" + segmented White / Black / Random.
- **Start**: `PrimaryButton` "Play Rookie Ron" at the bottom of that pinned bar.

## Game over (refs: `references/game-over/`)

- System sheet (glass) over the final position, so the board stays visible above it. Plan 2: one height detent measured from its content (result, accuracy, stats rows, buttons), so the stats rows never sit under the buttons (`screens/plan1-gameover.png` clipped "Blunders"); content taller than the screen scrolls.
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
