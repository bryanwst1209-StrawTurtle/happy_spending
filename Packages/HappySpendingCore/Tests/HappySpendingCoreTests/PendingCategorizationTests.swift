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

    /// 微信消息列表一次记好几笔:日期和记账时间都相同。顺序不能取决于传进来的先后。
    @Test func entriesRecordedAtTheSameMomentKeepAStableOrder() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let first = add(context)
        let second = add(context)
        first.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        second.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        let forward = PendingCategorization.pending([first, second]).map(\.id)
        let backward = PendingCategorization.pending([second, first]).map(\.id)

        #expect(forward == [first.id, second.id])
        #expect(backward == forward)
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

    // MARK: 归类

    @Test func assigningAMerchantEntryLearnsAndCategorizesTheSameMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, day: 14, merchant: "Luckin Coffee")
        let sameSpelling = add(context, day: 15, merchant: "Luckin Coffee")
        let otherSpelling = add(context, day: 16, merchant: " luckin  coffee ")
        let otherMerchant = add(context, day: 16, merchant: "Luckin Coffee 二店")
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.lunch, in: context, now: now)

        // 选中的这一笔保留二级分类;记忆和同商户一起归的账只到一级分类。
        #expect(others == 2)
        #expect(entry.category?.id == c.lunch.id)
        #expect(sameSpelling.category?.id == c.food.id)
        #expect(otherSpelling.category?.id == c.food.id)
        #expect(otherMerchant.category == nil)
        #expect(try memories(context).map(\.categoryID) == [c.food.id])
    }

    @Test func backfillLeavesCategorizedAndIncomeEntriesAlone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        let alreadyFood = add(context, category: c.food, merchant: "示例小吃")
        let income = add(context, kind: .income, merchant: "示例小吃")
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.lunch, in: context, now: now)

        #expect(others == 0)
        #expect(alreadyFood.category?.id == c.food.id)
        #expect(income.category == nil)
    }

    /// 通知记的账没有商户:两笔都没有商户不算"同商户"。
    @Test func anEntryWithoutAMerchantIsAssignedAlone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, source: .notification)
        let anotherWithout = add(context, source: .notification)
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.food, in: context, now: now)

        #expect(others == 0)
        #expect(entry.category?.id == c.food.id)
        #expect(anotherWithout.category == nil)
        #expect(try memories(context).isEmpty)
    }

    @Test func aManualEntryIsAssignedWithoutLearning() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let manual = add(context, source: nil, merchant: "示例小吃")
        let auto = add(context, merchant: "示例小吃")
        try context.save()

        let others = try PendingCategorization.assign(manual, to: c.food, in: context, now: now)

        #expect(others == 0)
        #expect(manual.category?.id == c.food.id)
        #expect(auto.category == nil)
        #expect(try memories(context).isEmpty)
    }

    @Test func anIncomeCategoryIsNeitherLearnedNorSpread() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        let twin = add(context, merchant: "示例小吃")
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.salary, in: context, now: now)

        #expect(others == 0)
        #expect(entry.category?.id == c.salary.id)
        #expect(twin.category == nil)
        #expect(try memories(context).isEmpty)
    }

    @Test func theNextAutoEntryOfThatMerchantArrivesCategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        try context.save()

        try PendingCategorization.assign(entry, to: c.lunch, in: context, now: now)
        let result = try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 2500, merchant: "示例小吃", note: "示例小吃"),
            now: now, calendar: testCalendar, in: context
        )

        let recorded = try context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == result.entryID }
        #expect(recorded?.category?.id == c.food.id)
    }

    @Test func backfillDoesNothingWithoutACategoryOrMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let noCategory = add(context, merchant: "示例小吃")
        let twin = add(context, merchant: "示例小吃")
        let noMerchant = add(context, category: c.food)
        let blank = add(context)
        try context.save()

        #expect(try PendingCategorization.backfill(sameMerchantAs: noCategory, in: context) == 0)
        #expect(try PendingCategorization.backfill(sameMerchantAs: noMerchant, in: context) == 0)
        #expect(twin.category == nil)
        #expect(blank.category == nil)
    }

    /// 编辑页的路径:改了自动账的分类,`learnFromEdit` 学到了,再 `backfill`。
    @Test func theEditPathAlsoCategorizesTheSameMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        let twin = add(context, merchant: "示例小吃")
        try context.save()

        entry.category = c.lunch
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)
        let others = try learned ? PendingCategorization.backfill(sameMerchantAs: entry, in: context) : 0
        try context.save()

        #expect(learned)
        #expect(others == 1)
        #expect(twin.category?.id == c.food.id)
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
