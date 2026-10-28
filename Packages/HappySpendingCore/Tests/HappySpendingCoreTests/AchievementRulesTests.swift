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

    @Test func aMonthWithNothingRecordedIsNotSpendingLess() {
        #expect(MonthlyHabits.bestDecreasingRun([300, 0]) == 0)
        #expect(MonthlyHabits.bestDecreasingRun([500, 400, 0, 300]) == 1)
    }
}
