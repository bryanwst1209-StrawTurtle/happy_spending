import SwiftUI
import HappySpendingCore

struct EntryRowView: View {
    let row: EntryRow

    var body: some View {
        let color = Color(hex: row.topColorHex)
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay(Circle().fill(color).frame(width: 12, height: 12))
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
