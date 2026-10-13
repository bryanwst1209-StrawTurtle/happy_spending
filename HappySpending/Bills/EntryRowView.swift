import SwiftUI
import HappySpendingCore

struct EntryRowView: View {
    let row: EntryRow

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(
                symbolName: row.topSymbolName, colorHex: row.topColorHex,
                iconData: row.displayIconData, size: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayCategory).font(.body)
                if !row.note.isEmpty {
                    Text(row.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text((row.kind == .income ? "+" : "") + Money.display(row.cents))
                .font(.body.monospacedDigit())
                .foregroundStyle(row.kind == .income ? Color.green : Color.primary)
        }
        .contentShape(Rectangle())
    }
}
