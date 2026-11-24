import Testing
import SwiftUI
import UIKit
import SwiftData
@testable import ChessCoach

@MainActor
struct LaunchTests {
    /// Smoke: the root view hosts in a real window and lays out without crashing.
    @Test func rootShowsFourTabs() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let host = UIHostingController(rootView: RootTabView()
            .environment(EngineHub())
            .modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let tabs = try #require(findTabBarController(host))
        #expect(tabs.viewControllers?.count == 4)
    }

    private func findTabBarController(_ vc: UIViewController) -> UITabBarController? {
        if let t = vc as? UITabBarController { return t }
        for child in vc.children { if let t = findTabBarController(child) { return t } }
        return nil
    }
}
