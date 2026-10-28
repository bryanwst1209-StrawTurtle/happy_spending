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

    // MARK: 性能

    /// 每次记账后都会跑一遍;5 年、每天 2 笔、一半待归类(自动记账攒下没归)时也要很快。
    @Test func gatheringStaysFastWithYearsOfEntries() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let f = food(context)
        for day in 0..<1825 {
            let date = now.addingTimeInterval(Double(-day) * 86400)
            for index in 0..<2 {
                context.insert(LedgerEntry(
                    amountInCents: 1000, kind: .expense, date: date, category: index == 0 ? nil : f,
                    createdAt: date, calendar: testCalendar
                ))
            }
        }
        try context.save()

        let clock = ContinuousClock()
        var facts = AchievementFacts()
        let elapsed = try clock.measure {
            facts = try Achievements.gather(from: context, hasBackedUp: false, now: now, calendar: testCalendar)
        }

        #expect(facts.pendingCount == 1825)
        #expect(elapsed < .milliseconds(100), "\(elapsed)")
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
