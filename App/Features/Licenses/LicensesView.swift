import SwiftUI

/// GPLv3 notice, the source link, and every third-party licence the app ships with.
/// Texts are bundled from App/Resources/Licenses (copied from the vendored sources).
struct LicensesView: View {
    struct Entry: Identifiable {
        let name: String
        let license: String
        let file: String?
        let note: String?
        let url: URL?
        var id: String { name }
    }

    static let software: [Entry] = [
        Entry(name: "Stockfish 18", license: "GPLv3", file: "GPLv3",
              note: "The chess engine behind every grade, hint and bot. Copyright the Stockfish developers (see Authors).",
              url: URL(string: "https://github.com/official-stockfish/Stockfish")),
        Entry(name: "Stockfish authors", license: "", file: "Stockfish-AUTHORS", note: nil, url: nil),
        Entry(name: "chesskit-swift", license: "MIT", file: "chesskit-swift-LICENSE", note: nil,
              url: URL(string: "https://github.com/chesskit-studio/chesskit-swift")),
        Entry(name: "RevenueCat purchases-ios", license: "MIT", file: "purchases-ios-LICENSE", note: nil,
              url: URL(string: "https://github.com/RevenueCat/purchases-ios")),
    ]

    static let data: [Entry] = [
        Entry(name: "Lichess opening names", license: "CC0",
              file: nil, note: "Opening names from lichess-org/chess-openings, dedicated to the public domain (CC0 1.0).",
              url: URL(string: "https://github.com/lichess-org/chess-openings")),
        Entry(name: "Lichess puzzles", license: "CC0",
              file: nil, note: "Puzzles from the Lichess puzzle database, dedicated to the public domain (CC0 1.0).",
              url: URL(string: "https://database.lichess.org/#puzzles")),
    ]

    static let art: [Entry] = [
        Entry(name: "Icons by Icons8 (icons8.com)", license: "Icons8",
              file: nil, note: "Interface icons by Icons8 (icons8.com), used under the Icons8 licence with attribution.",
              url: URL(string: "https://icons8.com")),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                notice
                SettingsGroup("Software") {
                    ForEach(Self.software) { entry in
                        NavigationLink { LicenseTextView(entry: entry) } label: {
                            SettingsLinkLabel(title: entry.name, value: entry.license.isEmpty ? nil : entry.license)
                        }
                        .buttonStyle(.plain)
                    }
                }
                SettingsGroup("Data") {
                    ForEach(Self.data) { entry in
                        NavigationLink { LicenseTextView(entry: entry) } label: {
                            SettingsLinkLabel(title: entry.name, value: entry.license)
                        }
                        .buttonStyle(.plain)
                    }
                }
                SettingsGroup("Art") {
                    ForEach(Self.art) { entry in
                        NavigationLink { LicenseTextView(entry: entry) } label: {
                            SettingsLinkLabel(title: entry.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.top, DS.Spacing.s)
            .padding(.bottom, DS.Spacing.xl)
        }
        .background(DS.Color.background)
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Powered by Stockfish")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.text)
            Text("Chess Coach is free software: you can redistribute and modify it under the terms of the GNU General Public License, version 3. It comes with no warranty. The complete source code is public.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: AppInfo.sourceURL) {
                Text(AppInfo.sourceURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .font(DS.Font.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Color.accent)
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}

/// One licence: its note and link, then the full text in mono.
struct LicenseTextView: View {
    let entry: LicensesView.Entry

    private var text: String? {
        guard let file = entry.file,
              let url = Bundle.main.url(forResource: file, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                if let note = entry.note {
                    Text(note)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = entry.url {
                    Link(destination: url) {
                        Text(url.host().map { $0 + url.path() } ?? url.absoluteString)
                            .font(DS.Font.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Color.accent)
                    }
                }
                if let text {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DS.Color.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.Spacing.m)
        }
        .background(DS.Color.background)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
