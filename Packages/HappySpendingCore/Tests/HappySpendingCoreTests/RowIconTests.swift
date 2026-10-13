import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct RowIconTests {
    private let icon = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])

    private func makeFood(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        return (food, lunch)
    }

    @Test func categoriesStartWithoutACustomIcon() throws {
        let container = try makeTestContainer()
        let (food, lunch) = try makeFood(container.mainContext)
        #expect(food.iconData == nil)
        #expect(lunch.iconData == nil)
    }

    @Test func rowCarriesTheTopLevelSymbolAndIconEvenForASubcategoryEntry() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        food.iconData = icon
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: lunch)
        context.insert(entry)

        let row = entry.row
        #expect(row.topSymbolName == "fork.knife")
        #expect(row.topIconData == icon)
    }

    @Test func rowWithoutACustomIconHasNoIconData() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: food)
        context.insert(entry)

        #expect(entry.row.topIconData == nil)
        #expect(entry.row.topSymbolName == "fork.knife")
    }

    @Test func uncategorizedRowsUseTheQuestionMarkSymbol() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10))
        context.insert(entry)

        #expect(Uncategorized.symbolName == "questionmark.circle.fill")
        #expect(entry.row.topSymbolName == Uncategorized.symbolName)
        #expect(entry.row.topIconData == nil)
    }

    @Test func archivedCategoriesKeepTheirIconOnHistoricalEntries() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        food.iconData = icon
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: lunch)
        context.insert(entry)

        CategoryRules.archive(food)

        #expect(entry.row.topIconData == icon)
        #expect(entry.row.displayCategory == "餐饮 · 午餐")
    }

    @Test func iconDataSurvivesASaveAndCanBeCleared() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)

        food.iconData = icon
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == "餐饮" }
        #expect(fetched?.iconData == icon)

        food.iconData = nil
        try context.save()
        #expect(fetched?.iconData == nil)
    }

    @Test func subcategoryIconIsCarriedSeparatelyFromTheTopLevelIcon() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        let subIcon = Data([0x89, 0x50, 0x4E, 0x47, 0x09, 0x09])
        food.iconData = icon
        lunch.iconData = subIcon
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: lunch)
        context.insert(entry)

        let row = entry.row
        #expect(row.topIconData == icon)
        #expect(row.subIconData == subIcon)
        #expect(row.displayIconData == subIcon)
    }

    @Test func displayIconFallsBackToTheTopLevelIcon() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        food.iconData = icon
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: lunch)
        context.insert(entry)

        #expect(entry.row.subIconData == nil)
        #expect(entry.row.displayIconData == icon)
    }

    @Test func entryOnATopLevelCategoryHasNoSubIcon() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        food.iconData = icon
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: food)
        context.insert(entry)

        #expect(entry.row.subIconData == nil)
        #expect(entry.row.displayIconData == icon)
    }

    @Test func displayIconIsNilWithoutAnyCustomIcon() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, lunch) = try makeFood(context)
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 10), category: lunch)
        context.insert(entry)

        #expect(entry.row.displayIconData == nil)
    }
}
