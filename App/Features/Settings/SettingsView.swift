import SwiftUI
import SwiftData
import StoreKit
import ChessCore

/// Settings: play defaults, feedback, Coach Pro, about (licenses, source), data.
/// Pushed from Profile's gear (inside Profile's navigation stack).
/// Premoves are not offered: Play has no premove support yet (spec lists the toggle).
struct SettingsView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var context
    @Environment(EngineHub.self) private var hub

    @AppStorage(Pref.sound) private var sound = Pref.Default.sound
    @AppStorage(Pref.haptics) private var haptics = Pref.Default.haptics
    @AppStorage(Pref.voice) private var voice = Pref.Default.voice
    @AppStorage(Pref.coordinates) private var coordinates = Pref.Default.coordinates
    /// Only set once the player picks one; until then the level decides (`EngineHub.wording`).
    @AppStorage(Pref.wording) private var explicitWording: Pref.Wording?
    @AppStorage(Pref.defaultMode) private var defaultMode = Pref.Default.defaultMode

    @State private var showingPaywall = false
    @State private var showingManage = false
    @State private var restoring = false
    @State private var restoreNote: String?
    @State private var confirmingReset = false
    @State private var resetFailed = false
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                games
                play
                feedback
                pro
                about
                data
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.top, DS.Spacing.s)
            .padding(.bottom, DS.Spacing.xl)
        }
        .background(DS.Color.background)
        .navigationTitle("Settings")
        .paywall(isPresented: $showingPaywall)
        #if DEBUG
        .task { if UserDefaults.standard.string(forKey: "debugOpen") == "paywall" { showingPaywall = true } }
        #endif
        .manageSubscriptionsSheet(isPresented: $showingManage)
        .fullScreenCover(isPresented: $importing) {
            OnboardingFlow(reimport: true) { importing = false }
        }
        .confirmationDialog("Delete all games and settings?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive, action: reset)
        } message: {
            Text("Your games, progress and settings on this iPhone and in iCloud are removed. Coach Pro stays.")
        }
    }

    // MARK: Sections

    private var games: some View {
        SettingsGroup("Your games", footer: "Reads your latest 20 chess.com or Lichess games and builds a new week of training.") {
            // The first import (onboarding) is free; importing again is Pro.
            ProGate(.gameImport) {
                Button { importing = true } label: { SettingsLinkLabel(title: "Import games") }
                    .buttonStyle(.plain)
            } locked: {
                UpgradeButton(.gameImport) { SettingsLinkLabel(title: "Import games", value: "Pro") }
            }
        }
    }

    private var play: some View {
        SettingsGroup("Play") {
            SettingsRow("Default mode") {
                Picker("Default mode", selection: $defaultMode) {
                    Text("Training").tag(PlayMode.training)
                    Text("Silent").tag(PlayMode.silent)
                }
                .pickerStyle(.segmented)
                .frame(width: 176)
                .labelsHidden()
            }
            SettingsRow("Show moves as") {
                Picker("Show moves as", selection: wording) {
                    ForEach(Pref.Wording.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 176)
                .labelsHidden()
            }
            SettingsToggle("Board coordinates", isOn: $coordinates)
        }
    }

    /// The picker shows what the coach uses now: the player's choice, else the level's.
    private var wording: Binding<Pref.Wording> {
        Binding {
            explicitWording ?? (hub.wording == .words ? .words : .notation)
        } set: { explicitWording = $0 }
    }

    private var feedback: some View {
        SettingsGroup("Feedback", footer: "Hold the mic in a game and say a move, like “knight to f3”. Speech is recognised on this iPhone and never leaves it.") {
            SettingsToggle("Sounds", isOn: $sound)
            SettingsToggle("Haptics", isOn: $haptics)
            SettingsToggle("Voice moves", isOn: $voice)
        }
    }

    private var pro: some View {
        SettingsGroup("Coach Pro", footer: restoreNote) {
            if entitlements.isPro {
                SettingsRow("Coach Pro", detail: "Active") { EmptyView() }
                Button { showingManage = true } label: { SettingsLinkLabel(title: "Manage subscription", kind: .external) }
                    .buttonStyle(.plain)
            } else {
                Button { showingPaywall = true } label: {
                    SettingsLinkLabel(title: "Get Coach Pro", kind: .push, color: DS.Color.accent)
                }
                .buttonStyle(.plain)
            }
            Button(action: restore) {
                SettingsLinkLabel(title: restoring ? "Restoring…" : "Restore purchases", kind: .action)
            }
            .buttonStyle(.plain)
            .disabled(restoring)
        }
    }

    private var about: some View {
        SettingsGroup("About", footer: "Chess Coach is free software (GPLv3). Powered by Stockfish.") {
            NavigationLink { LicensesView() } label: { SettingsLinkLabel(title: "Licenses") }
                .buttonStyle(.plain)
            Link(destination: AppInfo.sourceURL) { SettingsLinkLabel(title: "Source code", kind: .external) }
                .buttonStyle(.plain)
            SettingsRow("Version") {
                Text(AppInfo.version)
                    .font(DS.Font.body.monospacedDigit())
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    private var data: some View {
        SettingsGroup(footer: resetFailed ? "Couldn't delete everything. Try again." : nil) {
            Button { confirmingReset = true } label: {
                SettingsLinkLabel(title: "Reset all data", kind: .action, color: DS.Color.danger)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func restore() {
        restoring = true
        restoreNote = nil
        Task {
            do {
                let pro = try await entitlements.restore()
                restoreNote = pro ? "Coach Pro restored." : "No Coach Pro purchase found on this Apple Account."
            } catch {
                restoreNote = "Couldn't reach the App Store. Try again in a moment."
            }
            restoring = false
        }
    }

    private func reset() {
        do {
            try DataReset.run(in: context)
            resetFailed = false
        } catch {
            resetFailed = true
        }
    }
}

/// "Reset all data": every stored model and every preference. Purchases are the App Store's
/// and stay. Every model in `ModelStore.models`.
enum DataReset {
    static let models: [any PersistentModel.Type] = ModelStore.models

    @MainActor
    static func run(in context: ModelContext) throws {
        for model in models { try context.delete(model: model) }
        try context.save()
        for key in Pref.all { UserDefaults.standard.removeObject(forKey: key) }
    }
}
