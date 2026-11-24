# ChessCoach

A native iOS chess-coaching app (SwiftUI) that plays, analyzes and explains games with an on-device engine. No network, no LLM. Licensed under GPLv3.

Powered by Stockfish.

What's in it: play a bot (Training mode stops you after a mistake and explains it; Silent mode just plays), review any saved game (full-game analysis, move classes for both sides, the best move, trying your own lines), and a Profile with a rating estimate, accuracy trend and the mistakes you repeat. Where the code lives: [CODEMAP.md](CODEMAP.md).

## Build and run

Requires Xcode 26 (iOS 26 SDK) and XcodeGen.

```sh
brew install xcodegen
scripts/fetch-nnue.sh      # downloads the NNUE nets (gitignored); the build fails without them
xcodegen                   # generates ChessCoach.xcodeproj (gitignored); rerun after adding files
open ChessCoach.xcodeproj  # run the ChessCoach scheme on an iPhone simulator or device
```

From the command line (use a simulator id when more than one simulator is booted):

```sh
xcodebuild build -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcrun simctl install <sim-id> ~/Library/Developer/Xcode/DerivedData/ChessCoach-*/Build/Products/Debug-iphonesimulator/ChessCoach.app
xcrun simctl launch <sim-id> uz.xq.chessc
```

## Tests

```sh
(cd Packages/ChessCore && swift test)
(cd Packages/StockfishKit && swift test)
xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## DEBUG launch arguments

For simulator checks and screenshots (Debug builds only):

| Argument | Effect |
|---|---|
| `-debugScreen picker` | opens the bot picker |
| `-debugAutoplay <bot id>` | plays a Training game as White against that bot (`pip`, `ron`, …) to the end and saves it; `-debugMode silent` for Silent; `-debugHistory 1` looks back mid-game |
| `-debugReview latest` | opens the newest saved game in Review (`training`: the newest Training game); `-debugReviewStep 1` steps through every move, `-debugReviewPly blunder` (or a ply number) selects a move, `-debugReviewBranch 1` then tries the best move, `-debugReviewList 1` opens the move list |
| `-debugTab profile` | starts on the Profile tab; `-debugScroll bottom` scrolls it to the end |
| `-debugEmptyStore 1` | uses an empty in-memory store (first-launch look, saved games untouched) |
| `-engineBenchmark` | runs the engine benchmark headless |
