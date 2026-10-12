import Testing
import SwiftData
@testable import HappySpendingCore

@MainActor
struct RowMappingTests {
    private func makeFood(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        return (food, lunch)
    }

    @Test func entryOnASubcategoryMapsBothLevels() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        let entry = LedgerEntry(amountInCents: 2350, kind: .expense, date: makeDate(2026, 10, 10), note: "牛肉面", category: lunch)
        context.insert(entry)

        let row = entry.row
        #expect(row.topCategoryID == food.id)
        #expect(row.topCategoryName == "餐饮")
        #expect(row.subCategoryID == lunch.id)
        #expect(row.subCategoryName == "午餐")
        #expect(row.topColorHex == "#FF9F0A")
        #expect(row.cents == 2350)
        #expect(row.displayCategory == "餐饮 · 午餐")
    }

    @Test func entryOnATopLevelCategoryHasNoSubcategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: food)
        context.insert(entry)

        let row = entry.row
        #expect(row.topCategoryID == food.id)
        #expect(row.subCategoryID == nil)
        #expect(row.subCategoryName == nil)
        #expect(row.displayCategory == "餐饮")
    }

    @Test func entryWithoutACategoryIsUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10))
        context.insert(entry)

        let row = entry.row
        #expect(row.topCategoryID == nil)
        #expect(row.topCategoryName == "未分类")
        #expect(row.topColorHex == Uncategorized.colorHex)
        #expect(row.displayCategory == "未分类")
    }

    @Test func archivedCategoriesKeepTheirNamesOnHistoricalEntries() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: lunch)
        context.insert(entry)

        CategoryRules.archive(food)

        #expect(entry.row.displayCategory == "餐饮 · 午餐")
    }
}
