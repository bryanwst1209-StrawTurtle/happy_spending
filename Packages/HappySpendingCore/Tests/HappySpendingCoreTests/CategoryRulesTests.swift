import Testing
import SwiftData
@testable import HappySpendingCore

@MainActor
struct CategoryRulesTests {
    @Test func subcategoryInheritsKindAndColorAndLinksToParent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)

        #expect(lunch.parent === food)
        #expect(lunch.kind == .expense)
        #expect(lunch.colorHex == "#FF9F0A")
        #expect(food.parent == nil)
        #expect(food.children.count == 1)
        #expect(lunch.displayName == "餐饮 · 午餐")
        #expect(food.displayName == "餐饮")
    }

    @Test func subcategoryCannotBeNestedFurther() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)

        #expect(throws: CategoryError.parentMustBeTopLevel) {
            try CategoryRules.addSubcategory(name: "工作餐", under: lunch, in: context)
        }
    }

    @Test func archivingTopLevelArchivesChildren() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let dinner = try CategoryRules.addSubcategory(name: "晚餐", under: food, in: context)

        CategoryRules.archive(food)

        #expect(food.isArchived)
        #expect(lunch.isArchived)
        #expect(dinner.isArchived)
    }

    @Test func archivingAChildLeavesTheParentActive() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let dinner = try CategoryRules.addSubcategory(name: "晚餐", under: food, in: context)

        CategoryRules.archive(lunch)

        #expect(lunch.isArchived)
        #expect(!food.isArchived)
        #expect(!dinner.isArchived)
    }

    @Test func seedCreatesDefaultsOnlyOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let first = try DefaultCategories.seedIfNeeded(in: context)
        let countAfterFirst = try context.fetchCount(FetchDescriptor<LedgerCategory>())
        let second = try DefaultCategories.seedIfNeeded(in: context)
        let countAfterSecond = try context.fetchCount(FetchDescriptor<LedgerCategory>())

        #expect(first)
        #expect(!second)
        #expect(countAfterFirst > 0)
        #expect(countAfterFirst == countAfterSecond)
    }

    @Test func seededCategoriesRespectTheTwoLevelRule() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        try DefaultCategories.seedIfNeeded(in: context)

        let all = try context.fetch(FetchDescriptor<LedgerCategory>())
        let tops = all.filter { $0.parent == nil }
        let subs = all.filter { $0.parent != nil }

        #expect(tops.filter { $0.kind == .expense }.count == 7)
        #expect(tops.filter { $0.kind == .income }.count == 3)
        #expect(!subs.isEmpty)
        #expect(subs.allSatisfy { $0.parent?.parent == nil })
        #expect(subs.allSatisfy { $0.kind == $0.parent?.kind })
        #expect(all.allSatisfy { !$0.name.isEmpty && !$0.isArchived })
    }

    @Test func entryDateIsNormalizedToStartOfDay() throws {
        let entry = LedgerEntry(
            amountInCents: 100, kind: .expense,
            date: makeDate(2026, 10, 10, 15, 30), calendar: testCalendar
        )
        #expect(entry.date == makeDate(2026, 10, 10))
    }

    @Test func entryCanAttachToATopLevelCategoryWithoutASubcategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let entry = LedgerEntry(amountInCents: 2350, kind: .expense, date: makeDate(2026, 10, 10), category: food)
        context.insert(entry)
        try context.save()

        #expect(entry.category === food)
        #expect(food.entries.count == 1)
    }
}
