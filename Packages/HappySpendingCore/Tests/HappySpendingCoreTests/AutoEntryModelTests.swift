import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct AutoEntryModelTests {
    @Test func manualEntriesHaveNoAutoMetadata() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13))
        context.insert(entry)

        #expect(entry.autoSource == nil)
        #expect(entry.autoSourceRaw == nil)
        #expect(entry.merchant == nil)
        #expect(!entry.isAuto)
        #expect(!entry.row.isAuto)
    }

    @Test func autoEntriesCarryTheirSourceAndMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(
            amountInCents: 2500, kind: .expense, date: makeDate(2026, 10, 13),
            note: "美团", autoSource: .applePay, merchant: "美团"
        )
        context.insert(entry)
        try context.save()

        #expect(entry.autoSource == .applePay)
        #expect(entry.autoSourceRaw == "applePay")
        #expect(entry.merchant == "美团")
        #expect(entry.isAuto)
        #expect(entry.row.isAuto)
    }

    @Test func entrySourceUsesAStableRawValue() {
        #expect(EntrySource.applePay.rawValue == "applePay")
    }

    @Test func anUnknownFutureSourceStillCountsAsAuto() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13))
        entry.autoSourceRaw = "recurring"
        context.insert(entry)

        #expect(entry.isAuto)
        #expect(entry.autoSource == nil)
    }

    @Test func autoFieldsSurviveASaveAndFetch() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(LedgerEntry(
            amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13),
            autoSource: .applePay, merchant: "星巴克"
        ))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(fetched.count == 1)
        #expect(fetched[0].merchant == "星巴克")
        #expect(fetched[0].autoSource == .applePay)
    }

    @Test func merchantCategoriesCanBeStoredAndFetched() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let categoryID = UUID()
        context.insert(MerchantCategory(merchantKey: "美团", categoryID: categoryID, updatedAt: makeDate(2026, 10, 13)))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MerchantCategory>())
        #expect(fetched.count == 1)
        #expect(fetched[0].merchantKey == "美团")
        #expect(fetched[0].categoryID == categoryID)
        #expect(fetched[0].updatedAt == makeDate(2026, 10, 13))
    }

    @Test func rowSnapshotsKeepEverythingElseUnchanged() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(
            amountInCents: 2500, kind: .expense, date: makeDate(2026, 10, 13),
            note: "美团", autoSource: .applePay, merchant: "美团"
        )
        context.insert(entry)

        let row = entry.row
        #expect(row.cents == 2500)
        #expect(row.note == "美团")
        #expect(row.topCategoryName == Uncategorized.name)
    }
}
