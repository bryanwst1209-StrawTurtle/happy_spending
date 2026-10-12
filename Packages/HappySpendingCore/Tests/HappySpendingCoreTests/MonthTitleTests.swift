import Testing
@testable import HappySpendingCore

struct MonthTitleTests {
    @Test func monthTitleReadsYearAndMonth() {
        #expect(BillsLogic.monthTitle(makeDate(2026, 10, 15), calendar: testCalendar) == "2026年10月")
        #expect(BillsLogic.monthTitle(makeDate(2027, 1, 1), calendar: testCalendar) == "2027年1月")
    }
}
