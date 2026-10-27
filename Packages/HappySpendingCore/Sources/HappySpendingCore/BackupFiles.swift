import Foundation

/// 备份文件的命名与轮换规则(spec §2、§6)。文件名里的日期按用户本地日历。
public enum BackupFiles {
    /// 自动备份的文件名;轮换只认这种格式,别的文件一律不动。
    private static let autoPattern = #"^HappySpending 备份 \d{4}-\d{2}-\d{2}\.json$"#

    public static func autoName(for date: Date, calendar: Calendar) -> String {
        "HappySpending 备份 \(day(date, calendar)).json"
    }

    /// 手动导出总是带时间,和自动备份区分开,也不会被轮换删掉。
    public static func manualName(at date: Date, calendar: Calendar) -> String {
        "HappySpending 备份 \(day(date, calendar)) \(time(date, calendar)).json"
    }

    public static func preRestoreName(at date: Date, calendar: Calendar) -> String {
        "HappySpending 恢复前备份 \(day(date, calendar)) \(time(date, calendar)).json"
    }

    /// 文件夹里该删掉的旧自动备份:只保留最新的 `keep` 份,其他文件不管。
    public static func autoBackupsToDelete(_ names: [String], keep: Int = 7) -> [String] {
        let autos = names
            .filter { $0.range(of: autoPattern, options: .regularExpression) != nil }
            .sorted(by: >)
        return Array(autos.dropFirst(keep))
    }

    /// 本地日期的"今天"还没自动备份过。
    public static func needsAutoBackup(lastAutoBackup: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastAutoBackup else { return true }
        return !calendar.isDate(lastAutoBackup, inSameDayAs: now)
    }

    /// 没开自动备份,且超过 30 天没手动导出(或有账单却从没导出过)。
    public static func needsReminder(autoBackupOn: Bool, lastExport: Date?, hasEntries: Bool, now: Date) -> Bool {
        guard !autoBackupOn else { return false }
        guard let lastExport else { return hasEntries }
        return now.timeIntervalSince(lastExport) > 30 * 24 * 3600
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func time(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
