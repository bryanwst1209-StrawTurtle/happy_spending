import Foundation

/// 账单日期的存储约定:记账日期只关心"哪一天",所以存成该日 GMT 0 点的瞬间,
/// 并且永远用 GMT 公历读取。这样换时区、出国、夏令时都不会让历史账单挪到别的日子。
public enum DayStamp {
    /// 解读已存储日期时统一使用的日历:GMT 公历,与设备时区无关。
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    /// `date` 在 `calendar`(通常是用户本地日历)里落在哪一天,就返回那一天的存储值。
    public static func stamp(_ date: Date, in calendar: Calendar = .current) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return Self.calendar.date(from: day)!
    }

    /// 把存储值还原成 `calendar` 里同一天 0 点的瞬间,给日期选择器等本地界面使用。
    public static func localDate(from stamp: Date, in calendar: Calendar = .current) -> Date {
        let day = Self.calendar.dateComponents([.year, .month, .day], from: stamp)
        return calendar.date(from: day)!
    }
}
