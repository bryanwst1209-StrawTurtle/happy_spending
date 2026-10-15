import Testing
import Foundation
@testable import HappySpendingCore

struct TimeLabelTests {
    /// 2026-10-15 是星期四。
    private let now = makeDate(2026, 10, 15, 16, 40)

    private func resolve(_ line: String, now: Date? = nil) -> Date? {
        TimeLabel.resolve(line, now: now ?? self.now, calendar: testCalendar)
    }

    @Test func aBareTimeIsToday() {
        #expect(resolve("13:00") == makeDate(2026, 10, 15, 13, 0))
        #expect(resolve(" 9:05 ") == makeDate(2026, 10, 15, 9, 5))
    }

    @Test func yesterdayWithOrWithoutASpace() {
        #expect(resolve("昨天 18:23") == makeDate(2026, 10, 14, 18, 23))
        #expect(resolve("昨天18:23") == makeDate(2026, 10, 14, 18, 23))
    }

    @Test func aWeekdayIsTheMostRecentOneAtLeastTwoDaysBack() {
        #expect(resolve("星期六 11:01") == makeDate(2026, 10, 10, 11, 1))
        #expect(resolve("星期六11:01") == makeDate(2026, 10, 10, 11, 1))
    }

    /// 今天星期四、昨天星期三:"星期四"是 7 天前,"星期三"是 8 天前,都不能落到今天或昨天,也不能认不出。
    @Test func everyWeekdayResolvesToExactlyOneDayTwoToEightDaysBack() throws {
        let expected: [String: Int] = [
            "二": 13, "一": 12, "日": 11, "天": 11, "六": 10, "五": 9, "四": 8, "三": 7,
        ]
        for (name, day) in expected {
            let date = try #require(resolve("星期\(name) 08:00"), "星期\(name)")
            #expect(date == makeDate(2026, 10, day, 8, 0), "星期\(name)")
        }
    }

    /// 识别出来的中文标点常是全角(样本里的 `，` `（` `＞`),时间里的冒号也可能是 `：`。
    @Test func aFullWidthColonIsAccepted() {
        #expect(resolve("13：00") == makeDate(2026, 10, 15, 13, 0))
        #expect(resolve("昨天 18：23") == makeDate(2026, 10, 14, 18, 23))
    }

    @Test func aMonthAndDayIsThisYear() {
        #expect(resolve("10月8日 18:23") == makeDate(2026, 10, 8, 18, 23))
    }

    @Test func aMonthAndDayLaterThanNowIsLastYear() {
        let january = makeDate(2026, 1, 2, 9, 0)
        #expect(resolve("12月30日 18:23", now: january) == makeDate(2025, 12, 30, 18, 23))
    }

    @Test func aFullDateIsTakenAsWritten() {
        #expect(resolve("2025年10月8日 18:23") == makeDate(2025, 10, 8, 18, 23))
    }

    @Test func linesThatAreNotWholeValidLabelsAreRejected() {
        for line in ["25:00", "12:60", "昨天 24:10", "2月30日 12:00", "2026年13月1日 12:00",
                     "13:00 支付", "16:40 \\", "星期八 10:00", "·13.00", "", "账单详情＞"] {
            #expect(resolve(line) == nil, "\(line)")
        }
    }
}
