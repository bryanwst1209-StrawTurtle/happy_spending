# 待归类 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 账单页加"待归类 N 笔"入口和页签角标,点开逐笔归类;归好一笔有商户的自动账时记住商户,并把同商户的其他未分类支出一起归好(编辑页同样如此)。

**Architecture:** Core 新增 `PendingCategorization`(挑出待归类、归类并学习、同商户回填、提示文字)和 `EntrySource.displayName`,用 Swift Testing 测。app 层新增 `CategorizeSheet`(复用 `CategoryPicker`),在 `BillsView` 加入口、`RootTabView` 加角标,`EntryEditSheet` 保存时回填同商户。

**Tech Stack:** Swift 6、SwiftUI、SwiftData、Swift Testing;本地包 `Packages/HappySpendingCore`,工程由 XcodeGen 生成。

**Spec:** `docs/superpowers/specs/2026-10-16-pending-categorization-design.md`

## Global Constraints

- 最低系统 iOS 26;不引入第三方依赖。
- 业务逻辑放在 `Packages/HappySpendingCore`,用 Swift Testing 测;app 层保持很薄。
- "待归类" = `kind == .expense` 且 `category == nil`,不分月份,按 `date`、再按 `createdAt` 从早到晚。
- 只有"自动账 + 支出 + 商户非空 + 支出分类"才学习商户、才回填同商户;回填只改同商户(按 `MerchantKey.normalize` 比较)、`kind == .expense`、`category == nil` 的其他账。
- 面向用户的文字一字不差:`待归类 N 笔`、`待归类`、`跳过`、`就用『<一级分类名>』`、`已同时归类 N 笔 <商户>`(没有商户时只到 `笔`)、来源名 `Apple Pay` / `屏幕识别` / `通知`。
- 提交信息用英文,结尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 测试命令(仓库根目录):`swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`。开始前 310 个测试全部通过(28 个 suite)。
- app 构建命令(仓库根目录):`xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"`。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都在对应任务里有测试:

1. **两笔都没有商户的账不能被当成"同商户"**(`nil == nil`):归好一笔通知记的账,不能把其他通知账一起归了。→ Task 2 `anEntryWithoutAMerchantIsAssignedAlone`
2. **同商户里已有分类的账、收入**不能被回填覆盖。→ Task 2 `backfillLeavesCategorizedAndIncomeEntriesAlone`
3. **商户名只差大小写或空白算同一个,但"示例小吃"和"示例小吃二店"不算。** → Task 2 `assigningAMerchantEntryLearnsAndCategorizesTheSameMerchant`
4. **归到收入分类**(不该发生,但 Core 不能因此学到"商户 → 收入分类")。→ Task 2 `anIncomeCategoryIsNeitherLearnedNorSpread`
5. **同一天的多笔**按记账时间排,顺序稳定,不会每次打开面板顺序都变。→ Task 1 `pendingIsUncategorizedExpensesOldestFirst`

---

### Task 1: 待归类列表、提示文字、来源名

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/PendingCategorization.swift`
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/EntrySource.swift`(末尾加扩展)
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PendingCategorizationTests.swift`(新建)

**Interfaces:**
- Consumes: 已有的 `LedgerEntry`(`kind`、`category`、`date`、`createdAt`、`autoSource`、`merchant`)、`MerchantKey.trimmed(_:) -> String?`、`CategoryRules.addTopLevel(name:symbolName:colorHex:kind:sortOrder:in:) -> LedgerCategory`、`CategoryRules.addSubcategory(name:under:in:) throws -> LedgerCategory`、测试里的 `makeTestContainer()`、`makeDate(_:_:_:_:_:)`、`testCalendar`。
- Produces:
  - `public enum PendingCategorization`
  - `public static func pending(_ entries: [LedgerEntry]) -> [LedgerEntry]`
  - `public static func notice(count: Int, merchant: String?) -> String`
  - `extension EntrySource { public var displayName: String }`

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PendingCategorizationTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PendingCategorizationTests {
    private let now = makeDate(2026, 10, 16, 9, 0)

    private func makeCategories(_ context: ModelContext) throws -> (food: LedgerCategory, lunch: LedgerCategory, salary: LedgerCategory) {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let salary = CategoryRules.addTopLevel(
            name: "工资", symbolName: "banknote.fill", colorHex: "#30D158",
            kind: .income, sortOrder: 0, in: context
        )
        return (food, lunch, salary)
    }

    /// 插入一笔账;默认是没有分类、没有商户的屏幕识别支出。
    @discardableResult
    private func add(
        _ context: ModelContext,
        kind: EntryKind = .expense,
        month: Int = 10,
        day: Int = 15,
        createdMinute: Int = 0,
        category: LedgerCategory? = nil,
        source: EntrySource? = .screenText,
        merchant: String? = nil
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            amountInCents: 1000,
            kind: kind,
            date: makeDate(2026, month, day),
            note: merchant ?? "",
            category: category,
            createdAt: makeDate(2026, month, day, 12, createdMinute),
            calendar: testCalendar,
            autoSource: source,
            merchant: merchant
        )
        context.insert(entry)
        return entry
    }

    private func memories(_ context: ModelContext) throws -> [MerchantCategory] {
        try context.fetch(FetchDescriptor<MerchantCategory>())
    }

    // MARK: 待归类列表

    @Test func pendingIsUncategorizedExpensesOldestFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let late = add(context, day: 15, createdMinute: 30)
        let early = add(context, day: 15, createdMinute: 10)
        let lastMonth = add(context, month: 9, day: 28)

        let order = PendingCategorization.pending([late, early, lastMonth]).map(\.id)

        #expect(order == [lastMonth.id, early.id, late.id])
    }

    @Test func pendingSkipsIncomeAndCategorizedEntries() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let pending = add(context)
        let income = add(context, kind: .income)
        let categorized = add(context, category: c.food)
        let manual = add(context, category: c.lunch, source: nil)

        let ids = PendingCategorization.pending([pending, income, categorized, manual]).map(\.id)

        #expect(ids == [pending.id])
    }

    // MARK: 文字

    @Test func theNoticeNamesTheMerchant() {
        #expect(PendingCategorization.notice(count: 2, merchant: "示例小吃") == "已同时归类 2 笔 示例小吃")
        #expect(PendingCategorization.notice(count: 1, merchant: nil) == "已同时归类 1 笔")
        #expect(PendingCategorization.notice(count: 3, merchant: "  ") == "已同时归类 3 笔")
    }

    @Test func sourcesHaveReadableNames() {
        #expect(EntrySource.applePay.displayName == "Apple Pay")
        #expect(EntrySource.screenText.displayName == "屏幕识别")
        #expect(EntrySource.notification.displayName == "通知")
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'PendingCategorization' in scope`(以及 `displayName` 找不到)。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/PendingCategorization.swift`:

```swift
import Foundation
import SwiftData

/// 待归类:自动记下、还没有分类的支出。
/// 归好一笔有商户的自动账时,顺带记住商户,并把同商户的其他未分类支出一起归好。
public enum PendingCategorization {
    /// 待归类的账:没有分类的支出,按日期、再按记账时间从早到晚。
    public static func pending(_ entries: [LedgerEntry]) -> [LedgerEntry] {
        entries
            .filter { $0.kind == .expense && $0.category == nil }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    /// 同商户一起归好时的提示,例如"已同时归类 2 笔 示例小吃"。
    public static func notice(count: Int, merchant: String?) -> String {
        let name = merchant.flatMap(MerchantKey.trimmed).map { " \($0)" } ?? ""
        return "已同时归类 \(count) 笔\(name)"
    }
}
```

在 `Packages/HappySpendingCore/Sources/HappySpendingCore/EntrySource.swift` 末尾追加:

```swift

extension EntrySource {
    /// 界面上显示的来源名。
    public var displayName: String {
        switch self {
        case .applePay: "Apple Pay"
        case .screenText: "屏幕识别"
        case .notification: "通知"
        }
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 314 tests in 29 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: list pending uncategorized expenses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 归类、学习商户、同商户回填

**Files:**
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/PendingCategorization.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PendingCategorizationTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `PendingCategorization` 和测试辅助(`makeCategories`、`add`、`memories`、`now`);已有的 `MerchantMemory.learn(merchant:categoryID:in:now:) throws`、`MerchantMemory.learnFromEdit(entry:previousCategoryID:in:now:) throws -> Bool`、`MerchantKey.normalize(_:) -> String`、`AutoEntryRecorder.record(_:now:calendar:in:) throws -> AutoEntryResult`(`entryID`)、`PaymentRecord`。
- Produces:
  - `@discardableResult public static func assign(_ entry: LedgerEntry, to category: LedgerCategory, in context: ModelContext, now: Date = .now) throws -> Int`(返回一起归好的**其他**笔数;一次保存,失败时 `context.rollback()` 后抛错)
  - `@discardableResult public static func backfill(sameMerchantAs entry: LedgerEntry, in context: ModelContext) throws -> Int`(不保存)

- [ ] **Step 1: 写失败的测试**

在 `PendingCategorizationTests.swift` 里,紧挨 `    // MARK: 文字` 之前加入:

```swift
    // MARK: 归类

    @Test func assigningAMerchantEntryLearnsAndCategorizesTheSameMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, day: 14, merchant: "Luckin Coffee")
        let sameSpelling = add(context, day: 15, merchant: "Luckin Coffee")
        let otherSpelling = add(context, day: 16, merchant: " luckin  coffee ")
        let otherMerchant = add(context, day: 16, merchant: "Luckin Coffee 二店")
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.lunch, in: context, now: now)

        #expect(others == 2)
        #expect(entry.category?.id == c.lunch.id)
        #expect(sameSpelling.category?.id == c.lunch.id)
        #expect(otherSpelling.category?.id == c.lunch.id)
        #expect(otherMerchant.category == nil)
        #expect(try memories(context).map(\.categoryID) == [c.lunch.id])
    }

    @Test func backfillLeavesCategorizedAndIncomeEntriesAlone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        let alreadyFood = add(context, category: c.food, merchant: "示例小吃")
        let income = add(context, kind: .income, merchant: "示例小吃")
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.lunch, in: context, now: now)

        #expect(others == 0)
        #expect(alreadyFood.category?.id == c.food.id)
        #expect(income.category == nil)
    }

    /// 通知记的账没有商户:两笔都没有商户不算"同商户"。
    @Test func anEntryWithoutAMerchantIsAssignedAlone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, source: .notification)
        let anotherWithout = add(context, source: .notification)
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.food, in: context, now: now)

        #expect(others == 0)
        #expect(entry.category?.id == c.food.id)
        #expect(anotherWithout.category == nil)
        #expect(try memories(context).isEmpty)
    }

    @Test func aManualEntryIsAssignedWithoutLearning() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let manual = add(context, source: nil, merchant: "示例小吃")
        let auto = add(context, merchant: "示例小吃")
        try context.save()

        let others = try PendingCategorization.assign(manual, to: c.food, in: context, now: now)

        #expect(others == 0)
        #expect(manual.category?.id == c.food.id)
        #expect(auto.category == nil)
        #expect(try memories(context).isEmpty)
    }

    @Test func anIncomeCategoryIsNeitherLearnedNorSpread() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        let twin = add(context, merchant: "示例小吃")
        try context.save()

        let others = try PendingCategorization.assign(entry, to: c.salary, in: context, now: now)

        #expect(others == 0)
        #expect(entry.category?.id == c.salary.id)
        #expect(twin.category == nil)
        #expect(try memories(context).isEmpty)
    }

    @Test func theNextAutoEntryOfThatMerchantArrivesCategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        try context.save()

        try PendingCategorization.assign(entry, to: c.lunch, in: context, now: now)
        let result = try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 2500, merchant: "示例小吃", note: "示例小吃"),
            now: now, calendar: testCalendar, in: context
        )

        let recorded = try context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == result.entryID }
        #expect(recorded?.category?.id == c.lunch.id)
    }

    @Test func backfillDoesNothingWithoutACategoryOrMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let noCategory = add(context, merchant: "示例小吃")
        let twin = add(context, merchant: "示例小吃")
        let noMerchant = add(context, category: c.food)
        let blank = add(context)
        try context.save()

        #expect(try PendingCategorization.backfill(sameMerchantAs: noCategory, in: context) == 0)
        #expect(try PendingCategorization.backfill(sameMerchantAs: noMerchant, in: context) == 0)
        #expect(twin.category == nil)
        #expect(blank.category == nil)
    }

    /// 编辑页的路径:改了自动账的分类,`learnFromEdit` 学到了,再 `backfill`。
    @Test func theEditPathAlsoCategorizesTheSameMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let c = try makeCategories(context)
        let entry = add(context, merchant: "示例小吃")
        let twin = add(context, merchant: "示例小吃")
        try context.save()

        entry.category = c.food
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)
        let others = try learned ? PendingCategorization.backfill(sameMerchantAs: entry, in: context) : 0
        try context.save()

        #expect(learned)
        #expect(others == 1)
        #expect(twin.category?.id == c.food.id)
    }

```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: type 'PendingCategorization' has no member 'assign'`(以及 `backfill`)。

- [ ] **Step 3: 实现**

在 `PendingCategorization.swift` 里,紧挨 `    /// 同商户一起归好时的提示,例如"已同时归类 2 笔 示例小吃"。` 之前加入:

```swift
    /// 把一笔账归到分类。是有商户的自动支出、且归到支出分类时,记住"商户 → 分类",
    /// 并把同商户的其他未分类支出一起归好。一次保存;失败时撤回本次所有改动再抛错。
    /// 返回一起归好的**其他**笔数。
    @discardableResult
    public static func assign(
        _ entry: LedgerEntry,
        to category: LedgerCategory,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Int {
        do {
            entry.category = category
            var others = 0
            if entry.isAuto, entry.kind == .expense, category.kind == .expense,
               let merchant = entry.merchant.flatMap(MerchantKey.trimmed) {
                try MerchantMemory.learn(merchant: merchant, categoryID: category.id, in: context, now: now)
                others = try backfill(sameMerchantAs: entry, in: context)
            }
            try context.save()
            return others
        } catch {
            context.rollback()
            throw error
        }
    }

    /// 把与 `entry` 同商户(忽略大小写、多余空白)、还没分类的其他支出设成 `entry` 的分类;不保存。
    /// `entry` 没有分类、没有商户,或分类不是支出分类时什么也不做。返回改了几笔。
    @discardableResult
    public static func backfill(sameMerchantAs entry: LedgerEntry, in context: ModelContext) throws -> Int {
        guard let category = entry.category, category.kind == .expense,
              let merchant = entry.merchant.flatMap(MerchantKey.trimmed)
        else { return 0 }
        let key = MerchantKey.normalize(merchant)
        let matches = try context.fetch(FetchDescriptor<LedgerEntry>()).filter {
            $0.id != entry.id
                && $0.kind == .expense
                && $0.category == nil
                && $0.merchant.flatMap(MerchantKey.trimmed).map(MerchantKey.normalize) == key
        }
        for match in matches { match.category = category }
        return matches.count
    }

```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 322 tests in 29 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: assign a category and spread it to the same merchant

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 归类面板、账单页入口、页签角标、帮助页

**Files:**
- Create: `HappySpending/Bills/CategorizeSheet.swift`
- Modify: `HappySpending/Bills/BillsView.swift`
- Modify: `HappySpending/RootTabView.swift`
- Modify: `HappySpending/Settings/AutoRecordHelpView.swift`("分类怎么来的")

**Interfaces:**
- Consumes: Task 1/2 的 `PendingCategorization.pending`、`assign`、`notice`、`EntrySource.displayName`;已有的 `CategoryPicker(kind:categories:frequentIDs:selectedID:)`、`BillsLogic.frequentCategoryIDs(_:kind:excluding:)`、`BillsLogic.dayTitle(_:calendar:)`、`DayStamp.calendar`、`Money.display(_:)`、`ToastView(text:)`、`EntryRow`(`entries.map(\.row)`)。
- Produces: `struct CategorizeSheet: View`,`init(categories: [LedgerCategory], rows: [EntryRow])`。

没有可单测的逻辑(逻辑都在 Task 1/2);本任务的验证是构建通过 + 模拟器里走一遍。

- [ ] **Step 1: 新建归类面板**

新建 `HappySpending/Bills/CategorizeSheet.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

/// 待归类面板:一次一笔,选好分类就归好并显示下一笔;全部处理完自动关闭。
struct CategorizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var entries: [LedgerEntry]

    let categories: [LedgerCategory]
    let rows: [EntryRow]

    /// 这次打开面板时跳过的账;不记下来,下次打开还会出现。
    @State private var skipped: Set<UUID> = []
    @State private var selectedID: UUID?
    @State private var notice: String?
    @State private var errorMessage: String?

    private var queue: [LedgerEntry] {
        PendingCategorization.pending(entries).filter { !skipped.contains($0.id) }
    }
    private var current: LedgerEntry? { queue.first }
    private var selected: LedgerCategory? { categories.first { $0.id == selectedID } }

    /// 选中的是有二级分类的一级分类:等用户选二级分类,或点"就用『X』"。
    private var waitingForSubcategory: LedgerCategory? {
        guard let selected, selected.parent == nil,
              selected.children.contains(where: { !$0.isArchived })
        else { return nil }
        return selected
    }

    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            rows, kind: .expense,
            excluding: Set(categories.filter(\.isArchived).map(\.id))
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let current {
                    VStack(alignment: .leading, spacing: 16) {
                        summary(current)
                        CategoryPicker(
                            kind: .expense, categories: categories,
                            frequentIDs: frequentIDs, selectedID: $selectedID
                        )
                        if let waitingForSubcategory {
                            Button("就用『\(waitingForSubcategory.name)』") {
                                assign(current, to: waitingForSubcategory)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("待归类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("跳过") {
                        if let current { skipped.insert(current.id) }
                    }
                    .disabled(current == nil)
                }
            }
            .onChange(of: selectedID) {
                // 没有二级分类的一级分类、任意二级分类:点了就归好。
                guard let current, let selected, waitingForSubcategory == nil else { return }
                assign(current, to: selected)
            }
            .onChange(of: current?.id) { _, id in
                selectedID = nil
                guard id == nil else { return }
                // 全部处理完:有提示就让它多停一会儿再关。
                Task {
                    if notice != nil { try? await Task.sleep(for: .seconds(1.5)) }
                    dismiss()
                }
            }
            .overlay(alignment: .top) {
                if let notice {
                    ToastView(text: notice)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
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

    private func summary(_ entry: LedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Money.display(entry.amountInCents))
                .font(.largeTitle.weight(.semibold).monospacedDigit())
            Text(entry.merchant ?? (entry.note.isEmpty ? "没有商户名" : entry.note))
                .font(.headline)
            HStack(spacing: 6) {
                Text(BillsLogic.dayTitle(entry.date, calendar: DayStamp.calendar))
                if let source = entry.autoSource {
                    Text("·")
                    Text(source.displayName)
                }
                Spacer()
                Text("还剩 \(queue.count) 笔")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func assign(_ entry: LedgerEntry, to category: LedgerCategory) {
        let merchant = entry.merchant
        do {
            let others = try PendingCategorization.assign(entry, to: category, in: context)
            if others > 0 { show(PendingCategorization.notice(count: others, merchant: merchant)) }
        } catch {
            selectedID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if notice == text { notice = nil } }
        }
    }
}
```

(spec §4.2 没提"关闭"按钮;sheet 本来就能下滑关闭,左上角加一个"关闭"只是让关闭更明显,不改变任何规则。)

- [ ] **Step 2: 账单页入口**

在 `HappySpending/Bills/BillsView.swift` 里:

把

```swift
    @State private var errorMessage: String?
```

换成

```swift
    @State private var errorMessage: String?
    @State private var categorizing = false
```

把

```swift
    private var summary: PeriodSummary { Statistics.summary(monthRows) }
```

换成

```swift
    private var summary: PeriodSummary { Statistics.summary(monthRows) }
    /// 所有月份里待归类的笔数。
    private var pendingCount: Int { PendingCategorization.pending(entries).count }
```

把

```swift
            List {
                Section {
                    PeriodSwitcher(
```

换成

```swift
            List {
                if pendingCount > 0 {
                    Section {
                        Button { categorizing = true } label: {
                            HStack {
                                Label("待归类 \(pendingCount) 笔", systemImage: "tray.full")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                Section {
                    PeriodSwitcher(
```

把

```swift
            .sheet(item: $editing) { entry in
                EntryEditSheet(entry: entry, categories: categories, rows: allRows)
            }
```

换成

```swift
            .sheet(item: $editing) { entry in
                EntryEditSheet(entry: entry, categories: categories, rows: allRows)
            }
            .sheet(isPresented: $categorizing) {
                CategorizeSheet(categories: categories, rows: allRows)
            }
```

- [ ] **Step 3: 页签角标**

把 `HappySpending/RootTabView.swift` 整个换成:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    @Query private var entries: [LedgerEntry]

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(entries).count }

    var body: some View {
        TabView {
            Tab("记账", systemImage: "plus.circle.fill") { RecordView() }
            Tab("账单", systemImage: "list.bullet.rectangle") { BillsView() }
                .badge(pendingCount)
            Tab("统计", systemImage: "chart.pie.fill") { StatsView() }
            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }
        }
    }
}
```

- [ ] **Step 4: 帮助页**

在 `HappySpending/Settings/AutoRecordHelpView.swift` 里,把

```swift
                Text("有商户名的账,你在账单里改过分类并保存后,app 会记住这个商户,以后同一商户直接用这个分类。支付宝账单页自带的分类(如“日用百货”)会按对应关系预填。其余先归“未分类”。")
```

换成

```swift
                Text("有商户名的账,你在账单里改过分类并保存后,app 会记住这个商户,以后同一商户直接用这个分类。支付宝账单页自带的分类(如“日用百货”)会按对应关系预填。其余先归“未分类”,会出现在账单页的“待归类”里;归好一笔,同一商户的其他未分类账会一起归好。")
```

- [ ] **Step 5: 构建**

Run: 上面 Global Constraints 里的 app 构建命令。
Expected: `** BUILD SUCCEEDED **`,没有 HappySpending 目录下的警告。

- [ ] **Step 6: 模拟器里走一遍**

覆盖安装到模拟器(不要卸载)并启动。造数据:在模拟器的"快捷指令"app 里新建一个快捷指令,依次添加并运行这几个动作(每个参数都是单行文字):
- "记一笔(Apple Pay)":商户 `示例小吃`,金额 `55`
- "记一笔(Apple Pay)":商户 `示例小吃`,金额 `12`
- "记一笔(通知)":通知标题 `交易提醒`,通知正文 `你有一笔 15.12 元的支出`

回到 app。
Expected:
- 账单页签有角标 3,账单页最上面是"待归类 3 笔 ›"。
- 点开面板:第一笔显示金额、商户、日期和来源;点"餐饮"出现二级分类和"就用『餐饮』";点"午餐"后提示"已同时归类 1 笔 示例小吃",直接跳到"通知"那一笔。
- 点"跳过":面板关闭(没有剩下的了);入口变成"待归类 1 笔"。
- 再点开,把那笔通知账归到任意没有二级分类的一级分类:面板关闭,入口和角标消失。
- 之前的账单都还在。

- [ ] **Step 7: 提交**

```bash
git add HappySpending
git commit -m "feat: add the pending categorization sheet, bills entry and tab badge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 编辑页同商户回填、检查清单、README、最终验证

**Files:**
- Modify: `HappySpending/Bills/EntryEditSheet.swift`
- Modify: `docs/manual-test-checklist.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `PendingCategorization.backfill(sameMerchantAs:in:)`、`PendingCategorization.notice(count:merchant:)`(Task 1/2);已有的 `MerchantMemory.learnFromEdit(entry:previousCategoryID:in:) throws -> Bool`。
- Produces: 无代码接口。编辑页路径的 Core 逻辑已由 Task 2 的 `theEditPathAlsoCategorizesTheSameMerchant` 覆盖。

- [ ] **Step 1: 编辑页回填**

在 `HappySpending/Bills/EntryEditSheet.swift` 里:

把

```swift
    @State private var errorMessage: String?
```

换成

```swift
    @State private var errorMessage: String?
    /// 同商户一起归好时的提示;点"好"后关闭编辑页。
    @State private var backfillNotice: String?
```

把

```swift
        do {
            // 改了自动账的分类就记住"这个商户 → 这个分类"。
            try MerchantMemory.learnFromEdit(
                entry: entry, previousCategoryID: previousCategoryID, in: context
            )
            try context.save()
            dismiss()
        } catch {
```

换成

```swift
        do {
            // 改了自动账的分类就记住"这个商户 → 这个分类",并把同商户还没分类的支出一起归好。
            let learned = try MerchantMemory.learnFromEdit(
                entry: entry, previousCategoryID: previousCategoryID, in: context
            )
            let others = try learned ? PendingCategorization.backfill(sameMerchantAs: entry, in: context) : 0
            try context.save()
            if others > 0 {
                backfillNotice = PendingCategorization.notice(count: others, merchant: entry.merchant)
            } else {
                dismiss()
            }
        } catch {
```

把

```swift
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
```

换成

```swift
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(backfillNotice ?? "", isPresented: Binding(
                get: { backfillNotice != nil },
                set: { if !$0 { backfillNotice = nil } }
            )) {
                Button("好") { dismiss() }
            }
```

- [ ] **Step 2: 检查清单和 README**

Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "docs/manual-test-checklist.md"
s = open(p, encoding="utf-8").read()
assert s.count("## 深色模式") == 1
s = s.replace("## 深色模式", """## 待归类

模拟器里能看的:
- [ ] 有没分类的自动账时,账单页签有角标,账单页最上面是"待归类 N 笔";没有时都不显示
- [ ] 面板逐笔显示金额、商户、日期、来源;点没有二级分类的一级分类立即归好;点有二级分类的出现二级分类和"就用『X』"
- [ ] "跳过"只在本次有效;全部处理完面板自动关闭
- [ ] 归好一笔有商户的账,同商户其他未分类账一起归好,并提示"已同时归类 N 笔 <商户>"
- [ ] 编辑页把自动账改成某个分类:同商户未分类账一起归好,先提示再关闭编辑页

必须真机验证的:
- [ ] 1. 屏幕识别、通知各记一笔没分类的账后,账单页签出现角标,账单页出现"待归类 N 笔"
- [ ] 2. 在面板里归好一笔有商户的账,同商户的其他未分类账一起归好并有提示;再在该商户付一笔,自动记下时直接带分类
- [ ] 3. 没有商户的账(通知记的)归类后,不会影响其他账

## 深色模式""")
open(p, "w", encoding="utf-8").write(s)

p = "README.md"
s = open(p, encoding="utf-8").read()
old = "- 微信支付消息列表记账设计:`docs/superpowers/specs/2026-10-15-wechat-list-screen-record-design.md`\n"
assert s.count(old) == 1
s = s.replace(old, old + "- 待归类设计:`docs/superpowers/specs/2026-10-16-pending-categorization-design.md`\n")
open(p, "w", encoding="utf-8").write(s)
EOF
```

Expected: 没有输出(两个 `assert` 都通过)。

- [ ] **Step 3: 最终验证**

Run: Global Constraints 里的测试命令,再跑 app 构建命令。
Expected: `✔ Test run with 322 tests in 29 suites passed`;`** BUILD SUCCEEDED **`;没有 HappySpending 目录下的警告。

- [ ] **Step 4: 模拟器里看编辑页**

覆盖安装并启动。在"快捷指令"里再运行两次"记一笔(Apple Pay)":商户 `示例甜品`,金额 `20` 和 `30`。回到账单页,点开其中一笔(带"自动"标记),分类改成任意支出分类,点"保存"。
Expected: 弹出"已同时归类 1 笔 示例甜品",点"好"后编辑页关闭;另一笔示例甜品也有了同样的分类;"待归类"入口和角标随之减少。

- [ ] **Step 5: 提交**

```bash
git add HappySpending README.md docs/manual-test-checklist.md
git commit -m "feat: spread an edited category to the same merchant, checklist and README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
