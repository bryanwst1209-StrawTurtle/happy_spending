import Testing
import Foundation
@testable import HappySpendingCore

struct EntryDateTests {
    private let cal = testCalendar

    @Test func staleUntouchedDefaultMovesToToday() {
        let yesterdayEvening = makeDate(2026, 10, 9, 22, 0)
        let thisMorning = makeDate(2026, 10, 10, 8, 0)
        let result = EntryDate.refreshedDefault(current: yesterdayEvening, isUserChosen: false, now: thisMorning, calendar: cal)
        #expect(result == thisMorning)
    }

    @Test func untouchedDefaultOnTheSameDayIsKept() {
        let morning = makeDate(2026, 10, 10, 8, 0)
        let evening = makeDate(2026, 10, 10, 21, 0)
        let result = EntryDate.refreshedDefault(current: morning, isUserChosen: false, now: evening, calendar: cal)
        #expect(result == morning)
    }

    @Test func explicitlyChosenDateIsNeverReplaced() {
        let chosen = makeDate(2026, 10, 3, 0, 0)
        let result = EntryDate.refreshedDefault(current: chosen, isUserChosen: true, now: makeDate(2026, 10, 10, 8, 0), calendar: cal)
        #expect(result == chosen)
    }
}
