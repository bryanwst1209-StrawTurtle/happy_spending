import Foundation

/// 微信消息列表里的时间标签:`13:00`、`昨天 18:23`、`星期六 11:01`、`10月8日 18:23`、`2025年10月8日 18:23`。
enum TimeLabel {
    private static let weekdays: [String: Int] = [
        "日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7,
    ]

    /// 识别出来的冒号、数字可能是全角(`13：00`),统一成半角再匹配。
    private static func normalized(_ line: String) -> String {
        (line.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? line)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 整行是时间标签时,按 `now` 换算成具体时间(精确到分钟);不是就返回 nil。
    static func resolve(_ line: String, now: Date, calendar: Calendar) -> Date? {
        let text = normalized(line)
        let today = calendar.startOfDay(for: now)

        if let g = TextMatch.captures("^(\\d{1,2}):(\\d{2})$", in: text) {
            return at(today, g[1], g[2], calendar)
        }
        if let g = TextMatch.captures("^昨天\\s*(\\d{1,2}):(\\d{2})$", in: text) {
            return calendar.date(byAdding: .day, value: -1, to: today).flatMap { at($0, g[1], g[2], calendar) }
        }
        if let g = TextMatch.captures("^星期([一二三四五六日天])\\s*(\\d{1,2}):(\\d{2})$", in: text),
           let weekday = weekdays[g[1]] {
            // 今天显示成时间、昨天显示成"昨天",所以"星期X"是往前 2 到 8 天里的那一天(每个星期X 恰好一次)。
            for back in 2...8 {
                guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
                if calendar.component(.weekday, from: day) == weekday {
                    return at(day, g[2], g[3], calendar)
                }
            }
            return nil
        }
        if let g = TextMatch.captures("^(\\d{4})年(\\d{1,2})月(\\d{1,2})日\\s*(\\d{1,2}):(\\d{2})$", in: text),
           let year = Int(g[1]) {
            return date(year: year, month: g[2], day: g[3], calendar).flatMap { at($0, g[4], g[5], calendar) }
        }
        if let g = TextMatch.captures("^(\\d{1,2})月(\\d{1,2})日\\s*(\\d{1,2}):(\\d{2})$", in: text) {
            // 没写年份就是今年;比现在还晚,说明是去年的。
            let year = calendar.component(.year, from: now)
            guard let thisYear = date(year: year, month: g[1], day: g[2], calendar)
                .flatMap({ at($0, g[3], g[4], calendar) })
            else { return nil }
            if thisYear <= now { return thisYear }
            return date(year: year - 1, month: g[1], day: g[2], calendar).flatMap { at($0, g[3], g[4], calendar) }
        }
        return nil
    }

    /// 看起来像时间标签、但 `resolve` 认不出的行(12 小时制的 `下午1:00`、乱码的 `昨天 18.23`)。
    /// 只认带时间数字的开头,所以"周黑鸭""昨天咖啡"这类商户名不算。
    static func looksLikeTime(_ line: String) -> Bool {
        let pattern = "^(\\d{1,2}\\s*:"
            + "|(昨天|前天)\\s*(\\d|上午|下午|凌晨|中午|晚上)"
            + "|(星期|周)[一二三四五六日天]\\s*\\d"
            + "|(上午|下午|凌晨|中午|晚上)\\s*\\d"
            + "|\\d{1,4}年\\s*\\d|\\d{1,2}月\\s*\\d{1,2}日)"
        return TextMatch.captures(pattern, in: normalized(line)) != nil
    }

    /// 校验过的某一天(0 点);不存在的日期(2 月 30 日)返回 nil,而不是被日历进位。
    private static func date(year: Int, month: String, day: String, _ calendar: Calendar) -> Date? {
        guard let m = Int(month), let d = Int(day),
              let value = calendar.date(from: DateComponents(year: year, month: m, day: d))
        else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: value)
        return back.year == year && back.month == m && back.day == d ? value : nil
    }

    private static func at(_ day: Date, _ hour: String, _ minute: String, _ calendar: Calendar) -> Date? {
        guard let h = Int(hour), let m = Int(minute), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
    }
}
