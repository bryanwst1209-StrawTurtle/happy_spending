# 分类管理与自定义图标 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把预置分类换成作者常用的一套,新增"设置 → 分类管理"界面(新增、重命名、归档/恢复),并支持给每个分类上传自定义图标(裁成 128×128 PNG,原图 ≤ 10 MB)。

**Architecture:** 逻辑全部进 `HappySpendingCore`:预置分类、名称校验与新增/重命名/恢复规则、图标处理(ImageIO 纯函数)、`iconData` 字段与 `EntryRow` 上的图标信息,都用 `swift test` 在 Mac 上测。界面只做薄薄一层:一个共用的 `CategoryIconView`、第 4 个"设置"Tab、分类管理列表和编辑页(`PhotosPicker` 选图)。

**Tech Stack:** Swift 6.3 / Xcode 26.6, SwiftUI, SwiftData, ImageIO + UniformTypeIdentifiers, PhotosUI, Swift Testing。

**Spec:** `docs/superpowers/specs/2026-10-10-bookkeeping-app-design.md`(新增内容在 §14,另见 §2、§3、§4、§5 的改动)

## Global Constraints

- 最低系统 **iOS 26**;无后端、无网络请求、**无第三方依赖**;选图用 `PhotosPicker`(不申请相册权限),图片处理用 ImageIO。
- 预置分类只在库里还没有任何分类时写入;**收入分类不变**:工资、奖金、其他收入。
- 一级分类顺序即显示顺序:日用、餐饮、交通、宠物、娱乐、游戏、旅游、汽车、其他、服饰、购物、居住、医疗。
- 二级分类继承一级分类的颜色;分类只有两层;分类只归档不物理删除,归档一级分类时二级分类一并归档。
- 名称:去掉首尾空白后不能为空,**最长 10 个字符**;同一个父分类(一级分类则是同类型下)里不能重名,已归档的也算;不同父分类下允许同名二级分类。
- 图标:**居中裁成正方形,缩放到 128×128 像素,存成 PNG**;**原图超过 10 MB 直接拒绝**(提示"图片太大");无法解码提示"无法读取这张图片";单张图最大约 66 KB。
- 新增的一级分类从固定调色板按顺序分配颜色;v1 不提供自选颜色。
- 恢复一级分类时二级分类一并恢复;被归档的一级分类下的二级分类不能单独恢复。
- 图标显示为圆形;出现在记账页一级分类网格、账单页每一行、分类管理界面;统计页暂不显示。
- 命名沿用:`LedgerEntry`、`LedgerCategory`。
- 测试用 Swift Testing;SwiftData 测试用内存容器。
- Core 的命令都用 `swift test --package-path Packages/HappySpendingCore`;仓库根目录是 `/Users/strawturtle/Desktop/Develop/Self/Self IOS App/happy_spending`;工作在分支 `category-icons` 上。
- 提交信息末尾带上本次会话给出的 `Co-Authored-By` 署名行。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都在对应任务里有测试:

1. **手机竖拍的照片(EXIF 方向)**:从相册选的照片带旋转标记,做成图标后必须是正的,不能躺着。→ Task 3
2. **非正方形、很小、带透明的图**:横图、竖图、40×40 的小图、极扁的长条图都输出 128×128,不拉伸变形;透明 PNG 的透明通道保留。→ Task 3
3. **名称的怪输入**:全是空格、刚好 10 个字符、11 个字符(中文和 emoji 都按字符数)、只差首尾空格或大小写的重名、不同父分类下的同名二级分类、一级的"其他"和收入的"其他"。→ Task 2
4. **已归档分类**:历史账单仍显示原名和图标;恢复一级分类连带恢复二级分类;父分类已归档时二级分类不能单独恢复。→ Task 2、Task 4
5. **调色板用完之后**:新增超过 8 个一级分类时颜色循环使用,不崩溃、不越界。→ Task 2

---

### Task 1: 预置分类换成新的一套

**Files:**
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/DefaultCategories.swift`
- Modify: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryRulesTests.swift`(删掉被取代的一个测试)
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/DefaultCategoriesTests.swift`

**Interfaces:**
- Consumes: `CategoryRules.addTopLevel` / `addSubcategory`、`makeTestContainer()`(已有)
- Produces: `DefaultCategories.seedIfNeeded(in:)`(签名不变,内容换成新的预置)

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/DefaultCategoriesTests.swift`:

```swift
import Testing
import SwiftData
@testable import HappySpendingCore

@MainActor
struct DefaultCategoriesTests {
    /// 必须一直持有容器:容器一释放,里面的分类对象就会失效。
    private struct Seeded {
        let container: ModelContainer
        let all: [LedgerCategory]
    }

    private func seeded() throws -> Seeded {
        let container = try makeTestContainer()
        try DefaultCategories.seedIfNeeded(in: container.mainContext)
        let all = try container.mainContext.fetch(FetchDescriptor<LedgerCategory>())
        return Seeded(container: container, all: all)
    }

    private func tops(_ categories: [LedgerCategory], _ kind: EntryKind) -> [LedgerCategory] {
        categories.filter { $0.parent == nil && $0.kind == kind }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func childNames(of top: LedgerCategory) -> [String] {
        top.children.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
    }

    @Test func expenseTopLevelsAreTheAuthorsOnesFirstThenTheGenericOnes() throws {
        let store = try seeded()
        #expect(tops(store.all, .expense).map(\.name) == [
            "日用", "餐饮", "交通", "宠物", "娱乐", "游戏", "旅游", "汽车", "其他", "服饰",
            "购物", "居住", "医疗",
        ])
    }

    @Test func incomeCategoriesAreUnchanged() throws {
        let store = try seeded()
        #expect(tops(store.all, .income).map(\.name) == ["工资", "奖金", "其他收入"])
        #expect(store.all.filter { $0.kind == .income && $0.parent != nil }.isEmpty)
    }

    @Test func subcategoriesMatchTheSpec() throws {
        let store = try seeded()
        let byName = Dictionary(uniqueKeysWithValues: tops(store.all, .expense).map { ($0.name, $0) })

        #expect(childNames(of: byName["游戏"]!) == ["原神", "ZZZ", "steam", "暴雪"])
        #expect(childNames(of: byName["娱乐"]!) == ["电影"])
        #expect(childNames(of: byName["汽车"]!) == ["停车费", "加油"])
        #expect(childNames(of: byName["餐饮"]!) == ["早餐", "午餐", "晚餐", "零食"])
        #expect(childNames(of: byName["交通"]!) == ["公交地铁", "打车"])
        #expect(childNames(of: byName["购物"]!) == ["数码"])
        #expect(childNames(of: byName["居住"]!) == ["房租", "水电燃气", "网费"])
        #expect(childNames(of: byName["医疗"]!) == ["药品", "诊疗"])
        for name in ["日用", "宠物", "旅游", "其他", "服饰"] {
            #expect(childNames(of: byName[name]!).isEmpty)
        }
    }

    @Test func noSiblingsShareAName() throws {
        let store = try seeded()
        var seen = Set<String>()
        for category in store.all {
            let key = "\(category.kind.rawValue)|\(category.parent?.name ?? "-")|\(category.name)"
            #expect(seen.insert(key).inserted, "重复的分类:\(key)")
        }
    }

    @Test func seededCategoriesRespectTheTwoLevelRule() throws {
        let store = try seeded()
        let subs = store.all.filter { $0.parent != nil }
        #expect(!subs.isEmpty)
        #expect(subs.allSatisfy { $0.parent?.parent == nil })
        #expect(subs.allSatisfy { $0.kind == $0.parent?.kind })
        #expect(store.all.allSatisfy { !$0.name.isEmpty && !$0.isArchived })
    }

    @Test func subcategoriesInheritTheirParentsColor() throws {
        let store = try seeded()
        #expect(store.all.filter { $0.parent != nil }.allSatisfy { $0.colorHex == $0.parent?.colorHex })
    }

    @Test func sortOrdersAreUniqueAmongSiblings() throws {
        let store = try seeded()
        for kind in EntryKind.allCases {
            let orders = tops(store.all, kind).map(\.sortOrder)
            #expect(Set(orders).count == orders.count)
        }
    }
}
```

Modify `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryRulesTests.swift`:删掉旧测试 `seededCategoriesRespectTheTwoLevelRule`(它写死了旧的 7 个支出分类,已被上面的同名测试取代)。Run(仓库根目录):

```bash
python3 -I - <<'EOF'
import re
p = "Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryRulesTests.swift"
s = open(p, encoding="utf-8").read()
start = s.index("    @Test func seededCategoriesRespectTheTwoLevelRule()")
end = s.index("    @Test func entryDateIsNormalizedToStartOfDay()")
open(p, "w", encoding="utf-8").write(s[:start] + s[end:])
EOF
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter DefaultCategoriesTests`
Expected: `expenseTopLevelsAreTheAuthorsOnesFirstThenTheGenericOnes`、`subcategoriesMatchTheSpec` 失败(旧预置只有 7 个支出一级分类);其余可能通过。

- [ ] **Step 3: 写实现**

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/DefaultCategories.swift`:

```swift
import Foundation
import SwiftData

public enum DefaultCategories {
    private struct Spec {
        let name: String
        let symbol: String
        let color: String
        let children: [String]
    }

    /// 顺序即显示顺序:先是作者常用的,后是通用的。
    private static let expense: [Spec] = [
        Spec(name: "日用", symbol: "basket.fill", color: "#34C759", children: []),
        Spec(name: "餐饮", symbol: "fork.knife", color: "#FF9F0A", children: ["早餐", "午餐", "晚餐", "零食"]),
        Spec(name: "交通", symbol: "bus.fill", color: "#0A84FF", children: ["公交地铁", "打车"]),
        Spec(name: "宠物", symbol: "pawprint.fill", color: "#A2845E", children: []),
        Spec(name: "娱乐", symbol: "popcorn.fill", color: "#BF5AF2", children: ["电影"]),
        Spec(name: "游戏", symbol: "gamecontroller.fill", color: "#5E5CE6", children: ["原神", "ZZZ", "steam", "暴雪"]),
        Spec(name: "旅游", symbol: "airplane", color: "#30B0C7", children: []),
        Spec(name: "汽车", symbol: "car.fill", color: "#6C7A89", children: ["停车费", "加油"]),
        Spec(name: "其他", symbol: "ellipsis.circle.fill", color: "#8E8E93", children: []),
        Spec(name: "服饰", symbol: "tshirt.fill", color: "#FF375F", children: []),
        Spec(name: "购物", symbol: "cart.fill", color: "#D6336C", children: ["数码"]),
        Spec(name: "居住", symbol: "house.fill", color: "#00A6A6", children: ["房租", "水电燃气", "网费"]),
        Spec(name: "医疗", symbol: "cross.case.fill", color: "#FF453A", children: ["药品", "诊疗"]),
    ]

    private static let income: [Spec] = [
        Spec(name: "工资", symbol: "banknote.fill", color: "#30D158", children: []),
        Spec(name: "奖金", symbol: "gift.fill", color: "#FFD60A", children: []),
        Spec(name: "其他收入", symbol: "plus.circle.fill", color: "#64D2FF", children: []),
    ]

    /// 只在库里还没有任何分类时写入预置分类。返回是否写入了数据。
    @discardableResult
    public static func seedIfNeeded(in context: ModelContext) throws -> Bool {
        guard try context.fetchCount(FetchDescriptor<LedgerCategory>()) == 0 else { return false }

        let groups: [(EntryKind, [Spec])] = [(.expense, expense), (.income, income)]
        for (kind, specs) in groups {
            for (index, spec) in specs.enumerated() {
                let top = CategoryRules.addTopLevel(
                    name: spec.name, symbolName: spec.symbol, colorHex: spec.color,
                    kind: kind, sortOrder: index, in: context
                )
                for child in spec.children {
                    try CategoryRules.addSubcategory(name: child, under: top, in: context)
                }
            }
        }
        try context.save()
        return true
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(原有 80 个减去被删的 1 个,再加 DefaultCategories 的 7 个,共 86 个)。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: replace default categories with the author's set"
```

---

### Task 2: 名称规则、新增、重命名、恢复与调色板

**Files:**
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryRules.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryPalette.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryManagementTests.swift`

**Interfaces:**
- Consumes: `LedgerCategory`、`EntryKind`、`makeTestContainer()`、`CategoryRules.addTopLevel/addSubcategory/archive/resolveSelection`(已有,原样保留)
- Produces:
  - `enum CategoryError: Error, Equatable { case parentMustBeTopLevel, parentArchived }`
  - `enum CategoryNameError: Error, Equatable { case empty, tooLong, duplicate; var message: String }`
  - `enum CategoryPalette { static let colors: [String]; static func color(at index: Int) -> String }`
  - `CategoryRules.maxNameLength: Int`(10)
  - `CategoryRules.validatedName(_ raw: String, among siblings: [LedgerCategory], excluding: LedgerCategory? = nil) throws -> String`
  - `CategoryRules.createTopLevel(name:kind:among:in:) throws -> LedgerCategory`
  - `CategoryRules.createSubcategory(name:under:in:) throws -> LedgerCategory`
  - `CategoryRules.rename(_ category: LedgerCategory, to: String, among: [LedgerCategory]) throws`
  - `CategoryRules.restore(_ category: LedgerCategory) throws`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryManagementTests.swift`:

```swift
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
        #expect(created.iconDataIsNil)
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

private extension LedgerCategory {
    var iconDataIsNil: Bool { true }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter CategoryManagementTests`
Expected: 编译失败,报 `type 'CategoryRules' has no member 'validatedName'` 之类。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryPalette.swift`:

```swift
import Foundation

public enum CategoryPalette {
    /// 新增一级分类时按顺序轮换使用的颜色。
    public static let colors = [
        "#FF9F0A", "#0A84FF", "#30B0C7", "#BF5AF2",
        "#FF375F", "#34C759", "#5E5CE6", "#A2845E",
    ]

    /// 超出范围时循环使用(负数也安全)。
    public static func color(at index: Int) -> String {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
```

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryRules.swift`:

```swift
import Foundation
import SwiftData

public enum CategoryError: Error, Equatable {
    case parentMustBeTopLevel
    case parentArchived
}

public enum CategoryNameError: Error, Equatable {
    case empty
    case tooLong
    case duplicate

    public var message: String {
        switch self {
        case .empty: "名称不能为空"
        case .tooLong: "名称最多 \(CategoryRules.maxNameLength) 个字"
        case .duplicate: "已有同名分类(可能在已归档里)"
        }
    }
}

public enum CategoryRules {
    public static let maxNameLength = 10

    // MARK: 预置分类和测试使用的直接创建(不校验名称)

    @discardableResult
    public static func addTopLevel(
        name: String,
        symbolName: String,
        colorHex: String,
        kind: EntryKind,
        sortOrder: Int,
        in context: ModelContext
    ) -> LedgerCategory {
        let category = LedgerCategory(
            name: name, symbolName: symbolName, colorHex: colorHex,
            kind: kind, sortOrder: sortOrder
        )
        context.insert(category)
        return category
    }

    /// 二级分类继承一级分类的类型和颜色。
    @discardableResult
    public static func addSubcategory(
        name: String,
        symbolName: String = "tag.fill",
        under parent: LedgerCategory,
        in context: ModelContext
    ) throws -> LedgerCategory {
        guard parent.parent == nil else { throw CategoryError.parentMustBeTopLevel }
        let category = LedgerCategory(
            name: name, symbolName: symbolName, colorHex: parent.colorHex,
            kind: parent.kind, sortOrder: parent.children.count, parent: parent
        )
        context.insert(category)
        return category
    }

    // MARK: 名称校验

    /// 去掉首尾空白后校验名称并返回。`siblings` 是同一个父分类下的所有分类
    /// (一级分类则是同类型的所有一级分类),包括已归档的;`excluding` 是正在被改名的分类自己。
    public static func validatedName(
        _ raw: String,
        among siblings: [LedgerCategory],
        excluding: LedgerCategory? = nil
    ) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CategoryNameError.empty }
        guard name.count <= maxNameLength else { throw CategoryNameError.tooLong }
        let isDuplicate = siblings.contains { sibling in
            sibling !== excluding
                && sibling.name.compare(name, options: [.caseInsensitive]) == .orderedSame
        }
        guard !isDuplicate else { throw CategoryNameError.duplicate }
        return name
    }

    private static func siblings(
        of parent: LedgerCategory?,
        kind: EntryKind,
        in categories: [LedgerCategory]
    ) -> [LedgerCategory] {
        if let parent { return parent.children }
        return categories.filter { $0.parent == nil && $0.kind == kind }
    }

    // MARK: 管理界面使用

    /// 新增一级分类:图标用默认 SF Symbol,颜色从调色板按顺序取,排在同类型的最后。
    @discardableResult
    public static func createTopLevel(
        name: String,
        kind: EntryKind,
        among categories: [LedgerCategory],
        in context: ModelContext
    ) throws -> LedgerCategory {
        let existing = siblings(of: nil, kind: kind, in: categories)
        let validated = try validatedName(name, among: existing)
        let category = LedgerCategory(
            name: validated, symbolName: "tag.fill",
            colorHex: CategoryPalette.color(at: existing.count),
            kind: kind, sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(category)
        return category
    }

    /// 新增二级分类:继承一级分类的类型和颜色,排在它所有二级分类的最后。
    @discardableResult
    public static func createSubcategory(
        name: String,
        under parent: LedgerCategory,
        in context: ModelContext
    ) throws -> LedgerCategory {
        guard parent.parent == nil else { throw CategoryError.parentMustBeTopLevel }
        let validated = try validatedName(name, among: parent.children)
        let category = LedgerCategory(
            name: validated, symbolName: "tag.fill", colorHex: parent.colorHex,
            kind: parent.kind,
            sortOrder: (parent.children.map(\.sortOrder).max() ?? -1) + 1,
            parent: parent
        )
        context.insert(category)
        return category
    }

    /// 改名;名称不合法时抛错,原名称保持不变。
    public static func rename(
        _ category: LedgerCategory,
        to raw: String,
        among categories: [LedgerCategory]
    ) throws {
        let existing = siblings(of: category.parent, kind: category.kind, in: categories)
        category.name = try validatedName(raw, among: existing, excluding: category)
    }

    // MARK: 归档与恢复

    /// 决定记账表单当前应选中的分类:
    /// 当前选择仍然有效(类型一致且未归档)就保留;否则用上次用过的同类型分类;再不行取排序第一的一级分类。
    public static func resolveSelection(
        current: UUID?,
        kind: EntryKind,
        categories: [LedgerCategory],
        lastUsed: LedgerCategory?
    ) -> UUID? {
        let active = categories.filter { !$0.isArchived && $0.kind == kind }
        if let current, active.contains(where: { $0.id == current }) { return current }
        if let lastUsed, !lastUsed.isArchived, lastUsed.kind == kind { return lastUsed.id }
        return active
            .filter { $0.parent == nil }
            .min { $0.sortOrder < $1.sortOrder }?
            .id
    }

    /// 归档;归档一级分类时,二级分类一并归档。
    public static func archive(_ category: LedgerCategory) {
        category.isArchived = true
        for child in category.children {
            child.isArchived = true
        }
    }

    /// 恢复;恢复一级分类时二级分类一并恢复;父分类已归档的二级分类不能单独恢复。
    public static func restore(_ category: LedgerCategory) throws {
        if let parent = category.parent {
            guard !parent.isArchived else { throw CategoryError.parentArchived }
            category.isArchived = false
        } else {
            category.isArchived = false
            for child in category.children {
                child.isArchived = false
            }
        }
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(含 CategoryManagement 的 22 个测试)。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add category name rules, creation, rename, restore and color palette"
```

---

### Task 3: 图标处理(裁剪、缩放、限制)

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryIcon.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryIconTests.swift`

**Interfaces:**
- Produces:
  - `enum CategoryIconError: Error, Equatable { case tooLarge, unreadable; var message: String }`
  - `enum CategoryIcon { static let size: Int` (128)`; static let maxSourceBytes: Int` (10 MB)`; static func process(_ source: Data) throws -> Data }` — 返回 128×128 的 PNG 数据。

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryIconTests.swift`:

```swift
import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import HappySpendingCore

struct CategoryIconTests {
    // MARK: 测试用的图片工具

    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context)
        return context.makeImage()!
    }

    private func fill(_ context: CGContext, _ color: (CGFloat, CGFloat, CGFloat), _ rect: CGRect) {
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(rect)
    }

    private func encode(_ image: CGImage, as type: UTType, orientation: Int? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// 解码成 RGBA 像素;第 0 行是图片最上面一行。
    private func decode(_ data: Data) -> (width: Int, height: Int, pixel: (Int, Int) -> RGBA) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, { x, y in
            let i = (y * width + x) * 4
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        })
    }

    private let magenta: (CGFloat, CGFloat, CGFloat) = (1, 0, 1)
    private let green: (CGFloat, CGFloat, CGFloat) = (0, 1, 0)
    private let red: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)
    private let blue: (CGFloat, CGFloat, CGFloat) = (0, 0, 1)

    private func isGreen(_ p: RGBA) -> Bool { p.g > 200 && p.r < 60 && p.b < 60 }
    private func isMagenta(_ p: RGBA) -> Bool { p.r > 200 && p.b > 200 && p.g < 60 }
    private func isRed(_ p: RGBA) -> Bool { p.r > 200 && p.g < 80 && p.b < 80 }
    private func isBlue(_ p: RGBA) -> Bool { p.b > 200 && p.r < 80 && p.g < 80 }

    // MARK: 输出格式和尺寸

    @Test func limitsAreTheDocumentedOnes() {
        #expect(CategoryIcon.size == 128)
        #expect(CategoryIcon.maxSourceBytes == 10 * 1024 * 1024)
    }

    @Test func outputIsAlwaysAPNGOfExactly128Pixels() throws {
        for (width, height) in [(400, 200), (200, 400), (128, 128), (40, 40), (1000, 30), (30, 1000)] {
            let image = makeImage(width: width, height: height) { fill($0, red, CGRect(x: 0, y: 0, width: width, height: height)) }
            let output = try CategoryIcon.process(encode(image, as: .png))

            #expect(Array(output.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let decoded = decode(output)
            #expect(decoded.width == 128 && decoded.height == 128, "\(width)x\(height)")
        }
    }

    @Test func jpegSourcesWorkToo() throws {
        let image = makeImage(width: 300, height: 200) { fill($0, blue, CGRect(x: 0, y: 0, width: 300, height: 200)) }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .jpeg)))
        #expect(decoded.width == 128 && decoded.height == 128)
        #expect(isBlue(decoded.pixel(64, 64)))
    }

    // MARK: 居中裁剪而不是拉伸

    @Test func landscapeImagesAreCenterCroppedNotStretched() throws {
        // 400x200:左右各 100 像素是洋红,中间 200 像素是绿色。居中裁出的 200x200 正好全是绿色。
        let image = makeImage(width: 400, height: 200) { context in
            fill(context, magenta, CGRect(x: 0, y: 0, width: 400, height: 200))
            fill(context, green, CGRect(x: 100, y: 0, width: 200, height: 200))
        }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .png)))

        #expect(isGreen(decoded.pixel(4, 64)))
        #expect(isGreen(decoded.pixel(64, 64)))
        #expect(isGreen(decoded.pixel(123, 64)))
    }

    @Test func portraitImagesAreCenterCroppedNotStretched() throws {
        let image = makeImage(width: 200, height: 400) { context in
            fill(context, magenta, CGRect(x: 0, y: 0, width: 200, height: 400))
            fill(context, green, CGRect(x: 0, y: 100, width: 200, height: 200))
        }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .png)))

        #expect(isGreen(decoded.pixel(64, 4)))
        #expect(isGreen(decoded.pixel(64, 64)))
        #expect(isGreen(decoded.pixel(64, 123)))
    }

    @Test func tinyImagesAreScaledUpWithoutDistortion() throws {
        let image = makeImage(width: 40, height: 40) { fill($0, green, CGRect(x: 0, y: 0, width: 40, height: 40)) }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .png)))
        #expect(isGreen(decoded.pixel(2, 2)))
        #expect(isGreen(decoded.pixel(125, 125)))
    }

    // MARK: 透明与方向

    @Test func transparencyIsPreserved() throws {
        let transparent = makeImage(width: 64, height: 64) { _ in }
        let decodedClear = decode(try CategoryIcon.process(encode(transparent, as: .png)))
        #expect(decodedClear.pixel(64, 64).a == 0)

        let opaque = makeImage(width: 64, height: 64) { fill($0, red, CGRect(x: 0, y: 0, width: 64, height: 64)) }
        let decodedOpaque = decode(try CategoryIcon.process(encode(opaque, as: .png)))
        #expect(decodedOpaque.pixel(64, 64).a == 255)
    }

    @Test func exifOrientationIsApplied() throws {
        // 400x200,左半红、右半蓝,标记方向为 6(需要顺时针转 90° 才是正的):转正之后红色在上、蓝色在下。
        let image = makeImage(width: 400, height: 200) { context in
            fill(context, red, CGRect(x: 0, y: 0, width: 200, height: 200))
            fill(context, blue, CGRect(x: 200, y: 0, width: 200, height: 200))
        }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .jpeg, orientation: 6)))

        #expect(isRed(decoded.pixel(64, 12)))
        #expect(isBlue(decoded.pixel(64, 116)))
    }

    // MARK: 大小限制与坏数据

    @Test func noisyPhotosStayUnderTheStorageCap() throws {
        var generator = SystemRandomNumberGenerator()
        let image = makeImage(width: 1024, height: 768) { context in
            for _ in 0..<4000 {
                let color = (CGFloat.random(in: 0...1, using: &generator),
                             CGFloat.random(in: 0...1, using: &generator),
                             CGFloat.random(in: 0...1, using: &generator))
                fill(context, color, CGRect(
                    x: Int.random(in: 0..<1024, using: &generator),
                    y: Int.random(in: 0..<768, using: &generator),
                    width: 24, height: 24
                ))
            }
        }
        let output = try CategoryIcon.process(encode(image, as: .png))
        #expect(output.count <= 100 * 1024)
    }

    @Test func sourcesOverTenMegabytesAreRejected() {
        let tooBig = Data(count: CategoryIcon.maxSourceBytes + 1)
        #expect(throws: CategoryIconError.tooLarge) { try CategoryIcon.process(tooBig) }
    }

    @Test func exactlyTenMegabytesIsNotRejectedForItsSize() {
        let limit = Data(count: CategoryIcon.maxSourceBytes)
        #expect(throws: CategoryIconError.unreadable) { try CategoryIcon.process(limit) }
    }

    @Test func garbageIsUnreadable() {
        #expect(throws: CategoryIconError.unreadable) { try CategoryIcon.process(Data("not an image".utf8)) }
        #expect(throws: CategoryIconError.unreadable) { try CategoryIcon.process(Data()) }
    }

    @Test func errorsHaveReadableMessages() {
        #expect(CategoryIconError.tooLarge.message == "图片太大,请选择 10 MB 以内的图片")
        #expect(CategoryIconError.unreadable.message == "无法读取这张图片")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter CategoryIconTests`
Expected: 编译失败,报 `cannot find 'CategoryIcon' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryIcon.swift`:

```swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum CategoryIconError: Error, Equatable {
    case tooLarge
    case unreadable

    public var message: String {
        switch self {
        case .tooLarge: "图片太大,请选择 10 MB 以内的图片"
        case .unreadable: "无法读取这张图片"
        }
    }
}

/// 把用户选的任意图片处理成分类图标:居中裁成正方形,缩放到 128×128,存成 PNG。
public enum CategoryIcon {
    /// 图标边长(像素)。
    public static let size = 128
    /// 原图大小上限:10 MB。
    public static let maxSourceBytes = 10 * 1024 * 1024

    public static func process(_ source: Data) throws -> Data {
        guard source.count <= maxSourceBytes else { throw CategoryIconError.tooLarge }

        guard
            let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
            CGImageSourceGetCount(imageSource) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw CategoryIconError.unreadable }

        // 先缩到"短边约等于 128"的大小,同时应用 EXIF 方向;再按短边铺满画布,居中裁成正方形。
        let ratio = Double(max(width, height)) / Double(min(width, height))
        let maxPixel = min(Int((Double(size) * ratio).rounded(.up)), 4096)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(
            imageSource, 0, thumbnailOptions as CFDictionary
        ) else { throw CategoryIconError.unreadable }

        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CategoryIconError.unreadable }
        context.interpolationQuality = .high

        let scaledWidth = Double(scaled.width)
        let scaledHeight = Double(scaled.height)
        let scale = max(Double(size) / scaledWidth, Double(size) / scaledHeight)
        let drawWidth = scaledWidth * scale
        let drawHeight = scaledHeight * scale
        context.draw(scaled, in: CGRect(
            x: (Double(size) - drawWidth) / 2,
            y: (Double(size) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        ))

        guard let square = context.makeImage() else { throw CategoryIconError.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw CategoryIconError.unreadable }
        CGImageDestinationAddImage(destination, square, nil)
        guard CGImageDestinationFinalize(destination) else { throw CategoryIconError.unreadable }
        return output as Data
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore --filter CategoryIconTests`
Expected: 全部 PASS(13 个)。如果 `exifOrientationIsApplied` 失败,先确认测试里的方向假设(方向 6 = 顺时针转 90° 后才是正的,原图左边变成上边),再检查实现里是否用了 `kCGImageSourceCreateThumbnailWithTransform`。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add category icon processing (square crop, 128px PNG, size limit)"
```

---

### Task 4: `iconData` 字段与 `EntryRow` 上的图标信息

**Files:**
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerCategory.swift`
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/EntryRow.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/RowIconTests.swift`
- Modify: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryManagementTests.swift`(去掉占位的 `iconDataIsNil`,改成真实断言)

**Interfaces:**
- Consumes: `LedgerCategory`、`LedgerEntry`、`CategoryRules`
- Produces:
  - `LedgerCategory.iconData: Data?`;`init(... iconData: Data? = nil)`
  - `Uncategorized.symbolName: String`("questionmark.circle.fill")
  - `EntryRow.topSymbolName: String`、`EntryRow.topIconData: Data?`(init 里有默认值:`Uncategorized.symbolName`、`nil`)
  - `LedgerEntry.row` 带上一级分类的图标信息

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/RowIconTests.swift`:

```swift
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
}
```

Modify `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryManagementTests.swift`:把 Task 2 里占位的 `iconDataIsNil` 换成真实断言。Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryManagementTests.swift"
s = open(p, encoding="utf-8").read()
assert s.count("#expect(created.iconDataIsNil)") == 1
s = s.replace("#expect(created.iconDataIsNil)", "#expect(created.iconData == nil)")
tail = "\nprivate extension LedgerCategory {\n    var iconDataIsNil: Bool { true }\n}\n"
assert tail in s
s = s.replace(tail, "")
open(p, "w", encoding="utf-8").write(s)
EOF
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter "RowIconTests|CategoryManagementTests"`
Expected: 编译失败,报 `value of type 'LedgerCategory' has no member 'iconData'`。

- [ ] **Step 3: 写实现**

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerCategory.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class LedgerCategory {
    public var id: UUID
    public var name: String
    public var symbolName: String
    /// 自定义图标(128×128 PNG,见 `CategoryIcon`);有值时代替 `symbolName` 显示。
    public var iconData: Data?
    public var colorHex: String
    public var kindRaw: String
    public var sortOrder: Int
    public var isArchived: Bool
    public var parent: LedgerCategory?

    @Relationship(deleteRule: .nullify, inverse: \LedgerCategory.parent)
    public var children: [LedgerCategory] = []

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.category)
    public var entries: [LedgerEntry] = []

    public var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// "餐饮 · 午餐";一级分类就是 "餐饮"。
    public var displayName: String {
        if let parent { "\(parent.name) · \(name)" } else { name }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        colorHex: String,
        kind: EntryKind,
        sortOrder: Int = 0,
        parent: LedgerCategory? = nil,
        iconData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.iconData = iconData
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.isArchived = false
        self.parent = parent
    }
}
```

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/EntryRow.swift`:

```swift
import Foundation

public enum Uncategorized {
    public static let name = "未分类"
    public static let colorHex = "#8E8E93"
    public static let symbolName = "questionmark.circle.fill"
}

/// 一笔账的纯值快照,供统计、分组、导出等纯函数使用。
public struct EntryRow: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let createdAt: Date
    public let kind: EntryKind
    public let cents: Int
    public let note: String
    public let topCategoryID: UUID?
    public let topCategoryName: String
    public let topColorHex: String
    /// 一级分类的默认图标;`topIconData` 有值时界面用它代替。
    public let topSymbolName: String
    public let topIconData: Data?
    public let subCategoryID: UUID?
    public let subCategoryName: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        createdAt: Date? = nil,
        kind: EntryKind,
        cents: Int,
        note: String = "",
        topCategoryID: UUID?,
        topCategoryName: String,
        topColorHex: String,
        topSymbolName: String = Uncategorized.symbolName,
        topIconData: Data? = nil,
        subCategoryID: UUID? = nil,
        subCategoryName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.createdAt = createdAt ?? date
        self.kind = kind
        self.cents = cents
        self.note = note
        self.topCategoryID = topCategoryID
        self.topCategoryName = topCategoryName
        self.topColorHex = topColorHex
        self.topSymbolName = topSymbolName
        self.topIconData = topIconData
        self.subCategoryID = subCategoryID
        self.subCategoryName = subCategoryName
    }

    /// "餐饮 · 午餐";没有二级分类时就是 "餐饮"。
    public var displayCategory: String {
        if let subCategoryName { "\(topCategoryName) · \(subCategoryName)" } else { topCategoryName }
    }
}

extension LedgerEntry {
    public var row: EntryRow {
        let top = category?.parent ?? category
        let sub = category?.parent == nil ? nil : category
        return EntryRow(
            id: id,
            date: date,
            createdAt: createdAt,
            kind: kind,
            cents: amountInCents,
            note: note,
            topCategoryID: top?.id,
            topCategoryName: top?.name ?? Uncategorized.name,
            topColorHex: top?.colorHex ?? Uncategorized.colorHex,
            topSymbolName: top?.symbolName ?? Uncategorized.symbolName,
            topIconData: top?.iconData,
            subCategoryID: sub?.id,
            subCategoryName: sub?.name
        )
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(含 RowIcon 的 6 个测试),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add category iconData and carry icons on EntryRow"
```

---

### Task 5: 图标显示(记账页网格、账单行)

**Files:**
- Create: `HappySpending/Support/CategoryIconView.swift`
- Modify: `HappySpending/Record/CategoryPicker.swift`
- Replace: `HappySpending/Bills/EntryRowView.swift`

**Interfaces:**
- Consumes: `LedgerCategory.iconData`、`EntryRow.topSymbolName` / `topIconData` / `topColorHex`(Task 4);`Color(hex:)`(已有)
- Produces: `CategoryIconView(symbolName:colorHex:iconData:size:)`(Task 6 复用)

界面没有自动化测试;验证方式是编译通过 + Task 7 的模拟器检查。

- [ ] **Step 1: 共用的图标视图**

Create `HappySpending/Support/CategoryIconView.swift`:

```swift
import SwiftUI

/// 圆形分类图标:有自定义图片就显示图片,否则是带底色的 SF Symbol。
struct CategoryIconView: View {
    let symbolName: String
    let colorHex: String
    let iconData: Data?
    var size: CGFloat = 46

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(color.opacity(0.18))
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
```

- [ ] **Step 2: 记账页一级分类网格改用它**

Modify `HappySpending/Record/CategoryPicker.swift`。Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "HappySpending/Record/CategoryPicker.swift"
s = open(p, encoding="utf-8").read()
old = """                ZStack {
                    Circle().fill(color.opacity(0.18))
                    Image(systemName: top.symbolName).font(.body).foregroundStyle(color)
                }
                .frame(width: 46, height: 46)
                .overlay(Circle().stroke(color, lineWidth: isSelected ? 2.5 : 0))
"""
new = """                CategoryIconView(
                    symbolName: top.symbolName, colorHex: top.colorHex,
                    iconData: top.iconData, size: 46
                )
                .overlay(Circle().stroke(color, lineWidth: isSelected ? 2.5 : 0))
"""
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
EOF
```

- [ ] **Step 3: 账单行用图标替代色点**

Replace `HappySpending/Bills/EntryRowView.swift`:

```swift
import SwiftUI
import HappySpendingCore

struct EntryRowView: View {
    let row: EntryRow

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(
                symbolName: row.topSymbolName, colorHex: row.topColorHex,
                iconData: row.topIconData, size: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayCategory).font(.body)
                if !row.note.isEmpty {
                    Text(row.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text((row.kind == .income ? "+" : "") + Money.display(row.cents))
                .font(.body.monospacedDigit())
                .foregroundStyle(row.kind == .income ? Color.green : Color.primary)
        }
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 4: 编译**

Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: `** BUILD SUCCEEDED **`,没有 `error:`。

- [ ] **Step 5: 提交**

```bash
git add HappySpending
git commit -m "feat: show category icons on the record grid and bill rows"
```

---

### Task 6: "设置" Tab 与分类管理界面

**Files:**
- Modify: `HappySpending/RootTabView.swift`
- Create: `HappySpending/Settings/SettingsView.swift`
- Create: `HappySpending/Settings/CategoryManagementView.swift`
- Create: `HappySpending/Settings/CategoryEditView.swift`

**Interfaces:**
- Consumes: `CategoryRules.createTopLevel` / `createSubcategory` / `rename` / `archive` / `restore`、`CategoryNameError.message`、`CategoryError`、`CategoryIcon.process`、`CategoryIconError.message`、`LedgerCategory`(Core);`CategoryIconView`(Task 5)
- Produces: 第 4 个 Tab"设置";分类管理列表和编辑页

- [ ] **Step 1: 加第 4 个 Tab**

Modify `HappySpending/RootTabView.swift`。Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "HappySpending/RootTabView.swift"
s = open(p, encoding="utf-8").read()
old = '            Tab("统计", systemImage: "chart.pie.fill") { StatsView() }\n'
new = old + '            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }\n'
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
EOF
```

- [ ] **Step 2: 设置页**

Create `HappySpending/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CategoryManagementView()
                } label: {
                    Label("分类管理", systemImage: "square.grid.2x2")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

- [ ] **Step 3: 分类管理列表**

Create `HappySpending/Settings/CategoryManagementView.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var kind: EntryKind = .expense
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var errorMessage: String?

    private var inKind: [LedgerCategory] { categories.filter { $0.kind == kind } }
    private var tops: [LedgerCategory] { inKind.filter { $0.parent == nil && !$0.isArchived } }
    /// 已归档:一级分类,以及父分类仍在使用中的二级分类(父分类已归档的随父分类一起恢复)。
    private var archived: [LedgerCategory] {
        inKind.filter { $0.isArchived && ($0.parent == nil || $0.parent?.isArchived == false) }
    }

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $kind) {
                    ForEach(EntryKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(tops, id: \.id) { top in
                    NavigationLink(value: top) { row(top) }
                    ForEach(activeChildren(of: top), id: \.id) { child in
                        NavigationLink(value: child) { row(child) }
                            .padding(.leading, 28)
                    }
                }
            } footer: {
                if tops.isEmpty { Text("还没有分类,点右上角的 + 新增。") }
            }

            if !archived.isEmpty {
                Section("已归档") {
                    ForEach(archived, id: \.id) { category in
                        HStack {
                            row(category)
                            Spacer()
                            Button("恢复") { restore(category) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("分类管理")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: LedgerCategory.self) { CategoryEditView(category: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("新增一级分类", isPresented: $showingAdd) {
            TextField("分类名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("添加", action: addTopLevel)
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ category: LedgerCategory) -> some View {
        HStack(spacing: 12) {
            CategoryIconView(
                symbolName: category.symbolName, colorHex: category.colorHex,
                iconData: category.iconData, size: 34
            )
            Text(category.name)
        }
    }

    private func activeChildren(of top: LedgerCategory) -> [LedgerCategory] {
        top.children.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func addTopLevel() {
        do {
            try CategoryRules.createTopLevel(name: newName, kind: kind, among: categories, in: context)
            try context.save()
        } catch let error as CategoryNameError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ category: LedgerCategory) {
        do {
            try CategoryRules.restore(category)
            try context.save()
        } catch CategoryError.parentArchived {
            errorMessage = "请先恢复它的一级分类"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: 分类编辑页**

Create `HappySpending/Settings/CategoryEditView.swift`:

```swift
import SwiftUI
import SwiftData
import PhotosUI
import HappySpendingCore

struct CategoryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [LedgerCategory]
    @Bindable var category: LedgerCategory

    @State private var draftName: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingAddSub = false
    @State private var newSubName = ""
    @State private var errorMessage: String?

    init(category: LedgerCategory) {
        self.category = category
        _draftName = State(initialValue: category.name)
    }

    private var activeChildren: [LedgerCategory] {
        category.children.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    CategoryIconView(
                        symbolName: category.symbolName, colorHex: category.colorHex,
                        iconData: category.iconData, size: 56
                    )
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text("上传图标")
                    }
                }
                if category.iconData != nil {
                    Button("还原默认图标", role: .destructive) {
                        category.iconData = nil
                        save()
                    }
                }
            } footer: {
                Text("图标会被裁成正方形并缩小到 128×128 像素,原图不能超过 10 MB。")
            }

            Section("名称") {
                TextField("名称", text: $draftName)
                    .onSubmit(rename)
                Button("保存名称", action: rename)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines) == category.name)
            }

            if category.parent == nil {
                Section("二级分类") {
                    ForEach(activeChildren, id: \.id) { child in
                        NavigationLink(value: child) {
                            HStack(spacing: 12) {
                                CategoryIconView(
                                    symbolName: child.symbolName, colorHex: child.colorHex,
                                    iconData: child.iconData, size: 30
                                )
                                Text(child.name)
                            }
                        }
                    }
                    Button("新增二级分类") {
                        newSubName = ""
                        showingAddSub = true
                    }
                }
            }

            Section {
                Button("归档这个分类", role: .destructive, action: archive)
            } footer: {
                Text("归档后不再出现在记账页,已有账单保持不变,可以在分类管理里恢复。")
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { Task { await loadIcon() } }
        .alert("新增二级分类", isPresented: $showingAddSub) {
            TextField("分类名称", text: $newSubName)
            Button("取消", role: .cancel) {}
            Button("添加", action: addSubcategory)
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadIcon() async {
        guard let item = pickerItem else { return }
        defer { pickerItem = nil }
        let processed: Data
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CategoryIconError.unreadable
            }
            processed = try CategoryIcon.process(data)
        } catch let error as CategoryIconError {
            errorMessage = error.message
            return
        } catch {
            errorMessage = CategoryIconError.unreadable.message
            return
        }
        category.iconData = processed
        save()
    }

    private func rename() {
        do {
            try CategoryRules.rename(category, to: draftName, among: categories)
            draftName = category.name
            try context.save()
        } catch let error as CategoryNameError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSubcategory() {
        do {
            try CategoryRules.createSubcategory(name: newSubName, under: category, in: context)
            try context.save()
        } catch let error as CategoryNameError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive() {
        CategoryRules.archive(category)
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: 编译**

Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: `** BUILD SUCCEEDED **`,没有 `error:`。
可能要修的点:`NavigationLink(value:)` 需要 `LedgerCategory: Hashable`(`@Model` 类型自带);`@Bindable` 初始化若报错,把 `self.category = category` 改成 `_category = Bindable(category)`。

- [ ] **Step 6: 提交**

```bash
git add HappySpending
git commit -m "feat: add Settings tab with category management and icon upload"
```

---

### Task 7: 检查清单、模拟器验证与收尾

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `README.md`(结构说明里提到设置页)

- [ ] **Step 1: 更新手动检查清单**

Modify `docs/manual-test-checklist.md`。Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "docs/manual-test-checklist.md"
s = open(p, encoding="utf-8").read()

old = "- [ ] 打开后默认在\"记账\"Tab,支出分类里有餐饮、交通、购物、居住、娱乐、医疗、其他\n"
new = "- [ ] 打开后默认在\"记账\"Tab,支出分类按顺序是:日用、餐饮、交通、宠物、娱乐、游戏、旅游、汽车、其他、服饰、购物、居住、医疗\n"
assert s.count(old) == 1
s = s.replace(old, new)

s = s.replace("## 深色模式", """## 设置与分类管理
- [ ] Tab 栏有第 4 个"设置",里面有"分类管理"
- [ ] 游戏下有 原神、ZZZ、steam、暴雪;娱乐下有 电影;汽车下有 停车费、加油
- [ ] 支出/收入切换后列表对应变化;一级分类下缩进显示二级分类
- [ ] 右上角 + 新增一级分类:空名称、超过 10 个字、重名都有提示且不会新增
- [ ] 新增的分类出现在记账页;连续新增 9 个以上,颜色循环,不闪退
- [ ] 点进分类可以改名;改成已有的名字会提示
- [ ] 一级分类里可以新增二级分类;同一个父分类下重名会提示,不同父分类下同名可以
- [ ] 上传图标:从相册选一张横图,图标是居中裁出的正方形;选一张手机竖拍的照片,图标是正的不是躺着的
- [ ] 上传后记账页网格、账单行、分类管理里都显示这张图,是圆形
- [ ] "还原默认图标"后回到原来的 SF Symbol
- [ ] 选一张超过 10 MB 的图,提示"图片太大"
- [ ] 归档一个分类:记账页不再出现;已有账单仍显示原名和图标;"已归档"里能恢复
- [ ] 归档一级分类后,它的二级分类在"已归档"里不单独出现,恢复一级分类后二级分类也回来

## 深色模式""")
open(p, "w", encoding="utf-8").write(s)

p = "README.md"
s = open(p, encoding="utf-8").read()
old = "- `HappySpending`:SwiftUI 界面\n"
assert s.count(old) == 1
s = s.replace(old, "- `HappySpending`:SwiftUI 界面(记账、账单、统计、设置)\n")
open(p, "w", encoding="utf-8").write(s)
EOF
```

- [ ] **Step 2: 全量验证**

Run(仓库根目录):

```bash
swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run" && xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: 全部测试通过(预期 86 + 22 + 13 + 6 = 127 个),没有警告;`** BUILD SUCCEEDED **`。

- [ ] **Step 3: 模拟器里验证**

先验证**旧数据的自动迁移**:模拟器里现在装着旧版本的 app,里面有旧预置分类和一笔账。**不要先卸载**,直接装新版本覆盖,再启动。Run(仓库根目录):

```bash
DD=.superpowers/dd
xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'platform=iOS Simulator,id=DB2215EB-B088-47B2-9466-8DDD8E7C3277' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
```

用 iOS 模拟器工具 `launch` 装并启动 `.superpowers/dd/Build/Products/Debug-iphonesimulator/HappySpending.app`(用绝对路径)。
Expected: 正常启动、不闪退;旧的那笔账还在;分类还是旧的一套(预置只在空库时写入),说明 `iconData` 新字段的自动迁移成功。

然后**卸载重装**,让新预置分类写入。Run(仓库根目录):

```bash
xcrun simctl uninstall DB2215EB-B088-47B2-9466-8DDD8E7C3277 com.strawturtle.happyspending
```

再用 `launch` 装并启动一次,逐项过 `docs/manual-test-checklist.md` 里"首次启动"和"设置与分类管理"两节。要测上传图标,先用 `xcrun simctl addmedia DB2215EB-B088-47B2-9466-8DDD8E7C3277 <图片路径>` 往模拟器相册里加一张横图和一张竖图。
注意:模拟器截图总是滞后一步,每次操作后多拍一张再看。

- [ ] **Step 4: 提交**

```bash
git add README.md docs/manual-test-checklist.md
git commit -m "docs: update README and manual checklist for category management"
```
