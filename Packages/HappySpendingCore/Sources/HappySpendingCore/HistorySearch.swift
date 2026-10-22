import Foundation
import SwiftData

/// 搜索词当金额用时匹配的区间(分,左闭右开)。
public enum AmountQuery {
    /// 带小数点(`147.7`、`147.70`)按精确金额;整数(`147`)按"这个整数元"(¥147.00~¥147.99);
    /// 解析不了或不大于 0 时返回 nil。
    public static func range(for query: String) -> Range<Int>? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cents = try? AmountText.cents(from: text), cents > 0 else { return nil }
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidth.contains(".") ? cents..<(cents + 1) : cents..<(cents + 100)
    }
}

/// 一个月的搜索结果。
public struct MonthGroup: Equatable, Identifiable, Sendable {
    /// 该月 1 日。
    public let month: Date
    public let rows: [EntryRow]
    public let expenseCents: Int
    public var id: Date { month }
}

extension BillsLogic {
    /// 按月分组,月份新的在前;组内日期新的在前,同一天后记的在前。
    public static func groupByMonth(_ rows: [EntryRow], calendar: Calendar) -> [MonthGroup] {
        Dictionary(grouping: rows) { calendar.dateInterval(of: .month, for: $0.date)!.start }
            .map { month, members in
                MonthGroup(
                    month: month,
                    rows: members.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) },
                    expenseCents: members.filter { $0.kind == .expense }.reduce(0) { $0 + $1.cents }
                )
            }
            .sorted { $0.month > $1.month }
    }
}

/// 账单页搜"全部":在所有月份里搜。
public enum HistorySearch {
    /// 备注、一级 / 二级分类名(匹配一级分类时连同它的二级分类)、"未分类"、金额,任一命中即可。
    /// 备注和金额交给数据库查;分类名先在分类列表里找,再取它们的账。去重后按日期、记账时间倒序。
    public static func search(_ query: String, in context: ModelContext) throws -> [LedgerEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var found: [UUID: LedgerEntry] = [:]
        func add(_ entries: [LedgerEntry]) {
            for entry in entries { found[entry.id] = entry }
        }

        add(try context.fetch(FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.note.localizedStandardContains(text) }
        )))

        for category in try context.fetch(FetchDescriptor<LedgerCategory>())
        where category.name.localizedCaseInsensitiveContains(text) {
            add(category.entries)
            if category.parent == nil {
                for child in category.children { add(child.entries) }
            }
        }

        if Uncategorized.name.localizedCaseInsensitiveContains(text) {
            add(try context.fetch(LedgerQueries.uncategorized()))
        }

        if let range = AmountQuery.range(for: text) {
            let low = range.lowerBound
            let high = range.upperBound
            add(try context.fetch(FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.amountInCents >= low && $0.amountInCents < high }
            )))
        }

        return found.values.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }
}
