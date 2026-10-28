import Foundation
import SwiftData
@testable import HappySpendingCore

/// 与生产代码读取账单日期时用的是同一个日历:GMT 公历,与设备时区无关。
let testCalendar = DayStamp.calendar

func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func makeTestContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self, AchievementUnlock.self, OpenDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}
