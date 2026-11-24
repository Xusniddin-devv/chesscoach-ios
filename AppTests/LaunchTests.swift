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
            for: ModelStore.schema,
            configurations: ModelConfiguration(schema: ModelStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let onboarded = UserDefaults.standard.object(forKey: Pref.hasOnboarded)
        UserDefaults.standard.set(true, forKey: Pref.hasOnboarded)
        defer { UserDefaults.standard.set(onboarded, forKey: Pref.hasOnboarded) }
        let host = UIHostingController(rootView: RootTabView()
            .environment(EngineHub())
            .environment(Entitlements())
            .modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let tabs = try #require(findTabBarController(host))
        #expect(tabs.viewControllers?.count == 4)
    }

    /// First launch: onboarding instead of the tabs.
    @Test func firstLaunchShowsOnboarding() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = try ModelContainer(
            for: ModelStore.schema,
            configurations: ModelConfiguration(schema: ModelStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let onboarded = UserDefaults.standard.object(forKey: Pref.hasOnboarded)
        UserDefaults.standard.removeObject(forKey: Pref.hasOnboarded)
        defer { UserDefaults.standard.set(onboarded, forKey: Pref.hasOnboarded) }
        let host = UIHostingController(rootView: RootTabView()
            .environment(EngineHub())
            .environment(Entitlements())
            .modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        #expect(findTabBarController(host) == nil)
    }

    private func findTabBarController(_ vc: UIViewController) -> UITabBarController? {
        if let t = vc as? UITabBarController { return t }
        for child in vc.children { if let t = findTabBarController(child) { return t } }
        return nil
    }
}
