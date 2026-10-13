import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct MerchantMemoryTests {
    private func makeFood(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory, transport: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let transport = CategoryRules.addTopLevel(
            name: "交通", symbolName: "bus.fill", colorHex: "#0A84FF",
            kind: .expense, sortOrder: 1, in: context
        )
        return (food, lunch, transport)
    }

    private func memories(_ context: ModelContext) throws -> [MerchantCategory] {
        try context.fetch(FetchDescriptor<MerchantCategory>())
    }

    // MARK: 商户键

    @Test func normalizeTrimsCollapsesAndIgnoresCase() {
        #expect(MerchantKey.normalize("  美团  ") == "美团")
        #expect(MerchantKey.normalize("Star  Bucks") == "star bucks")
        #expect(MerchantKey.normalize("STARBUCKS") == "starbucks")
        #expect(MerchantKey.normalize("星巴克\n 中关村\t店") == "星巴克 中关村 店")
        #expect(MerchantKey.normalize("星巴克\u{3000}店") == "星巴克 店")
        #expect(MerchantKey.normalize("🧋 喜茶") == "🧋 喜茶")
    }

    @Test func normalizeOfBlankIsEmpty() {
        #expect(MerchantKey.normalize("") == "")
        #expect(MerchantKey.normalize("   \n\t ") == "")
    }

    @Test func trimmedKeepsTheOriginalSpellingAndRejectsBlank() {
        #expect(MerchantKey.trimmed("  Star Bucks \n") == "Star Bucks")
        #expect(MerchantKey.trimmed("   ") == nil)
        #expect(MerchantKey.trimmed("") == nil)
    }

    // MARK: 记忆查找

    @Test func lookupFindsTheRememberedCategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let memory = [MerchantCategory(merchantKey: "美团", categoryID: food.id)]

        let id = MerchantMemory.categoryID(for: " 美团 ", memory: memory, categories: [food])
        #expect(id == food.id)
    }

    @Test func lookupIgnoresCaseAndSpacing() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let memory = [MerchantCategory(merchantKey: "star bucks", categoryID: food.id)]

        #expect(MerchantMemory.categoryID(for: "STAR   BUCKS", memory: memory, categories: [food]) == food.id)
    }

    @Test func lookupWithoutMemoryOrMerchantIsNil() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let memory = [MerchantCategory(merchantKey: "美团", categoryID: food.id)]

        #expect(MerchantMemory.categoryID(for: "饿了么", memory: memory, categories: [food]) == nil)
        #expect(MerchantMemory.categoryID(for: nil, memory: memory, categories: [food]) == nil)
        #expect(MerchantMemory.categoryID(for: "   ", memory: memory, categories: [food]) == nil)
    }

    @Test func lookupIgnoresArchivedCategories() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, transport) = try makeFood(context)
        let memory = [MerchantCategory(merchantKey: "美团", categoryID: transport.id)]
        CategoryRules.archive(transport)

        #expect(MerchantMemory.categoryID(for: "美团", memory: memory, categories: [food, transport]) == nil)
    }

    @Test func lookupIgnoresASubcategoryWhoseTopLevelIsArchived() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch, _) = try makeFood(context)
        let memory = [MerchantCategory(merchantKey: "美团", categoryID: lunch.id)]
        CategoryRules.archive(food)

        #expect(MerchantMemory.categoryID(for: "美团", memory: memory, categories: [food, lunch]) == nil)
    }

    @Test func lookupAcceptsAnActiveSubcategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch, _) = try makeFood(context)
        let memory = [MerchantCategory(merchantKey: "美团", categoryID: lunch.id)]

        #expect(MerchantMemory.categoryID(for: "美团", memory: memory, categories: [food, lunch]) == lunch.id)
    }

    @Test func lookupIgnoresACategoryThatNoLongerExists() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let memory = [MerchantCategory(merchantKey: "美团", categoryID: UUID())]

        #expect(MerchantMemory.categoryID(for: "美团", memory: memory, categories: [food]) == nil)
    }

    // MARK: 学习

    @Test func learnCreatesAMemoryWithANormalizedKey() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)

        try MerchantMemory.learn(merchant: "  Star  Bucks ", categoryID: food.id, in: context, now: makeDate(2026, 10, 13))

        let all = try memories(context)
        #expect(all.count == 1)
        #expect(all[0].merchantKey == "star bucks")
        #expect(all[0].categoryID == food.id)
        #expect(all[0].updatedAt == makeDate(2026, 10, 13))
    }

    @Test func learningTheSameMerchantAgainOverwritesInsteadOfAddingASecondRow() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, transport) = try makeFood(context)

        try MerchantMemory.learn(merchant: "滴滴", categoryID: food.id, in: context, now: makeDate(2026, 10, 12))
        try MerchantMemory.learn(merchant: " 滴滴 ", categoryID: transport.id, in: context, now: makeDate(2026, 10, 13))

        let all = try memories(context)
        #expect(all.count == 1)
        #expect(all[0].categoryID == transport.id)
        #expect(all[0].updatedAt == makeDate(2026, 10, 13))
    }

    @Test func differentMerchantsGetSeparateMemories() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, transport) = try makeFood(context)

        try MerchantMemory.learn(merchant: "美团", categoryID: food.id, in: context)
        try MerchantMemory.learn(merchant: "滴滴", categoryID: transport.id, in: context)

        #expect(try memories(context).count == 2)
    }

    // MARK: 编辑后学习

    private func autoEntry(_ context: ModelContext, merchant: String?, category: LedgerCategory?) -> LedgerEntry {
        let entry = LedgerEntry(
            amountInCents: 2500, kind: .expense, date: makeDate(2026, 10, 13),
            category: category, autoSource: .applePay, merchant: merchant
        )
        context.insert(entry)
        return entry
    }

    @Test func editingAnAutoEntryToANewCategoryLearns() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let entry = autoEntry(context, merchant: "美团", category: nil)

        entry.category = food
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)

        #expect(learned)
        let all = try memories(context)
        #expect(all.count == 1)
        #expect(all[0].merchantKey == "美团")
        #expect(all[0].categoryID == food.id)
    }

    @Test func changingAnAutoEntryBetweenTwoCategoriesLearnsTheNewOne() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, transport) = try makeFood(context)
        let entry = autoEntry(context, merchant: "美团", category: food)

        entry.category = transport
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: food.id, in: context)

        #expect(learned)
        #expect(try memories(context).first?.categoryID == transport.id)
    }

    @Test func manualEntriesNeverLearn() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let entry = LedgerEntry(
            amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 13),
            category: food, merchant: "美团"
        )
        context.insert(entry)

        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)

        #expect(!learned)
        #expect(try memories(context).isEmpty)
    }

    @Test func editsThatKeepTheSameCategoryDoNotLearn() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let entry = autoEntry(context, merchant: "美团", category: food)

        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: food.id, in: context)

        #expect(!learned)
        #expect(try memories(context).isEmpty)
    }

    @Test func autoEntriesWithoutAMerchantDoNotLearn() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)

        for merchant in [nil, "", "   "] as [String?] {
            let entry = autoEntry(context, merchant: merchant, category: food)
            let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)
            #expect(!learned)
        }
        #expect(try memories(context).isEmpty)
    }

    @Test func clearingTheCategoryDoesNotLearn() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let entry = autoEntry(context, merchant: "美团", category: food)

        entry.category = nil
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: food.id, in: context)

        #expect(!learned)
        #expect(try memories(context).isEmpty)
    }

    // MARK: 只学支出

    private func incomeCategory(_ context: ModelContext) -> LedgerCategory {
        CategoryRules.addTopLevel(
            name: "工资", symbolName: "banknote.fill", colorHex: "#30D158",
            kind: .income, sortOrder: 0, in: context
        )
    }

    @Test func switchingAnAutoEntryToIncomeDoesNotLearn() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _, _) = try makeFood(context)
        let salary = incomeCategory(context)
        let entry = autoEntry(context, merchant: "美团", category: food)

        entry.kind = .income
        entry.category = salary
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: food.id, in: context)

        #expect(!learned)
        #expect(try memories(context).isEmpty)
    }

    @Test func anExpenseEntryOnAnIncomeCategoryDoesNotLearn() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let salary = incomeCategory(context)
        let entry = autoEntry(context, merchant: "美团", category: nil)

        entry.category = salary
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)

        #expect(!learned)
        #expect(try memories(context).isEmpty)
    }

    @Test func lookupIgnoresAMemoryThatPointsAtAnIncomeCategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let salary = incomeCategory(context)
        let memory = [MerchantCategory(merchantKey: "美团", categoryID: salary.id)]

        #expect(MerchantMemory.categoryID(for: "美团", memory: memory, categories: [salary]) == nil)
    }
}
