import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct DeletedEntrySnapshotTests {
    private func makeFood(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        return (food, lunch)
    }

    @Test func restoringAManualEntryKeepsEveryField() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, lunch) = try makeFood(context)
        let original = LedgerEntry(
            id: UUID(), amountInCents: 2350, kind: .expense, date: makeDate(2026, 10, 10),
            note: "牛肉面", category: lunch, createdAt: makeDate(2026, 10, 10, 12, 30),
            calendar: testCalendar
        )
        context.insert(original)

        let snapshot = DeletedEntrySnapshot(original)
        context.delete(original)
        let restored = snapshot.makeEntry(categories: [lunch])

        #expect(restored.id == snapshot.id)
        #expect(restored.amountInCents == 2350)
        #expect(restored.kind == .expense)
        #expect(restored.date == makeDate(2026, 10, 10))
        #expect(restored.createdAt == makeDate(2026, 10, 10, 12, 30))
        #expect(restored.note == "牛肉面")
        #expect(restored.category === lunch)
        #expect(!restored.isAuto)
        #expect(restored.merchant == nil)
    }

    @Test func restoringAnAutoEntryKeepsItsSourceAndMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let original = LedgerEntry(
            amountInCents: 2500, kind: .expense, date: makeDate(2026, 10, 13),
            note: "美团", autoSource: .applePay, merchant: "美团"
        )
        context.insert(original)

        let snapshot = DeletedEntrySnapshot(original)
        context.delete(original)
        let restored = snapshot.makeEntry(categories: [])

        #expect(restored.isAuto)
        #expect(restored.autoSource == .applePay)
        #expect(restored.merchant == "美团")
        #expect(restored.row.isAuto)
    }

    @Test func anUnknownFutureSourceIsPreservedToo() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let original = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13))
        original.autoSourceRaw = "recurring"
        context.insert(original)

        let restored = DeletedEntrySnapshot(original).makeEntry(categories: [])

        #expect(restored.autoSourceRaw == "recurring")
        #expect(restored.isAuto)
    }

    @Test func aCategoryThatNoLongerExistsRestoresAsUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        let original = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13), category: food)
        context.insert(original)

        let restored = DeletedEntrySnapshot(original).makeEntry(categories: [])

        #expect(restored.category == nil)
    }

    @Test func snapshotsOfDifferentEntriesAreNotEqual() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let a = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13))
        let b = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13))
        context.insert(a)
        context.insert(b)

        #expect(DeletedEntrySnapshot(a) != DeletedEntrySnapshot(b))
        #expect(DeletedEntrySnapshot(a) == DeletedEntrySnapshot(a))
    }
}
