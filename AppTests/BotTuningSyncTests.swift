import Foundation
import Testing
import ChessCore
@testable import ChessCoach

/// Serves one canned response for `BotTuningSync.url`.
final class TuningStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var hits = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hits += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor struct BotTuningSyncTests {
    let defaults: UserDefaults
    let session: URLSession

    init() {
        defaults = UserDefaults(suiteName: "BotTuningSyncTests-\(UUID().uuidString)")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TuningStubProtocol.self]
        session = URLSession(configuration: config)
        TuningStubProtocol.hits = 0
        TuningStubProtocol.status = 200
    }

    @Test func downloadedTuningIsAppliedCachedAndThrottled() async throws {
        defer { BotTuning.current = .builtIn }
        var tuning = BotTuning.builtIn
        tuning.uciEloOffset = 400
        TuningStubProtocol.body = try JSONEncoder().encode(tuning)
        let now = Date(timeIntervalSince1970: 1_000_000)

        await BotTuningSync.refresh(defaults: defaults, session: session, now: now)
        #expect(BotTuning.current.uciEloOffset == 400)
        #expect(botStyle(elo: 1600) == .limited(uciElo: 1320, movetimeMs: 800))

        await BotTuningSync.refresh(defaults: defaults, session: session, now: now.addingTimeInterval(3_600))
        #expect(TuningStubProtocol.hits == 1)  // within a day: no second download

        BotTuning.current = .builtIn
        BotTuningSync.applyCached(defaults: defaults)
        #expect(BotTuning.current.uciEloOffset == 400)
    }

    @Test func brokenOrMissingFileKeepsCurrentTuning() async throws {
        defer { BotTuning.current = .builtIn }
        BotTuning.current = .builtIn
        TuningStubProtocol.body = Data("not json".utf8)
        await BotTuningSync.refresh(defaults: defaults, session: session)
        #expect(BotTuning.current == .builtIn)
        TuningStubProtocol.status = 404
        TuningStubProtocol.body = try JSONEncoder().encode(BotTuning.builtIn)
        await BotTuningSync.refresh(defaults: defaults, session: session)
        #expect(BotTuning.current == .builtIn && defaults.data(forKey: BotTuningSync.cacheKey) == nil)
    }
}
