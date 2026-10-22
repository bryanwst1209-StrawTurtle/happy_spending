import Foundation

public struct DayGroup: Equatable, Identifiable, Sendable {
    public let day: Date
    public let rows: [EntryRow]
    public let incomeCents: Int
    public let expenseCents: Int
    public var id: Date { day }
}

public enum BillsLogic {
    /// 按天分组,日期新的在前;同一天内后创建的在前。
    public static func groupByDay(_ rows: [EntryRow], calendar: Calendar) -> [DayGroup] {
        Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
            .map { day, members in
                DayGroup(
                    day: day,
                    rows: members.sorted { $0.createdAt > $1.createdAt },
                    incomeCents: members.filter { $0.kind == .income }.reduce(0) { $0 + $1.cents },
                    expenseCents: members.filter { $0.kind == .expense }.reduce(0) { $0 + $1.cents }
                )
            }
            .sorted { $0.day > $1.day }
    }

    /// "10月10日 周六"
    public static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: day)
    }

    /// "2026年10月"
    public static func monthTitle(_ anchor: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "y年M月"
        return formatter.string(from: anchor)
    }

    /// 在备注、一级分类名、二级分类名里做不区分大小写的包含匹配;搜索词能当金额时也按金额匹配
    /// (规则见 `AmountQuery`)。空查询返回全部。
    public static func search(_ rows: [EntryRow], query: String) -> [EntryRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        let amount = AmountQuery.range(for: query)
        return rows.filter { row in
            [row.note, row.topCategoryName, row.subCategoryName ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
                || amount?.contains(row.cents) == true
        }
    }

    /// 最近 `window` 笔同类型账单里用得最多的分类(叶子分类:有二级用二级,否则用一级)。
    /// 次数相同时,最近用过的在前。
    public static func frequentCategoryIDs(
        _ rows: [EntryRow],
        kind: EntryKind,
        excluding: Set<UUID> = [],
        limit: Int = 5,
        window: Int = 200
    ) -> [UUID] {
        let recent = rows
            .filter { $0.kind == kind }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(window)

        var stats: [UUID: (count: Int, latest: Date)] = [:]
        for row in recent {
            guard let id = row.subCategoryID ?? row.topCategoryID, !excluding.contains(id) else { continue }
            let current = stats[id]
            stats[id] = (
                count: (current?.count ?? 0) + 1,
                latest: max(current?.latest ?? .distantPast, row.createdAt)
            )
        }
        return stats
            .sorted { lhs, rhs in
                lhs.value.count != rhs.value.count
                    ? lhs.value.count > rhs.value.count
                    : lhs.value.latest > rhs.value.latest
            }
            .prefix(limit)
            .map(\.key)
    }
}
