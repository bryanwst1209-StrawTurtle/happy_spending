import SwiftUI
import HappySpendingCore

struct CategoryPicker: View {
    let kind: EntryKind
    let categories: [LedgerCategory]
    let frequentIDs: [UUID]
    @Binding var selectedID: UUID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var tops: [LedgerCategory] {
        categories
            .filter { $0.kind == kind && $0.parent == nil && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var selected: LedgerCategory? { categories.first { $0.id == selectedID } }
    private var selectedTop: LedgerCategory? { selected?.parent ?? selected }
    private var subs: [LedgerCategory] {
        (selectedTop?.children ?? [])
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var frequent: [LedgerCategory] {
        frequentIDs
            .compactMap { id in categories.first { $0.id == id } }
            .filter { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 常用和一级分类放在可滚动区;二级分类行固定在下方,选中后始终可见。
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !frequent.isEmpty {
                        chipRow(frequent, symbol: "star.fill")
                    }
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(tops, id: \.id) { top in topCell(top) }
                    }
                }
            }
            if !subs.isEmpty {
                chipRow(subs)
            }
        }
    }

    private func topCell(_ top: LedgerCategory) -> some View {
        let color = Color(hex: top.colorHex)
        let isSelected = selectedTop?.id == top.id
        return Button { selectedID = top.id } label: {
            VStack(spacing: 5) {
                CategoryIconView(
                    symbolName: top.symbolName, colorHex: top.colorHex,
                    iconData: top.iconData, size: 46
                )
                .overlay(Circle().stroke(color, lineWidth: isSelected ? 2.5 : 0))
                Text(top.name).font(.caption).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func chipRow(_ items: [LedgerCategory], symbol: String? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let color = Color(hex: item.colorHex)
                    let isSelected = selectedID == item.id
                    Button { selectedID = item.id } label: {
                        HStack(spacing: 4) {
                            if let symbol {
                                Image(systemName: symbol).font(.caption2).foregroundStyle(color)
                            }
                            Text(item.displayName).font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(color.opacity(isSelected ? 0.28 : 0.10)))
                        .overlay(Capsule().stroke(color, lineWidth: isSelected ? 1.5 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
