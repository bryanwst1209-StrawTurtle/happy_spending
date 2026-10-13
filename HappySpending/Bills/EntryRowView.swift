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
                HStack(spacing: 6) {
                    Text(row.displayCategory).font(.body)
                    if row.isAuto {
                        Text("自动")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
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
