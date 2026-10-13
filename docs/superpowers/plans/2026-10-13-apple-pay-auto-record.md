# Apple Pay 自动入账 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供快捷指令动作"记一笔(Apple Pay)":付款后由"钱包交易"自动化调用,自动记一笔带"自动"标记的支出,并通过"记住我的选择"让同一商户沿用你改过的分类。

**Architecture:** 业务逻辑全部放进 `HappySpendingCore`:金额文本解析、商户归一化与记忆、`AutoEntryRecorder.record`、编辑后学习,都用 `swift test` 在 Mac 上测。app 层只做薄薄一层:全局共享的数据容器(界面和后台动作共用)、一个只转调 Core 的 `AppIntent`、账单行的"自动"标记、编辑页保存时触发学习、设置页的帮助页。

**Tech Stack:** Swift 6.3 / Xcode 26.6, SwiftData, App Intents, Swift Testing。

**Spec:** `docs/superpowers/specs/2026-10-13-apple-pay-auto-record-design.md`(上位文档:`2026-10-10-bookkeeping-app-design.md`)

## Global Constraints

- 最低系统 **iOS 26**;无后端、无网络请求、**无第三方依赖**;不申请通知、相册之外的任何新权限(这个功能不需要任何权限)。
- 只覆盖 **Apple Pay**;**不做**短信解析、微信/支付宝、收入/退款、重复检测、商户记忆管理界面、周期性账单。
- 自动账**直接入账**:类型为支出,金额为解析结果,日期是触发当天(`DayStamp.stamp`),备注 = 商户名(无商户则为空),`autoSource = applePay`,`merchant` = 商户原名(去首尾空白)。
- 金额解析:去掉首尾空白、`¥`、`￥`、`元`、`CNY`、`RMB`(不区分大小写)、所有空白和千分位逗号后按十进制解析;**四舍五入到分**;无法解析 → `invalidAmount`,小于等于 0 → `notAnExpense`,超过 `Money.maxCents`(9,999,999.99)→ `tooLarge`。
- 商户键(`merchantKey`):去首尾空白、连续空白合并为一个空格、忽略大小写。
- 分类记忆:记忆指向的分类必须存在且**未归档**(二级分类还要求其一级分类未归档),否则当作没有记忆,记为"未分类"。
- 学习只在**编辑一笔自动账**并保存时发生,且同时满足:是自动账、`merchant` 非空、保存后分类非空、与保存前分类不同。手动账从不学习。
- 新增字段都是可选的,新实体是纯新增,依靠 SwiftData 轻量迁移,已有数据不受影响。
- 动作返回结果文本(`已记 ¥25.00 · 美团`);错误用中文提示;`openAppWhenRun = false`。
- 命名沿用:`LedgerEntry`、`LedgerCategory`。
- 测试用 Swift Testing;SwiftData 测试用内存容器,**测试里必须一直持有 `ModelContainer`**(容器一释放,里面的对象就失效)。
- Core 命令都用 `swift test --package-path Packages/HappySpendingCore`;仓库根目录是 `/Users/strawturtle/Desktop/Develop/Self/Self IOS App/happy_spending`;工作在分支 `auto-record` 上。
- 提交信息末尾带上本次会话给出的 `Co-Authored-By` 署名行。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都在对应任务里有测试:

1. **金额文本的怪格式**:全角数字和全角逗号、`25.`、`.5`、`+25`、`1.2.3`、`1e3`、只有货币符号、空串。→ Task 1
2. **金额的边界**:`25.005` 进位到 `25.01`、`0.004` 舍成 0 算无效、`9999999.995` 进位后超过上限、整数部分超长到十几位。→ Task 1
3. **商户名的怪输入**:全是空白、内部有换行或多个空格、大小写和全半角空格不同的同一商户、emoji。→ Task 3、Task 4
4. **记忆指向的分类已被归档**(包括二级分类的一级分类被归档)或已不存在:记为"未分类",不报错、不崩溃。→ Task 3、Task 4
5. **学习的触发条件**:手动账不学习、没改分类不学习、没有商户不学习、同一商户再次改分类是覆盖而不是新增第二条。→ Task 3

---

### Task 1: 金额文本解析

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/AmountText.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AmountTextTests.swift`

**Interfaces:**
- Consumes: `Money.maxCents`(已有)
- Produces:
  - `enum AmountError: Error, Equatable, LocalizedError { case invalidAmount, notAnExpense, tooLarge; var message: String }`
  - `enum AmountText { static func cents(from text: String) throws -> Int }`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AmountTextTests.swift`:

```swift
import Testing
@testable import HappySpendingCore

struct AmountTextTests {
    @Test(arguments: [
        ("25", 2500),
        ("25.5", 2550),
        ("25.50", 2550),
        ("¥25.00", 2500),
        ("￥25", 2500),
        ("25元", 2500),
        ("RMB 25.5", 2550),
        ("cny25", 2500),
        ("CNY 1,234.56", 123456),
        ("1,234.56", 123456),
        ("１，２３４．５６", 123456),
        ("２５", 2500),
        ("  25.00  ", 2500),
        ("25.", 2500),
        (".5", 50),
        ("+25", 2500),
        ("0.01", 1),
        ("9999999.99", 999_999_999),
    ])
    func parsesCommonFormats(text: String, cents: Int) throws {
        #expect(try AmountText.cents(from: text) == cents)
    }

    @Test(arguments: [
        ("25.004", 2500),
        ("25.005", 2501),
        ("25.994", 2599),
        ("25.995", 2600),
        ("0.005", 1),
    ])
    func roundsToTheNearestCentHalfUp(text: String, cents: Int) throws {
        #expect(try AmountText.cents(from: text) == cents)
    }

    @Test(arguments: ["", "   ", "abc", "1.2.3", "1e3", "¥", "元", "--5", "25-", "12abc", "$25.00x"])
    func rejectsTextThatIsNotAnAmount(text: String) {
        #expect(throws: AmountError.invalidAmount) { try AmountText.cents(from: text) }
    }

    @Test(arguments: ["0", "0.00", "-5", "-0.5", "0.004", "0.001", "-0"])
    func rejectsZeroAndNegativeAmounts(text: String) {
        #expect(throws: AmountError.notAnExpense) { try AmountText.cents(from: text) }
    }

    @Test(arguments: ["10000000", "9999999.995", "1234567890123", "99999999999999999999999999999999999999"])
    func rejectsAmountsOverTheCap(text: String) {
        #expect(throws: AmountError.tooLarge) { try AmountText.cents(from: text) }
    }

    @Test func theCapItselfIsAccepted() throws {
        #expect(try AmountText.cents(from: "9999999.99") == Money.maxCents)
    }

    @Test func errorsHaveReadableChineseMessages() {
        #expect(AmountError.invalidAmount.message == "无法识别金额")
        #expect(AmountError.notAnExpense.message == "金额必须大于 0")
        #expect(AmountError.tooLarge.message == "金额超过 9,999,999.99")
        #expect(AmountError.invalidAmount.errorDescription == "无法识别金额")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter AmountTextTests`
Expected: 编译失败,报 `cannot find 'AmountText' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/AmountText.swift`:

```swift
import Foundation

public enum AmountError: Error, Equatable, LocalizedError {
    case invalidAmount
    case notAnExpense
    case tooLarge

    public var message: String {
        switch self {
        case .invalidAmount: "无法识别金额"
        case .notAnExpense: "金额必须大于 0"
        case .tooLarge: "金额超过 9,999,999.99"
        }
    }

    public var errorDescription: String? { message }
}

/// 把快捷指令传来的金额文本解析成整数分。快捷指令传出的是数字还是带符号的文本要等真机验证,
/// 所以两种都要能处理。
public enum AmountText {
    /// 最多接受的整数位数;超过它直接判为过大,避免 Decimal 溢出。
    private static let maxIntegerDigits = 12

    public static func cents(from text: String) throws -> Int {
        var s = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        for token in ["¥", "\u{FFE5}", "元", "cny", "rmb"] {
            s = s.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        s = String(s.filter { !$0.isWhitespace && $0 != "," })

        guard s.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil else {
            throw AmountError.invalidAmount
        }

        let negative = s.hasPrefix("-")
        if s.hasPrefix("+") || s.hasPrefix("-") { s.removeFirst() }
        if s.hasPrefix(".") { s = "0" + s }
        if s.hasSuffix(".") { s.removeLast() }

        let integerDigits = s.split(separator: ".", omittingEmptySubsequences: false).first?.count ?? 0
        guard integerDigits <= maxIntegerDigits else {
            throw negative ? AmountError.notAnExpense : AmountError.tooLarge
        }

        guard let decimal = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw AmountError.invalidAmount
        }

        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)

        if negative || rounded <= 0 { throw AmountError.notAnExpense }
        if rounded > Decimal(Money.maxCents) { throw AmountError.tooLarge }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(现有 131 个 + AmountText 的 7 个 = 138 个),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add amount text parsing for auto-recorded payments"
```

---

### Task 2: 自动账的数据字段与商户记忆实体

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/EntrySource.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/MerchantCategory.swift`
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerEntry.swift`
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/EntryRow.swift`
- Replace: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/Fixtures.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AutoEntryModelTests.swift`

**Interfaces:**
- Consumes: 已有的 `LedgerEntry`、`EntryRow`、`makeTestContainer()`
- Produces:
  - `enum EntrySource: String, Codable, Sendable { case applePay }`
  - `LedgerEntry.autoSourceRaw: String?`、`merchant: String?`、`autoSource: EntrySource?`(可读写)、`isAuto: Bool`;`init(... autoSource: EntrySource? = nil, merchant: String? = nil)`(新增的两个参数放在最后)
  - `@Model MerchantCategory`:`merchantKey: String`、`categoryID: UUID`、`updatedAt: Date`;`init(merchantKey:categoryID:updatedAt:)`
  - `EntryRow.isAuto: Bool`(init 里有默认值 `false`,放在最后)
  - 测试辅助 `makeTestContainer()` 的模型列表里加上 `MerchantCategory`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AutoEntryModelTests.swift`:

```swift
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
```

Replace `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/Fixtures.swift`:

```swift
import Foundation
import SwiftData
@testable import HappySpendingCore

/// 与生产代码读取账单日期时用的是同一个日历:GMT 公历,与设备时区无关。
let testCalendar = DayStamp.calendar

func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func makeTestContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter AutoEntryModelTests`
Expected: 编译失败,报 `cannot find 'MerchantCategory' in scope`(以及 `EntrySource`、`autoSource` 等)。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/EntrySource.swift`:

```swift
/// 自动账的来源。目前只有 Apple Pay;做成枚举是因为之后的周期性账单也要标记为自动。
public enum EntrySource: String, Codable, Sendable {
    case applePay
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/MerchantCategory.swift`:

```swift
import Foundation
import SwiftData

/// "记住我的选择":商户到分类的记忆。同一个 `merchantKey` 只保留一条。
@Model
public final class MerchantCategory {
    /// 归一化后的商户名,见 `MerchantKey.normalize(_:)`。
    public var merchantKey: String
    /// 指向一级或二级分类。用 ID 而不是关系,避免给分类加反向关系;使用时再按 ID 查分类。
    public var categoryID: UUID
    public var updatedAt: Date

    public init(merchantKey: String, categoryID: UUID, updatedAt: Date = .now) {
        self.merchantKey = merchantKey
        self.categoryID = categoryID
        self.updatedAt = updatedAt
    }
}
```

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerEntry.swift`:

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
    /// 空表示手动账;有值表示自动账(见 `EntrySource`)。
    public var autoSourceRaw: String?
    /// 商户原名(去首尾空白),自动账才有,作为"记住我的选择"的依据。
    public var merchant: String?

    public var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public var autoSource: EntrySource? {
        get { autoSourceRaw.flatMap(EntrySource.init(rawValue:)) }
        set { autoSourceRaw = newValue?.rawValue }
    }

    /// 以后新增了来源取值、而旧版本不认识时,仍然算自动账。
    public var isAuto: Bool { autoSourceRaw != nil }

    public init(
        id: UUID = UUID(),
        amountInCents: Int,
        kind: EntryKind,
        date: Date,
        note: String = "",
        category: LedgerCategory? = nil,
        createdAt: Date = .now,
        calendar: Calendar = .current,
        autoSource: EntrySource? = nil,
        merchant: String? = nil
    ) {
        self.id = id
        self.amountInCents = amountInCents
        self.kindRaw = kind.rawValue
        self.date = DayStamp.stamp(date, in: calendar)
        self.createdAt = createdAt
        self.note = note
        self.category = category
        self.autoSourceRaw = autoSource?.rawValue
        self.merchant = merchant
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
    /// 二级分类自己的自定义图标(没有二级分类或没上传时为 nil)。
    public let subIconData: Data?
    /// 是否是自动记下的账(账单行显示"自动"标记)。
    public let isAuto: Bool

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
        subCategoryName: String? = nil,
        subIconData: Data? = nil,
        isAuto: Bool = false
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
        self.subIconData = subIconData
        self.isAuto = isAuto
    }

    /// "餐饮 · 午餐";没有二级分类时就是 "餐饮"。
    public var displayCategory: String {
        if let subCategoryName { "\(topCategoryName) · \(subCategoryName)" } else { topCategoryName }
    }

    /// 账单行显示的自定义图标:二级分类有就用它,否则用一级分类的;都没有就是 nil(界面改用 SF Symbol)。
    public var displayIconData: Data? { subIconData ?? topIconData }
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
            subCategoryName: sub?.name,
            subIconData: sub?.iconData,
            isAuto: isAuto
        )
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(145 个),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add auto-entry fields, MerchantCategory entity and EntryRow.isAuto"
```

---

### Task 3: 商户归一化、记忆查找与编辑后学习

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/MerchantMemory.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/MerchantMemoryTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `LedgerEntry.isAuto`/`merchant`、`MerchantCategory`;已有的 `CategoryRules`、`LedgerCategory`
- Produces:
  - `enum MerchantKey { static func normalize(_ raw: String) -> String; static func trimmed(_ raw: String) -> String? }`(`trimmed` 去首尾空白,为空返回 nil)
  - `enum MerchantMemory`:
    - `static func categoryID(for merchant: String?, memory: [MerchantCategory], categories: [LedgerCategory]) -> UUID?`
    - `@discardableResult static func learn(merchant: String, categoryID: UUID, in context: ModelContext, now: Date = .now) throws -> MerchantCategory`
    - `@discardableResult static func learnFromEdit(entry: LedgerEntry, previousCategoryID: UUID?, in context: ModelContext, now: Date = .now) throws -> Bool`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/MerchantMemoryTests.swift`:

```swift
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
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter MerchantMemoryTests`
Expected: 编译失败,报 `cannot find 'MerchantKey' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/MerchantMemory.swift`:

```swift
import Foundation
import SwiftData

public enum MerchantKey {
    /// 去首尾空白、连续空白(含换行、制表符、全角空格)合并为一个空格、忽略大小写。
    public static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    /// 商户原名:只去首尾空白;为空返回 nil。
    public static func trimmed(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// "记住我的选择":商户到分类的记忆。
public enum MerchantMemory {
    /// 记忆里该商户对应的分类 ID。分类不存在、已归档、或其一级分类已归档时返回 nil。
    public static func categoryID(
        for merchant: String?,
        memory: [MerchantCategory],
        categories: [LedgerCategory]
    ) -> UUID? {
        guard let merchant else { return nil }
        let key = MerchantKey.normalize(merchant)
        guard !key.isEmpty,
              let remembered = memory.first(where: { $0.merchantKey == key }),
              let category = categories.first(where: { $0.id == remembered.categoryID }),
              !category.isArchived,
              category.parent?.isArchived != true
        else { return nil }
        return category.id
    }

    /// 记下"这个商户 → 这个分类";同一个商户已有记忆时更新,不新增第二条。
    @discardableResult
    public static func learn(
        merchant: String,
        categoryID: UUID,
        in context: ModelContext,
        now: Date = .now
    ) throws -> MerchantCategory {
        let key = MerchantKey.normalize(merchant)
        var descriptor = FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantKey == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.categoryID = categoryID
            existing.updatedAt = now
            return existing
        }
        let created = MerchantCategory(merchantKey: key, categoryID: categoryID, updatedAt: now)
        context.insert(created)
        return created
    }

    /// 编辑一笔账并改了分类后调用。只有同时满足这些条件才学习:
    /// 是自动账、商户非空、保存后分类非空、分类与保存前不同。返回是否学习了。
    @discardableResult
    public static func learnFromEdit(
        entry: LedgerEntry,
        previousCategoryID: UUID?,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Bool {
        guard entry.isAuto,
              let merchant = entry.merchant.flatMap(MerchantKey.trimmed),
              let newCategoryID = entry.category?.id,
              newCategoryID != previousCategoryID
        else { return false }
        try learn(merchant: merchant, categoryID: newCategoryID, in: context, now: now)
        return true
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(164 个),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add merchant memory lookup and learn-from-edit"
```

---

### Task 4: 记一笔(`AutoEntryRecorder`)

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/AutoEntryRecorder.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AutoEntryRecorderTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `AmountText.cents(from:)`、`AmountError`;Task 2 的 `LedgerEntry`(自动字段)、`MerchantCategory`;Task 3 的 `MerchantKey.trimmed`、`MerchantMemory.categoryID`;已有的 `Money.display`
- Produces:
  - `struct AutoEntryResult: Equatable, Sendable { let entryID: UUID; let cents: Int; let message: String }`
  - `enum AutoEntryRecorder { @discardableResult static func record(merchant: String, amountText: String, now: Date = .now, calendar: Calendar = .current, in context: ModelContext) throws -> AutoEntryResult }`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/AutoEntryRecorderTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct AutoEntryRecorderTests {
    private let now = makeDate(2026, 10, 13, 15, 30)

    private func makeFood(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        return (food, lunch)
    }

    private func entries(_ context: ModelContext) throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    @Test func recordsAnAutoExpenseWithAllFields() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try AutoEntryRecorder.record(
            merchant: "美团", amountText: "¥25.50", now: now, calendar: testCalendar, in: context
        )

        let all = try entries(context)
        #expect(all.count == 1)
        let entry = all[0]
        #expect(entry.kind == .expense)
        #expect(entry.amountInCents == 2550)
        #expect(entry.date == makeDate(2026, 10, 13))
        #expect(entry.createdAt == now)
        #expect(entry.note == "美团")
        #expect(entry.merchant == "美团")
        #expect(entry.autoSource == .applePay)
        #expect(entry.isAuto)
        #expect(entry.category == nil)
        #expect(result.entryID == entry.id)
        #expect(result.cents == 2550)
    }

    @Test func theResultMessageNamesTheAmountAndMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let withMerchant = try AutoEntryRecorder.record(
            merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context
        )
        let withoutMerchant = try AutoEntryRecorder.record(
            merchant: "  ", amountText: "1234.5", now: now, calendar: testCalendar, in: context
        )

        #expect(withMerchant.message == "已记 ¥25.00 · 美团")
        #expect(withoutMerchant.message == "已记 ¥1,234.50")
    }

    @Test func aBlankMerchantStillRecordsWithAnEmptyNoteAndNoMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(merchant: "   \n ", amountText: "9.9", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.note == "")
        #expect(entry.merchant == nil)
        #expect(entry.isAuto)
        #expect(entry.category == nil)
    }

    @Test func theMerchantIsTrimmedButOtherwiseKeptAsGiven() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(merchant: "  Star Bucks \n", amountText: "30", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.merchant == "Star Bucks")
        #expect(entry.note == "Star Bucks")
    }

    @Test func emojiMerchantsAreKept() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try AutoEntryRecorder.record(merchant: "🧋 喜茶", amountText: "18", now: now, calendar: testCalendar, in: context)

        #expect(result.message == "已记 ¥18.00 · 🧋 喜茶")
        #expect(try entries(context).first?.merchant == "🧋 喜茶")
    }

    // MARK: 分类记忆

    @Test func usesTheRememberedCategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: food.id, in: context)

        try AutoEntryRecorder.record(merchant: " 美团 ", amountText: "25", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category === food)
    }

    @Test func aRememberedSubcategoryIsUsedAsIs() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, lunch) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: lunch.id, in: context)

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category === lunch)
        #expect(entry.row.displayCategory == "餐饮 · 午餐")
    }

    @Test func withoutAMemoryTheEntryIsUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try makeFood(context)

        try AutoEntryRecorder.record(merchant: "饿了么", amountText: "25", now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category == nil)
        #expect(entry.row.topCategoryName == Uncategorized.name)
    }

    @Test func aMemoryPointingAtAnArchivedCategoryFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, _) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: food.id, in: context)
        CategoryRules.archive(food)

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func aMemoryWhoseSubcategoryParentIsArchivedFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (food, lunch) = try makeFood(context)
        try MerchantMemory.learn(merchant: "美团", categoryID: lunch.id, in: context)
        CategoryRules.archive(food)

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func aMemoryPointingAtAMissingCategoryFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try makeFood(context)
        context.insert(MerchantCategory(merchantKey: "美团", categoryID: UUID()))

        try AutoEntryRecorder.record(merchant: "美团", amountText: "25", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    // MARK: 无效金额

    @Test func invalidAmountsCreateNothing() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        #expect(throws: AmountError.invalidAmount) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "abc", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: AmountError.notAnExpense) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "-5", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: AmountError.notAnExpense) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "0", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: AmountError.tooLarge) {
            try AutoEntryRecorder.record(merchant: "美团", amountText: "10000000", now: now, calendar: testCalendar, in: context)
        }
        #expect(try entries(context).isEmpty)
    }

    @Test func eachCallCreatesItsOwnEntry() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(merchant: "星巴克", amountText: "15", now: now, calendar: testCalendar, in: context)
        try AutoEntryRecorder.record(merchant: "星巴克", amountText: "15", now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).count == 2)
    }

    @Test func theDateIsTheDayOfTheTriggerInTheGivenCalendar() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(
            merchant: "美团", amountText: "25",
            now: makeDate(2026, 12, 31, 23, 59), calendar: testCalendar, in: context
        )

        #expect(try entries(context).first?.date == makeDate(2026, 12, 31))
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter AutoEntryRecorderTests`
Expected: 编译失败,报 `cannot find 'AutoEntryRecorder' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/AutoEntryRecorder.swift`:

```swift
import Foundation
import SwiftData

public struct AutoEntryResult: Equatable, Sendable {
    public let entryID: UUID
    public let cents: Int
    /// 给快捷指令显示的一句话,例如 "已记 ¥25.00 · 美团"。
    public let message: String
}

public enum AutoEntryRecorder {
    /// 记一笔 Apple Pay 自动账:金额解析失败时抛错、不记账;分类取商户记忆里的,没有就是"未分类"。
    @discardableResult
    public static func record(
        merchant rawMerchant: String,
        amountText: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> AutoEntryResult {
        let cents = try AmountText.cents(from: amountText)
        let merchant = MerchantKey.trimmed(rawMerchant)

        let memory = try context.fetch(FetchDescriptor<MerchantCategory>())
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let categoryID = MerchantMemory.categoryID(for: merchant, memory: memory, categories: categories)
        let category = categoryID.flatMap { id in categories.first { $0.id == id } }

        let entry = LedgerEntry(
            amountInCents: cents,
            kind: .expense,
            date: now,
            note: merchant ?? "",
            category: category,
            createdAt: now,
            calendar: calendar,
            autoSource: .applePay,
            merchant: merchant
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            throw error
        }

        let suffix = merchant.map { " · \($0)" } ?? ""
        return AutoEntryResult(entryID: entry.id, cents: cents, message: "已记 \(Money.display(cents))\(suffix)")
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(178 个),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add AutoEntryRecorder for Apple Pay auto entries"
```

---

### Task 5: app 层:共享容器、快捷指令动作、"自动"标记、编辑后学习、帮助页

**Files:**
- Create: `HappySpending/SharedModelContainer.swift`
- Create: `HappySpending/Intents/RecordApplePayIntent.swift`
- Create: `HappySpending/Settings/AutoRecordHelpView.swift`
- Replace: `HappySpending/HappySpendingApp.swift`
- Replace: `HappySpending/Bills/EntryRowView.swift`
- Replace: `HappySpending/Bills/EntryEditSheet.swift`
- Replace: `HappySpending/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: Core 的 `AutoEntryRecorder.record(merchant:amountText:in:)`、`AmountError.message`、`MerchantMemory.learnFromEdit`、`EntryRow.isAuto`、`MerchantCategory`、`DefaultCategories.seedIfNeeded`
- Produces: `SharedModelContainer.shared`(主线程隔离的全局单例);快捷指令动作 `RecordApplePayIntent`;`AutoRecordHelpView`

界面和动作本身没有自动化测试(动作只转调 Core,逻辑已被测);验证方式是编译 + 检查动作元数据 + 模拟器迁移与帮助页 + 真机清单(Task 6)。

- [ ] **Step 1: 共享数据容器**

Create `HappySpending/SharedModelContainer.swift`:

```swift
import SwiftData
import HappySpendingCore

/// 全局共享的数据容器。app 界面和被快捷指令在后台唤起的动作共用它,
/// 避免同一进程里有两个容器指向同一份数据。首次创建时写入默认分类,
/// 所以全新安装后第一次就被快捷指令唤起也能正常分类。
@MainActor
enum SharedModelContainer {
    static let shared: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self
            )
            try DefaultCategories.seedIfNeeded(in: container.mainContext)
            return container
        } catch {
            fatalError("无法初始化数据存储:\(error)")
        }
    }()
}
```

Replace `HappySpending/HappySpendingApp.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

@main
struct HappySpendingApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(SharedModelContainer.shared)
    }
}
```

- [ ] **Step 2: 快捷指令动作**

Create `HappySpending/Intents/RecordApplePayIntent.swift`:

```swift
import AppIntents
import SwiftData
import HappySpendingCore

/// 在快捷指令的错误提示里显示中文原因。
struct AutoRecordError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// 快捷指令动作"记一笔(Apple Pay)"。通常由"钱包 → 交易"自动化调用。
/// 参数用文本,以便容错:快捷指令传来的金额是数字还是带符号的文本要等真机验证。
struct RecordApplePayIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔(Apple Pay)"
    static var description = IntentDescription(
        "把一笔 Apple Pay 消费记为支出。商户和金额通常来自快捷指令里“钱包 → 交易”自动化。"
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$merchant) \(\.$amount)")
    }

    @Parameter(title: "商户")
    var merchant: String

    @Parameter(title: "金额")
    var amount: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let result = try AutoEntryRecorder.record(
                merchant: merchant,
                amountText: amount,
                in: SharedModelContainer.shared.mainContext
            )
            return .result(value: result.message)
        } catch let error as AmountError {
            throw AutoRecordError(message: error.message)
        } catch {
            throw AutoRecordError(message: "保存失败:\(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 3: 账单行的"自动"标记**

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
                iconData: row.displayIconData, size: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayCategory).font(.body)
                    if row.isAuto {
                        Text("自动")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
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

- [ ] **Step 4: 编辑页保存时学习**

Replace `HappySpending/Bills/EntryEditSheet.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct EntryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let entry: LedgerEntry
    let categories: [LedgerCategory]
    let rows: [EntryRow]

    @State private var form: EntryFormState
    @State private var errorMessage: String?

    init(entry: LedgerEntry, categories: [LedgerCategory], rows: [EntryRow]) {
        self.entry = entry
        self.categories = categories
        self.rows = rows
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
            .onChange(of: form.kind) {
                form.categoryID = CategoryRules.resolveSelection(
                    current: form.categoryID, kind: form.kind,
                    categories: categories, lastUsed: nil
                )
            }
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

    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            rows, kind: form.kind,
            excluding: Set(categories.filter(\.isArchived).map(\.id))
        )
    }

    private func apply() {
        guard form.amount.isValid else { return }
        let previousCategoryID = entry.category?.id
        entry.amountInCents = form.amount.cents
        entry.kind = form.kind
        entry.date = DayStamp.stamp(form.date)
        entry.note = form.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.category = categories.first { $0.id == form.categoryID }
        do {
            // 改了自动账的分类就记住"这个商户 → 这个分类"。
            try MerchantMemory.learnFromEdit(
                entry: entry, previousCategoryID: previousCategoryID, in: context
            )
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: 帮助页与设置入口**

Create `HappySpending/Settings/AutoRecordHelpView.swift`:

```swift
import SwiftUI

struct AutoRecordHelpView: View {
    var body: some View {
        List {
            Section {
                Text("用 Apple Pay(含加入 Apple Pay 的银行卡)付款后,app 会自动记一笔支出,账单里带“自动”标记。")
            } header: {
                Text("它做什么")
            }

            Section("怎么设置(只需要一次)") {
                step(1, "打开系统的“快捷指令”app,切到底部的“自动化”。")
                step(2, "点右上角“+”,新建“个人自动化”,选择“钱包”下面的“交易”。")
                step(3, "选择要监控的卡,点“下一步”。")
                step(4, "添加操作,搜索“记一笔”,选择“记一笔(Apple Pay)”。")
                step(5, "把“商户”和“金额”两个参数分别设成触发器给出的“商户”和“金额”(点参数框,在变量里选)。")
                step(6, "在最后一页把“运行前先询问”关掉,点“完成”。")
            }

            Section {
                Text("想在记账后收到提醒:在动作后面再加一步“显示通知”,内容选“记一笔”的输出结果。")
            } header: {
                Text("可选:记账提醒")
            }

            Section("分类怎么来的") {
                Text("自动记的账先归“未分类”。你在账单里点开它、改成某个分类并保存后,app 会记住这个商户,以后同一商户的自动账会直接用这个分类。")
            }

            Section("能覆盖什么") {
                Label("Apple Pay 和加入 Apple Pay 的银行卡", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("微信支付、支付宝、直接刷实体卡:iOS 不允许 app 读取这些支付,无法自动记", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("自动入账")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.footnote.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
    }
}
```

Replace `HappySpending/Settings/SettingsView.swift`:

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
                NavigationLink {
                    AutoRecordHelpView()
                } label: {
                    Label("自动入账", systemImage: "wand.and.stars")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

- [ ] **Step 6: 编译并检查动作元数据**

Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'platform=iOS Simulator,id=DB2215EB-B088-47B2-9466-8DDD8E7C3277' -derivedDataPath .superpowers/dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: `** BUILD SUCCEEDED **`,没有 `error:`。
然后确认动作被注册进了 app 的 App Intents 元数据:

```bash
grep -a -c "RecordApplePayIntent" .superpowers/dd/Build/Products/Debug-iphonesimulator/HappySpending.app/Metadata.appintents/extract.actionsdata
```

Expected: 输出 `1`。还可以进一步确认元数据里 `RecordApplePayIntent` 的 `openAppWhenRun` 为 false、参数是 `merchant` 和 `amount`(已在临时副本里验证过)。
可能要修的点:`LocalizedStringResource` 用字符串插值构造时若编译器报错,改成 `LocalizedStringResource(stringLiteral: message)`;`static var` 若在 Swift 6 严格并发下报共享可变状态,改成 `static let`。

- [ ] **Step 7: 模拟器验证迁移与帮助页**

模拟器里现在装着上一个版本(有账单、分类和自定义图标)。**不要卸载**,直接覆盖安装再启动。用 iOS 模拟器工具 `launch`(绝对路径 `<仓库>/.superpowers/dd/Build/Products/Debug-iphonesimulator/HappySpending.app`,设备 `DB2215EB-B088-47B2-9466-8DDD8E7C3277`)。
Expected:
- 正常启动、不闪退;之前的账单、分类、自定义图标都还在(新增的可选字段和新实体靠轻量迁移)。
- 设置页多了"自动入账",点进去能看到六步说明、分类说明和"能覆盖什么"。
- 账单页原有账单行显示正常、**没有**"自动"标记(它们都是手动账)。

注意:模拟器截图总是滞后一步,每次操作后多拍一张再看。自动账的标记和"学习"只能真机上随真实交易验证,见 Task 6 的清单。

- [ ] **Step 8: 提交**

```bash
git add HappySpending
git commit -m "feat: add Apple Pay auto-record intent, shared container and auto badge"
```

---

### Task 6: 检查清单、README 与最终验证

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `README.md`

- [ ] **Step 1: 更新手动检查清单**

Modify `docs/manual-test-checklist.md`。Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "docs/manual-test-checklist.md"
s = open(p, encoding="utf-8").read()

assert s.count("## 深色模式") == 1
s = s.replace("## 深色模式", """## 自动入账(Apple Pay)

模拟器里能看的:
- [ ] 用新版本覆盖旧版本安装后不闪退,已有账单、分类、自定义图标都还在
- [ ] 设置 → 自动入账:能看到六步说明、分类说明和"能覆盖什么"
- [ ] 手动记的账在账单行里**没有**"自动"标记

必须真机验证的(依赖快捷指令和 Apple Pay,Mac 和模拟器上无法确认):
- [ ] 1. 快捷指令里能搜到"记一笔(Apple Pay)"动作,参数是商户和金额(搜不到再补注册 AppShortcutsProvider)
- [ ] 2. 个人自动化里能选"钱包 → 交易",并且能关闭"运行前先询问"
- [ ] 3. 触发器实际传出的金额是什么格式,动作能否解析(不能解析时快捷指令会提示"无法识别金额",把它传出的格式告诉我)
- [ ] 4. app 被杀掉、手机锁屏时刷一次 Apple Pay,账单里出现带"自动"标记的账,备注是商户名
- [ ] 5. app 在前台时触发,没有崩溃,新账立刻出现在界面上
- [ ] 6. 把某个自动账改成某个分类并保存,再刷同一商户,分类自动沿用
- [ ] 7. 免费账号的证书 7 天过期后动作会失效,重装后应能恢复
- [ ] 手动在快捷指令里运行一次"记一笔(Apple Pay)",商户填"测试"、金额填"12.5":账单里出现 ¥12.50、备注"测试"、带"自动"标记,快捷指令的输出是"已记 ¥12.50 · 测试"
- [ ] 手动运行时金额填"abc":快捷指令提示"无法识别金额",账单里没有新账

## 深色模式""")
open(p, "w", encoding="utf-8").write(s)

p = "README.md"
s = open(p, encoding="utf-8").read()
old = "- 手动检查清单:`docs/manual-test-checklist.md`\n"
assert s.count(old) == 1
s = s.replace(old, old + "- Apple Pay 自动入账设计:`docs/superpowers/specs/2026-10-13-apple-pay-auto-record-design.md`\n")
open(p, "w", encoding="utf-8").write(s)
EOF
```

- [ ] **Step 2: 最终验证**

Run(仓库根目录):

```bash
swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run" && xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: 178 个测试全部通过,没有警告;`** BUILD SUCCEEDED **`。

- [ ] **Step 3: 提交**

```bash
git add README.md docs/manual-test-checklist.md
git commit -m "docs: add Apple Pay auto-record checklist and README link"
```
