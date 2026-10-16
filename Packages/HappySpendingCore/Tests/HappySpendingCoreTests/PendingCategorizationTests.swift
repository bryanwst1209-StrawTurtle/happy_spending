import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PendingCategorizationTests {
    private let now = makeDate(2026, 10, 16, 9, 0)

    private func makeCategories(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory, salary: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let salary = CategoryRules.addTopLevel(
            name: "工资", symbolName: "banknote.fill", colorHex: "#30D158",
            kind: .income, sortOrder: 0, in: context
        )
        return (food, lunch, salary)
    }

    /// 插入一笔账;默认是没有分类、没有商户的屏幕识别支出。
    @discardableResult
    private func add(
        _ context: ModelContext,
        kind: EntryKind = .expense,
        month: Int = 10,
        day: Int = 15,
        createdMinute: Int = 0,
        category: LedgerCategory? = nil,
        source: EntrySource? = .screenText,
        merchant: String? = nil
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            amountInCents: 1000,
            kind: kind,
            date: makeDate(2026, month, day),
            note: merchant ?? "",
            category: category,
            createdAt: makeDate(2026, month, day, 12, createdMinute),
            calendar: testCalendar,
            autoSource: source,
            merchant: merchant
        )
        context.insert(entry)
        return entry
    }

    private func memories(_ context: ModelContext) throws -> [MerchantCategory] {
        try context.fetch(FetchDescriptor<MerchantCategory>())
    }

    // MARK: 待归类列表

    @Test func pendingIsUncategorizedExpensesOldestFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let late = add(context, day: 15, createdMinute: 30)
        let early = add(context, day: 15, createdMinute: 10)
        let lastMonth = add(context, month: 9, day: 28)

        let order = PendingCategorization.pending([late, early, lastMonth]).map(\.id)

        #expect(order == [lastMonth.id, early.id, late.id])
    }

    @Test func pendingSkipsIncomeAndCategorizedEntries() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let pending = add(context)
        let income = add(context, kind: .income)
        let categorized = add(context, category: c.food)
        let manual = add(context, category: c.lunch, source: nil)

        let ids = PendingCategorization.pending([pending, income, categorized, manual]).map(\.id)

        #expect(ids == [pending.id])
    }

    // MARK: 文字

    @Test func theNoticeNamesTheMerchant() {
        #expect(PendingCategorization.notice(count: 2, merchant: "示例小吃") == "已同时归类 2 笔 示例小吃")
        #expect(PendingCategorization.notice(count: 1, merchant: nil) == "已同时归类 1 笔")
        #expect(PendingCategorization.notice(count: 3, merchant: "  ") == "已同时归类 3 笔")
    }

    @Test func sourcesHaveReadableNames() {
        #expect(EntrySource.applePay.displayName == "Apple Pay")
        #expect(EntrySource.screenText.displayName == "屏幕识别")
        #expect(EntrySource.notification.displayName == "通知")
    }
}
