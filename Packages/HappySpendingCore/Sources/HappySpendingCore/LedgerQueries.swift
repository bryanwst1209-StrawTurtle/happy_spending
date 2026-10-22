import Foundation
import SwiftData

/// 各页面用的查询:只从数据库取要显示的那部分,避免每次刷新都把全部账单读出来再挑。
public enum LedgerQueries {
    /// 某个月或某一年的账:日期新的在前,同一天后记的在前。
    public static func entries(in period: Period, calendar: Calendar) -> FetchDescriptor<LedgerEntry> {
        let interval = period.interval(calendar: calendar)
        let start = interval.start
        let end = interval.end
        return FetchDescriptor(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    /// 还没有分类的账(含收入);再交给 `PendingCategorization.pending` 挑出支出并排序。
    public static func uncategorized() -> FetchDescriptor<LedgerEntry> {
        FetchDescriptor(predicate: #Predicate { $0.category == nil })
    }

    /// 最近记的若干笔(按记账时间倒序),给"常用分类"用。
    public static func recent(limit: Int = 300) -> FetchDescriptor<LedgerEntry> {
        var descriptor = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// 日期最早的一笔,给年月选择器定起始年份。
    public static func earliest() -> FetchDescriptor<LedgerEntry> {
        var descriptor = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// 按 id 找一笔(撤销删除时防止重复恢复)。
    public static func entry(id: UUID) -> FetchDescriptor<LedgerEntry> {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// 全部账单,日期从早到晚(导出全部用,只在点导出时才查)。
    public static func all() -> FetchDescriptor<LedgerEntry> {
        FetchDescriptor(sortBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt)])
    }
}
