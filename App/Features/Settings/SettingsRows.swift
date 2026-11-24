import SwiftUI

/// A labelled group of rows in one `surface` container with hairlines, like Home's recent
/// games: `label` above, optional footnote below.
struct SettingsGroup<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            if let title { SectionLabel(title).padding(.leading, DS.Spacing.m) }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().overlay(DS.Color.surface2).padding(.leading, DS.Spacing.m)
                        }
                        row
                    }
                }
            }
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            if let footer {
                Text(footer)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.m)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Title on the left, any control or value on the right, 44 pt minimum.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                if let detail {
                    Text(detail)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer(minLength: DS.Spacing.s)
            trailing
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: 48)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

/// A switch row; the switch uses the accent.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(DS.Font.body).foregroundStyle(DS.Color.text)
        }
        .tint(DS.Color.accent)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: 48)
    }
}

/// A tappable row with a trailing chevron (push) or arrow (leaves the app).
struct SettingsLinkLabel: View {
    enum Kind { case push, external, action }
    let title: String
    var value: String?
    var kind: Kind = .push
    var color: Color = DS.Color.text

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(title)
                .font(DS.Font.body)
                .foregroundStyle(color)
            Spacer(minLength: DS.Spacing.s)
            if let value {
                Text(value)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            switch kind {
            case .push:
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)
            case .external:
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)
            case .action:
                EmptyView()
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}
