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
| `label` | `.caption2` | 11 semibold | Small labels. **No all-caps tracked labels** (de-slop): `SectionLabel` is 13 pt semibold secondary, sentence case ("Recent games", "Mode") |
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

**One pack: Icons8 "iOS 27 Filled" (`ios_filled`)**, locked in `icons8.json` (de-slop pass, 2026-11-24). PNGs fetched at 500 px and vectorised with potrace (owner decision), imported as SVG template assets `Icons/<name>` (Preserves Vector Data) so tokens tint them. Tab bar: `tab-home` (home), `tab-puzzle` (puzzle), `tab-learn` (open book), `tab-profile` (pawn — your piece). Game action bars: `resign` (flag), `close`, `hint` (idea bulb, also Review's Best), `back` / `forward` (chevrons), `flip` (sorting arrows), `moves` (list), `return` (undo, back to the game from a branch); `lock` on locked ladder bots; `edit` (pencil, Freeplay's Edit), `eraser` (editor tray), `guess` (help — question in a circle, Review's Guess); merge with feat/settings-paywall: `mic` (Play's Voice cell), `settings` (gear, Profile's top bar), `check`, `plus` / `minus`, `solution` (eye), and the onboarding glyphs (`puzzle`, `lesson`, `newplayer`, `play` = knight, `review` = target) redrawn from the same pack. The chess.com / Lichess logos are the one exception (brand marks from Icons8's logo set, only next to the platform name). System navigation chrome (back button, sheets) keeps its SF glyphs. Everywhere else: text labels, numerals, move-class glyph badges and our own piece / avatar art. No icon grids, no icon per stat row, no emoji. Attribution "Icons by Icons8 (icons8.com)" goes in Licenses (merge with feat/settings-paywall).

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
- **Player bars** (44 pt each, directly above and below the board): 32 pt avatar on the board-dark tile — the bot's figure, and for the user **their tier's cream piece** (`RatingTier`: Pawn < 800 … King ≥ 2100, the Pawn until there is an estimate; no letter tile), name `headline`, Elo `numeral` secondary, captured pieces on the right as 22 pt piece images (same-kind pieces overlap) + material lead "+2" in mono, for both bars.
- **Status line** (one quiet `subheadline` secondary line): the opening's name (lichess openings, `OpeningBook.deepest`) through move 12; then "Pip is thinking…", "Checking your move…" or the last grade "Nf3 · Best ★" (Training). Game over: the reason. Engine failure: "The engine stopped." with an accent "Retry" on the right.
- **History** (read-only): ‹ › or a tap in the strip shows an earlier position; the board is not interactive, the viewed move's grade is marked on the board, and a "Back to live" chip (`surface2` capsule) sits at the right of the status line. If the bot moves meanwhile the view stays where it is and the chip gets a 6 pt accent dot. The user's own move, a Training interrupt or the end of the game return to live.
- **Action bar** (de-slop, Liquid Glass ruling): **flat** `GameActionBar` on `surface` running to the bottom edge, 1 pt `surface2` hairline on top, equal cells of a 24 pt Icons8 icon over an 11 pt medium label: Resign (Close before the first move and after the game) · Hint (Training) · Back · Forward · Flip. Pressed: `surface2` cell + 0.96 press-in; disabled: in place at 30 %; a toggle that is on (Review's Best): accent. No glass on game screens (refs: `references/deslop/notes.md`).
- **Coach card** on a training interrupt: slides up **in place of the action bar** (the bar fades out), opaque `surface` with a 1 pt `surface2` hairline, top corners `Radius.large`, bottom corners concentric with the screen's. It never covers the board: when it would, the board shrinks by up to 8 % in place, then the stack moves up into its free space, then the board shrinks the rest (animated); the user bar and status line under it fade out. Content: verdict header (the real `MoveBadge` disc + class name in its colour, sentence case "Blunder"), explanation in `body`, Take back (`SecondaryButton`) + Show best (`PrimaryButton`) side by side, Continue as a plain text button under them. Not glass: it is content (anti-slop rule).
- Danger red appears only in the blunder pill/badge/tint/strip glyph — never as a screen background.

## Review (refs: `references/review/`)

Screens: `screens/plan2-review-analysing.png`, `-blunder.png`, `-branch.png`, `-moves.png`; end-to-end check on a Training game: `screens/plan2-verify-review.png`, `-verify-branch.png`. Pushed from Home's recent games (and Profile's history); tab bar hidden, system back button, inline title "vs Rookie Ron" with the opening name as the subtitle.

- **Scaffold**: the Play layout (`GameBoardScaffold`). Flat action bar: Moves (inside a branch: Game, back to the game) · Best (accent when shown; enabled on negative moves) · Back · Forward · Flip.
- **Analysis**: runs once per game (depth 14, MultiPV 2, both colours) the first time the game is opened, then stored in the record. Status line "Analysing 13 / 25" with a 96 pt accent progress capsule on the right; moves can be stepped meanwhile, the board is read-only. Error: "Analysis stopped" + accent "Retry", inline.
- **Accuracy**: in the navigation subtitle as plain text, "You 50.6 · Rookie Ron 91.6" (locale decimal), once analysed; the opening name / date before. No accuracy chips in the bars.
- **Board**: the selected move's destination in its class tint + `MoveBadge`; best-move arrow (accent) when toggled on a negative move; eval bar from the analysis' win %.
- **Strip**: every move of both sides carries its class glyph.
- **Comment card** above the action bar for every graded move, in the coach card's language (same verdict header, body, surface + hairline): one sentence ("Nf3 is the best move.", "Rookie Ron played Bxg5, a book move."); the user's own inaccuracy / mistake / miss / blunder gets the full `explain` text. Opaque `surface`, 1 pt `surface2` hairline, `Radius.large`. The stack keeps 146 pt for it at all times so the board never resizes while stepping (a taller card moves the stack up, it does not shrink the board); the status line sits in that room when there is no card (start position, analysing, checking a branch move).
- **Branches**: a move on the board that differs from the game starts a line from the shown position; its moves sit on `surface2` tiles in the strip, are graded live and in order (`LineGrader`), and are never saved. A move that equals the line's next move just steps forward.
- **Move list** (sheet, medium / large): ACCURACY (You / bot), class count rows per side (only classes that occur), then the moves in rows of two with class glyphs; the selected move on a `surface2` tile.

## Profile (concept: `concepts/profile-concept.png`, refs: `references/profile/`)

Screens: `screens/plan2-profile-empty.png`, `screens/plan2-profile.png`, `screens/plan2-profile-bottom.png`. The first version (rating card, three stat tiles, line chart, card list, all-caps tracked labels) was rejected by the owner as generic; this is the controller's concept. Tab "Profile", large title "You", 20 pt margins, sentence-case section titles (20 pt semibold, −0.3 tracking, 30 pt above). No all-caps labels and no stat tiles on this screen.

- **Your piece** (hero, 250 pt): rating tiers are pieces — `RatingTier` Pawn < 800, Knight 800–1199, Bishop 1200–1499, Rook 1500–1799, Queen 1800–2099, King ≥ 2100. "Your piece" (15 pt secondary), the estimate in 96 pt heavy with −4 tracking, the tier name 26 pt bold; the tier's cream piece art 250 pt bleeding off the right edge with a soft drop shadow. Progress to the next tier: 8 board-square cells (10 pt, radius 2, 3 pt gaps; filled cells alternate board light / dark, empty `surface2`) and the next tier's piece at 45 % at the end; "260 points to Bishop" (13 pt secondary). Goal line under the tier name: "Goal 1500 by May · 656 to go" (onboarding's saved goal, measured from the estimate, else the platform rating; "reached" once there); hidden until a goal exists. Settings: the Icons8 gear in Profile's top bar pushes Settings (Home has no gear). Under 3 finished games: the Pawn, "Pawn" at 64 pt, three cells for the games played, "Play 3 games to find your piece" · "1 of 3 played".
- **Your last games**: horizontal filmstrip (to the screen edge) of 112 pt `MiniBoardView`s of the final position (the user's side at the bottom, real piece art), a result tag on the corner (`background` chip, 11 pt bold: Won in accent, Lost / Drawn / Unfinished muted); below: 20 pt bot avatar on board dark, name 13 pt, accuracy "91%" SF Mono 12 secondary. Tap → Review.
- **How you move**: the average accuracy of the last 10 games in 44 pt heavy, "accuracy, last 7 games", and the change on the 10 games before ("↑ 6" accent / "↓ 3" muted, hidden without earlier games). Move-quality ribbon: one stacked column per game (120 pt, radius 4), bottom → top good-or-better (best green), inaccuracy, mistake (+ miss), blunder in the move-class colours; legend with 8 pt squares, 12 pt secondary.
- **What keeps costing you**: the top habit as a `surface` card (radius 18, 14 pt padding): a 118 pt mini board of the real position after the user's move, destination tinted with the class colour and badged; the habit said to the player ("You leave pieces undefended", 17 pt semibold); one line from that move ("Like Bg5 here — Rookie Ron took it for free."); red pips = games with the habit out of graded games (7 max, scaled). "Fix it · 5 puzzles" (accent, 3 pt darker edge) opens five puzzles for that habit: the player's own positions with it first, then other own mistakes, then bank puzzles on its themes (`BlunderPuzzles.fixIt`; the free daily allowance applies). Other habits as rows: title 16 pt + 5 pips, `surface2` hairlines.
- Sections without data are left out (no placeholder chart or empty cards); an empty profile is the Pawn hero and "Play a bot and your games show up here."
- The estimate also sets the player's level (`EngineHub.playerRating`): Training thresholds and explanation wording (words below 1200), default 800 until 3 games.

## Bot picker → sparring ladder (refs: `references/bot-picker/`, Chessigma notes)

- Pushed from Home, large title "Sparring".
- **Ladder** (`BotLadder`, ChessCore): the 8 bots in order as characters, 52 pt figures on board-dark tiles joined by a 2 pt rail (lit `textSecondary` up to the last beaten bot, `surface2` beyond). Each rung: name `headline` + Elo mono secondary, then its state: "Beaten · 2 wins" (wins from saved games), **"Next up"** in accent for the first open unbeaten bot (also the default selection and Home's "Next up"), the blurb for other open bots, or a 13 pt lock + "Beat Cadet to unlock" with the figure desaturated at 35 %. Pip, Rookie Ron and Cadet are always open; a bot also opens when the previous one is beaten or the player's estimate is within 100 of it. Locked rows can't be selected. Selected row: `surface` rounded row + 2 pt accent ring on the figure.
- **Settings** pinned in the bottom bar above the Play button (Mode Training / Silent with one sentence; Play as White / Black / Random), labels sentence case.
- **Start**: `PrimaryButton` "Play Rookie Ron".

## Game over — result panel (refs: `references/game-over/`, `references/deslop/notes.md`)

De-slop pass (owner: "AI slop in match score modal"). Screen: `screens/plan4-deslop-gameover.png`.

- Sheet over the final position, **opaque `surface`** (content, not glass), one height detent from its content, close button top-right, buttons pinned at the bottom.
- **Header** (FotMob / Fixtured pattern): your tier piece | score | bot figure, 64 pt tiles, name + tier name / Elo under each; the winner's tile gets a 2 pt accent ring. Centre: "1 – 0" (from your side) in 40 pt heavy, one small line under it: "You won by checkmate" / "Pip won by checkmate" / "You resigned" / "Draw by stalemate". No result word block, no mono score line.
- **Accuracy**: one plain heavy 34 pt number per side under its player, "Accuracy" small in the middle. No ring gauge.
- **Move quality**: per side, chips of the real badge disc + count (only classes that occur, brilliant → blunder) on `background` capsules, centred under that side.
- The bot is not graded live, so the panel runs the full analysis (`GameAnalyzer`, Review depth 14) as soon as the live grades are in; the bot side shows "Checking Pip's moves" + a thin progress line until it lands, then both sides switch to the analysis' numbers. The analysis is saved with the game (Review opens without analysing). Rematch / New bot / close cancel it (saved without; Review analyses later); Review game waits for it ("Analysing… 64%").
- **Key moment**: the move with the biggest win-% drop (≥ 10, either side once analysed) on a 112 pt mini board with its badge, "Key moment · move 14", the verdict header and the coach's line (Review's comment wording). Hidden in a clean game.
- **Buttons**: Review game (`PrimaryButton`), Rematch + New bot (`SecondaryButton`s side by side). New bot opens the ladder; Review game opens the saved game in Review.
- Win only: a quiet confetti burst (36 flat pieces, 60 % opacity, 1.8 s, once) clipped to the header, behind it. Nothing with Reduce Motion.

## Analysis board — Freeplay (refs: `references/freeplay/notes.md`)

Screen: `screens/plan4-freeplay.png`. Pushed from Home's "Analysis board" card (a quiet `surface` card: title, "Continue · Italian Game · 4 moves" or "Move both sides. Every move gets a grade.", a 64 pt `MiniBoardView` of the line's position; the Play card stays the one accent). Inline title "Analysis board", the opening (or "Start position" / "Your position") as the subtitle, tab bar hidden.

- **Scaffold**: the Play layout. Bars are the two colours ("White" / "Black", the king on the board-dark tile, captured pieces + lead). Eval bar always on (the shown position's own search, depth 14; the last eval holds while the next search runs).
- **Moves**: either side moves on the board; every move is graded live and in order (`LineGrader`, depth 14, the Review semantics), badge on the destination + glyph in the strip. A move at an earlier position replaces the rest of the line (no variations); the line's own next move just steps forward.
- **Status line**: "Nf3 · Best ★", "Bxf7+ · Mistake ? · best O-O", "Checking Nf3…", "White to move", or the result ("Checkmate · White wins").
- **Flat action bar**: Edit (position editor, Icons8 `edit`) · Best (a mode: the arrow of the engine's best move in the shown position stays on from move to move; accent when on) · Take back (`return`) · Back · Forward · Flip.
- **Deep**: a text toggle in the navigation bar (navigation layer, so system glass is fine there): accent "Deep" = depth 20 for the eval bar and the best move; grades stay at 14 so they match Review.
- **Autosave**: an owner-less `GameRecord` (`source: "freeplay"`, `botId` empty, `userColor` White as the nominal colour, Silent), updated in place after every move and when grades land; an empty fresh board is not saved. Freeplay lines never count: Profile (`ProfileModel`), the rating, the ladder's wins and Home's recent games skip `isFreeplay`.

## Position editor (refs: `references/freeplay/notes.md`)

Screen: `screens/plan4-editor.png`. Full-screen cover from Freeplay's Edit; inline title "Edit position", close (system xmark) left, Flip right. No FEN anywhere.

- Board on top (takes the room the controls leave). Under it one `surface` tray: two rows of six pieces (White, Black: K Q R B N P) and a tall eraser cell; the selected tool sits on `surface2` with a 2 pt accent ring. Tap a square to place the tool's piece (the same piece again removes it); a king moves instead of doubling; drag pieces around the board, off the board to remove, or from the tray onto a square.
- "White to move | Black to move" (system segmented control). "White can castle [Kingside] [Queenside]" and the same for Black: on = light chip with ink text, off = `surface2`; a right whose king or rook is off its home square is greyed out (the choice is kept and returns when the piece does).
- "Clear board" · "Start position" as quiet `surface2` buttons; one inline message line: the first `PositionValidator` problem with a small inaccuracy-yellow dot ("Add a black king.", "Only one white king, please.", "Black's king is in check, so it has to be Black to move.", "Pawns can't stand on the first or last rank.", "White has more than 16 pieces.") or a quiet hint. "Analyse this position" (`PrimaryButton`, 40 % while invalid) starts a new Freeplay line from it.

## Guess the move

Screens: `screens/plan4-guess.png`, `screens/plan4-guess-result.png`. From Review's flat bar ("Guess", Icons8 `help`; enabled once the game is analysed), pushed; title "Guess the move", subtitle "You as White · 3 / 18".

- **Pick a side**: a card in place of the action bar (the coach card's language): "Whose moves will you guess?", one line on the points, two side options (avatar, name, "White · 18 moves"; selected = `surface2` + accent ring), Start.
- **Guessing**: the board shows the position before each of that side's moves (the other side's moves play themselves, last move highlighted); flat bar End · Skip · Flip; status "Move 12 · what would you play?".
- **Reveal**: card in place of the bar: three rows with the real badge discs — "Your move", "You played" / "Pip played", "Best" — and the points on the right in 40 pt heavy ("+3" in accent, else text). On the board each move is an arrow in its class colour (one arrow when moves coincide) and the guess's badge sits on its destination. "Next move" / "See your score".
- **Scoring** (`GuessScoring`): the saved best move 3, within 50 cp 2, within 150 cp 1, else 0. The game's own move and the saved best need no engine; any other move is searched (depth 14, MultiPV 3) and classified like a played move.
- **Score screen**: "Your score", the points in 96 pt heavy (−4 tracking) with "of 27" beside it, one sentence ("You found the best move 4 times. Your moves in the game would have scored 15."), "Move by move" as a grid of result chips (badge disc, your move, points; 3 in accent) on `surface` capsules. Back to review (`PrimaryButton`), Try again (`SecondaryButton`). No gauge, no confetti, no headline exclamation.

## Settings, paywall, Pro gates (merge of feat/settings-paywall, 2026-11-24)

Screens: `screens/merged-settings.png`, `-paywall.png`, `-licenses.png`, `-review-free.png`. Paywall references and rules: `references/paywall/notes.md`.

- Settings is pushed from Profile's gear: Your games (Import games — Pro after onboarding's free first import), Play (default mode, "Show moves as" — shows the level's wording until the player picks one, coordinates), Feedback (sounds, haptics, voice), Coach Pro, About (Licenses, source, version), Reset all data.
- Pro gates are UI only; every analysis is computed and saved for everyone. Training: the coach card's explanation. Review: move classes on the board and in the strip, the comment card (free users see the coach and "Unlock full review"), Best and trying lines (the move is not played; the paywall opens). Guess the move. Freeplay's Deep. Puzzles beyond five a day (daily free). Lessons after the first per track. Re-importing games.
- Voice: a "Voice" cell in Play's flat bar (hold to talk; accent "Listening" while held), when enabled in Settings.
- Coach character: Play's coach card and Review's comment card show the coach figure (pose from the move class) beside the verdict header; the text is chip-aware (`[e4]` squares as board chips, the move in bold).
- Puzzle solver, lesson player, Learn and Puzzles tabs: see "Training screens" below.

## Training screens — final design (owner picks: Duolingo Chess + Chessigma, 2026-11-24)

Screens: `screens/final-puzzle.png`, `-puzzle-hint.png`, `-puzzle-solved.png`, `-puzzle-wrong.png`, `-puzzle-solution.png`, `-lesson.png`, `-lesson-question.png`, `-lesson-wrong.png`, `-learn.png`, `-learn-popover.png`, `-puzzles-tab.png`. References: `references/redesign-r1/m-duo-*.img` (Duolingo Chess puzzle, mate, path), `references/chessigma/` (narrator, square chips, "Which move?", locked bosses).

- **One frame** (`App/Features/Shared/TrainingFrame.swift`) for the solver and the lesson player, Duolingo's structure in our tokens: top row = Icons8 close + a thick segmented progress bar (one segment per puzzle / per move to play; done = accent with a highlight stripe, missed = blunder red, current = accent outline) + the puzzle rating in SF Mono. Under it the coach knight (84 pt) narrating in bubbles: the current line in a `surface` speech bubble (semibold, square / move chips, bold), the line before it above, smaller and dimmed — the session reads as a story (Chessigma). The board edge to edge, centred between the narration and the bottom row (equal spacers). Bottom row: a square chunky Hint button + a full-width chunky button (disabled while solving).
- **Chunky** = a solid face over a 4 pt darker edge the face sinks into when pressed (`ChunkyButtonStyle`), the only depth device; no shadows, no gradients.
- **Verdict band** slides up over the bottom row, full width, 26 pt top corners, into the home-indicator area: accent "Solved first try · +8" (the puzzle-rating change, Elo from first outcomes, `ChessCore/Puzzles/PuzzleRating.swift`), or blunder red "Not quite · −6" with "[Nh3+] was the fork." and Show solution / Retry (then Skip / Retry). White chunky primary button in the band's colour. Success / error haptic. The board shows the verdict like Review: Best ★ (Brilliant !! for a clean solve ≥ 200 above the player) on the solving move, Mistake on a wrong one. Reduce Motion: the band fades instead of sliding.
- **Coach lines** for puzzles: the opponent's last move as a chip ("Black played [g3]."), the task ("White to move. **Find the fork.**" — the chosen or the puzzle's first theme), the hint ("Start with the piece on [f4]."), then the solution explained (`PuzzleExplainer`: what the move attacks, mate, what it wins).
- **Lessons**: the coach narrates each step (the lesson's summary, the last move's note, the question). Scripted lines ask "Which move will develop a knight and attack the [e5] pawn?" with 2–3 real answer pills under the board (piece glyph + SAN in mono; the right move and other moves of the same piece first); the board accepts the move too. Right → accent band "Correct" + the step's note; wrong → red band "Not this one. [Nf3] is the move here." and the piece marked on the board; end → "Lesson complete" with Next lesson / Again.
- **Learn tab**: a dark winding path. Each track is a unit with a chunky banner ("Unit 1 · Openings", its goal, progress bar, 3/12 in mono; accent for the unit in progress, `surface` otherwise). Lessons are round chunky tokens (74 pt) with Icons8 piece glyphs by subject (queen / rook / bishop / knight / pawn / king), snaking ±76 pt: done = accent with a check badge, next = accent with a pulsing ring and the coach standing beside it, later = dimmed, Pro = lock. Each unit ends with a **boss**: the sparring bot (Rookie Ron, Blaze, Cadet) on a bigger token — a dark silhouette and "Boss · ???" until the unit's lessons are done, then the figure on the board-dark tile; beating it (a saved win) clears the unit (check badge). Tapping a token opens a popover anchored to it (title, meta, summary, chunky Start / Unlock with Pro / Play Ron).
- **Puzzles tab** (fix wave): the coach at the top carries the streak and today's hook from the daily puzzle's solution ("Day 3 of your streak. Today's puzzle is a knight fork."); the daily puzzle hero; own mistakes as a filmstrip; Practice = a scrubbable rating ruler (the onboarding goal picker's bars: one per 50 points, height from the rating distribution, accent up to the level, value on the handle, haptic tick per 50) and the themes as a vertical list — a chunky round token with the theme's Icons8 piece glyph, name, one line, solved count as ten small ticks; tapping a row starts practice there. No pills, no stepper, no streak pill. Screens: `final-puzzles-tab.png`, `-practice.png`, `-themes.png`.
- **Home** (fix wave): no greeting and no orange block. A compact header (streak; rating → goal "960 → 1500 by May" over a thin accent line), the coach (118 pt) with a line written from real data (last game, the habit that keeps costing, today's hook: "You beat Pip earlier today. Now: 5 of your own mistakes, then **Cadet**."), today's plan as a three-token path joined by a track (two practice steps, then the bot to play as the boss token with its avatar; done = check badge, current = pulsing ring, next = dim) with one chunky "Start · …" for the current step, a quiet "Sparring ladder · next up Cadet" link, and "Continue": the analysis board and the recent games as a filmstrip of final positions with result tags (Profile's `GameThumb`). New player: "No streak yet · 0 of 3 games to your rating", the coach's welcome, the default path (daily puzzle → next lesson → Pip). Screens: `final-home.png`, `final-home-new.png`.
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
