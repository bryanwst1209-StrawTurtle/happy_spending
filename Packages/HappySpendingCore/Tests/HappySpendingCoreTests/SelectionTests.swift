import Testing
import SwiftData
@testable import HappySpendingCore

@MainActor
struct SelectionTests {
    private struct Fixture {
        let container: ModelContainer
        let all: [LedgerCategory]
        let food: LedgerCategory
        let lunch: LedgerCategory
        let transport: LedgerCategory
        let salary: LedgerCategory
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A", kind: .expense, sortOrder: 0, in: context)
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let transport = CategoryRules.addTopLevel(name: "交通", symbolName: "car.fill", colorHex: "#0A84FF", kind: .expense, sortOrder: 1, in: context)
        let salary = CategoryRules.addTopLevel(name: "工资", symbolName: "banknote.fill", colorHex: "#30D158", kind: .income, sortOrder: 0, in: context)
        return Fixture(container: container, all: [transport, salary, lunch, food], food: food, lunch: lunch, transport: transport, salary: salary)
    }

    @Test func keepsAValidCurrentSelection() throws {
        let f = try makeFixture()
        let id = CategoryRules.resolveSelection(current: f.transport.id, kind: .expense, categories: f.all, lastUsed: f.food)
        #expect(id == f.transport.id)
    }

    @Test func aSubcategoryOfTheRightKindIsAValidSelection() throws {
        let f = try makeFixture()
        let id = CategoryRules.resolveSelection(current: f.lunch.id, kind: .expense, categories: f.all, lastUsed: nil)
        #expect(id == f.lunch.id)
    }

    @Test func switchingKindDropsTheOldCategoryAndUsesLastUsedOfTheNewKind() throws {
        let f = try makeFixture()
        let id = CategoryRules.resolveSelection(current: f.lunch.id, kind: .income, categories: f.all, lastUsed: f.salary)
        #expect(id == f.salary.id)
    }

    @Test func lastUsedOfTheWrongKindIsIgnored() throws {
        let f = try makeFixture()
        let id = CategoryRules.resolveSelection(current: nil, kind: .income, categories: f.all, lastUsed: f.food)
        #expect(id == f.salary.id)
    }

    @Test func withoutAnyHintItPicksTheFirstTopLevelBySortOrder() throws {
        let f = try makeFixture()
        let id = CategoryRules.resolveSelection(current: nil, kind: .expense, categories: f.all, lastUsed: nil)
        #expect(id == f.food.id)
    }

    @Test func anArchivedCurrentSelectionIsReplaced() throws {
        let f = try makeFixture()
        CategoryRules.archive(f.food)
        let id = CategoryRules.resolveSelection(current: f.lunch.id, kind: .expense, categories: f.all, lastUsed: nil)
        #expect(id == f.transport.id)
    }

    @Test func noCategoriesMeansNoSelection() {
        let id = CategoryRules.resolveSelection(current: nil, kind: .expense, categories: [], lastUsed: nil)
        #expect(id == nil)
    }
}
