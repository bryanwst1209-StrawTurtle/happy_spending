import Foundation
import SwiftData
@testable import HappySpendingCore

let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}()

func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func makeTestContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LedgerCategory.self, LedgerEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}
