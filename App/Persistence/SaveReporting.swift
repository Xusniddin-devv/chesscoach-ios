import SwiftUI
import SwiftData
import OSLog

/// A save of the user's progress that failed: logged, then shown once as a quiet inline
/// notice with Retry (`SaveNotice`). The unsaved changes stay in the context, so Retry
/// saves them again. Never a silent `try?` on progress.
@MainActor
@Observable
final class SaveIssues {
    static let shared = SaveIssues()

    /// What could not be saved ("your puzzle progress"); nil when all is saved.
    private(set) var failed: String?
    @ObservationIgnored private weak var context: ModelContext?

    fileprivate static let log = Logger(subsystem: "uz.xq.chessc", category: "persistence")

    func report(_ what: String, error: any Error, context: ModelContext) {
        Self.log.error("Save failed (\(what, privacy: .public)): \(String(describing: error), privacy: .public)")
        failed = what
        self.context = context
    }

    /// Saves the pending changes again; the notice goes away when that works.
    func retry() {
        guard let context, let what = failed else { failed = nil; return }
        failed = nil
        context.saveReporting(what)
    }

    func dismiss() { failed = nil }
}

extension ModelContext {
    /// Saves; a failure is logged and surfaced through `SaveIssues` instead of vanishing.
    @MainActor @discardableResult
    func saveReporting(_ what: String) -> Bool {
        do {
            try save()
            return true
        } catch {
            SaveIssues.shared.report(what, error: error, context: self)
            return false
        }
    }
}

/// The inline notice for a failed save: one line and Retry, over the top of the screen.
struct SaveNotice: View {
    let issues: SaveIssues

    var body: some View {
        if let what = issues.failed {
            HStack(spacing: DS.Spacing.sm) {
                Circle().fill(DS.Color.danger).frame(width: 8, height: 8)
                Text("Couldn't save \(what).")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(2)
                Spacer(minLength: DS.Spacing.s)
                Button("Retry") { issues.retry() }
                    .font(DS.Font.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Color.accent)
                Button { issues.dismiss() } label: {
                    Image("Icons/close").renderingMode(.template).resizable().frame(width: 14, height: 14)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .foregroundStyle(DS.Color.textSecondary)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            .padding(.horizontal, DS.Spacing.m)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
