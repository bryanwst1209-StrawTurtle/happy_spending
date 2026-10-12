import Foundation

public enum CSVExporter {
    public static let header = ["日期", "类型", "金额", "一级分类", "二级分类", "备注"]

    /// UTF-8 带 BOM,RFC 4180 转义,CRLF 换行;按日期从旧到新排列。
    public static func csv(_ rows: [EntryRow], calendar: Calendar = DayStamp.calendar) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let ordered = rows.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        var lines = [header.joined(separator: ",")]
        for row in ordered {
            let fields = [
                formatter.string(from: row.date),
                row.kind.title,
                Money.plain(row.cents),
                row.topCategoryName,
                row.subCategoryName ?? "",
                row.note,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        return Data(("\u{FEFF}" + text).utf8)
    }

    /// `nil` 表示导出全部。
    public static func fileName(for period: Period?, calendar: Calendar = DayStamp.calendar) -> String {
        switch period {
        case nil:
            return "happy_spending-all.csv"
        case .month(let date)?:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM"
            return "happy_spending-\(formatter.string(from: date)).csv"
        case .year(let year)?:
            return "happy_spending-\(year).csv"
        }
    }

    private static let specialScalars: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]

    /// 注意要按 Unicode 标量判断:"\r\n" 在 Swift 里是单个 Character,不会等于 "\n"。
    static func escape(_ field: String) -> String {
        guard field.unicodeScalars.contains(where: specialScalars.contains) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
