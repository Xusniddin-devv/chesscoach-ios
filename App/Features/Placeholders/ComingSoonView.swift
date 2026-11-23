import SwiftUI

struct ComingSoonView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(title).font(DS.Font.title).foregroundStyle(DS.Color.text)
            Text("Not built yet.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Spacing.m)
        .background(DS.Color.background)
    }
}
