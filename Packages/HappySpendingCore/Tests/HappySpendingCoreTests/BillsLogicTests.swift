import Testing
import Foundation
@testable import HappySpendingCore

struct BillsLogicTests {
    private let cal = testCalendar

    // MARK: groupByDay

    @Test func groupsByDayNewestFirstWithSubtotals() {
        let rows = [
            makeRow(cents: 100, on: makeDate(2026, 10, 8)),
            makeRow(cents: 200, on: makeDate(2026, 10, 10)),
            makeRow(cents: 3000, kind: .income, on: makeDate(2026, 10, 10), top: "工资"),
            makeRow(cents: 50, on: makeDate(2026, 10, 10)),
        ]
        let groups = BillsLogic.groupByDay(rows, calendar: cal)

        #expect(groups.map(\.day) == [makeDate(2026, 10, 10), makeDate(2026, 10, 8)])
        #expect(groups[0].expenseCents == 250)
        #expect(groups[0].incomeCents == 3000)
        #expect(groups[0].rows.count == 3)
        #expect(groups[1].expenseCents == 100)
        #expect(groups[1].incomeCents == 0)
    }

    @Test func rowsWithinADayAreNewestCreatedFirst() {
        let day = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 1, on: day, createdAt: makeDate(2026, 10, 10, 9, 0)),
            makeRow(cents: 2, on: day, createdAt: makeDate(2026, 10, 10, 21, 0)),
            makeRow(cents: 3, on: day, createdAt: makeDate(2026, 10, 10, 12, 0)),
        ]
        let groups = BillsLogic.groupByDay(rows, calendar: cal)
        #expect(groups[0].rows.map(\.cents) == [2, 3, 1])
    }

    @Test func groupingNothingGivesNoGroups() {
        #expect(BillsLogic.groupByDay([], calendar: cal).isEmpty)
    }

    @Test func dayTitleShowsDateAndWeekday() {
        #expect(BillsLogic.dayTitle(makeDate(2026, 10, 10), calendar: cal) == "10月10日 周六")
    }

    // MARK: search

    @Test func searchMatchesNoteAndCategoryNamesIgnoringCase() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 1, on: d, top: "餐饮", sub: "午餐", note: "Starbucks 拿铁"),
            makeRow(cents: 2, on: d, top: "交通", note: "地铁"),
            makeRow(cents: 3, on: d, top: "购物", note: ""),
        ]
        #expect(BillsLogic.search(rows, query: "starbucks").map(\.cents) == [1])
        #expect(BillsLogic.search(rows, query: "午餐").map(\.cents) == [1])
        #expect(BillsLogic.search(rows, query: "交通").map(\.cents) == [2])
        #expect(BillsLogic.search(rows, query: "不存在").isEmpty)
    }

    @Test func blankQueryReturnsEverything() {
        let rows = [makeRow(cents: 1, on: makeDate(2026, 10, 10)), makeRow(cents: 2, on: makeDate(2026, 10, 10))]
        #expect(BillsLogic.search(rows, query: "").count == 2)
        #expect(BillsLogic.search(rows, query: "   ").count == 2)
    }

    // MARK: frequentCategoryIDs

    @Test func frequentCategoriesAreOrderedByCountThenRecency() {
        let rows = [
            makeRow(cents: 1, on: makeDate(2026, 10, 1), top: "餐饮", sub: "午餐", createdAt: makeDate(2026, 10, 1)),
            makeRow(cents: 1, on: makeDate(2026, 10, 2), top: "餐饮", sub: "午餐", createdAt: makeDate(2026, 10, 2)),
            makeRow(cents: 1, on: makeDate(2026, 10, 3), top: "交通", createdAt: makeDate(2026, 10, 3)),
            makeRow(cents: 1, on: makeDate(2026, 10, 4), top: "购物", createdAt: makeDate(2026, 10, 4)),
        ]
        let ids = BillsLogic.frequentCategoryIDs(rows, kind: .expense)
        #expect(ids == [stableID("午餐"), stableID("购物"), stableID("交通")])
    }

    @Test func frequentCategoriesRespectLimitKindAndExclusions() {
        let d = makeDate(2026, 10, 1)
        var rows: [EntryRow] = []
        for (i, name) in ["甲", "乙", "丙", "丁", "戊", "己"].enumerated() {
            rows.append(makeRow(cents: 1, on: d, top: name, createdAt: makeDate(2026, 10, 1, i, 0)))
        }
        rows.append(makeRow(cents: 1, kind: .income, on: d, top: "工资", createdAt: makeDate(2026, 10, 2)))

        let limited = BillsLogic.frequentCategoryIDs(rows, kind: .expense, limit: 3)
        #expect(limited.count == 3)
        #expect(!limited.contains(stableID("工资")))

        let excluded = BillsLogic.frequentCategoryIDs(rows, kind: .expense, excluding: [stableID("己")], limit: 10)
        #expect(!excluded.contains(stableID("己")))
        #expect(excluded.count == 5)
    }

    @Test func frequentCategoriesSkipEntriesWithoutACategory() {
        let row = EntryRow(
            date: makeDate(2026, 10, 1), kind: .expense, cents: 1,
            topCategoryID: nil, topCategoryName: Uncategorized.name, topColorHex: Uncategorized.colorHex
        )
        #expect(BillsLogic.frequentCategoryIDs([row], kind: .expense).isEmpty)
    }
}
