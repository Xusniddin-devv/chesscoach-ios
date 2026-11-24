import Testing

/// The bridge owns one global Stockfish (std::cin/std::cout), so every test that drives it
/// lives in a suite nested here and runs one at a time, never interleaved with another.
@Suite(.serialized)
struct GlobalEngineSuite {}
