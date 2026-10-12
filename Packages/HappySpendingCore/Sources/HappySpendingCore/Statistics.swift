import Foundation

public struct PeriodSummary: Equatable, Sendable {
    public let incomeCents: Int
    public let expenseCents: Int
    public var balanceCents: Int { incomeCents - expenseCents }
}

public struct SubcategoryShare: Equatable, Hashable, Identifiable, Sendable {
    /// nil 表示"未细分"(账单直接挂在一级分类上)。
    public let id: UUID?
    public let name: String
    public let cents: Int
    /// 占所属一级分类的比例。
    public let fraction: Double
}

public struct CategoryShare: Equatable, Hashable, Identifiable, Sendable {
    /// nil 表示"未分类"。
    public let id: UUID?
    public let name: String
    public let colorHex: String
    public let cents: Int
    /// 占该类型总额的比例。
    public let fraction: Double
    public let children: [SubcategoryShare]
}

public struct TrendPoint: Equatable, Identifiable, Sendable {
    public let date: Date
    public let cents: Int
    public var id: Date { date }
}

public enum Statistics {
    public static func summary(_ rows: [EntryRow]) -> PeriodSummary {
        PeriodSummary(
            incomeCents: rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.cents },
            expenseCents: rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.cents }
        )
    }

    /// 按一级分类汇总,金额从大到小;金额相同按名称排序。没有数据时返回空数组。
    public static func shares(_ rows: [EntryRow], kind: EntryKind) -> [CategoryShare] {
        let rows = rows.filter { $0.kind == kind }
        let total = rows.reduce(0) { $0 + $1.cents }
        guard total > 0 else { return [] }

        return Dictionary(grouping: rows, by: \.topCategoryID)
            .map { topID, members -> CategoryShare in
                let cents = members.reduce(0) { $0 + $1.cents }
                let children = Dictionary(grouping: members, by: \.subCategoryID)
                    .map { subID, subMembers -> SubcategoryShare in
                        let subCents = subMembers.reduce(0) { $0 + $1.cents }
                        return SubcategoryShare(
                            id: subID,
                            name: subMembers[0].subCategoryName ?? "未细分",
                            cents: subCents,
                            fraction: Double(subCents) / Double(cents)
                        )
                    }
                    .sorted { lhs, rhs in
                        lhs.cents != rhs.cents ? lhs.cents > rhs.cents : lhs.name < rhs.name
                    }
                return CategoryShare(
                    id: topID,
                    name: members[0].topCategoryName,
                    colorHex: members[0].topColorHex,
                    cents: cents,
                    fraction: Double(cents) / Double(total),
                    children: children
                )
            }
            .sorted { lhs, rhs in
                lhs.cents != rhs.cents ? lhs.cents > rhs.cents : lhs.name < rhs.name
            }
    }

    /// 某月每一天一个点,没有账单的日子补零。
    public static func dailyTrend(
        _ rows: [EntryRow],
        month: Date,
        kind: EntryKind = .expense,
        calendar: Calendar
    ) -> [TrendPoint] {
        let interval = calendar.dateInterval(of: .month, for: month)!
        var totals: [Date: Int] = [:]
        for row in rows where row.kind == kind && row.date >= interval.start && row.date < interval.end {
            totals[calendar.startOfDay(for: row.date), default: 0] += row.cents
        }
        let dayCount = calendar.range(of: .day, in: .month, for: month)!.count
        return (0..<dayCount).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: interval.start)!
            return TrendPoint(date: day, cents: totals[day] ?? 0)
        }
    }

    /// 某年 12 个月各一个点,没有账单的月份补零。
    public static func monthlyTrend(
        _ rows: [EntryRow],
        year: Int,
        kind: EntryKind = .expense,
        calendar: Calendar
    ) -> [TrendPoint] {
        let interval = Period.year(year).interval(calendar: calendar)
        var totals: [Date: Int] = [:]
        for row in rows where row.kind == kind && row.date >= interval.start && row.date < interval.end {
            let monthStart = calendar.dateInterval(of: .month, for: row.date)!.start
            totals[monthStart, default: 0] += row.cents
        }
        return (1...12).map { month in
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            return TrendPoint(date: start, cents: totals[start] ?? 0)
        }
    }
}
