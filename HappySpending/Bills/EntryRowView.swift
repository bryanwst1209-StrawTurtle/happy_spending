import SwiftUI
import HappySpendingCore

struct EntryRowView: View {
    let row: EntryRow
    /// 跨月份的搜索结果里在备注前显示日期(如"3月14日 周五 · 示例小吃")。
    var showsDate = false

    private var caption: String {
        var parts: [String] = []
        if showsDate { parts.append(BillsLogic.dayTitle(row.date, calendar: DayStamp.calendar)) }
        if !row.note.isEmpty { parts.append(row.note) }
        return parts.joined(separator: " · ")
    }

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
                if !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
