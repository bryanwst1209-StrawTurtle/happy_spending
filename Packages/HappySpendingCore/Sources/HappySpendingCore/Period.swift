import Foundation

public enum Period: Equatable, Sendable {
    /// 关联值是该月内的任意一天。
    case month(Date)
    case year(Int)

    /// 左闭右开:包含起点,不包含终点。
    public func interval(calendar: Calendar) -> DateInterval {
        switch self {
        case .month(let date):
            return calendar.dateInterval(of: .month, for: date)!
        case .year(let year):
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            return DateInterval(start: start, end: end)
        }
    }

    public func filter(_ rows: [EntryRow], calendar: Calendar) -> [EntryRow] {
        let interval = interval(calendar: calendar)
        return rows.filter { $0.date >= interval.start && $0.date < interval.end }
    }
}
