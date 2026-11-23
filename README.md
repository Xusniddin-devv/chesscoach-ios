# ChessCoach

A native iOS chess-coaching app (SwiftUI) that plays, analyzes and explains games with an on-device engine. No network, no LLM. Licensed under GPLv3.

Powered by Stockfish.

## Build

```sh
brew install xcodegen
scripts/fetch-nnue.sh      # downloads the NNUE nets (gitignored)
xcodegen                   # generates ChessCoach.xcodeproj (gitignored)
open ChessCoach.xcodeproj
```

Tests: `xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
