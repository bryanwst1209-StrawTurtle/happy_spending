import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct AutoEntryRecorderTests {
    private let now = makeDate(2026, 10, 13, 15, 30)

    private func makeFood(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        return (food, lunch)
    }

    private func entries(_ context: ModelContext) throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    @Test func recordsAnAutoExpenseWithAllFields() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try AutoEntryRecorder.record(
            merchant: "美团", amountText: "¥25.50", now: now, calendar: testCalendar, in: context
        )

        let all = try entries(context)
        #expect(all.count == 1)
        let entry = all[0]
        #expect(entry.kind == .expense)
        #expect(entry.amountInCents == 2550)
        #expect(entry.date == makeDate(2026, 10, 13))
        #expect(entry.createdAt == now)
        #expect(entry.note == "美团")
        #expect(entry.merchant == "美团")
        #expect(entry.autoSource == .applePay)
        #expect(entry.isAuto)
        #expect(entry.category == nil)
        #expect(result.entryID == entry.id)
        #expect(result.cents == 2550)
    }

    @Test func theResultMessageNamesTheAmountAndMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let withMerchant = try AutoEntryRecorder.record(
            merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context
        )
        let withoutMerchant = try AutoEntryRecorder.record(
            merchant: "  ", amountText: "1234.5", now: now, calendar: testCalendar, in: context
        )

        #expect(withMerchant.message == "已记 ¥25.00 · 美团")
        #expect(withoutMerchant.message == "已记 ¥1,234.50")
    }

    @Test func aBlankMerchantStillRecordsWithAnEmptyNoteAndNoMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(merchant: "   \n ", amountText: "9.9", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.note == "")
        #expect(entry.merchant == nil)
        #expect(entry.isAuto)
        #expect(entry.category == nil)
    }

    @Test func theMerchantIsTrimmedButOtherwiseKeptAsGiven() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(merchant: "  Star Bucks \n", amountText: "30", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.merchant == "Star Bucks")
        #expect(entry.note == "Star Bucks")
    }

    @Test func emojiMerchantsAreKept() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try AutoEntryRecorder.record(merchant: "🧋 喜茶", amountText: "18", now: now, calendar: testCalendar, in: context)

        #expect(result.message == "已记 ¥18.00 · 🧋 喜茶")
        #expect(try entries(context).first?.merchant == "🧋 喜茶")
    }

    // MARK: 分类记忆

    @Test func usesTheRememberedCategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: food.id, in: context)

        try AutoEntryRecorder.record(merchant: " 美团 ", amountText: "25", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category === food)
    }

    /// 以前记成二级分类的旧记忆:自动账归到它的一级分类。
    @Test func anOldSubcategoryMemoryRecordsTheTopLevel() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: lunch.id, in: context)

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category === food)
        #expect(entry.row.displayCategory == "餐饮")
    }

    @Test func withoutAMemoryTheEntryIsUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try makeFood(context)

        try AutoEntryRecorder.record(merchant: "饿了么", amountText: "25", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category == nil)
        #expect(entry.row.topCategoryName == Uncategorized.name)
    }

    @Test func aMemoryPointingAtAnArchivedCategoryFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: food.id, in: context)
        CategoryRules.archive(food)

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func aMemoryWhoseSubcategoryParentIsArchivedFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: lunch.id, in: context)
        CategoryRules.archive(food)

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func aMemoryPointingAtAMissingCategoryFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try makeFood(context)
        context.insert(MerchantCategory(merchantKey: "美团", categoryID: UUID()))

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    // MARK: 无效金额

    @Test func invalidAmountsCreateNothing() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        #expect(throws: AmountError.invalidAmount) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "abc", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: AmountError.notAnExpense) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "-5", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: AmountError.notAnExpense) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "0", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: AmountError.tooLarge) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "10000000", now: now, calendar: testCalendar, in: context)
        }
        #expect(try entries(context).isEmpty)
    }

    @Test func eachCallCreatesItsOwnEntry() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(merchant: "星巴克", amountText: "15", now: now, calendar: testCalendar, in: context)
        try AutoEntryRecorder.record(merchant: "星巴克", amountText: "15", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).count == 2)
    }

    @Test func theDateIsTheDayOfTheTriggerInTheGivenCalendar() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(
            merchant: "美团", amountText: "25",
            now: makeDate(2026, 12, 31, 23, 59), calendar: testCalendar, in: context
        )

        #expect(try entries(context).first?.date == makeDate(2026, 12, 31))
    }
}
