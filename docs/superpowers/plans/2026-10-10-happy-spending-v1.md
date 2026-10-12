# happy_spending v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出 v1 记账 app:极速记账、按月账单、月/年统计(Liquid Glass 风格)、两级分类、CSV 导出。

**Architecture:** 所有可测试的逻辑(数据模型、分类规则、键盘状态机、统计聚合、账单分组、CSV)放进本地 Swift Package `HappySpendingCore`,用 `swift test` 在 Mac 上直接跑,不需要模拟器。界面(SwiftUI)放在 App target `HappySpending`,通过 `@Query` 直接取 SwiftData 数据,再把 `LedgerEntry` 映射成纯值类型 `EntryRow` 交给 Core 的纯函数处理。Xcode 工程由 XcodeGen 从 `project.yml` 生成。

**Tech Stack:** Swift 6.3 / Xcode 26.6 / iOS 26 SDK, SwiftUI, SwiftData, Swift Charts, Swift Testing, XcodeGen(仅开发工具)。

**Spec:** `docs/superpowers/specs/2026-10-10-bookkeeping-app-design.md`

## Global Constraints

- 最低系统 **iOS 26**,不写 `#available` 降级;Liquid Glass 用 `.glassEffect()`、`GlassEffectContainer`、`.buttonStyle(.glass)`。
- 技术栈只用 SwiftUI + SwiftData + Swift Charts;**无后端、无网络请求、无第三方依赖**。
- 金额用 `Int` 分存储,恒为正数;输入与显示固定两位小数;上限 9,999,999.99(`Money.maxCents == 999_999_999`)。
- 单一币种,符号 `¥`。
- 分类只有两层;一笔账可挂在一级或二级分类上;分类只归档不物理删除;归档一级分类时二级分类一并归档。
- 记账页:两步完成一笔;自定义数字键盘;点"完成"后停留在记账页,保留日期、类型、分类,清空金额和备注。
- 删除账单不弹确认框,提供几秒"撤销"。
- CSV:UTF-8 带 BOM;RFC 4180 转义;表头 `日期,类型,金额,一级分类,二级分类,备注`;日期 `yyyy-MM-dd`;类型为"支出"/"收入";金额为不带符号的两位小数。
- v1 **不做**:CSV 导入、多账户、预算、云同步、小组件、自定义时间范围、同比环比、复杂筛选。
- 命名:spec 中的 `Transaction` 在代码里叫 `LedgerEntry`,`Category` 叫 `LedgerCategory`(避免与 `SwiftUI.Transaction`、ObjC 运行时的 `Category` 重名)。
- 测试用 Swift Testing;SwiftData 测试用内存容器。
- Core 的所有命令都在 `Packages/HappySpendingCore` 目录下执行;仓库根目录是 `/Users/strawturtle/Desktop/Develop/Self/Self IOS App/happy_spending`。
- 提交信息末尾带上本次会话给出的 `Co-Authored-By` 署名行。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都在对应任务里有测试:

1. **月末/年末边界**:10 月 31 日 23:59 属于 10 月,11 月 1 日 00:00 不属于;12 月 31 日与次年 1 月 1 日分属两年;闰年二月有 29 天。→ Task 5
2. **空周期**:没有任何账单的月份,汇总为 0、占比为空数组(不能除以 0 出现 NaN)、趋势图仍按天/月补零。→ Task 5
3. **数字键盘的怪输入**:先按小数点、连按两次小数点、连按 `0`、超过 7 位整数、第三位小数、空内容按退格、退格删掉小数点。→ Task 4
4. **CSV 里的怪备注**:备注含逗号、双引号、`\n`、`\r\n`、emoji、中文,导出后字段不能错位。→ Task 7
5. **分类身份**:账单没有分类时显示"未分类";分类被归档后历史账单仍显示原名;两个同名但不同 ID 的分类不能被合并成一块。→ Task 5

---

### Task 1: Core 包骨架与金额格式化

**Files:**
- Create: `.gitignore`
- Create: `Packages/HappySpendingCore/Package.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/Money.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/MoneyTests.swift`

**Interfaces:**
- Produces: `Money.maxCents: Int`、`Money.plain(_ cents: Int) -> String`(`"12.34"`)、`Money.display(_ cents: Int) -> String`(`"¥1,234.56"`,负数为 `"-¥0.50"`)。

- [ ] **Step 1: 创建目录与 `.gitignore`**

Run(在仓库根目录):

```bash
mkdir -p Packages/HappySpendingCore/Sources/HappySpendingCore Packages/HappySpendingCore/Tests/HappySpendingCoreTests
```

Create `.gitignore`:

```
.DS_Store
.build/
.swiftpm/
DerivedData/
xcuserdata/
*.xcodeproj
```

- [ ] **Step 2: 创建包清单和一个空的 Money 类型**

Create `Packages/HappySpendingCore/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HappySpendingCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HappySpendingCore", targets: ["HappySpendingCore"]),
    ],
    targets: [
        .target(name: "HappySpendingCore"),
        .testTarget(name: "HappySpendingCoreTests", dependencies: ["HappySpendingCore"]),
    ]
)
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/Money.swift`:

```swift
import Foundation

public enum Money {}
```

- [ ] **Step 3: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/MoneyTests.swift`:

```swift
import Testing
@testable import HappySpendingCore

struct MoneyTests {
    @Test func plainAlwaysHasTwoDecimals() {
        #expect(Money.plain(0) == "0.00")
        #expect(Money.plain(5) == "0.05")
        #expect(Money.plain(1234) == "12.34")
        #expect(Money.plain(2350) == "23.50")
    }

    @Test func displayHasSymbolAndGrouping() {
        #expect(Money.display(123456) == "¥1,234.56")
        #expect(Money.display(Money.maxCents) == "¥9,999,999.99")
        #expect(Money.display(0) == "¥0.00")
    }

    @Test func negativeValuesKeepTheirSign() {
        #expect(Money.plain(-1234) == "-12.34")
        #expect(Money.display(-50) == "-¥0.50")
    }

    @Test func maxCentsIsNineMillionNineHundredNinetyNineThousandNineHundredNinetyNinePointNinetyNine() {
        #expect(Money.maxCents == 999_999_999)
    }
}
```

- [ ] **Step 4: 运行,确认失败**

Run: `cd Packages/HappySpendingCore && swift test --filter MoneyTests`
Expected: 编译失败,报 `type 'Money' has no member 'plain'`(或 `maxCents`)。

- [ ] **Step 5: 写最小实现**

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/Money.swift`:

```swift
import Foundation

public enum Money {
    /// 9,999,999.99,以分为单位。
    public static let maxCents = 999_999_999

    /// 两位小数、无符号、无千分位,例如 "12.34"。
    public static func plain(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        return "\(sign)\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    /// 带 ¥ 和千分位,例如 "¥1,234.56";负数为 "-¥0.50"。
    public static func display(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        let whole = (magnitude / 100).formatted(
            .number.grouping(.automatic).locale(Locale(identifier: "en_US"))
        )
        return "\(sign)¥\(whole).\(String(format: "%02d", magnitude % 100))"
    }
}
```

- [ ] **Step 6: 运行,确认通过**

Run: `cd Packages/HappySpendingCore && swift test --filter MoneyTests`
Expected: 4 个测试全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add .gitignore Packages/HappySpendingCore
git commit -m "feat: scaffold HappySpendingCore package with Money formatting"
```

---

### Task 2: Xcode 工程骨架(XcodeGen)

**Files:**
- Create: `project.yml`
- Create: `HappySpending/HappySpendingApp.swift`
- Create: `HappySpending/RootTabView.swift`
- Create: `HappySpending/Record/RecordView.swift`(占位,Task 8 整体替换)
- Create: `HappySpending/Bills/BillsView.swift`(占位,Task 9 整体替换)
- Create: `HappySpending/Stats/StatsView.swift`(占位,Task 10 整体替换)

**Interfaces:**
- Produces: 可编译的 iOS App target `HappySpending`,依赖 `HappySpendingCore`;三个 Tab 的入口视图 `RecordView`、`BillsView`、`StatsView`。

- [ ] **Step 1: 安装 XcodeGen(需要先征得用户同意再执行)**

Run: `brew install xcodegen`
Expected: `xcodegen --version` 能输出版本号。它只是开发工具,不进入产品依赖。

- [ ] **Step 2: 写 `project.yml`**

Create `project.yml`:

```yaml
name: HappySpending
options:
  bundleIdPrefix: com.strawturtle
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
packages:
  HappySpendingCore:
    path: Packages/HappySpendingCore
targets:
  HappySpending:
    type: application
    platform: iOS
    sources:
      - path: HappySpending
    dependencies:
      - package: HappySpendingCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.strawturtle.happyspending
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: Happy Spending
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: UIInterfaceOrientationPortrait
        CODE_SIGN_STYLE: Automatic
```

- [ ] **Step 3: 写 App 入口与三个占位 Tab**

Create `HappySpending/HappySpendingApp.swift`:

```swift
import SwiftUI

@main
struct HappySpendingApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
```

Create `HappySpending/RootTabView.swift`:

```swift
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("记账", systemImage: "plus.circle.fill") { RecordView() }
            Tab("账单", systemImage: "list.bullet.rectangle") { BillsView() }
            Tab("统计", systemImage: "chart.pie.fill") { StatsView() }
        }
    }
}
```

Create `HappySpending/Record/RecordView.swift`:

```swift
import SwiftUI

struct RecordView: View {
    var body: some View { Text("记账") }
}
```

Create `HappySpending/Bills/BillsView.swift`:

```swift
import SwiftUI

struct BillsView: View {
    var body: some View { Text("账单") }
}
```

Create `HappySpending/Stats/StatsView.swift`:

```swift
import SwiftUI

struct StatsView: View {
    var body: some View { Text("统计") }
}
```

- [ ] **Step 4: 生成工程并编译**

Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -15
```

Expected: 末尾出现 `** BUILD SUCCEEDED **`。
若报找不到 destination:本机没有安装模拟器运行时,`generic/platform=iOS Simulator` 通常仍可编译;若仍失败,改用 `-sdk iphonesimulator -arch arm64` 代替 `-destination`。

- [ ] **Step 5: 提交**

```bash
git add project.yml HappySpending
git commit -m "feat: add Xcode project scaffold with three-tab shell"
```

---

### Task 3: 数据模型、分类规则与默认分类

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/EntryKind.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerCategory.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerEntry.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryRules.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/DefaultCategories.swift`
- Create: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/Fixtures.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryRulesTests.swift`
- Modify: `docs/superpowers/specs/2026-10-10-bookkeeping-app-design.md`(§5 加命名说明)

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum EntryKind: String, Codable, CaseIterable, Sendable { case expense, income; var title: String }`
  - `@Model LedgerCategory`:`id: UUID`、`name`、`symbolName`、`colorHex`、`kind: EntryKind`、`sortOrder: Int`、`isArchived: Bool`、`parent: LedgerCategory?`、`children: [LedgerCategory]`、`entries: [LedgerEntry]`、`displayName: String`
  - `@Model LedgerEntry`:`id: UUID`、`amountInCents: Int`、`kind: EntryKind`、`date: Date`(自动取当天 0 点)、`createdAt: Date`、`note: String`、`category: LedgerCategory?`;`init(id:amountInCents:kind:date:note:category:createdAt:calendar:)`
  - `CategoryRules.addTopLevel(name:symbolName:colorHex:kind:sortOrder:in:) -> LedgerCategory`、`CategoryRules.addSubcategory(name:symbolName:under:in:) throws -> LedgerCategory`、`CategoryRules.archive(_:)`、`CategoryError.parentMustBeTopLevel`
  - `DefaultCategories.seedIfNeeded(in:) throws -> Bool`
  - 测试辅助:`makeTestContainer() throws -> ModelContainer`、`testCalendar: Calendar`(Asia/Shanghai 公历)、`makeDate(_ y:_ m:_ d:_ h:_ min:) -> Date`

> 注意:自引用关系 `parent` 必须显式声明 `children` 作为反向关系,否则 SwiftData 会把 `parent` 当成自己的反向,导致一级分类的 `parent` 也不为空(已在本机验证)。

- [ ] **Step 1: 写测试辅助和失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/Fixtures.swift`:

```swift
import Foundation
import SwiftData
@testable import HappySpendingCore

let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}()

func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func makeTestContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LedgerCategory.self, LedgerEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}
```

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CategoryRulesTests.swift`:

```swift
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `cd Packages/HappySpendingCore && swift test --filter CategoryRulesTests`
Expected: 编译失败,报 `cannot find 'LedgerCategory' in scope` 之类。

- [ ] **Step 3: 写模型与规则**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/EntryKind.swift`:

```swift
public enum EntryKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income

    public var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        }
    }
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerCategory.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class LedgerCategory {
    public var id: UUID
    public var name: String
    public var symbolName: String
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
        parent: LedgerCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.isArchived = false
        self.parent = parent
    }
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerEntry.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class LedgerEntry {
    public var id: UUID
    public var amountInCents: Int
    public var kindRaw: String
    public var date: Date
    public var createdAt: Date
    public var note: String
    public var category: LedgerCategory?

    public var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        amountInCents: Int,
        kind: EntryKind,
        date: Date,
        note: String = "",
        category: LedgerCategory? = nil,
        createdAt: Date = .now,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.amountInCents = amountInCents
        self.kindRaw = kind.rawValue
        self.date = calendar.startOfDay(for: date)
        self.createdAt = createdAt
        self.note = note
        self.category = category
    }
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/CategoryRules.swift`:

```swift
import Foundation
import SwiftData

public enum CategoryError: Error, Equatable {
    case parentMustBeTopLevel
}

public enum CategoryRules {
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

    /// 归档;归档一级分类时,二级分类一并归档。
    public static func archive(_ category: LedgerCategory) {
        category.isArchived = true
        for child in category.children {
            child.isArchived = true
        }
    }
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/DefaultCategories.swift`:

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

    private static let expense: [Spec] = [
        Spec(name: "餐饮", symbol: "fork.knife", color: "#FF9F0A", children: ["早餐", "午餐", "晚餐", "零食"]),
        Spec(name: "交通", symbol: "car.fill", color: "#0A84FF", children: ["公交地铁", "打车", "加油"]),
        Spec(name: "购物", symbol: "bag.fill", color: "#FF375F", children: ["日用", "服饰", "数码"]),
        Spec(name: "居住", symbol: "house.fill", color: "#30B0C7", children: ["房租", "水电燃气", "网费"]),
        Spec(name: "娱乐", symbol: "gamecontroller.fill", color: "#BF5AF2", children: ["电影", "游戏", "旅行"]),
        Spec(name: "医疗", symbol: "cross.case.fill", color: "#FF453A", children: ["药品", "诊疗"]),
        Spec(name: "其他", symbol: "ellipsis.circle.fill", color: "#8E8E93", children: []),
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

Run: `cd Packages/HappySpendingCore && swift test --filter CategoryRulesTests`
Expected: 8 个测试全部 PASS。

- [ ] **Step 5: 给 spec 加命名说明**

Edit `docs/superpowers/specs/2026-10-10-bookkeeping-app-design.md`:在 `## 5. 数据模型` 标题下面插入一行:

```
> 实现命名:`Transaction` 在代码中叫 `LedgerEntry`,`Category` 叫 `LedgerCategory`,避免与 `SwiftUI.Transaction` 及 ObjC 运行时的 `Category` 重名。
```

- [ ] **Step 6: 提交**

```bash
git add Packages/HappySpendingCore docs/superpowers/specs
git commit -m "feat: add SwiftData models, two-level category rules and default categories"
```

---

### Task 4: 数字键盘状态机

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/AmountInput.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AmountInputTests.swift`

**Interfaces:**
- Consumes: `Money.plain`、`Money.maxCents`(Task 1)
- Produces:
  - `enum KeypadKey: Hashable, Sendable { case digit(Int), dot, backspace }`
  - `struct AmountInput: Equatable, Sendable`:`init()`、`init(cents:)`、`text: String`、`cents: Int`、`isValid: Bool`、`displayText: String`、`mutating func press(_ key: KeypadKey)`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AmountInputTests.swift`:

```swift
import Testing
@testable import HappySpendingCore

struct AmountInputTests {
    private func typed(_ keys: [KeypadKey]) -> AmountInput {
        var input = AmountInput()
        for key in keys { input.press(key) }
        return input
    }

    @Test func typesDigitsAndTwoDecimals() {
        let input = typed([.digit(1), .digit(2), .dot, .digit(3), .digit(4)])
        #expect(input.text == "12.34")
        #expect(input.cents == 1234)
    }

    @Test func thirdDecimalIsIgnored() {
        let input = typed([.digit(1), .dot, .digit(2), .digit(3), .digit(4)])
        #expect(input.text == "1.23")
        #expect(input.cents == 123)
    }

    @Test func leadingZerosCollapse() {
        #expect(typed([.digit(0), .digit(0), .digit(5)]).text == "5")
        #expect(typed([.digit(0), .digit(0)]).text == "0")
    }

    @Test func dotFirstProducesZeroDot() {
        let input = typed([.dot])
        #expect(input.text == "0.")
        #expect(input.cents == 0)
        #expect(!input.isValid)
    }

    @Test func secondDotIsIgnored() {
        let input = typed([.digit(1), .dot, .digit(2), .dot, .digit(3)])
        #expect(input.text == "1.23")
    }

    @Test func integerPartIsCappedAtSevenDigits() {
        let input = typed(Array(repeating: .digit(9), count: 8))
        #expect(input.text == "9999999")
        #expect(input.cents == 999_999_900)
    }

    @Test func largestAmountEqualsTheCapAndRejectsMore() {
        var input = typed(Array(repeating: .digit(9), count: 7) + [.dot, .digit(9), .digit(9)])
        #expect(input.cents == Money.maxCents)
        input.press(.digit(9))
        #expect(input.text == "9999999.99")
    }

    @Test func backspaceOnEmptyDoesNothing() {
        var input = AmountInput()
        input.press(.backspace)
        #expect(input.text == "")
        #expect(input.cents == 0)
    }

    @Test func backspaceCanRemoveTheDot() {
        var input = typed([.digit(1), .digit(2), .dot])
        input.press(.backspace)
        #expect(input.text == "12")
    }

    @Test func partialDecimalsArePadded() {
        #expect(typed([.digit(1), .digit(2), .dot]).cents == 1200)
        #expect(typed([.digit(1), .digit(2), .dot, .digit(3)]).cents == 1230)
        #expect(typed([.dot, .digit(5)]).cents == 50)
    }

    @Test func zeroAmountIsNotValid() {
        #expect(!AmountInput().isValid)
        #expect(!typed([.digit(0), .dot, .digit(0), .digit(0)]).isValid)
        #expect(typed([.dot, .digit(0), .digit(1)]).isValid)
    }

    @Test func displayTextShowsWhatWasTyped() {
        #expect(AmountInput().displayText == "¥0.00")
        #expect(typed([.digit(1), .digit(2), .dot]).displayText == "¥12.")
    }

    @Test func initFromCentsRoundTrips() {
        let input = AmountInput(cents: 2350)
        #expect(input.text == "23.50")
        #expect(input.cents == 2350)
        #expect(AmountInput(cents: 0).text == "")
        #expect(AmountInput(cents: Money.maxCents).cents == Money.maxCents)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `cd Packages/HappySpendingCore && swift test --filter AmountInputTests`
Expected: 编译失败,报 `cannot find 'AmountInput' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/AmountInput.swift`:

```swift
public enum KeypadKey: Hashable, Sendable {
    case digit(Int)
    case dot
    case backspace
}

/// 自定义数字键盘的输入状态:整数最多 7 位,小数最多 2 位,不允许前导零。
public struct AmountInput: Equatable, Sendable {
    /// 用户已输入的内容:"" / "0." / "12" / "12.3" / "12.34"。
    public private(set) var text: String

    public init() {
        text = ""
    }

    public init(cents: Int) {
        let clamped = min(max(cents, 0), Money.maxCents)
        text = clamped == 0 ? "" : Money.plain(clamped)
    }

    public var cents: Int {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(parts.first ?? "") ?? 0
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        while fraction.count < 2 { fraction += "0" }
        return whole * 100 + (Int(fraction) ?? 0)
    }

    public var isValid: Bool { cents > 0 }

    public var displayText: String {
        text.isEmpty ? "¥0.00" : "¥" + text
    }

    public mutating func press(_ key: KeypadKey) {
        switch key {
        case .digit(let digit):
            guard (0...9).contains(digit) else { return }
            if let dot = text.firstIndex(of: ".") {
                let decimals = text.distance(from: dot, to: text.endIndex) - 1
                guard decimals < 2 else { return }
                text.append(String(digit))
            } else if text == "0" {
                text = String(digit)
            } else {
                guard text.count < 7 else { return }
                text.append(String(digit))
            }
        case .dot:
            guard !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
        case .backspace:
            if !text.isEmpty { text.removeLast() }
        }
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `cd Packages/HappySpendingCore && swift test --filter AmountInputTests`
Expected: 13 个测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add amount keypad state machine"
```

---

### Task 5: EntryRow 与统计聚合

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/EntryRow.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/Period.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/Statistics.swift`
- Create: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/RowFixtures.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/RowMappingTests.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/StatisticsTests.swift`

**Interfaces:**
- Consumes: `LedgerEntry`、`LedgerCategory`、`EntryKind`(Task 3);测试辅助 `testCalendar`、`makeDate`、`makeTestContainer`(Task 3)
- Produces:
  - `enum Uncategorized { static let name = "未分类"; static let colorHex = "#8E8E93" }`
  - `struct EntryRow: Equatable, Identifiable, Sendable`:`id, date, createdAt, kind, cents, note, topCategoryID: UUID?, topCategoryName, topColorHex, subCategoryID: UUID?, subCategoryName: String?`、`displayCategory: String`;`LedgerEntry.row: EntryRow`
  - `enum Period: Equatable, Sendable { case month(Date), year(Int) }`:`interval(calendar:) -> DateInterval`(左闭右开)、`filter(_:calendar:) -> [EntryRow]`
  - `struct PeriodSummary { incomeCents, expenseCents, balanceCents }`
  - `struct CategoryShare: Equatable, Hashable, Identifiable, Sendable { id: UUID?, name, colorHex, cents, fraction: Double, children: [SubcategoryShare] }`
  - `struct SubcategoryShare: Equatable, Hashable, Identifiable, Sendable { id: UUID?, name, cents, fraction: Double }`(`fraction` 是占其一级分类的比例;`id == nil` 表示"未细分")
  - `struct TrendPoint: Equatable, Identifiable, Sendable { date: Date, cents: Int }`
  - `enum Statistics`:`summary(_:)`、`shares(_:kind:)`、`dailyTrend(_:month:kind:calendar:)`、`monthlyTrend(_:year:kind:calendar:)`
  - 测试辅助:`makeRow(cents:kind:on:top:topID:sub:subID:note:createdAt:) -> EntryRow`、`stableID(_:) -> UUID`

- [ ] **Step 1: 写测试辅助**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/RowFixtures.swift`:

```swift
import Foundation
@testable import HappySpendingCore

/// 同一个名字在同一次测试进程里总是得到同一个 UUID。
func stableID(_ name: String) -> UUID {
    let suffix = UInt64(truncatingIfNeeded: name.hashValue) & 0xFFFF_FFFF_FFFF
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", suffix))!
}

func makeRow(
    cents: Int,
    kind: EntryKind = .expense,
    on date: Date,
    top: String = "餐饮",
    topID: UUID? = nil,
    sub: String? = nil,
    subID: UUID? = nil,
    note: String = "",
    createdAt: Date? = nil
) -> EntryRow {
    EntryRow(
        date: date,
        createdAt: createdAt,
        kind: kind,
        cents: cents,
        note: note,
        topCategoryID: topID ?? stableID(top),
        topCategoryName: top,
        topColorHex: "#FF9F0A",
        subCategoryID: sub.map { subID ?? stableID($0) },
        subCategoryName: sub
    )
}
```

- [ ] **Step 2: 写失败的测试(行映射)**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/RowMappingTests.swift`:

```swift
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
```

- [ ] **Step 3: 写失败的测试(统计)**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/StatisticsTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct StatisticsTests {
    private let cal = testCalendar

    // MARK: Period

    @Test func monthPeriodIsHalfOpenAtBothEnds() {
        let rows = [
            makeRow(cents: 1, on: makeDate(2026, 9, 30, 23, 59)),
            makeRow(cents: 2, on: makeDate(2026, 10, 1, 0, 0)),
            makeRow(cents: 4, on: makeDate(2026, 10, 31, 23, 59)),
            makeRow(cents: 8, on: makeDate(2026, 11, 1, 0, 0)),
        ]
        let filtered = Period.month(makeDate(2026, 10, 15)).filter(rows, calendar: cal)
        #expect(filtered.map(\.cents) == [2, 4])
    }

    @Test func yearPeriodSeparatesDecemberFromNextJanuary() {
        let rows = [
            makeRow(cents: 1, on: makeDate(2025, 12, 31, 23, 59)),
            makeRow(cents: 2, on: makeDate(2026, 1, 1, 0, 0)),
            makeRow(cents: 4, on: makeDate(2026, 12, 31, 23, 59)),
            makeRow(cents: 8, on: makeDate(2027, 1, 1, 0, 0)),
        ]
        let filtered = Period.year(2026).filter(rows, calendar: cal)
        #expect(filtered.map(\.cents) == [2, 4])
    }

    // MARK: summary

    @Test func summaryAddsIncomeAndExpenseSeparately() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 1000, on: d),
            makeRow(cents: 250, on: d),
            makeRow(cents: 5000, kind: .income, on: d, top: "工资"),
        ]
        let summary = Statistics.summary(rows)
        #expect(summary.incomeCents == 5000)
        #expect(summary.expenseCents == 1250)
        #expect(summary.balanceCents == 3750)
    }

    @Test func summaryOfNothingIsZero() {
        let summary = Statistics.summary([])
        #expect(summary.incomeCents == 0)
        #expect(summary.expenseCents == 0)
        #expect(summary.balanceCents == 0)
    }

    @Test func balanceCanBeNegative() {
        let rows = [makeRow(cents: 300, on: makeDate(2026, 10, 10))]
        #expect(Statistics.summary(rows).balanceCents == -300)
    }

    // MARK: shares

    @Test func sharesGroupByTopLevelWithSubcategoryDetail() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 3000, on: d, top: "餐饮", sub: "午餐"),
            makeRow(cents: 1000, on: d, top: "餐饮", sub: "晚餐"),
            makeRow(cents: 1000, on: d, top: "餐饮"),
            makeRow(cents: 2000, on: d, top: "交通"),
        ]
        let shares = Statistics.shares(rows, kind: .expense)

        #expect(shares.map(\.name) == ["餐饮", "交通"])
        #expect(shares[0].cents == 5000)
        #expect(abs(shares[0].fraction - 5.0 / 7.0) < 1e-9)
        #expect(abs(shares.map(\.fraction).reduce(0, +) - 1.0) < 1e-9)

        let children = shares[0].children
        #expect(children.map(\.name) == ["午餐", "晚餐", "未细分"])
        #expect(children.map(\.cents) == [3000, 1000, 1000])
        #expect(abs(children[0].fraction - 0.6) < 1e-9)
        #expect(children[2].id == nil)
        #expect(shares[1].children.map(\.name) == ["未细分"])
    }

    @Test func sharesOnlyCountTheRequestedKind() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 100, on: d, top: "餐饮"),
            makeRow(cents: 9000, kind: .income, on: d, top: "工资"),
        ]
        #expect(Statistics.shares(rows, kind: .expense).map(\.name) == ["餐饮"])
        #expect(Statistics.shares(rows, kind: .income).map(\.name) == ["工资"])
    }

    @Test func sharesOfNothingIsEmptyNotNaN() {
        #expect(Statistics.shares([], kind: .expense).isEmpty)
        let onlyIncome = [makeRow(cents: 100, kind: .income, on: makeDate(2026, 10, 10), top: "工资")]
        #expect(Statistics.shares(onlyIncome, kind: .expense).isEmpty)
    }

    @Test func sameNamedCategoriesWithDifferentIDsStaySeparate() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 100, on: d, top: "其他", topID: UUID()),
            makeRow(cents: 200, on: d, top: "其他", topID: UUID()),
        ]
        let shares = Statistics.shares(rows, kind: .expense)
        #expect(shares.count == 2)
        #expect(shares.map(\.cents) == [200, 100])
    }

    @Test func entriesWithoutACategoryFormAnUncategorizedShare() {
        let row = EntryRow(
            date: makeDate(2026, 10, 10), kind: .expense, cents: 500,
            topCategoryID: nil, topCategoryName: Uncategorized.name, topColorHex: Uncategorized.colorHex
        )
        let shares = Statistics.shares([row], kind: .expense)
        #expect(shares.count == 1)
        #expect(shares[0].name == "未分类")
        #expect(shares[0].id == nil)
    }

    // MARK: daily trend

    @Test func dailyTrendHasOnePointPerDayAndFillsZeros() {
        let rows = [
            makeRow(cents: 100, on: makeDate(2026, 10, 1)),
            makeRow(cents: 400, on: makeDate(2026, 10, 1, 18, 0)),
        ]
        let points = Statistics.dailyTrend(rows, month: makeDate(2026, 10, 15), calendar: cal)

        #expect(points.count == 31)
        #expect(points.first?.date == makeDate(2026, 10, 1))
        #expect(points.last?.date == makeDate(2026, 10, 31))
        #expect(points[0].cents == 500)
        #expect(points[1].cents == 0)
    }

    @Test func dailyTrendRespectsMonthBoundaries() {
        let rows = [
            makeRow(cents: 700, on: makeDate(2026, 10, 31, 23, 59)),
            makeRow(cents: 900, on: makeDate(2026, 11, 1, 0, 0)),
            makeRow(cents: 50, on: makeDate(2026, 9, 30, 23, 59)),
        ]
        let points = Statistics.dailyTrend(rows, month: makeDate(2026, 10, 15), calendar: cal)

        #expect(points[30].cents == 700)
        #expect(points.map(\.cents).reduce(0, +) == 700)
    }

    @Test func dailyTrendOnlyCountsTheRequestedKind() {
        let rows = [
            makeRow(cents: 100, on: makeDate(2026, 10, 5)),
            makeRow(cents: 9000, kind: .income, on: makeDate(2026, 10, 5), top: "工资"),
        ]
        let points = Statistics.dailyTrend(rows, month: makeDate(2026, 10, 1), calendar: cal)
        #expect(points[4].cents == 100)
    }

    @Test func dailyTrendKnowsLeapYears() {
        #expect(Statistics.dailyTrend([], month: makeDate(2028, 2, 10), calendar: cal).count == 29)
        #expect(Statistics.dailyTrend([], month: makeDate(2027, 2, 10), calendar: cal).count == 28)
    }

    @Test func dailyTrendOfAnEmptyMonthIsAllZeros() {
        let points = Statistics.dailyTrend([], month: makeDate(2026, 10, 1), calendar: cal)
        #expect(points.count == 31)
        #expect(points.allSatisfy { $0.cents == 0 })
    }

    // MARK: monthly trend

    @Test func monthlyTrendHasTwelvePointsAndRespectsYearBoundaries() {
        let rows = [
            makeRow(cents: 200, on: makeDate(2026, 1, 15)),
            makeRow(cents: 50, on: makeDate(2026, 12, 1)),
            makeRow(cents: 300, on: makeDate(2026, 12, 31, 23, 59)),
            makeRow(cents: 900, on: makeDate(2027, 1, 1, 0, 0)),
            makeRow(cents: 7, on: makeDate(2025, 12, 31, 23, 59)),
        ]
        let points = Statistics.monthlyTrend(rows, year: 2026, calendar: cal)

        #expect(points.count == 12)
        #expect(points.first?.date == makeDate(2026, 1, 1))
        #expect(points.last?.date == makeDate(2026, 12, 1))
        #expect(points[0].cents == 200)
        #expect(points[11].cents == 350)
        #expect(points.map(\.cents).reduce(0, +) == 550)
    }

    @Test func monthlyTrendOfAnEmptyYearIsAllZeros() {
        let points = Statistics.monthlyTrend([], year: 2026, calendar: cal)
        #expect(points.count == 12)
        #expect(points.allSatisfy { $0.cents == 0 })
    }
}
```

- [ ] **Step 4: 运行,确认失败**

Run: `cd Packages/HappySpendingCore && swift test --filter "RowMappingTests|StatisticsTests"`
Expected: 编译失败,报 `cannot find 'EntryRow' in scope` 之类。

- [ ] **Step 5: 写 EntryRow**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/EntryRow.swift`:

```swift
import Foundation

public enum Uncategorized {
    public static let name = "未分类"
    public static let colorHex = "#8E8E93"
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
            subCategoryID: sub?.id,
            subCategoryName: sub?.name
        )
    }
}
```

- [ ] **Step 6: 写 Period**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/Period.swift`:

```swift
import Foundation

public enum Period: Equatable, Sendable {
    /// 关联值是该月内的任意一天。
    case month(Date)
    case year(Int)

    /// 左闭右开:包含起点,不包含终点。
    public func interval(calendar: Calendar) -> DateInterval {
        switch self {
        case .month(let date):
            return calendar.dateInterval(of: .month, for: date)!
        case .year(let year):
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            return DateInterval(start: start, end: end)
        }
    }

    public func filter(_ rows: [EntryRow], calendar: Calendar) -> [EntryRow] {
        let interval = interval(calendar: calendar)
        return rows.filter { $0.date >= interval.start && $0.date < interval.end }
    }
}
```

- [ ] **Step 7: 写 Statistics**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/Statistics.swift`:

```swift
import Foundation

public struct PeriodSummary: Equatable, Sendable {
    public let incomeCents: Int
    public let expenseCents: Int
    public var balanceCents: Int { incomeCents - expenseCents }
}

public struct SubcategoryShare: Equatable, Hashable, Identifiable, Sendable {
    /// nil 表示"未细分"(账单直接挂在一级分类上)。
    public let id: UUID?
    public let name: String
    public let cents: Int
    /// 占所属一级分类的比例。
    public let fraction: Double
}

public struct CategoryShare: Equatable, Hashable, Identifiable, Sendable {
    /// nil 表示"未分类"。
    public let id: UUID?
    public let name: String
    public let colorHex: String
    public let cents: Int
    /// 占该类型总额的比例。
    public let fraction: Double
    public let children: [SubcategoryShare]
}

public struct TrendPoint: Equatable, Identifiable, Sendable {
    public let date: Date
    public let cents: Int
    public var id: Date { date }
}

public enum Statistics {
    public static func summary(_ rows: [EntryRow]) -> PeriodSummary {
        PeriodSummary(
            incomeCents: rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.cents },
            expenseCents: rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.cents }
        )
    }

    /// 按一级分类汇总,金额从大到小;金额相同按名称排序。没有数据时返回空数组。
    public static func shares(_ rows: [EntryRow], kind: EntryKind) -> [CategoryShare] {
        let rows = rows.filter { $0.kind == kind }
        let total = rows.reduce(0) { $0 + $1.cents }
        guard total > 0 else { return [] }

        return Dictionary(grouping: rows, by: \.topCategoryID)
            .map { topID, members -> CategoryShare in
                let cents = members.reduce(0) { $0 + $1.cents }
                let children = Dictionary(grouping: members, by: \.subCategoryID)
                    .map { subID, subMembers -> SubcategoryShare in
                        let subCents = subMembers.reduce(0) { $0 + $1.cents }
                        return SubcategoryShare(
                            id: subID,
                            name: subMembers[0].subCategoryName ?? "未细分",
                            cents: subCents,
                            fraction: Double(subCents) / Double(cents)
                        )
                    }
                    .sorted { lhs, rhs in
                        lhs.cents != rhs.cents ? lhs.cents > rhs.cents : lhs.name < rhs.name
                    }
                return CategoryShare(
                    id: topID,
                    name: members[0].topCategoryName,
                    colorHex: members[0].topColorHex,
                    cents: cents,
                    fraction: Double(cents) / Double(total),
                    children: children
                )
            }
            .sorted { lhs, rhs in
                lhs.cents != rhs.cents ? lhs.cents > rhs.cents : lhs.name < rhs.name
            }
    }

    /// 某月每一天一个点,没有账单的日子补零。
    public static func dailyTrend(
        _ rows: [EntryRow],
        month: Date,
        kind: EntryKind = .expense,
        calendar: Calendar
    ) -> [TrendPoint] {
        let interval = calendar.dateInterval(of: .month, for: month)!
        var totals: [Date: Int] = [:]
        for row in rows where row.kind == kind && row.date >= interval.start && row.date < interval.end {
            totals[calendar.startOfDay(for: row.date), default: 0] += row.cents
        }
        let dayCount = calendar.range(of: .day, in: .month, for: month)!.count
        return (0..<dayCount).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: interval.start)!
            return TrendPoint(date: day, cents: totals[day] ?? 0)
        }
    }

    /// 某年 12 个月各一个点,没有账单的月份补零。
    public static func monthlyTrend(
        _ rows: [EntryRow],
        year: Int,
        kind: EntryKind = .expense,
        calendar: Calendar
    ) -> [TrendPoint] {
        let interval = Period.year(year).interval(calendar: calendar)
        var totals: [Date: Int] = [:]
        for row in rows where row.kind == kind && row.date >= interval.start && row.date < interval.end {
            let monthStart = calendar.dateInterval(of: .month, for: row.date)!.start
            totals[monthStart, default: 0] += row.cents
        }
        return (1...12).map { month in
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            return TrendPoint(date: start, cents: totals[start] ?? 0)
        }
    }
}
```

- [ ] **Step 8: 运行,确认通过**

Run: `cd Packages/HappySpendingCore && swift test --filter "RowMappingTests|StatisticsTests"`
Expected: 全部 PASS(行映射 4 个,统计 17 个)。

- [ ] **Step 9: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add EntryRow snapshot, periods and statistics aggregation"
```

---

### Task 6: 账单分组、搜索与常用分类

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/BillsLogic.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BillsLogicTests.swift`

**Interfaces:**
- Consumes: `EntryRow`、`EntryKind`(Task 3、5);测试辅助 `makeRow`、`makeDate`、`testCalendar`
- Produces:
  - `struct DayGroup: Equatable, Identifiable, Sendable { day: Date, rows: [EntryRow], incomeCents: Int, expenseCents: Int }`
  - `enum BillsLogic`:`groupByDay(_:calendar:) -> [DayGroup]`(日期倒序;同一天内按 `createdAt` 倒序)、`dayTitle(_:calendar:) -> String`(`"10月10日 周六"`)、`search(_:query:) -> [EntryRow]`、`frequentCategoryIDs(_:kind:excluding:limit:window:) -> [UUID]`(返回叶子分类 ID:有二级用二级,否则用一级)

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BillsLogicTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct BillsLogicTests {
    private let cal = testCalendar

    // MARK: groupByDay

    @Test func groupsByDayNewestFirstWithSubtotals() {
        let rows = [
            makeRow(cents: 100, on: makeDate(2026, 10, 8)),
            makeRow(cents: 200, on: makeDate(2026, 10, 10)),
            makeRow(cents: 3000, kind: .income, on: makeDate(2026, 10, 10), top: "工资"),
            makeRow(cents: 50, on: makeDate(2026, 10, 10)),
        ]
        let groups = BillsLogic.groupByDay(rows, calendar: cal)

        #expect(groups.map(\.day) == [makeDate(2026, 10, 10), makeDate(2026, 10, 8)])
        #expect(groups[0].expenseCents == 250)
        #expect(groups[0].incomeCents == 3000)
        #expect(groups[0].rows.count == 3)
        #expect(groups[1].expenseCents == 100)
        #expect(groups[1].incomeCents == 0)
    }

    @Test func rowsWithinADayAreNewestCreatedFirst() {
        let day = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 1, on: day, createdAt: makeDate(2026, 10, 10, 9, 0)),
            makeRow(cents: 2, on: day, createdAt: makeDate(2026, 10, 10, 21, 0)),
            makeRow(cents: 3, on: day, createdAt: makeDate(2026, 10, 10, 12, 0)),
        ]
        let groups = BillsLogic.groupByDay(rows, calendar: cal)
        #expect(groups[0].rows.map(\.cents) == [2, 3, 1])
    }

    @Test func groupingNothingGivesNoGroups() {
        #expect(BillsLogic.groupByDay([], calendar: cal).isEmpty)
    }

    @Test func dayTitleShowsDateAndWeekday() {
        #expect(BillsLogic.dayTitle(makeDate(2026, 10, 10), calendar: cal) == "10月10日 周六")
    }

    // MARK: search

    @Test func searchMatchesNoteAndCategoryNamesIgnoringCase() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 1, on: d, top: "餐饮", sub: "午餐", note: "Starbucks 拿铁"),
            makeRow(cents: 2, on: d, top: "交通", note: "地铁"),
            makeRow(cents: 3, on: d, top: "购物", note: ""),
        ]
        #expect(BillsLogic.search(rows, query: "starbucks").map(\.cents) == [1])
        #expect(BillsLogic.search(rows, query: "午餐").map(\.cents) == [1])
        #expect(BillsLogic.search(rows, query: "交通").map(\.cents) == [2])
        #expect(BillsLogic.search(rows, query: "不存在").isEmpty)
    }

    @Test func blankQueryReturnsEverything() {
        let rows = [makeRow(cents: 1, on: makeDate(2026, 10, 10)), makeRow(cents: 2, on: makeDate(2026, 10, 10))]
        #expect(BillsLogic.search(rows, query: "").count == 2)
        #expect(BillsLogic.search(rows, query: "   ").count == 2)
    }

    // MARK: frequentCategoryIDs

    @Test func frequentCategoriesAreOrderedByCountThenRecency() {
        let rows = [
            makeRow(cents: 1, on: makeDate(2026, 10, 1), top: "餐饮", sub: "午餐", createdAt: makeDate(2026, 10, 1)),
            makeRow(cents: 1, on: makeDate(2026, 10, 2), top: "餐饮", sub: "午餐", createdAt: makeDate(2026, 10, 2)),
            makeRow(cents: 1, on: makeDate(2026, 10, 3), top: "交通", createdAt: makeDate(2026, 10, 3)),
            makeRow(cents: 1, on: makeDate(2026, 10, 4), top: "购物", createdAt: makeDate(2026, 10, 4)),
        ]
        let ids = BillsLogic.frequentCategoryIDs(rows, kind: .expense)
        #expect(ids == [stableID("午餐"), stableID("购物"), stableID("交通")])
    }

    @Test func frequentCategoriesRespectLimitKindAndExclusions() {
        let d = makeDate(2026, 10, 1)
        var rows: [EntryRow] = []
        for (i, name) in ["甲", "乙", "丙", "丁", "戊", "己"].enumerated() {
            rows.append(makeRow(cents: 1, on: d, top: name, createdAt: makeDate(2026, 10, 1, i, 0)))
        }
        rows.append(makeRow(cents: 1, kind: .income, on: d, top: "工资", createdAt: makeDate(2026, 10, 2)))

        let limited = BillsLogic.frequentCategoryIDs(rows, kind: .expense, limit: 3)
        #expect(limited.count == 3)
        #expect(!limited.contains(stableID("工资")))

        let excluded = BillsLogic.frequentCategoryIDs(rows, kind: .expense, excluding: [stableID("己")], limit: 10)
        #expect(!excluded.contains(stableID("己")))
        #expect(excluded.count == 5)
    }

    @Test func frequentCategoriesSkipEntriesWithoutACategory() {
        let row = EntryRow(
            date: makeDate(2026, 10, 1), kind: .expense, cents: 1,
            topCategoryID: nil, topCategoryName: Uncategorized.name, topColorHex: Uncategorized.colorHex
        )
        #expect(BillsLogic.frequentCategoryIDs([row], kind: .expense).isEmpty)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `cd Packages/HappySpendingCore && swift test --filter BillsLogicTests`
Expected: 编译失败,报 `cannot find 'BillsLogic' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/BillsLogic.swift`:

```swift
import Foundation

public struct DayGroup: Equatable, Identifiable, Sendable {
    public let day: Date
    public let rows: [EntryRow]
    public let incomeCents: Int
    public let expenseCents: Int
    public var id: Date { day }
}

public enum BillsLogic {
    /// 按天分组,日期新的在前;同一天内后创建的在前。
    public static func groupByDay(_ rows: [EntryRow], calendar: Calendar) -> [DayGroup] {
        Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
            .map { day, members in
                DayGroup(
                    day: day,
                    rows: members.sorted { $0.createdAt > $1.createdAt },
                    incomeCents: members.filter { $0.kind == .income }.reduce(0) { $0 + $1.cents },
                    expenseCents: members.filter { $0.kind == .expense }.reduce(0) { $0 + $1.cents }
                )
            }
            .sorted { $0.day > $1.day }
    }

    /// "10月10日 周六"
    public static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: day)
    }

    /// 在备注、一级分类名、二级分类名里做不区分大小写的包含匹配。空查询返回全部。
    public static func search(_ rows: [EntryRow], query: String) -> [EntryRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            [row.note, row.topCategoryName, row.subCategoryName ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// 最近 `window` 笔同类型账单里用得最多的分类(叶子分类:有二级用二级,否则用一级)。
    /// 次数相同时,最近用过的在前。
    public static func frequentCategoryIDs(
        _ rows: [EntryRow],
        kind: EntryKind,
        excluding: Set<UUID> = [],
        limit: Int = 5,
        window: Int = 200
    ) -> [UUID] {
        let recent = rows
            .filter { $0.kind == kind }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(window)

        var stats: [UUID: (count: Int, latest: Date)] = [:]
        for row in recent {
            guard let id = row.subCategoryID ?? row.topCategoryID, !excluding.contains(id) else { continue }
            let current = stats[id]
            stats[id] = (
                count: (current?.count ?? 0) + 1,
                latest: max(current?.latest ?? .distantPast, row.createdAt)
            )
        }
        return stats
            .sorted { lhs, rhs in
                lhs.value.count != rhs.value.count
                    ? lhs.value.count > rhs.value.count
                    : lhs.value.latest > rhs.value.latest
            }
            .prefix(limit)
            .map(\.key)
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `cd Packages/HappySpendingCore && swift test --filter BillsLogicTests`
Expected: 9 个测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add bills grouping, search and frequent categories"
```

---

### Task 7: CSV 导出

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/CSVExporter.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CSVExporterTests.swift`

**Interfaces:**
- Consumes: `EntryRow`、`Money.plain`、`Period`(Task 1、5)
- Produces: `enum CSVExporter`:`header: [String]`、`csv(_ rows: [EntryRow], calendar: Calendar) -> Data`(UTF-8 带 BOM,CRLF 换行)、`fileName(for period: Period?, calendar: Calendar) -> String`(`nil` 表示全部)

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/CSVExporterTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct CSVExporterTests {
    private let cal = testCalendar
    private let headerLine = "日期,类型,金额,一级分类,二级分类,备注"

    /// 去掉 BOM 后的正文。
    private func body(_ rows: [EntryRow]) -> String {
        let text = String(decoding: CSVExporter.csv(rows, calendar: cal), as: UTF8.self)
        return String(text.dropFirst())
    }

    @Test func startsWithUTF8BOM() {
        let data = CSVExporter.csv([], calendar: cal)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
    }

    @Test func emptyExportIsJustTheHeader() {
        #expect(body([]) == headerLine + "\r\n")
    }

    @Test func rowMatchesTheDocumentedFormat() {
        let row = makeRow(
            cents: 2350, on: makeDate(2026, 10, 10),
            top: "餐饮", sub: "午餐", note: "牛肉面, 加蛋"
        )
        #expect(body([row]) == headerLine + "\r\n" + "2026-10-10,支出,23.50,餐饮,午餐,\"牛肉面, 加蛋\"\r\n")
    }

    @Test func incomeAndMissingSubcategoryAreWritten() {
        let row = makeRow(cents: 500000, kind: .income, on: makeDate(2026, 10, 1), top: "工资")
        #expect(body([row]) == headerLine + "\r\n" + "2026-10-01,收入,5000.00,工资,,\r\n")
    }

    @Test func quotesAreDoubled() {
        let row = makeRow(cents: 100, on: makeDate(2026, 10, 10), note: "他说\"好\"")
        #expect(body([row]).hasSuffix("2026-10-10,支出,1.00,餐饮,,\"他说\"\"好\"\"\"\r\n"))
    }

    @Test func newlinesInNotesStayInsideTheirField() {
        let lf = makeRow(cents: 100, on: makeDate(2026, 10, 10), note: "第一行\n第二行")
        #expect(body([lf]).hasSuffix("2026-10-10,支出,1.00,餐饮,,\"第一行\n第二行\"\r\n"))

        let crlf = makeRow(cents: 100, on: makeDate(2026, 10, 10), note: "a\r\nb")
        #expect(body([crlf]).hasSuffix("2026-10-10,支出,1.00,餐饮,,\"a\r\nb\"\r\n"))
    }

    @Test func emojiAndChineseSurviveTheRoundTrip() {
        let row = makeRow(cents: 100, on: makeDate(2026, 10, 10), top: "餐饮", note: "奶茶🧋 好喝")
        #expect(body([row]).contains("奶茶🧋 好喝"))
    }

    @Test func uncategorizedEntriesAreExportedWithThatName() {
        let row = EntryRow(
            date: makeDate(2026, 10, 10), kind: .expense, cents: 100,
            topCategoryID: nil, topCategoryName: Uncategorized.name, topColorHex: Uncategorized.colorHex
        )
        #expect(body([row]).contains("2026-10-10,支出,1.00,未分类,,"))
    }

    @Test func rowsAreExportedOldestFirst() {
        let later = makeRow(cents: 200, on: makeDate(2026, 10, 12))
        let earlier = makeRow(cents: 100, on: makeDate(2026, 10, 3))
        let lines = body([later, earlier]).components(separatedBy: "\r\n")
        #expect(lines[1].hasPrefix("2026-10-03"))
        #expect(lines[2].hasPrefix("2026-10-12"))
    }

    @Test func fileNamesDescribeTheScope() {
        #expect(CSVExporter.fileName(for: nil, calendar: cal) == "happy_spending-all.csv")
        #expect(CSVExporter.fileName(for: .month(makeDate(2026, 10, 15)), calendar: cal) == "happy_spending-2026-10.csv")
        #expect(CSVExporter.fileName(for: .year(2026), calendar: cal) == "happy_spending-2026.csv")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `cd Packages/HappySpendingCore && swift test --filter CSVExporterTests`
Expected: 编译失败,报 `cannot find 'CSVExporter' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/CSVExporter.swift`:

```swift
import Foundation

public enum CSVExporter {
    public static let header = ["日期", "类型", "金额", "一级分类", "二级分类", "备注"]

    /// UTF-8 带 BOM,RFC 4180 转义,CRLF 换行;按日期从旧到新排列。
    public static func csv(_ rows: [EntryRow], calendar: Calendar = .current) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let ordered = rows.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        var lines = [header.joined(separator: ",")]
        for row in ordered {
            let fields = [
                formatter.string(from: row.date),
                row.kind.title,
                Money.plain(row.cents),
                row.topCategoryName,
                row.subCategoryName ?? "",
                row.note,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        return Data(("\u{FEFF}" + text).utf8)
    }

    /// `nil` 表示导出全部。
    public static func fileName(for period: Period?, calendar: Calendar = .current) -> String {
        switch period {
        case nil:
            return "happy_spending-all.csv"
        case .month(let date)?:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM"
            return "happy_spending-\(formatter.string(from: date)).csv"
        case .year(let year)?:
            return "happy_spending-\(year).csv"
        }
    }

    private static let specialScalars: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]

    /// 注意要按 Unicode 标量判断:"\r\n" 在 Swift 里是单个 Character,不会等于 "\n"。
    static func escape(_ field: String) -> String {
        guard field.unicodeScalars.contains(where: specialScalars.contains) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `cd Packages/HappySpendingCore && swift test --filter CSVExporterTests`
Expected: 10 个测试全部 PASS。

- [ ] **Step 5: 跑一遍 Core 全部测试并提交**

Run: `cd Packages/HappySpendingCore && swift test`
Expected: 全部 PASS(Money 4 + CategoryRules 8 + AmountInput 13 + RowMapping 4 + Statistics 17 + BillsLogic 9 + CSV 10)。

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add CSV exporter"
```

---

### Task 8: 记账页(界面)

**Files:**
- Modify: `HappySpending/HappySpendingApp.swift`(接入 SwiftData、写入预置分类)
- Replace: `HappySpending/Record/RecordView.swift`
- Create: `HappySpending/Record/EntryFormState.swift`
- Create: `HappySpending/Record/EntryFormView.swift`
- Create: `HappySpending/Record/CategoryPicker.swift`
- Create: `HappySpending/Record/NumericKeypad.swift`
- Create: `HappySpending/Support/Color+Hex.swift`
- Create: `HappySpending/Support/ToastView.swift`

**Interfaces:**
- Consumes: `LedgerEntry`、`LedgerCategory`、`DefaultCategories.seedIfNeeded`、`AmountInput`、`KeypadKey`、`BillsLogic.frequentCategoryIDs`、`EntryKind`(Core)
- Produces:
  - `struct EntryFormState: Equatable`:`kind`、`amount: AmountInput`、`categoryID: UUID?`、`date`、`note`、`canSave`、`resetAfterSave()`、`init(entry: LedgerEntry)`
  - `struct EntryFormView: View`:`init(form: Binding<EntryFormState>, categories: [LedgerCategory], frequentIDs: [UUID], saveTitle: String, onSave: () -> Void)`(Task 9 的编辑页复用)
  - `struct ToastView: View`:`init(text: String, actionTitle: String? = nil, action: (() -> Void)? = nil)`
  - `Color(hex:)`

界面部分没有自动化测试;验证方式是编译通过 + 手动清单(Task 11)。API 名字若与 SDK 不符(例如 `.glassProminent`),以 Xcode 26.5 SDK 的编译报错为准修正。

- [ ] **Step 1: 工具类**

Create `HappySpending/Support/Color+Hex.swift`:

```swift
import SwiftUI

extension Color {
    /// 支持 "#RRGGBB" 或 "RRGGBB"。
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
```

Create `HappySpending/Support/ToastView.swift`:

```swift
import SwiftUI

struct ToastView: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Text(text)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 8)
    }
}
```

- [ ] **Step 2: 表单状态**

Create `HappySpending/Record/EntryFormState.swift`:

```swift
import Foundation
import HappySpendingCore

struct EntryFormState: Equatable {
    var kind: EntryKind = .expense
    var amount = AmountInput()
    var categoryID: UUID?
    var date: Date = .now
    var note: String = ""

    var canSave: Bool { amount.isValid }

    init() {}

    init(entry: LedgerEntry) {
        kind = entry.kind
        amount = AmountInput(cents: entry.amountInCents)
        categoryID = entry.category?.id
        date = entry.date
        note = entry.note
    }

    /// 连续记账:只清空金额和备注,保留类型、分类和日期。
    mutating func resetAfterSave() {
        amount = AmountInput()
        note = ""
    }
}
```

- [ ] **Step 3: 数字键盘**

Create `HappySpending/Record/NumericKeypad.swift`:

```swift
import SwiftUI
import HappySpendingCore

struct NumericKeypad: View {
    let saveTitle: String
    let canSave: Bool
    let onKey: (KeypadKey) -> Void
    let onSave: () -> Void

    private let rows: [[KeypadKey]] = [
        [.digit(7), .digit(8), .digit(9)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(1), .digit(2), .digit(3)],
        [.dot, .digit(0), .backspace],
    ]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 8) {
                            ForEach(rows[r], id: \.self) { key in
                                Button { onKey(key) } label: {
                                    keyLabel(key)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
                Button(action: onSave) {
                    Text(saveTitle)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSave)
                .frame(width: 84)
            }
        }
        .frame(height: 4 * 54 + 3 * 8)
    }

    @ViewBuilder
    private func keyLabel(_ key: KeypadKey) -> some View {
        switch key {
        case .digit(let d): Text("\(d)").font(.title2.weight(.medium))
        case .dot: Text(".").font(.title2.weight(.medium))
        case .backspace: Image(systemName: "delete.left").font(.title3)
        }
    }
}
```

- [ ] **Step 4: 分类选择**

Create `HappySpending/Record/CategoryPicker.swift`:

```swift
import SwiftUI
import HappySpendingCore

struct CategoryPicker: View {
    let kind: EntryKind
    let categories: [LedgerCategory]
    let frequentIDs: [UUID]
    @Binding var selectedID: UUID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var tops: [LedgerCategory] {
        categories
            .filter { $0.kind == kind && $0.parent == nil && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var selected: LedgerCategory? { categories.first { $0.id == selectedID } }
    private var selectedTop: LedgerCategory? { selected?.parent ?? selected }
    private var subs: [LedgerCategory] {
        (selectedTop?.children ?? [])
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var frequent: [LedgerCategory] {
        frequentIDs.compactMap { id in categories.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !frequent.isEmpty {
                Text("常用").font(.caption).foregroundStyle(.secondary)
                chipRow(frequent)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tops, id: \.id) { top in topCell(top) }
            }
            if !subs.isEmpty {
                chipRow(subs)
            }
        }
    }

    private func topCell(_ top: LedgerCategory) -> some View {
        let color = Color(hex: top.colorHex)
        let isSelected = selectedTop?.id == top.id
        return Button { selectedID = top.id } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(color.opacity(0.18))
                    Image(systemName: top.symbolName).font(.title3).foregroundStyle(color)
                }
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(color, lineWidth: isSelected ? 2.5 : 0))
                Text(top.name).font(.caption).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func chipRow(_ items: [LedgerCategory]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let color = Color(hex: item.colorHex)
                    let isSelected = selectedID == item.id
                    Button { selectedID = item.id } label: {
                        Text(item.displayName)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(color.opacity(isSelected ? 0.28 : 0.10)))
                            .overlay(Capsule().stroke(color, lineWidth: isSelected ? 1.5 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 5: 表单视图(记账页和编辑页共用)**

Create `HappySpending/Record/EntryFormView.swift`:

```swift
import SwiftUI
import HappySpendingCore

struct EntryFormView: View {
    @Binding var form: EntryFormState
    let categories: [LedgerCategory]
    let frequentIDs: [UUID]
    let saveTitle: String
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("类型", selection: $form.kind) {
                ForEach(EntryKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(form.amount.displayText)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())

            ScrollView {
                CategoryPicker(
                    kind: form.kind,
                    categories: categories,
                    frequentIDs: frequentIDs,
                    selectedID: $form.categoryID
                )
            }

            HStack(spacing: 8) {
                DatePicker("日期", selection: $form.date, displayedComponents: .date)
                    .labelsHidden()
                Button("今天") { form.date = .now }
                Button("昨天") { form.date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now }
                Spacer()
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            TextField("备注(可选)", text: $form.note)
                .textFieldStyle(.roundedBorder)

            NumericKeypad(
                saveTitle: saveTitle,
                canSave: form.canSave,
                onKey: { form.amount.press($0) },
                onSave: onSave
            )
        }
    }
}
```

- [ ] **Step 6: 记账页**

Replace `HappySpending/Record/RecordView.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct RecordView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \LedgerEntry.createdAt, order: .reverse) private var entries: [LedgerEntry]

    @State private var form = EntryFormState()
    @State private var savedCount = 0
    @State private var showToast = false
    @State private var errorMessage: String?

    private var archivedIDs: Set<UUID> {
        Set(categories.filter(\.isArchived).map(\.id))
    }

    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            entries.prefix(300).map(\.row),
            kind: form.kind,
            excluding: archivedIDs
        )
    }

    var body: some View {
        EntryFormView(
            form: $form,
            categories: categories,
            frequentIDs: frequentIDs,
            saveTitle: "完成",
            onSave: save
        )
        .padding(.horizontal)
        .overlay(alignment: .top) {
            if showToast {
                ToastView(text: "已记一笔")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear(perform: ensureCategory)
        .onChange(of: form.kind) { ensureCategory() }
        .onChange(of: categories.count) { ensureCategory() }
        .alert("保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// 确保选中的分类属于当前类型且未归档;否则回到上次用过的分类,再不行就取第一个一级分类。
    private func ensureCategory() {
        let active = categories.filter { !$0.isArchived && $0.kind == form.kind }
        if let id = form.categoryID, active.contains(where: { $0.id == id }) { return }
        let lastUsed = entries.first {
            $0.kind == form.kind && $0.category.map { !$0.isArchived } == true
        }?.category
        form.categoryID = (lastUsed ?? active.first { $0.parent == nil })?.id
    }

    private func save() {
        guard form.amount.isValid else { return }
        let category = categories.first { $0.id == form.categoryID }
        let entry = LedgerEntry(
            amountInCents: form.amount.cents,
            kind: form.kind,
            date: form.date,
            note: form.note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            errorMessage = error.localizedDescription
            return
        }
        form.resetAfterSave()
        savedCount += 1
        withAnimation { showToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showToast = false }
        }
    }
}
```

- [ ] **Step 7: 接入 SwiftData 与预置分类**

Replace `HappySpending/HappySpendingApp.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

@main
struct HappySpendingApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: LedgerCategory.self, LedgerEntry.self)
            try DefaultCategories.seedIfNeeded(in: container.mainContext)
        } catch {
            fatalError("无法初始化数据存储:\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 8: 编译**

Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | head -20
```

Expected: `** BUILD SUCCEEDED **`,无 `error:`。

- [ ] **Step 9: 手动检查(有模拟器或真机时)**

按 `docs/manual-test-checklist.md`(Task 11 创建)里"记账页"一节检查。暂时没有运行环境时,跳过并在最终报告中如实说明。

- [ ] **Step 10: 提交**

```bash
git add HappySpending
git commit -m "feat: add record screen with custom keypad and category picker"
```

---

### Task 9: 账单页(界面)

**Files:**
- Replace: `HappySpending/Bills/BillsView.swift`
- Create: `HappySpending/Bills/EntryRowView.swift`
- Create: `HappySpending/Bills/EntryEditSheet.swift`
- Create: `HappySpending/Bills/CSVFile.swift`
- Create: `HappySpending/Support/PeriodSwitcher.swift`

**Interfaces:**
- Consumes: Task 8 的 `EntryFormState`、`EntryFormView`、`ToastView`、`Color(hex:)`;Core 的 `EntryRow`、`Period`、`BillsLogic`、`Statistics.summary`、`CSVExporter`、`Money`
- Produces: `PeriodSwitcher(title:onPrevious:onNext:)`(Task 10 复用)

- [ ] **Step 1: 周期切换器**

Create `HappySpending/Support/PeriodSwitcher.swift`:

```swift
import SwiftUI

struct PeriodSwitcher: View {
    let title: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) { Image(systemName: "chevron.left") }
                .buttonStyle(.glass)
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button(action: onNext) { Image(systemName: "chevron.right") }
                .buttonStyle(.glass)
        }
    }
}
```

- [ ] **Step 2: 账单行**

Create `HappySpending/Bills/EntryRowView.swift`:

```swift
import SwiftUI
import HappySpendingCore

struct EntryRowView: View {
    let row: EntryRow

    var body: some View {
        let color = Color(hex: row.topColorHex)
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay(Circle().fill(color).frame(width: 12, height: 12))
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

- [ ] **Step 3: 导出文件(给 ShareLink)**

Create `HappySpending/Bills/CSVFile.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers
import HappySpendingCore

struct CSVFile: Transferable {
    let name: String
    let rows: [EntryRow]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try CSVExporter.csv(file.rows).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
```

- [ ] **Step 4: 编辑页**

Create `HappySpending/Bills/EntryEditSheet.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct EntryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let entry: LedgerEntry
    let categories: [LedgerCategory]
    let frequentIDs: [UUID]

    @State private var form: EntryFormState
    @State private var errorMessage: String?

    init(entry: LedgerEntry, categories: [LedgerCategory], frequentIDs: [UUID]) {
        self.entry = entry
        self.categories = categories
        self.frequentIDs = frequentIDs
        _form = State(initialValue: EntryFormState(entry: entry))
    }

    var body: some View {
        NavigationStack {
            EntryFormView(
                form: $form,
                categories: categories,
                frequentIDs: frequentIDs,
                saveTitle: "保存",
                onSave: apply
            )
            .padding(.horizontal)
            .navigationTitle("编辑账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func apply() {
        guard form.amount.isValid else { return }
        entry.amountInCents = form.amount.cents
        entry.kind = form.kind
        entry.date = Calendar.current.startOfDay(for: form.date)
        entry.note = form.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.category = categories.first { $0.id == form.categoryID }
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: 账单页**

Replace `HappySpending/Bills/BillsView.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

/// 删除前的快照,用于"撤销"。
private struct DeletedEntry: Equatable {
    let id: UUID
    let amountInCents: Int
    let kind: EntryKind
    let date: Date
    let createdAt: Date
    let note: String
    let categoryID: UUID?

    init(_ entry: LedgerEntry) {
        id = entry.id
        amountInCents = entry.amountInCents
        kind = entry.kind
        date = entry.date
        createdAt = entry.createdAt
        note = entry.note
        categoryID = entry.category?.id
    }
}

struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var month = Date.now
    @State private var query = ""
    @State private var editing: LedgerEntry?
    @State private var undo: DeletedEntry?
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    private var allRows: [EntryRow] { entries.map(\.row) }
    private var monthRows: [EntryRow] { Period.month(month).filter(allRows, calendar: calendar) }
    private var groups: [DayGroup] {
        BillsLogic.groupByDay(BillsLogic.search(monthRows, query: query), calendar: calendar)
    }
    private var summary: PeriodSummary { Statistics.summary(monthRows) }
    private var entriesByID: [UUID: LedgerEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }
    private var monthTitle: String {
        month.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN")))
    }
    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            allRows, kind: editing?.kind ?? .expense,
            excluding: Set(categories.filter(\.isArchived).map(\.id))
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PeriodSwitcher(
                        title: monthTitle,
                        onPrevious: { shiftMonth(-1) },
                        onNext: { shiftMonth(1) }
                    )
                    .listRowBackground(Color.clear)
                    summaryRow
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            EntryRowView(row: row)
                                .onTapGesture { editing = entriesByID[row.id] }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("删除", role: .destructive) {
                                        if let entry = entriesByID[row.id] { delete(entry) }
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(BillsLogic.dayTitle(group.day, calendar: calendar))
                            Spacer()
                            Text(daySubtotal(group)).monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if monthRows.isEmpty {
                    ContentUnavailableView("本月还没有账单", systemImage: "tray")
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("账单")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索备注或分类")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(
                            item: CSVFile(
                                name: CSVExporter.fileName(for: .month(month), calendar: calendar),
                                rows: monthRows
                            ),
                            preview: SharePreview("导出 \(monthTitle)")
                        ) { Label("导出当月 CSV", systemImage: "calendar") }
                        ShareLink(
                            item: CSVFile(
                                name: CSVExporter.fileName(for: nil, calendar: calendar),
                                rows: allRows
                            ),
                            preview: SharePreview("导出全部账单")
                        ) { Label("导出全部 CSV", systemImage: "tray.full") }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                }
            }
            .sheet(item: $editing) { entry in
                EntryEditSheet(entry: entry, categories: categories, frequentIDs: frequentIDs)
            }
            .overlay(alignment: .bottom) {
                if let undo {
                    ToastView(text: "已删除一笔", actionTitle: "撤销") { restore(undo) }
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var summaryRow: some View {
        HStack {
            summaryCell("收入", summary.incomeCents, .green)
            summaryCell("支出", summary.expenseCents, .primary)
            summaryCell("结余", summary.balanceCents, .primary)
        }
    }

    private func summaryCell(_ title: String, _ cents: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.display(cents)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func daySubtotal(_ group: DayGroup) -> String {
        var parts: [String] = []
        if group.expenseCents > 0 { parts.append("支出 " + Money.display(group.expenseCents)) }
        if group.incomeCents > 0 { parts.append("收入 " + Money.display(group.incomeCents)) }
        return parts.joined(separator: "  ")
    }

    private func shiftMonth(_ delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func delete(_ entry: LedgerEntry) {
        let snapshot = DeletedEntry(entry)
        context.delete(entry)
        guard persist() else { return }
        withAnimation { undo = snapshot }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undo == snapshot { withAnimation { undo = nil } }
        }
    }

    private func restore(_ snapshot: DeletedEntry) {
        let entry = LedgerEntry(
            id: snapshot.id,
            amountInCents: snapshot.amountInCents,
            kind: snapshot.kind,
            date: snapshot.date,
            note: snapshot.note,
            category: categories.first { $0.id == snapshot.categoryID },
            createdAt: snapshot.createdAt
        )
        context.insert(entry)
        _ = persist()
        withAnimation { undo = nil }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 6: 编译**

Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | head -20
```

Expected: `** BUILD SUCCEEDED **`。
常见需要修的点:`.sheet(item:)` 要求 `LedgerEntry: Identifiable`——`@Model` 类型自带 `Identifiable`,若编译器提示歧义(自定义的 `id: UUID` 与默认实现),改为 `.sheet(isPresented:)` 加 `@State var editing` 的可选绑定。

- [ ] **Step 7: 提交**

```bash
git add HappySpending
git commit -m "feat: add bills screen with month paging, search, edit, undo delete and CSV export"
```

---

### Task 10: 统计页(Liquid Glass)

**Files:**
- Replace: `HappySpending/Stats/StatsView.swift`
- Create: `HappySpending/Stats/StatsBackground.swift`
- Create: `HappySpending/Stats/SummaryCard.swift`
- Create: `HappySpending/Stats/SharesSection.swift`
- Create: `HappySpending/Stats/TrendSection.swift`
- Create: `HappySpending/Stats/CategoryDetailView.swift`

**Interfaces:**
- Consumes: `PeriodSwitcher`、`Color(hex:)`(Task 8、9);Core 的 `Period`、`Statistics`、`PeriodSummary`、`CategoryShare`、`TrendPoint`、`Money`

设计原则:图表(内容)保持高饱和、边界清晰、直接放在渐变背景上;玻璃只用于浮在内容之上的汇总卡片和周期控制条。

- [ ] **Step 1: 背景**

Create `HappySpending/Stats/StatsBackground.swift`:

```swift
import SwiftUI

/// 给玻璃层提供可折射的彩色内容。
struct StatsBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.35), Color.teal.opacity(0.25), Color.pink.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.orange.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: -120, y: -220)
            Circle()
                .fill(Color.blue.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: 140, y: 120)
        }
        .background(Color(.systemBackground))
    }
}
```

- [ ] **Step 2: 汇总卡片**

Create `HappySpending/Stats/SummaryCard.swift`:

```swift
import SwiftUI
import HappySpendingCore

struct SummaryCard: View {
    let summary: PeriodSummary

    var body: some View {
        HStack {
            cell("收入", summary.incomeCents, .green)
            cell("支出", summary.expenseCents, .primary)
            cell("结余", summary.balanceCents, .primary)
        }
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func cell(_ title: String, _ cents: Int, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.display(cents))
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 3: 分类占比(环形图 + 列表)**

Create `HappySpending/Stats/SharesSection.swift`:

```swift
import SwiftUI
import Charts
import HappySpendingCore

struct SharesSection: View {
    let title: String
    let shares: [CategoryShare]

    private var total: Int { shares.reduce(0) { $0 + $1.cents } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if shares.isEmpty {
                Text("暂无数据").foregroundStyle(.secondary)
            } else {
                Chart(shares) { share in
                    SectorMark(
                        angle: .value("金额", share.cents),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(Color(hex: share.colorHex))
                }
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 2) {
                        Text("合计").font(.caption).foregroundStyle(.secondary)
                        Text(Money.display(total)).font(.title3.weight(.semibold).monospacedDigit())
                    }
                }

                VStack(spacing: 0) {
                    ForEach(shares) { share in
                        NavigationLink(value: share) {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: share.colorHex)).frame(width: 10, height: 10)
                                Text(share.name)
                                Spacer()
                                Text(share.fraction.formatted(.percent.precision(.fractionLength(1))))
                                    .foregroundStyle(.secondary)
                                Text(Money.display(share.cents)).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: 趋势图**

Create `HappySpending/Stats/TrendSection.swift`:

```swift
import SwiftUI
import Charts
import HappySpendingCore

enum StatsScope: String, CaseIterable, Identifiable {
    case month = "月"
    case year = "年"
    var id: String { rawValue }
}

struct TrendSection: View {
    let points: [TrendPoint]
    let scope: StatsScope

    private var unit: Calendar.Component { scope == .month ? .day : .month }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scope == .month ? "每日支出" : "每月支出").font(.headline)
            Chart(points) { point in
                BarMark(
                    x: .value("日期", point.date, unit: unit),
                    y: .value("支出", Double(point.cents) / 100)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: unit, count: scope == .month ? 5 : 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: scope == .month
                        ? Date.FormatStyle().day()
                        : Date.FormatStyle().month(.narrow))
                }
            }
            .frame(height: 180)
        }
    }
}
```

- [ ] **Step 5: 一级分类详情**

Create `HappySpending/Stats/CategoryDetailView.swift`:

```swift
import SwiftUI
import HappySpendingCore

struct CategoryDetailView: View {
    let share: CategoryShare

    var body: some View {
        List {
            Section {
                HStack {
                    Text("合计")
                    Spacer()
                    Text(Money.display(share.cents)).monospacedDigit()
                }
            }
            Section("二级分类") {
                ForEach(share.children) { child in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(child.name)
                            Spacer()
                            Text(Money.display(child.cents)).monospacedDigit()
                        }
                        ProgressView(value: child.fraction)
                            .tint(Color(hex: share.colorHex))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(share.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 6: 统计页**

Replace `HappySpending/Stats/StatsView.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct StatsView: View {
    @Query(sort: \LedgerEntry.date) private var entries: [LedgerEntry]
    @State private var scope: StatsScope = .month
    @State private var anchor = Date.now

    private let calendar = Calendar.current

    private var year: Int { calendar.component(.year, from: anchor) }
    private var period: Period { scope == .month ? .month(anchor) : .year(year) }
    private var rows: [EntryRow] { period.filter(entries.map(\.row), calendar: calendar) }
    private var title: String {
        scope == .month
            ? anchor.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN")))
            : "\(year)年"
    }
    private var trend: [TrendPoint] {
        scope == .month
            ? Statistics.dailyTrend(rows, month: anchor, calendar: calendar)
            : Statistics.monthlyTrend(rows, year: year, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StatsBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        controls
                        SummaryCard(summary: Statistics.summary(rows))
                        if rows.isEmpty {
                            ContentUnavailableView("这段时间还没有账单", systemImage: "chart.pie")
                        } else {
                            SharesSection(title: "支出分类", shares: Statistics.shares(rows, kind: .expense))
                            TrendSection(points: trend, scope: scope)
                            DisclosureGroup("收入分类") {
                                SharesSection(title: "", shares: Statistics.shares(rows, kind: .income))
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CategoryShare.self) { CategoryDetailView(share: $0) }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Picker("周期", selection: $scope) {
                    ForEach(StatsScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                PeriodSwitcher(title: title, onPrevious: { shift(-1) }, onNext: { shift(1) })
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    private func shift(_ delta: Int) {
        let component: Calendar.Component = scope == .month ? .month : .year
        anchor = calendar.date(byAdding: component, value: delta, to: anchor) ?? anchor
    }
}
```

- [ ] **Step 7: 编译**

Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | head -20
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 8: 提交**

```bash
git add HappySpending
git commit -m "feat: add stats screen with donut, trend chart and Liquid Glass styling"
```

---

### Task 11: 手动检查清单、README 与最终验证

**Files:**
- Create: `docs/manual-test-checklist.md`
- Create: `README.md`

- [ ] **Step 1: 写手动检查清单**

Create `docs/manual-test-checklist.md`:

```markdown
# 手动检查清单

界面部分没有自动化 UI 测试,每次改动界面后按此清单在模拟器或真机上过一遍。

## 首次启动
- [ ] 打开后默认在"记账"Tab,支出分类里有餐饮、交通、购物、居住、娱乐、医疗、其他
- [ ] 切到"收入",分类是工资、奖金、其他收入
- [ ] 杀掉 app 重开,分类没有重复

## 记账页
- [ ] 输入 `12.34`,显示 `¥12.34`;第三位小数按不动
- [ ] 先按 `.` 显示 `¥0.`;连按两次 `.` 只有一个小数点
- [ ] 连按 `0` 不出现 `000`;整数部分最多 7 位
- [ ] 金额为 0 时"完成"不可点
- [ ] 点"完成":轻震动、出现"已记一笔"、金额和备注清空,类型/分类/日期保留
- [ ] 点"餐饮"后下方展开二级分类;只选"餐饮"不选二级也能保存
- [ ] 记过几笔后,"常用"一行出现用得最多的分类
- [ ] 点"昨天",保存后账单页该笔在昨天;再记一笔日期仍是昨天
- [ ] 数字键盘、"完成"按钮是玻璃质感

## 账单页
- [ ] 顶部汇总的收入/支出/结余与列表一致
- [ ] 左右箭头切换月份,没数据的月份显示"本月还没有账单"
- [ ] 同一天的账单在一组,组标题形如"10月10日 周六"
- [ ] 点一笔进入编辑,改金额/分类/日期/备注后保存生效
- [ ] 左滑删除,底部出现"撤销";点撤销后账单恢复,不点则几秒后消失
- [ ] 搜索备注、一级分类名、二级分类名都能命中
- [ ] 右上角菜单:导出当月、导出全部都能调出系统分享面板
- [ ] 把导出的 CSV 用 Numbers 或 Excel 打开,中文不乱码,表头为"日期,类型,金额,一级分类,二级分类,备注"

## 统计页
- [ ] 月/年切换有效,左右箭头翻页
- [ ] 汇总卡片和周期控制条是玻璃质感,背景渐变能透出来
- [ ] 环形图颜色与分类颜色一致,点列表行进入二级分类详情
- [ ] 趋势图:月视图横轴是日,年视图横轴是 12 个月
- [ ] 没有账单的周期显示空状态,不闪退、不出现 NaN

## 深色模式
- [ ] 三个 Tab 在深色模式下文字清晰、玻璃效果正常
```

- [ ] **Step 2: 写 README**

Create `README.md`:

````markdown
# happy_spending

无广告、免费、干净的 iOS 记账 app(iOS 26+,SwiftUI + SwiftData)。

- 设计文档:`docs/superpowers/specs/2026-10-10-bookkeeping-app-design.md`
- 实现计划:`docs/superpowers/plans/2026-10-10-happy-spending-v1.md`
- 手动检查清单:`docs/manual-test-checklist.md`

## 结构

- `Packages/HappySpendingCore`:数据模型与全部可测试的逻辑(Swift Package)
- `HappySpending`:SwiftUI 界面
- `project.yml`:XcodeGen 配置,`.xcodeproj` 由它生成,不入库

## 常用命令

```bash
# 跑 Core 的全部测试(不需要模拟器)
cd Packages/HappySpendingCore && swift test

# 生成 Xcode 工程(需要 brew install xcodegen)
xcodegen generate

# 编译 App
xcodebuild -project HappySpending.xcodeproj -scheme HappySpending \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## 装到自己的 iPhone

1. `xcodegen generate` 后用 Xcode 打开 `HappySpending.xcodeproj`
2. Signing & Capabilities 里选自己的 Apple ID 团队
3. 连接 iPhone,选它为运行目标,点 Run
4. 免费账号的证书 7 天过期,过期后重新 Run 一次即可

## 在模拟器里运行

本机需要先在 Xcode → Settings → Components 下载 iOS 26 模拟器运行时。
````

- [ ] **Step 3: 最终验证**

Run(仓库根目录):

```bash
(cd Packages/HappySpendingCore && swift test 2>&1 | tail -5) && xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning:.*HappySpending|BUILD" | head -20
```

Expected: Core 测试全部通过(65 个),App `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 提交**

```bash
git add README.md docs/manual-test-checklist.md
git commit -m "docs: add README and manual test checklist"
```
