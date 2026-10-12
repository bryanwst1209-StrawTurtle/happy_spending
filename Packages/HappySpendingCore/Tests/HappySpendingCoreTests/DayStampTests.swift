import Testing
import Foundation
@testable import HappySpendingCore

struct DayStampTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func local(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func stampKeepsTheCalendarDayOfTheCalendarItWasMadeIn() {
        let shanghai = calendar("Asia/Shanghai")
        let losAngeles = calendar("America/Los_Angeles")

        let a = DayStamp.stamp(local(shanghai, 2026, 10, 1, 0, 30), in: shanghai)
        let b = DayStamp.stamp(local(losAngeles, 2026, 10, 1, 23, 30), in: losAngeles)

        #expect(a == b)
        let parts = DayStamp.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: a)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 1)
        #expect(parts.hour == 0 && parts.minute == 0)
    }

    @Test func localDateRoundTripsThroughTheStamp() {
        let losAngeles = calendar("America/Los_Angeles")
        let stamp = DayStamp.stamp(local(losAngeles, 2026, 10, 1, 15, 0), in: losAngeles)

        let back = DayStamp.localDate(from: stamp, in: losAngeles)

        let parts = losAngeles.dateComponents([.year, .month, .day, .hour], from: back)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 1 && parts.hour == 0)
    }

    @Test func entryDateIsTheStampNotLocalMidnight() {
        let shanghai = calendar("Asia/Shanghai")
        let entry = LedgerEntry(
            amountInCents: 100, kind: .expense,
            date: local(shanghai, 2026, 10, 1, 0, 30), calendar: shanghai
        )
        #expect(entry.date == makeDate(2026, 10, 1))
    }

    @Test func entryMadeInOneTimeZoneStaysInTheSameMonthWhenReadAnywhere() {
        let shanghai = calendar("Asia/Shanghai")
        let losAngeles = calendar("America/Los_Angeles")

        let firstOfOctober = LedgerEntry(
            amountInCents: 100, kind: .expense,
            date: local(shanghai, 2026, 10, 1, 0, 30), calendar: shanghai
        ).row
        let lastOfSeptember = LedgerEntry(
            amountInCents: 100, kind: .expense,
            date: local(losAngeles, 2026, 9, 30, 23, 30), calendar: losAngeles
        ).row

        let october = Period.month(makeDate(2026, 10, 15))
        #expect(october.filter([firstOfOctober, lastOfSeptember], calendar: DayStamp.calendar) == [firstOfOctober])
    }
}
