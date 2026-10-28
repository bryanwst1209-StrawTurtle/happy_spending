import Foundation
import SwiftData

/// 解锁记录:每个徽章最多一条,写下就不再删(数据变了也不收回)。
@Model
public final class AchievementUnlock {
    /// `Achievement.rawValue`。
    public var id: String
    public var unlockedAt: Date

    public init(id: String, unlockedAt: Date) {
        self.id = id
        self.unlockedAt = unlockedAt
    }
}

/// 打开过 app 的日子:每天最多一条,用来算连续天数。日期约定同账单(本地日期存成 GMT 当天 0 点)。
@Model
public final class OpenDay {
    public var day: Date

    public init(day: Date) {
        self.day = day
    }
}

/// 14 个徽章(spec §2)。
public enum Achievement: String, CaseIterable, Identifiable, Sendable {
    case firstEntry, firstAuto, firstBackup
    case inboxZero, tidyMonth, merchants10
    case streak7, streak30, streak100
    case spendLess, spendLess3
    case entries100, entries1000, anniversary

    public enum Category: String, CaseIterable, Sendable {
        case start, tidy, streak, habit, milestone

        public var title: String {
            switch self {
            case .start: "起步"
            case .tidy: "整理"
            case .streak: "坚持"
            case .habit: "习惯"
            case .milestone: "里程碑"
            }
        }
    }

    public var id: String { rawValue }

    public var category: Category {
        switch self {
        case .firstEntry, .firstAuto, .firstBackup: .start
        case .inboxZero, .tidyMonth, .merchants10: .tidy
        case .streak7, .streak30, .streak100: .streak
        case .spendLess, .spendLess3: .habit
        case .entries100, .entries1000, .anniversary: .milestone
        }
    }

    public var name: String {
        switch self {
        case .firstEntry: "第一笔"
        case .firstAuto: "自动驾驶"
        case .firstBackup: "未雨绸缪"
        case .inboxZero: "清清爽爽"
        case .tidyMonth: "井井有条"
        case .merchants10: "识途老马"
        case .streak7: "一周"
        case .streak30: "一月"
        case .streak100: "百日"
        case .spendLess: "小有节余"
        case .spendLess3: "稳扎稳打"
        case .entries100: "百笔"
        case .entries1000: "千笔"
        case .anniversary: "一周年"
        }
    }

    /// 详情卡片里的解锁条件。
    public var condition: String {
        switch self {
        case .firstEntry: "记下第一笔账"
        case .firstAuto: "第一次自动记账成功"
        case .firstBackup: "导出一次备份,或自动备份成功一次"
        case .inboxZero: "待归类清零"
        case .tidyMonth: "某个已结束的月份,所有支出都有分类(至少 10 笔)"
        case .merchants10: "记住 10 个商户的分类"
        case .streak7: "连续 7 天打开 app 看账"
        case .streak30: "连续 30 天打开 app 看账"
        case .streak100: "连续 100 天打开 app 看账"
        case .spendLess: "某个已结束的月份,支出比上个月少"
        case .spendLess3: "连续 3 个已结束的月份,每月支出都比上月少"
        case .entries100: "累计记账 100 笔"
        case .entries1000: "累计记账 1000 笔"
        case .anniversary: "第一笔账满一年"
        }
    }

    public var symbolName: String {
        switch self {
        case .firstEntry: "pencil.and.list.clipboard"
        case .firstAuto: "bolt.fill"
        case .firstBackup: "externaldrive.fill.badge.checkmark"
        case .inboxZero: "tray.fill"
        case .tidyMonth: "square.grid.3x3.fill"
        case .merchants10: "storefront.fill"
        case .streak7, .streak30, .streak100: "flame.fill"
        case .spendLess: "arrow.down.right.circle.fill"
        case .spendLess3: "chart.line.downtrend.xyaxis"
        case .entries100: "number.circle.fill"
        case .entries1000: "star.circle.fill"
        case .anniversary: "birthday.cake.fill"
        }
    }
}

/// 判定徽章所需的事实,由 `Achievements.gather` 从数据库算出。
public struct AchievementFacts: Equatable, Sendable {
    public var entryCount = 0
    public var autoEntryCount = 0
    public var hasBackedUp = false
    public var pendingCount = 0
    public var hasTidyMonth = false
    public var merchantCount = 0
    public var openStreak = 0
    /// 最近已结束的月份里,"比上月少"最长连续了几个月。
    public var bestSpendLessRun = 0
    /// 离第一笔账满一年还有几天;没有账单时为 nil,已满为 0。
    public var daysUntilAnniversary: Int?

    public init() {}
}

public enum Achievements {
    public static func isMet(_ badge: Achievement, _ f: AchievementFacts) -> Bool {
        switch badge {
        case .firstEntry: f.entryCount >= 1
        case .firstAuto: f.autoEntryCount >= 1
        case .firstBackup: f.hasBackedUp
        case .inboxZero: f.entryCount > 0 && f.pendingCount == 0
        case .tidyMonth: f.hasTidyMonth
        case .merchants10: f.merchantCount >= 10
        case .streak7: f.openStreak >= 7
        case .streak30: f.openStreak >= 30
        case .streak100: f.openStreak >= 100
        case .spendLess: f.bestSpendLessRun >= 1
        case .spendLess3: f.bestSpendLessRun >= 3
        case .entries100: f.entryCount >= 100
        case .entries1000: f.entryCount >= 1000
        case .anniversary: f.daysUntilAnniversary == 0
        }
    }

    /// 未解锁时徽章下面那行字。
    public static func progress(_ badge: Achievement, _ f: AchievementFacts) -> String {
        switch badge {
        case .firstEntry: "记下第一笔账"
        case .firstAuto: "设置一次自动入账"
        case .firstBackup: "导出一次备份"
        case .inboxZero: f.entryCount == 0 ? "先记一笔账" : "待归类还有 \(f.pendingCount) 笔"
        case .tidyMonth: "让一整个月的支出都有分类"
        case .merchants10: "记住了 \(f.merchantCount)/10 个商户"
        case .streak7: "连续 \(f.openStreak)/7 天"
        case .streak30: "连续 \(f.openStreak)/30 天"
        case .streak100: "连续 \(f.openStreak)/100 天"
        case .spendLess: "等一个月比上月花得少"
        case .spendLess3: "连续 \(f.bestSpendLessRun)/3 个月"
        case .entries100: "还差 \(max(0, 100 - f.entryCount)) 笔"
        case .entries1000: "还差 \(max(0, 1000 - f.entryCount)) 笔"
        case .anniversary: f.daysUntilAnniversary.map { "还差 \($0) 天" } ?? "记下第一笔账"
        }
    }
}

public enum OpenStreak {
    /// 从 `today` 往回数,连续有打开记录的天数;今天没打开过就是 0。
    public static func current(days: Set<Date>, today: Date) -> Int {
        var count = 0
        var day = today
        while days.contains(day) {
            count += 1
            guard let previous = DayStamp.calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

public enum MonthlyHabits {
    /// `totals` 是连续几个已结束月份的支出(从早到晚)。返回"比上月少"最长连续了几个月;
    /// 上个月没有支出时,这个月不算。
    public static func bestDecreasingRun(_ totals: [Int]) -> Int {
        var best = 0
        var run = 0
        for index in totals.indices.dropFirst() {
            if totals[index - 1] > 0 && totals[index] < totals[index - 1] {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return best
    }
}
