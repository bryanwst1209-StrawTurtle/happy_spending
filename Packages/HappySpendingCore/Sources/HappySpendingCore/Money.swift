import Foundation

public enum Money {
    /// 9,999,999.99,以分为单位。
    public static let maxCents = 999_999_999

    /// 两位小数、无符号、无千分位,例如 "12.34"。
    public static func plain(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        return "\(sign)\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    /// 带 ¥ 和千分位,例如 "¥1,234.56";负数为 "-¥0.50"。
    public static func display(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        let whole = (magnitude / 100).formatted(
            .number.grouping(.automatic).locale(Locale(identifier: "en_US"))
        )
        return "\(sign)¥\(whole).\(String(format: "%02d", magnitude % 100))"
    }
}
