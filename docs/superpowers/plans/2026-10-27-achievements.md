# 成就徽章 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 14 个徽章(解锁后永久保留)、打开记录与连续天数、统计页入口与徽章墙、解锁提示,备份带上解锁与打开记录。

**Architecture:** Core 新增两个 SwiftData 实体(`AchievementUnlock`、`OpenDay`),徽章目录 `Achievement`,纯函数 `Achievements.isMet/progress`(输入 `AchievementFacts`),`OpenStreak`、`MonthlyHabits` 两个小计算,`Achievements.gather/check/recordOpen` 从数据库取事实并写解锁记录;`BackupDocument` 增加两个可选字段。app 层新增 `AchievementCenter`(提示、红点、打开徽章墙)、`AchievementWallView`,统计页加入口,`RootTabView` 在打开 / 回到前台时记录并检查,记账与导出备份后再检查。

**Tech Stack:** Swift、SwiftUI、SwiftData、Swift Testing;本地包 `Packages/HappySpendingCore`,XcodeGen。

**Spec:** `docs/superpowers/specs/2026-10-27-achievements-design.md`

## Global Constraints

- 最低系统 iOS 26;不引入第三方依赖;新增实体是纯新增(轻量迁移),不改已有实体。
- 日期约定:`OpenDay.day` 和账单日期一样,是"本地日期当天"按 `DayStamp.stamp(now)` 存成 GMT 当天 0 点;月份、连续天数都在 `DayStamp.calendar` 里算。
- 业务逻辑放 Core,用 Swift Testing + 内存数据库测;app 层保持很薄。
- 面向用户的文字一字不差(徽章名、条件、进度见 spec §2):`成就`、`🏆 解锁:<名字>`、`🏆 解锁了 N 个徽章`、`M月d日解锁`、`起步`、`整理`、`坚持`、`习惯`、`里程碑`。
- "已结束的月份"只看**最近 13 个已结束的月份**(避免每次检查都扫全部历史):检查每次打开都会跑,任何一个月在结束后一年内都会被看到;只有第一次升级时更早的月份不算。
- 提交信息用英文,结尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 测试命令(仓库根目录):`swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`。开始前 391 个测试全部通过(37 个 suite)。
- app 构建命令:`xcodegen generate --quiet && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"`。

## Review Focus

1. **永久保留**:解锁后删掉账单再检查,解锁记录不能消失,也不能写第二条。→ Task 2 `unlocksAreKeptAndNeverDuplicated`
2. **连续天数断档**:中间缺一天,从今天往回数到缺口为止;今天没打开过时为 0。→ Task 1 `theStreakCountsBackFromToday`
3. **本月不算**:本月花得少不能解锁"小有节余"。→ Task 2 `theCurrentMonthNeverCounts`
4. **上月为 0**:上月没有支出时,这个月不算"比上月少"。→ Task 1 `aMonthAfterAnEmptyMonthDoesNotCount`
5. **旧备份**:没有徽章字段的备份照样能恢复,恢复后徽章与打开记录被清空(按空处理)。→ Task 3 `anOldBackupWithoutAchievementsStillRestores`

---

### Task 1: 实体、徽章目录、判定与进度

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/Achievement.swift`
- Modify: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/Fixtures.swift`(测试容器加两个实体)
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AchievementRulesTests.swift`(新建)

**Interfaces:**
- Produces:
  - `@Model public final class AchievementUnlock { id: String; unlockedAt: Date }`、`@Model public final class OpenDay { day: Date }`
  - `public enum Achievement: String, CaseIterable, Identifiable, Sendable`(14 个,`category`、`name`、`condition`、`symbolName`),`Achievement.Category`(`start/tidy/streak/habit/milestone`,`title`)
  - `public struct AchievementFacts`(可变字段,`public init()`)
  - `public enum Achievements { static func isMet(_:_:) -> Bool; static func progress(_:_:) -> String }`
  - `public enum OpenStreak { static func current(days: Set<Date>, today: Date) -> Int }`
  - `public enum MonthlyHabits { static func bestDecreasingRun(_ totals: [Int]) -> Int }`

- [ ] **Step 1: 写失败的测试**

在 `Fixtures.swift` 里,把

```swift
        for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self,
```

换成

```swift
        for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self, AchievementUnlock.self, OpenDay.self,
```

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AchievementRulesTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct AchievementRulesTests {
    private func facts(_ change: (inout AchievementFacts) -> Void) -> AchievementFacts {
        var f = AchievementFacts()
        change(&f)
        return f
    }

    @Test func thereAreFourteenBadgesInFiveGroups() {
        #expect(Achievement.allCases.count == 14)
        #expect(Set(Achievement.allCases.map(\.category)).count == 5)
        #expect(Set(Achievement.allCases.map(\.name)).count == 14)
    }

    @Test func eachBadgeUnlocksExactlyAtItsThreshold() {
        let cases: [(Achievement, AchievementFacts, AchievementFacts)] = [
            (.firstEntry, facts { $0.entryCount = 1 }, facts { $0.entryCount = 0 }),
            (.firstAuto, facts { $0.autoEntryCount = 1 }, facts { $0.autoEntryCount = 0 }),
            (.firstBackup, facts { $0.hasBackedUp = true }, facts { $0.hasBackedUp = false }),
            (.inboxZero, facts { $0.entryCount = 5; $0.pendingCount = 0 }, facts { $0.entryCount = 5; $0.pendingCount = 1 }),
            (.tidyMonth, facts { $0.hasTidyMonth = true }, facts { $0.hasTidyMonth = false }),
            (.merchants10, facts { $0.merchantCount = 10 }, facts { $0.merchantCount = 9 }),
            (.streak7, facts { $0.openStreak = 7 }, facts { $0.openStreak = 6 }),
            (.streak30, facts { $0.openStreak = 30 }, facts { $0.openStreak = 29 }),
            (.streak100, facts { $0.openStreak = 100 }, facts { $0.openStreak = 99 }),
            (.spendLess, facts { $0.bestSpendLessRun = 1 }, facts { $0.bestSpendLessRun = 0 }),
            (.spendLess3, facts { $0.bestSpendLessRun = 3 }, facts { $0.bestSpendLessRun = 2 }),
            (.entries100, facts { $0.entryCount = 100 }, facts { $0.entryCount = 99 }),
            (.entries1000, facts { $0.entryCount = 1000 }, facts { $0.entryCount = 999 }),
            (.anniversary, facts { $0.daysUntilAnniversary = 0 }, facts { $0.daysUntilAnniversary = 1 }),
        ]
        #expect(cases.count == 14)
        for (badge, met, notMet) in cases {
            #expect(Achievements.isMet(badge, met), "\(badge)")
            #expect(!Achievements.isMet(badge, notMet), "\(badge)")
        }
    }

    @Test func anEmptyLedgerIsNotInboxZero() {
        #expect(!Achievements.isMet(.inboxZero, AchievementFacts()))
    }

    @Test func noEntriesMeansNoAnniversary() {
        #expect(!Achievements.isMet(.anniversary, AchievementFacts()))
    }

    @Test func progressTextsTellWhatIsLeft() {
        #expect(Achievements.progress(.inboxZero, facts { $0.entryCount = 5; $0.pendingCount = 3 }) == "待归类还有 3 笔")
        #expect(Achievements.progress(.merchants10, facts { $0.merchantCount = 4 }) == "记住了 4/10 个商户")
        #expect(Achievements.progress(.streak7, facts { $0.openStreak = 4 }) == "连续 4/7 天")
        #expect(Achievements.progress(.streak100, facts { $0.openStreak = 12 }) == "连续 12/100 天")
        #expect(Achievements.progress(.spendLess3, facts { $0.bestSpendLessRun = 1 }) == "连续 1/3 个月")
        #expect(Achievements.progress(.entries100, facts { $0.entryCount = 63 }) == "还差 37 笔")
        #expect(Achievements.progress(.anniversary, facts { $0.daysUntilAnniversary = 40 }) == "还差 40 天")
        #expect(Achievements.progress(.firstEntry, AchievementFacts()) == "记下第一笔账")
    }

    // MARK: 连续天数

    @Test func theStreakCountsBackFromToday() {
        let days: Set<Date> = [makeDate(2026, 10, 27), makeDate(2026, 10, 26), makeDate(2026, 10, 25), makeDate(2026, 10, 23)]
        #expect(OpenStreak.current(days: days, today: makeDate(2026, 10, 27)) == 3)
        #expect(OpenStreak.current(days: days, today: makeDate(2026, 10, 28)) == 0)
        #expect(OpenStreak.current(days: [], today: makeDate(2026, 10, 27)) == 0)
    }

    @Test func theStreakCrossesMonthsAndYears() {
        let days: Set<Date> = [makeDate(2027, 1, 1), makeDate(2026, 12, 31), makeDate(2026, 12, 30)]
        #expect(OpenStreak.current(days: days, today: makeDate(2027, 1, 1)) == 3)
    }

    // MARK: 月度习惯

    @Test func theBestRunOfMonthsSpendingLess() {
        #expect(MonthlyHabits.bestDecreasingRun([500, 400, 300, 200]) == 3)
        #expect(MonthlyHabits.bestDecreasingRun([500, 600, 400, 300, 350]) == 2)
        #expect(MonthlyHabits.bestDecreasingRun([500, 500]) == 0)
        #expect(MonthlyHabits.bestDecreasingRun([500]) == 0)
        #expect(MonthlyHabits.bestDecreasingRun([]) == 0)
    }

    @Test func aMonthAfterAnEmptyMonthDoesNotCount() {
        #expect(MonthlyHabits.bestDecreasingRun([0, 0]) == 0)
        #expect(MonthlyHabits.bestDecreasingRun([0, 300, 200]) == 1)
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'AchievementFacts' in scope`(以及 `AchievementUnlock`、`OpenDay` 等找不到)。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/Achievement.swift`:

```swift
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
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 400 tests in 38 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: achievement catalog, unlock rules, streak and monthly habits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 从数据库取事实、检查并写解锁、记录打开

**Files:**
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/Achievement.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AchievementCheckTests.swift`(新建)

**Interfaces:**
- Consumes: Task 1 的全部;已有的 `LedgerQueries.uncategorized()/earliest()`、`PendingCategorization.pending`、`DayStamp`。
- Produces(在 `Achievements` 上):
  - `static func recordOpen(in: ModelContext, now: Date, calendar: Calendar = .current) throws`
  - `static func gather(from: ModelContext, hasBackedUp: Bool, now: Date, calendar: Calendar = .current) throws -> AchievementFacts`
  - `@discardableResult static func check(in: ModelContext, hasBackedUp: Bool, now: Date, calendar: Calendar = .current) throws -> [Achievement]`(新解锁的,按 `allCases` 顺序)

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AchievementCheckTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct AchievementCheckTests {
    /// 2026-10-27 是星期二;本月是 10 月,已结束的月份从 9 月往前。
    private let now = makeDate(2026, 10, 27, 9, 0)

    private func food(_ context: ModelContext) -> LedgerCategory {
        CategoryRules.addTopLevel(name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A", kind: .expense, sortOrder: 0, in: context)
    }

    private func add(
        _ context: ModelContext, _ cents: Int, _ y: Int, _ m: Int, _ d: Int,
        category: LedgerCategory? = nil, auto: Bool = false, kind: EntryKind = .expense
    ) {
        context.insert(LedgerEntry(
            amountInCents: cents, kind: kind, date: makeDate(y, m, d), category: category,
            createdAt: makeDate(y, m, d, 12), calendar: testCalendar, autoSource: auto ? .screenText : nil
        ))
    }

    private func unlocked(_ context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<AchievementUnlock>()).map(\.id))
    }

    @Test func anEmptyLedgerUnlocksNothing() throws {
        let container = try makeTestContainer()
        let new = try Achievements.check(in: container.mainContext, hasBackedUp: false, now: now, calendar: testCalendar)
        #expect(new.isEmpty)
    }

    @Test func theFirstChecksUnlockWhatIsAlreadyTrue() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let f = food(context)
        add(context, 1000, 2026, 10, 1, category: f, auto: true)
        try context.save()

        let new = try Achievements.check(in: context, hasBackedUp: true, now: now, calendar: testCalendar)

        #expect(new == [.firstEntry, .firstAuto, .firstBackup, .inboxZero])
        let unlock = try #require(try context.fetch(FetchDescriptor<AchievementUnlock>()).first { $0.id == "firstEntry" })
        #expect(unlock.unlockedAt == now)
    }

    @Test func unlocksAreKeptAndNeverDuplicated() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 1000, 2026, 10, 1, category: food(context))
        try context.save()
        try Achievements.check(in: context, hasBackedUp: false, now: now, calendar: testCalendar)

        for entry in try context.fetch(FetchDescriptor<LedgerEntry>()) { context.delete(entry) }
        try context.save()
        let again = try Achievements.check(in: context, hasBackedUp: false, now: now, calendar: testCalendar)

        #expect(again.isEmpty)
        #expect(try unlocked(context).contains("firstEntry"))
        #expect(try context.fetch(FetchDescriptor<AchievementUnlock>()).count == 2)
    }

    @Test func pendingEntriesBlockInboxZero() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 1000, 2026, 10, 1)
        try context.save()

        let facts = try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar)

        #expect(facts.pendingCount == 1)
        #expect(!(try Achievements.check(in: context, hasBackedUp: false, now: now, calendar: testCalendar)).contains(.inboxZero))
    }

    // MARK: 打开记录

    @Test func openingTwiceADayRecordsOneDay() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        try Achievements.recordOpen(in: context, now: now, calendar: testCalendar)
        try Achievements.recordOpen(in: context, now: now.addingTimeInterval(3600), calendar: testCalendar)

        #expect(try context.fetch(FetchDescriptor<OpenDay>()).map(\.day) == [makeDate(2026, 10, 27)])
    }

    @Test func sevenDaysInARowUnlocksTheWeek() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        for offset in 0..<7 {
            try Achievements.recordOpen(in: context, now: now.addingTimeInterval(Double(-offset) * 86400), calendar: testCalendar)
        }

        let facts = try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar)

        #expect(facts.openStreak == 7)
        #expect(try Achievements.check(in: context, hasBackedUp: false, now: now, calendar: testCalendar).contains(.streak7))
    }

    // MARK: 月份

    @Test func aMonthSpendingLessThanTheOneBeforeUnlocks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let f = food(context)
        add(context, 50000, 2026, 8, 10, category: f)
        add(context, 30000, 2026, 9, 10, category: f)
        try context.save()

        #expect(try Achievements.check(in: context, hasBackedUp: false, now: now, calendar: testCalendar).contains(.spendLess))
    }

    @Test func theCurrentMonthNeverCounts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let f = food(context)
        add(context, 50000, 2026, 9, 10, category: f)
        add(context, 100, 2026, 10, 10, category: f)
        try context.save()

        let facts = try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar)

        #expect(facts.bestSpendLessRun == 0)
    }

    @Test func monthsAcrossTheYearAreCompared() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let f = food(context)
        add(context, 40000, 2025, 12, 5, category: f)
        add(context, 30000, 2026, 1, 5, category: f)
        add(context, 20000, 2026, 2, 5, category: f)
        add(context, 10000, 2026, 3, 5, category: f)
        try context.save()

        let facts = try Achievements.gather(from: context, hasBackedUp: false, now: makeDate(2026, 4, 2), calendar: testCalendar)

        #expect(facts.bestSpendLessRun == 3)
    }

    @Test func incomeDoesNotCountAsSpending() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 30000, 2026, 8, 10)
        add(context, 99999, 2026, 9, 1, kind: .income)
        add(context, 20000, 2026, 9, 10)
        try context.save()

        let facts = try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar)

        #expect(facts.bestSpendLessRun == 1)
    }

    @Test func aTidyMonthNeedsTenCategorizedExpenses() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let f = food(context)
        for day in 1...10 { add(context, 100, 2026, 9, day, category: f) }
        try context.save()
        #expect(try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar).hasTidyMonth)

        add(context, 100, 2026, 9, 11)
        try context.save()
        #expect(!(try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar).hasTidyMonth))
    }

    @Test func nineEntriesAreNotATidyMonth() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let f = food(context)
        for day in 1...9 { add(context, 100, 2026, 9, day, category: f) }
        try context.save()
        #expect(!(try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar).hasTidyMonth))
    }

    // MARK: 周年

    @Test func theAnniversaryCountsDaysFromTheFirstEntry() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 100, 2025, 11, 6)
        try context.save()

        #expect(try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar).daysUntilAnniversary == 10)
        #expect(try Achievements.gather(from: context, hasBackedUp: false, now: makeDate(2026, 11, 6, 8), calendar: testCalendar).daysUntilAnniversary == 0)
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: type 'Achievements' has no member 'check'`(以及 `gather`、`recordOpen`)。

- [ ] **Step 3: 实现**

在 `Achievement.swift` 末尾追加:

```swift

extension Achievements {
    /// 记下今天打开过 app;今天已经记过就什么也不做。
    public static func recordOpen(in context: ModelContext, now: Date, calendar: Calendar = .current) throws {
        let today = DayStamp.stamp(now, in: calendar)
        var descriptor = FetchDescriptor<OpenDay>(predicate: #Predicate { $0.day == today })
        descriptor.fetchLimit = 1
        guard try context.fetchCount(descriptor) == 0 else { return }
        context.insert(OpenDay(day: today))
        try context.save()
    }

    /// 从数据库算出判定所需的事实。月份只看最近 13 个已结束的月份(本月不算)。
    public static func gather(
        from context: ModelContext, hasBackedUp: Bool, now: Date, calendar: Calendar = .current
    ) throws -> AchievementFacts {
        let stamps = DayStamp.calendar
        let today = DayStamp.stamp(now, in: calendar)
        var facts = AchievementFacts()
        facts.hasBackedUp = hasBackedUp
        facts.entryCount = try context.fetchCount(FetchDescriptor<LedgerEntry>())
        facts.autoEntryCount = try context.fetchCount(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.autoSourceRaw != nil }))
        facts.pendingCount = PendingCategorization.pending(try context.fetch(LedgerQueries.uncategorized())).count
        facts.merchantCount = try context.fetchCount(FetchDescriptor<MerchantCategory>())
        facts.openStreak = OpenStreak.current(
            days: Set(try context.fetch(FetchDescriptor<OpenDay>()).map(\.day)), today: today
        )

        // 最近 13 个已结束的月份:每月支出合计,以及是否"全部有分类且至少 10 笔"。
        let thisMonth = stamps.dateInterval(of: .month, for: today)!.start
        let months = (1...13).reversed().compactMap { stamps.date(byAdding: .month, value: -$0, to: thisMonth) }
        if let start = months.first {
            let expense = EntryKind.expense.rawValue
            let entries = try context.fetch(FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.kindRaw == expense && $0.date >= start && $0.date < thisMonth }
            ))
            let byMonth = Dictionary(grouping: entries) { stamps.dateInterval(of: .month, for: $0.date)!.start }
            facts.bestSpendLessRun = MonthlyHabits.bestDecreasingRun(
                months.map { byMonth[$0]?.reduce(0) { $0 + $1.amountInCents } ?? 0 }
            )
            facts.hasTidyMonth = byMonth.values.contains { $0.count >= 10 && $0.allSatisfy { $0.category != nil } }
        }

        if let first = try context.fetch(LedgerQueries.earliest()).first?.date,
           let anniversary = stamps.date(byAdding: .year, value: 1, to: first) {
            facts.daysUntilAnniversary = max(0, stamps.dateComponents([.day], from: today, to: anniversary).day ?? 0)
        }
        return facts
    }

    /// 检查还没解锁的徽章,满足的写下解锁记录(日期为 `now`),返回这次新解锁的。已解锁的不再判定、不收回。
    @discardableResult
    public static func check(
        in context: ModelContext, hasBackedUp: Bool, now: Date, calendar: Calendar = .current
    ) throws -> [Achievement] {
        let done = Set(try context.fetch(FetchDescriptor<AchievementUnlock>()).map(\.id))
        let remaining = Achievement.allCases.filter { !done.contains($0.rawValue) }
        guard !remaining.isEmpty else { return [] }
        let facts = try gather(from: context, hasBackedUp: hasBackedUp, now: now, calendar: calendar)
        let new = remaining.filter { isMet($0, facts) }
        guard !new.isEmpty else { return [] }
        for badge in new { context.insert(AchievementUnlock(id: badge.rawValue, unlockedAt: now)) }
        try context.save()
        return new
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 413 tests in 39 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: gather facts, check and record achievements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 备份带上解锁与打开记录

**Files:**
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/Backup.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BackupTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `AchievementUnlock`、`OpenDay`;已有的 `Backup`、`BackupDocument`、测试辅助 `fill`、`appearance`、`now`、`snapshot`、`json`、`validObject`。
- Produces: `BackupDocument.Unlock { id: String; unlockedAt: Date }`;`BackupDocument.achievements: [Unlock]?`、`openDays: [Date]?`;`makeDocument` 填入,`replace` 整体替换(nil 按空)。

- [ ] **Step 1: 写失败的测试**

在 `BackupTests.swift` 里,紧挨 `    // MARK: 预览` 之前加入:

```swift
    // MARK: 成就

    @Test func achievementsAndOpenDaysTravelWithTheBackup() throws {
        let source = try makeTestContainer()
        let context = source.mainContext
        try fill(context)
        context.insert(AchievementUnlock(id: "firstEntry", unlockedAt: makeDate(2026, 10, 20, 8)))
        context.insert(OpenDay(day: makeDate(2026, 10, 26)))
        context.insert(OpenDay(day: makeDate(2026, 10, 27)))
        try context.save()
        let document = try snapshot(context)
        #expect(document.achievements?.map(\.id) == ["firstEntry"])
        #expect(document.openDays == [makeDate(2026, 10, 26), makeDate(2026, 10, 27)])

        let target = try makeTestContainer()
        try Backup.replace(with: try Backup.decode(try Backup.encode(document)), in: target.mainContext)

        #expect(try snapshot(target.mainContext) == document)
    }

    @Test func anOldBackupWithoutAchievementsStillRestores() throws {
        var object = try validObject()
        object.removeValue(forKey: "achievements")
        object.removeValue(forKey: "openDays")
        let document = try Backup.decode(json(object))
        #expect(document.achievements == nil)

        let target = try makeTestContainer()
        let context = target.mainContext
        context.insert(AchievementUnlock(id: "firstEntry", unlockedAt: now))
        context.insert(OpenDay(day: makeDate(2026, 10, 27)))
        try context.save()

        try Backup.replace(with: document, in: context)

        #expect(try context.fetch(FetchDescriptor<AchievementUnlock>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<OpenDay>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<LedgerEntry>()).count == 2)
    }

```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: value of type 'BackupDocument' has no member 'achievements'`(以及 `openDays`)。

- [ ] **Step 3: 实现**

在 `Backup.swift` 里:

把

```swift
    public var merchantMemory: [Memory]
    public var appearance: Appearance
```

换成

```swift
    public var merchantMemory: [Memory]
    public var appearance: Appearance
    /// 成就解锁记录;旧版本的备份没有这一项(nil,恢复时按空处理)。
    public var achievements: [Unlock]?
    /// 打开过 app 的日子;旧版本的备份没有这一项。
    public var openDays: [Date]?

    public struct Unlock: Codable, Equatable, Sendable {
        public var id: String
        public var unlockedAt: Date
    }
```

把

```swift
            appearance: appearance
        )
    }
```

(在 `makeDocument` 里)换成

```swift
            appearance: appearance,
            achievements: try context.fetch(FetchDescriptor<AchievementUnlock>(sortBy: [SortDescriptor(\.id)]))
                .map { BackupDocument.Unlock(id: $0.id, unlockedAt: $0.unlockedAt) },
            openDays: try context.fetch(FetchDescriptor<OpenDay>(sortBy: [SortDescriptor(\.day)])).map(\.day)
        )
    }
```

把

```swift
            for memory in try context.fetch(FetchDescriptor<MerchantCategory>()) { context.delete(memory) }
```

换成

```swift
            for memory in try context.fetch(FetchDescriptor<MerchantCategory>()) { context.delete(memory) }
            for unlock in try context.fetch(FetchDescriptor<AchievementUnlock>()) { context.delete(unlock) }
            for day in try context.fetch(FetchDescriptor<OpenDay>()) { context.delete(day) }
```

把

```swift
            try beforeSave()
```

换成

```swift
            var seenBadges = Set<String>()
            for item in document.achievements ?? [] where seenBadges.insert(item.id).inserted {
                context.insert(AchievementUnlock(id: item.id, unlockedAt: item.unlockedAt))
            }
            for day in Set(document.openDays ?? []) {
                context.insert(OpenDay(day: day))
            }

            try beforeSave()
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 415 tests in 39 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: include achievements and open days in backups

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: app 层:容器、检查时机、提示、统计页入口、徽章墙

**Files:**
- Modify: `HappySpending/SharedModelContainer.swift`
- Create: `HappySpending/Stats/AchievementCenter.swift`
- Create: `HappySpending/Stats/AchievementWallView.swift`
- Modify(整个换成): `HappySpending/RootTabView.swift`
- Modify: `HappySpending/HappySpendingApp.swift`
- Modify: `HappySpending/Stats/StatsView.swift`
- Modify: `HappySpending/Record/RecordView.swift`
- Modify: `HappySpending/Settings/BackupSection.swift`

**Interfaces:**
- Consumes: Task 1~2 的 `Achievement`、`AchievementUnlock`、`OpenDay`、`Achievements.recordOpen/check/gather/progress`;已有的 `BackupService`(`lastExport`、`lastAutoBackup`、`autoBackupIfNeeded`)、`AppearanceModel`。
- Produces: `AchievementCenter`(`@MainActor @Observable`:`toast`、`showWall`、`seenAt`、`appeared(context:backup:)`、`check(context:backup:)`、`markSeen()`),`AchievementWallView`。

界面层没有单元测试;验证是构建通过 + 模拟器走一遍。

- [ ] **Step 1: 容器和提示中心**

在 `HappySpending/SharedModelContainer.swift` 里,把

```swift
                for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self
```

换成

```swift
                for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self, AchievementUnlock.self, OpenDay.self
```

新建 `HappySpending/Stats/AchievementCenter.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

/// 成就的检查时机、解锁提示和"看过"红点。
@MainActor
@Observable
final class AchievementCenter {
    private static let seenKey = "achievementsSeenAt"

    /// 顶部的小提示;约 3 秒后自动消失。
    private(set) var toast: String?
    /// 点提示时切到统计页并打开徽章墙。
    var showWall = false
    /// 上次看徽章墙的时间,之后解锁的徽章带红点。
    private(set) var seenAt: Date

    init() {
        seenAt = UserDefaults.standard.object(forKey: Self.seenKey) as? Date ?? .distantPast
    }

    /// 打开 app / 回到前台:先记下今天打开过,再检查。
    func appeared(context: ModelContext, backup: BackupService, now: Date = .now) {
        try? Achievements.recordOpen(in: context, now: now)
        check(context: context, backup: backup, now: now)
    }

    func check(context: ModelContext, backup: BackupService, now: Date = .now) {
        let backedUp = backup.lastExport != nil || backup.lastAutoBackup != nil
        guard let new = try? Achievements.check(in: context, hasBackedUp: backedUp, now: now), !new.isEmpty else { return }
        let text = new.count == 1 ? "🏆 解锁:\(new[0].name)" : "🏆 解锁了 \(new.count) 个徽章"
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if toast == text { toast = nil } }
        }
    }

    func dismissToast() {
        withAnimation { toast = nil }
    }

    func markSeen(now: Date = .now) {
        seenAt = now
        UserDefaults.standard.set(now, forKey: Self.seenKey)
    }
}
```

- [ ] **Step 2: 徽章墙**

新建 `HappySpending/Stats/AchievementWallView.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

/// 徽章墙:按类别分组,已解锁彩色、未解锁灰色带进度;点开看条件。
struct AchievementWallView: View {
    @Environment(\.modelContext) private var context
    @Environment(AchievementCenter.self) private var center
    @Environment(BackupService.self) private var backup
    @Query private var unlocks: [AchievementUnlock]

    @State private var facts = AchievementFacts()
    @State private var detail: Achievement?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var unlockedAt: [String: Date] {
        Dictionary(unlocks.map { ($0.id, $0.unlockedAt) }, uniquingKeysWith: min)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Achievement.Category.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category.title).font(.headline)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Achievement.allCases.filter { $0.category == category }) { badge in
                                Button { detail = badge } label: { tile(badge) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background { AppBackground() }
        .navigationTitle("成就")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let backedUp = backup.lastExport != nil || backup.lastAutoBackup != nil
            facts = (try? Achievements.gather(from: context, hasBackedUp: backedUp, now: .now)) ?? AchievementFacts()
            center.markSeen()
        }
        .sheet(item: $detail) { badge in
            VStack(spacing: 14) {
                icon(badge, unlocked: unlockedAt[badge.rawValue] != nil, size: 72)
                Text(badge.name).font(.title2.weight(.semibold))
                Text(badge.condition).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text(statusText(badge)).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .presentationDetents([.height(300)])
        }
    }

    private func tile(_ badge: Achievement) -> some View {
        let date = unlockedAt[badge.rawValue]
        return VStack(spacing: 6) {
            icon(badge, unlocked: date != nil, size: 56)
            Text(badge.name).font(.subheadline.weight(.medium)).foregroundStyle(date == nil ? .secondary : .primary)
            Text(statusText(badge))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func icon(_ badge: Achievement, unlocked: Bool, size: CGFloat) -> some View {
        Image(systemName: badge.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(unlocked ? .white : .secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(unlocked ? color(badge.category).gradient : Color.secondary.opacity(0.15).gradient))
    }

    private func statusText(_ badge: Achievement) -> String {
        if let date = unlockedAt[badge.rawValue] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日解锁"
            return formatter.string(from: date)
        }
        return Achievements.progress(badge, facts)
    }

    private func color(_ category: Achievement.Category) -> Color {
        switch category {
        case .start: .orange
        case .tidy: .teal
        case .streak: .red
        case .habit: .green
        case .milestone: .purple
        }
    }
}
```

- [ ] **Step 3: 检查时机、提示、入口**

把 `HappySpending/RootTabView.swift` 整个换成:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    enum Page: Hashable { case record, bills, stats, settings }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppearanceModel.self) private var appearance
    @Environment(BackupService.self) private var backup
    @Environment(AchievementCenter.self) private var achievements

    /// 只查没有分类的账,再挑出支出,作为账单页签的角标。
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]
    @Query(LedgerQueries.earliest()) private var anyEntry: [LedgerEntry]
    @State private var page = Page.record

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }

    var body: some View {
        TabView(selection: $page) {
            Tab("记账", systemImage: "plus.circle.fill", value: .record) { RecordView() }
            Tab("账单", systemImage: "list.bullet.rectangle", value: .bills) { BillsView() }
                .badge(pendingCount)
            Tab("统计", systemImage: "chart.pie.fill", value: .stats) { StatsView() }
            Tab("设置", systemImage: "gearshape.fill", value: .settings) { SettingsView() }
                .badge(backup.needsReminder(hasEntries: !anyEntry.isEmpty) ? Text("!") : nil)
        }
        // 打开或回到前台:记下今天打开过、自动备份(没开就跳过)、检查成就。
        .task { await appeared() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appeared() }
        }
        .overlay(alignment: .top) {
            if let toast = achievements.toast {
                Button {
                    achievements.dismissToast()
                    page = .stats
                    achievements.showWall = true
                } label: {
                    ToastView(text: toast)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: achievements.toast) { _, new in new != nil }
    }

    private func appeared() async {
        achievements.appeared(context: context, backup: backup)
        await backup.autoBackupIfNeeded(context: context, appearance: appearance)
        achievements.check(context: context, backup: backup)
    }
}
```

在 `HappySpending/HappySpendingApp.swift` 里,把

```swift
    @State private var backup = BackupService()
```

换成

```swift
    @State private var backup = BackupService()
    @State private var achievements = AchievementCenter()
```

再把

```swift
                .environment(backup)
```

换成

```swift
                .environment(backup)
                .environment(achievements)
```

在 `HappySpending/Stats/StatsView.swift` 里,把

```swift
struct StatsView: View {
    @Environment(AppearanceModel.self) private var appearance
```

换成

```swift
struct StatsView: View {
    @Environment(AppearanceModel.self) private var appearance
    @Environment(AchievementCenter.self) private var achievements
    @Query private var unlocks: [AchievementUnlock]
```

再把

```swift
            .navigationTitle("统计")
```

换成

```swift
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { achievements.showWall = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                            Text("\(Set(unlocks.map(\.id)).count)/\(Achievement.allCases.count)")
                                .font(.subheadline.monospacedDigit())
                        }
                        .overlay(alignment: .topLeading) {
                            if unlocks.contains(where: { $0.unlockedAt > achievements.seenAt }) {
                                Circle().fill(.red).frame(width: 8, height: 8).offset(x: -4, y: -4)
                            }
                        }
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { achievements.showWall },
                set: { achievements.showWall = $0 }
            )) {
                AchievementWallView()
            }
```

在 `HappySpending/Record/RecordView.swift` 里,把

```swift
        savedCount += 1
```

换成

```swift
        savedCount += 1
        achievements.check(context: context, backup: backup)
```

并在 `RecordView` 的属性里,把

```swift
    @Environment(\.modelContext) private var context
```

换成

```swift
    @Environment(\.modelContext) private var context
    @Environment(AchievementCenter.self) private var achievements
    @Environment(BackupService.self) private var backup
```

在 `HappySpending/Settings/BackupSection.swift` 里,把

```swift
    @Environment(BackupService.self) private var backup
```

换成

```swift
    @Environment(BackupService.self) private var backup
    @Environment(AchievementCenter.self) private var achievements
```

再把

```swift
                    data: { [context, appearance, backup] in
                        try backup.exportData(context: context, appearance: appearance)
                    }
```

换成

```swift
                    data: { [context, appearance, backup, achievements] in
                        let data = try backup.exportData(context: context, appearance: appearance)
                        achievements.check(context: context, backup: backup)
                        return data
                    }
```

- [ ] **Step 4: 构建**

Run: Global Constraints 里的 app 构建命令。
Expected: `** BUILD SUCCEEDED **`,没有 HappySpending 目录下的警告。

- [ ] **Step 5: 模拟器里走一遍**

覆盖安装到模拟器(已有账单、导出过备份)并启动。
Expected:
- 启动后顶部滑下"🏆 解锁了 N 个徽章"(第一次升级批量解锁),约 3 秒后消失。
- 统计页右上角是奖杯和"N/14",带红点;点进去是徽章墙,五组;已解锁的彩色并写"M月d日解锁",未解锁的灰色并写进度(如"连续 1/7 天"、"还差 N 笔")。返回后红点消失。
- 点一个徽章弹出详情卡片,写着条件。
- 再记一笔账,如果触发新徽章(比如待归类清零后),顶部弹出"🏆 解锁:<名字>",点它跳到统计页的徽章墙。

- [ ] **Step 6: 提交**

```bash
git add HappySpending
git commit -m "feat: achievement wall, stats entry, unlock toast and checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 文档与最终验证

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `README.md`

- [ ] **Step 1: 文档**

Run(仓库根目录):

```bash
python3 -I - <<'EOF'
def rep(p, old, new):
    s = open(p, encoding="utf-8").read()
    assert s.count(old) == 1, (p, old)
    open(p, "w", encoding="utf-8").write(s.replace(old, new))

rep("docs/manual-test-checklist.md", "## 深色模式", """## 成就徽章

- [ ] 升级后第一次打开:已满足的徽章一次性解锁,只提示一次"解锁了 N 个徽章"
- [ ] 统计页右上角奖杯 + "N/14";有新解锁时带红点,看过后消失
- [ ] 徽章墙五组;已解锁彩色、写解锁日期;未解锁灰色、写进度;点开看条件
- [ ] 记账后触发新徽章时顶部弹提示,点提示跳到徽章墙
- [ ] 连续几天打开 app,"一周"的进度每天加一;断一天从 1 重新计,已解锁的不收回
- [ ] 导出备份再恢复,徽章和连续天数都还在

## 深色模式""")

rep("README.md",
    "- 备份与恢复设计:`docs/superpowers/specs/2026-10-27-backup-and-restore-design.md`\n",
    "- 备份与恢复设计:`docs/superpowers/specs/2026-10-27-backup-and-restore-design.md`\n"
    "- 成就徽章设计:`docs/superpowers/specs/2026-10-27-achievements-design.md`\n")
EOF
```

Expected: 没有输出。

- [ ] **Step 2: 最终验证**

Run: 测试命令,再跑 app 构建命令。
Expected: `✔ Test run with 415 tests in 39 suites passed`;`** BUILD SUCCEEDED **`。

- [ ] **Step 3: 提交**

```bash
git add README.md docs
git commit -m "docs: achievements checklist and README link

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
