import Foundation

/// 账单页、统计页"查历史"用到的范围计算。
public enum HistoryRange {
    /// 年月选择器可选的年份:最早一笔所在年到今年;没有账时只有今年。
    public static func years(earliest: Date?, now: Date, calendar: Calendar) -> ClosedRange<Int> {
        let thisYear = calendar.component(.year, from: now)
        let first = earliest.map { calendar.component(.year, from: $0) } ?? thisYear
        return min(first, thisYear)...thisYear
    }

    /// 某一年可选的月份:今年只到本月,不能选未来。
    public static func months(in year: Int, now: Date, calendar: Calendar) -> ClosedRange<Int> {
        let components = calendar.dateComponents([.year, .month], from: now)
        return 1...(year == components.year ? (components.month ?? 12) : 12)
    }

    /// `period` 是否就是现在所在的月(或年),用于置灰 › 和显示"回到本月"。
    /// 左闭右开:`DateInterval.contains` 包含终点,不能直接用。
    public static func isCurrent(_ period: Period, now: Date, calendar: Calendar) -> Bool {
        let interval = period.interval(calendar: calendar)
        return now >= interval.start && now < interval.end
    }
}
