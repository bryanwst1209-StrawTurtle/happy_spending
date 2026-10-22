import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct LedgerQueriesTests {
    @discardableResult
    private func add(
        _ context: ModelContext, _ y: Int, _ m: Int, _ d: Int,
        createdMinute: Int = 0, kind: EntryKind = .expense, category: LedgerCategory? = nil
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            amountInCents: 1000, kind: kind, date: makeDate(y, m, d), category: category,
            createdAt: makeDate(y, m, d, 12, createdMinute), calendar: testCalendar
        )
        context.insert(entry)
        return entry
    }

    @Test func aMonthQueryReturnsOnlyThatMonthNewestFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 2026, 9, 30)
        let first = add(context, 2026, 10, 1)
        let last = add(context, 2026, 10, 31)
        add(context, 2026, 11, 1)
        try context.save()

        let found = try context.fetch(LedgerQueries.entries(in: .month(makeDate(2026, 10, 15)), calendar: testCalendar))

        #expect(found.map(\.id) == [last.id, first.id])
    }

    @Test func aYearQueryReturnsOnlyThatYear() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 2025, 12, 31)
        let first = add(context, 2026, 1, 1)
        let last = add(context, 2026, 12, 31)
        add(context, 2027, 1, 1)
        try context.save()

        let found = try context.fetch(LedgerQueries.entries(in: .year(2026), calendar: testCalendar))

        #expect(found.map(\.id) == [last.id, first.id])
    }

    @Test func sameDayEntriesComeNewestRecordedFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let early = add(context, 2026, 10, 15, createdMinute: 5)
        let late = add(context, 2026, 10, 15, createdMinute: 30)
        try context.save()

        let found = try context.fetch(LedgerQueries.entries(in: .month(makeDate(2026, 10, 1)), calendar: testCalendar))

        #expect(found.map(\.id) == [late.id, early.id])
    }

    @Test func theUncategorizedQueryFindsEntriesWithoutACategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let pending = add(context, 2026, 10, 15)
        let income = add(context, 2026, 10, 15, kind: .income)
        add(context, 2026, 10, 15, category: food)
        try context.save()

        let found = try context.fetch(LedgerQueries.uncategorized())

        #expect(Set(found.map(\.id)) == [pending.id, income.id])
        #expect(PendingCategorization.pending(found).map(\.id) == [pending.id])
    }

    @Test func theRecentQueryKeepsTheLatestRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entries = (1...5).map { add(context, 2026, 10, $0) }
        try context.save()

        let found = try context.fetch(LedgerQueries.recent(limit: 3))

        #expect(found.map(\.id) == [entries[4].id, entries[3].id, entries[2].id])
    }

    @Test func theEarliestQueryFindsTheOldestEntry() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        #expect(try context.fetch(LedgerQueries.earliest()).isEmpty)

        add(context, 2026, 10, 15)
        let oldest = add(context, 2024, 3, 1)
        add(context, 2025, 1, 1)
        try context.save()

        #expect(try context.fetch(LedgerQueries.earliest()).map(\.id) == [oldest.id])
    }

    @Test func anEntryCanBeLookedUpByID() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = add(context, 2026, 10, 15)
        try context.save()

        #expect(try context.fetch(LedgerQueries.entry(id: entry.id)).map(\.id) == [entry.id])
        #expect(try context.fetch(LedgerQueries.entry(id: UUID())).isEmpty)
    }
}
