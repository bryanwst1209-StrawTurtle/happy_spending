import Testing
import Foundation
@testable import HappySpendingCore

struct WeChatPaymentKeyTests {
    private func time(_ h: Int, _ m: Int, _ s: Int) -> Date {
        testCalendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: h, minute: m, second: s))!
    }

    @Test func theKeyIsChannelAmountAndMinute() {
        #expect(WeChatPaymentKey.make(cents: 14770, time: time(18, 23, 27), calendar: testCalendar)
                == "微信|14770|2026-10-14 18:23")
    }

    @Test func secondsAreDropped() {
        let early = WeChatPaymentKey.make(cents: 20, time: time(9, 5, 0), calendar: testCalendar)
        let late = WeChatPaymentKey.make(cents: 20, time: time(9, 5, 59), calendar: testCalendar)
        #expect(early == "微信|20|2026-10-14 09:05")
        #expect(late == early)
    }
}
