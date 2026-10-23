import Testing
import Foundation
@testable import HappySpendingCore

struct HistoryRangeTests {
    private let now = makeDate(2026, 10, 22)

    @Test func yearsRunFromTheEarliestEntryToThisYear() {
        #expect(HistoryRange.years(earliest: makeDate(2023, 5, 1), now: now, calendar: testCalendar) == 2023...2026)
        #expect(HistoryRange.years(earliest: nil, now: now, calendar: testCalendar) == 2026...2026)
        #expect(HistoryRange.years(earliest: makeDate(2027, 1, 1), now: now, calendar: testCalendar) == 2026...2026)
    }

    @Test func thisYearOnlyOffersMonthsUpToNow() {
        #expect(HistoryRange.months(in: 2026, now: now, calendar: testCalendar) == 1...10)
        #expect(HistoryRange.months(in: 2025, now: now, calendar: testCalendar) == 1...12)
    }

    @Test func theCurrentMonthAndYearAreRecognized() {
        #expect(HistoryRange.isCurrent(.month(makeDate(2026, 10, 1)), now: now, calendar: testCalendar))
        #expect(!HistoryRange.isCurrent(.month(makeDate(2026, 9, 30)), now: now, calendar: testCalendar))
        #expect(HistoryRange.isCurrent(.year(2026), now: now, calendar: testCalendar))
        #expect(!HistoryRange.isCurrent(.year(2025), now: now, calendar: testCalendar))
    }

    /// `DateInterval.contains` 包含终点:不能把下个月 1 号算进上个月。
    @Test func theFirstDayOfTheNextMonthIsNotInThePreviousMonth() {
        let october1 = makeDate(2026, 10, 1)
        #expect(!HistoryRange.isCurrent(.month(makeDate(2026, 9, 15)), now: october1, calendar: testCalendar))
        #expect(!HistoryRange.isCurrent(.year(2025), now: makeDate(2026, 1, 1), calendar: testCalendar))
    }

    /// 年视图从 2025年11月按 › 到 2026 年:不能落在 2026年11月(未来),切回月视图会停在未来月份。
    @Test func shiftingNeverLandsInTheFuture() {
        let now = makeDate(2026, 10, 22)
        let fromLastNovember = HistoryRange.shift(makeDate(2025, 11, 1), by: 1, .year, now: now, calendar: testCalendar)
        #expect(fromLastNovember == makeDate(2026, 10, 22))
        #expect(HistoryRange.isCurrent(.month(fromLastNovember), now: now, calendar: testCalendar))

        let back = HistoryRange.shift(makeDate(2026, 10, 1), by: -1, .month, now: now, calendar: testCalendar)
        #expect(back == makeDate(2026, 9, 1))
    }
}
