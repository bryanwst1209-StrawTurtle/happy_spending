import Testing
import SwiftData
@testable import HappySpendingCore

@MainActor
struct CategoryManagementTests {
    private func all(_ context: ModelContext) throws -> [LedgerCategory] {
        try context.fetch(FetchDescriptor<LedgerCategory>())
    }

    private func makeFood(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        return (food, lunch)
    }

    // MARK: 名称校验

    @Test func nameIsTrimmed() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        #expect(try CategoryRules.validatedName("  晚餐 \n", among: food.children) == "晚餐")
    }

    @Test func blankNamesAreRejected() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        #expect(throws: CategoryNameError.empty) { try CategoryRules.validatedName("", among: food.children) }
        #expect(throws: CategoryNameError.empty) { try CategoryRules.validatedName("   \n\t ", among: food.children) }
    }

    @Test func tenCharactersFitButElevenDoNot() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        #expect(try CategoryRules.validatedName("一二三四五六七八九十", among: food.children).count == 10)
        #expect(throws: CategoryNameError.tooLong) {
            try CategoryRules.validatedName("一二三四五六七八九十零", among: food.children)
        }
    }

    @Test func emojiCountAsOneCharacterEach() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        let ten = String(repeating: "🐶", count: 10)
        let eleven = String(repeating: "🐶", count: 11)
        #expect(try CategoryRules.validatedName(ten, among: food.children) == ten)
        #expect(throws: CategoryNameError.tooLong) { try CategoryRules.validatedName(eleven, among: food.children) }
    }

    @Test func duplicatesIgnoreCaseAndSurroundingSpaces() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        try CategoryRules.addSubcategory(name: "steam", under: food, in: context)
        #expect(throws: CategoryNameError.duplicate) { try CategoryRules.validatedName(" 午餐 ", among: food.children) }
        #expect(throws: CategoryNameError.duplicate) { try CategoryRules.validatedName("STEAM", among: food.children) }
    }

    @Test func archivedSiblingsStillCountAsDuplicates() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        CategoryRules.archive(lunch)
        #expect(throws: CategoryNameError.duplicate) { try CategoryRules.validatedName("午餐", among: food.children) }
    }

    @Test func keepingYourOwnNameIsNotADuplicate() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        #expect(try CategoryRules.validatedName("午餐", among: food.children, excluding: lunch) == "午餐")
    }

    @Test func sameSubcategoryNameIsFineUnderDifferentParents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        let car = CategoryRules.addTopLevel(
            name: "汽车", symbolName: "car.fill", colorHex: "#6C7A89",
            kind: .expense, sortOrder: 1, in: context
        )
        try CategoryRules.addSubcategory(name: "加油", under: car, in: context)
        let created = try CategoryRules.createSubcategory(name: "加油", under: food, in: context)
        #expect(created.parent === food)
    }

    @Test func topLevelDuplicatesAreScopedToTheKind() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        CategoryRules.addTopLevel(name: "其他", symbolName: "ellipsis.circle.fill", colorHex: "#8E8E93", kind: .expense, sortOrder: 0, in: context)
        let income = try CategoryRules.createTopLevel(name: "其他", kind: .income, among: try all(context), in: context)
        #expect(income.kind == .income)
        #expect(throws: CategoryNameError.duplicate) {
            try CategoryRules.createTopLevel(name: "其他", kind: .expense, among: try all(context), in: context)
        }
    }

    @Test func nameErrorsHaveReadableMessages() {
        #expect(CategoryNameError.empty.message == "名称不能为空")
        #expect(CategoryNameError.tooLong.message == "名称最多 10 个字")
        #expect(CategoryNameError.duplicate.message == "已有同名分类(可能在已归档里)")
    }

    // MARK: 新增

    @Test func createTopLevelAppendsWithTheNextPaletteColor() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        try DefaultCategories.seedIfNeeded(in: context)
        let existing = try all(context)

        let created = try CategoryRules.createTopLevel(name: "学习", kind: .expense, among: existing, in: context)

        #expect(created.parent == nil)
        #expect(created.kind == .expense)
        #expect(created.sortOrder == 13)
        #expect(created.colorHex == CategoryPalette.color(at: 13))
        #expect(!created.isArchived)
        #expect(created.iconData == nil)
        #expect(try all(context).contains { $0 === created })
    }

    @Test func createSubcategoryInheritsColorAndKindAndAppends() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)

        let created = try CategoryRules.createSubcategory(name: "夜宵", under: food, in: context)

        #expect(created.parent === food)
        #expect(created.kind == .expense)
        #expect(created.colorHex == "#FF9F0A")
        #expect(created.sortOrder == 1)
    }

    @Test func subcategoriesCannotBeNested() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, lunch) = try makeFood(context)
        #expect(throws: CategoryError.parentMustBeTopLevel) {
            try CategoryRules.createSubcategory(name: "工作餐", under: lunch, in: context)
        }
    }

    @Test func rejectedNamesCreateNothing() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        let before = try all(context).count
        #expect(throws: CategoryNameError.duplicate) {
            try CategoryRules.createSubcategory(name: "午餐", under: food, in: context)
        }
        #expect(throws: CategoryNameError.empty) {
            try CategoryRules.createTopLevel(name: " ", kind: .expense, among: try all(context), in: context)
        }
        #expect(try all(context).count == before)
    }

    // MARK: 调色板

    @Test func paletteHasEightDistinctColorsAndWrapsAround() {
        #expect(CategoryPalette.colors.count == 8)
        #expect(Set(CategoryPalette.colors).count == 8)
        #expect(CategoryPalette.color(at: 8) == CategoryPalette.color(at: 0))
        #expect(CategoryPalette.color(at: 21) == CategoryPalette.color(at: 5))
        #expect(CategoryPalette.color(at: -1) == CategoryPalette.colors.last)
    }

    @Test func manyNewCategoriesKeepGettingColors() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        for index in 0..<20 {
            let created = try CategoryRules.createTopLevel(
                name: "分类\(index)", kind: .expense, among: try all(context), in: context
            )
            #expect(created.colorHex == CategoryPalette.color(at: index))
        }
    }

    // MARK: 重命名

    @Test func renameChangesTheNameAndTrims() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, lunch) = try makeFood(context)
        try CategoryRules.rename(lunch, to: "  工作餐 ", among: try all(context))
        #expect(lunch.name == "工作餐")
    }

    @Test func renameToADuplicateKeepsTheOldName() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        try CategoryRules.addSubcategory(name: "晚餐", under: food, in: context)
        #expect(throws: CategoryNameError.duplicate) {
            try CategoryRules.rename(lunch, to: "晚餐", among: try all(context))
        }
        #expect(lunch.name == "午餐")
    }

    @Test func renamingToTheSameNameIsAllowed() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, lunch) = try makeFood(context)
        try CategoryRules.rename(lunch, to: "午餐", among: try all(context))
        #expect(lunch.name == "午餐")
    }

    // MARK: 恢复

    @Test func restoringATopLevelBringsItsChildrenBack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        CategoryRules.archive(food)

        try CategoryRules.restore(food)

        #expect(!food.isArchived)
        #expect(!lunch.isArchived)
    }

    @Test func aChildCannotBeRestoredWhileItsParentIsArchived() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        CategoryRules.archive(food)

        #expect(throws: CategoryError.parentArchived) { try CategoryRules.restore(lunch) }
        #expect(lunch.isArchived)
        #expect(food.isArchived)
    }

    @Test func aChildArchivedOnItsOwnCanBeRestored() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        CategoryRules.archive(lunch)
        #expect(!food.isArchived)

        try CategoryRules.restore(lunch)

        #expect(!lunch.isArchived)
    }
}
