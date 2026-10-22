import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct HistorySearchTests {
    // MARK: 金额

    @Test func decimalAmountsMatchExactly() {
        for text in ["147.7", "147.70", "¥147.70", " 147.70 "] {
            #expect(AmountQuery.range(for: text) == 14770..<14771, "\(text)")
        }
    }

    @Test func wholeAmountsMatchTheWholeYuan() {
        #expect(AmountQuery.range(for: "147") == 14700..<14800)
        #expect(AmountQuery.range(for: "147元") == 14700..<14800)
    }

    @Test func textThatIsNotAnAmountHasNoRange() {
        for text in ["0", "abc", "", "-5", "示例"] {
            #expect(AmountQuery.range(for: text) == nil, "\(text)")
        }
    }

    // MARK: 本月搜索与分组

    private func row(_ cents: Int, note: String = "", date: Date = makeDate(2026, 10, 15)) -> EntryRow {
        EntryRow(
            date: date, kind: .expense, cents: cents, note: note,
            topCategoryID: nil, topCategoryName: "餐饮", topColorHex: "#000000"
        )
    }

    @Test func monthSearchAlsoMatchesAmounts() {
        let rows = [row(14770), row(1470), row(147000), row(500, note: "147 号店")]
        #expect(BillsLogic.search(rows, query: "147").map(\.cents) == [14770, 500])
    }

    @Test func resultsAreGroupedByMonthNewestFirst() {
        let rows = [
            row(100, date: makeDate(2025, 3, 2)),
            row(200, date: makeDate(2026, 10, 15)),
            row(300, date: makeDate(2025, 3, 20)),
        ]

        let groups = BillsLogic.groupByMonth(rows, calendar: testCalendar)

        #expect(groups.map(\.month) == [makeDate(2026, 10, 1), makeDate(2025, 3, 1)])
        #expect(groups[1].rows.map(\.cents) == [300, 100])
        #expect(groups.map(\.expenseCents) == [200, 400])
    }

    // MARK: 全部历史

    private struct Fixture {
        let context: ModelContext
        let food: LedgerCategory
        let lunch: LedgerCategory
        let transport: LedgerCategory
    }

    private func makeFixture(_ container: ModelContainer) throws -> Fixture {
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let transport = CategoryRules.addTopLevel(
            name: "交通", symbolName: "bus.fill", colorHex: "#0A84FF",
            kind: .expense, sortOrder: 1, in: context
        )
        return Fixture(context: context, food: food, lunch: lunch, transport: transport)
    }

    @discardableResult
    private func add(
        _ context: ModelContext, cents: Int = 1000, note: String = "",
        category: LedgerCategory? = nil, _ y: Int = 2026, _ m: Int = 10, _ d: Int = 15
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            amountInCents: cents, kind: .expense, date: makeDate(y, m, d), note: note,
            category: category, createdAt: makeDate(y, m, d, 12), calendar: testCalendar
        )
        context.insert(entry)
        return entry
    }

    @Test func notesMatchInAnyMonth() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let old = add(f.context, note: "示例小吃", 2024, 1, 1)
        let new = add(f.context, note: "示例小吃二店", 2026, 10, 15)
        add(f.context, note: "别的")
        try f.context.save()

        #expect(try HistorySearch.search("小吃", in: f.context).map(\.id) == [new.id, old.id])
    }

    @Test func aTopLevelCategoryMatchIncludesItsSubcategories() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let food = add(f.context, category: f.food, 2026, 10, 2)
        let lunch = add(f.context, category: f.lunch, 2026, 10, 1)
        add(f.context, category: f.transport)
        try f.context.save()

        #expect(try HistorySearch.search("餐饮", in: f.context).map(\.id) == [food.id, lunch.id])
    }

    @Test func aSubcategoryMatchOnlyIncludesThatSubcategory() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        add(f.context, category: f.food)
        let lunch = add(f.context, category: f.lunch)
        try f.context.save()

        #expect(try HistorySearch.search("午餐", in: f.context).map(\.id) == [lunch.id])
    }

    @Test func searchingUncategorizedFindsEntriesWithoutACategory() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let none = add(f.context)
        add(f.context, category: f.food)
        try f.context.save()

        #expect(try HistorySearch.search("未分类", in: f.context).map(\.id) == [none.id])
    }

    @Test func amountsMatchAcrossMonths() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let exact = add(f.context, cents: 14770, 2024, 5, 1)
        let sameYuan = add(f.context, cents: 14799, 2026, 10, 15)
        add(f.context, cents: 1470)
        add(f.context, cents: 147000)
        try f.context.save()

        #expect(try HistorySearch.search("147", in: f.context).map(\.id) == [sameYuan.id, exact.id])
        #expect(try HistorySearch.search("147.7", in: f.context).map(\.id) == [exact.id])
    }

    @Test func anEntryMatchingSeveralWaysAppearsOnce() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        add(f.context, note: "餐饮外卖", category: f.food)
        try f.context.save()

        #expect(try HistorySearch.search("餐饮", in: f.context).count == 1)
    }

    @Test func aBlankQueryFindsNothing() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        add(f.context, note: "示例")
        try f.context.save()

        #expect(try HistorySearch.search("  ", in: f.context).isEmpty)
    }
}
