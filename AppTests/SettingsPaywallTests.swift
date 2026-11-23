import Testing
import Foundation
import SwiftData
import ChessCore
@testable import ChessCoach

@MainActor
struct SettingsPaywallTests {
    @Test func soundForSAN() {
        #expect(SoundPlayer.effect(forSAN: "e4") == .move)
        #expect(SoundPlayer.effect(forSAN: "Nxe5") == .capture)
        #expect(SoundPlayer.effect(forSAN: "O-O") == .castle)
        #expect(SoundPlayer.effect(forSAN: "O-O-O") == .castle)
        #expect(SoundPlayer.effect(forSAN: "Qxf7#") == .check)
        #expect(SoundPlayer.effect(forSAN: "Bb5+") == .check)
    }

    @Test func emptyOrUnexpandedKeyMeansStoreKitOnly() {
        #expect(Entitlements(apiKey: "").backend == .storeKit)
        #expect(Entitlements(apiKey: nil).backend == .storeKit)
        #expect(Entitlements(apiKey: "$(REVENUECAT_API_KEY)").backend == .storeKit)
    }

    @Test func everyProFeatureHasAPitch() {
        for feature in ProFeature.allCases { #expect(!feature.pitch.isEmpty) }
        #expect(PaywallView.values.count == 4)
    }

    @Test func prefDefaultsWhenUnset() {
        let key = Pref.sound
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(Pref.bool(key, default: true))
        UserDefaults.standard.set(false, forKey: key)
        #expect(!Pref.bool(key, default: true))
    }

    @Test func resetDeletesGamesAndPreferences() throws {
        let container = try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(try GameRecord(snapshot: GameSnapshot(
            id: UUID(), date: .now, botId: "pip", userColor: .white, mode: .silent,
            startFen: Rules.startFen, moves: [], sans: [], result: .ongoing,
            verdicts: [], analysisVersion: 1, playerRatingUsed: 800)))
        try context.save()
        UserDefaults.standard.set(false, forKey: Pref.haptics)
        try DataReset.run(in: context)
        #expect(try context.fetchCount(FetchDescriptor<GameRecord>()) == 0)
        #expect(UserDefaults.standard.object(forKey: Pref.haptics) == nil)
    }

    /// The test host's store (built at launch) stays local under XCTest.
    @Test func localStoreWithoutCloudKitInTests() {
        #expect(!ModelStore.isSyncing)
    }

    @Test func licenseTextsAreBundled() {
        for entry in LicensesView.software {
            guard let file = entry.file else { continue }
            let url = Bundle.main.url(forResource: file, withExtension: "txt")
            #expect(url != nil, "\(file).txt missing")
        }
    }
}
