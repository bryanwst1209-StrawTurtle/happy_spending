# 账单查历史与长期使用不卡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每个页面只从数据库读要显示的数据,用 3~5 年也不卡;账单页点标题跳任意月份、› 不翻到未来、"回到本月",搜索支持"本月 / 全部"和金额匹配;统计页同样能跳月份 / 年份。

**Architecture:** Core 新增 `LedgerQueries`(各页面的 `FetchDescriptor`)、`AmountQuery` + `HistorySearch`(全量搜索)、`BillsLogic.groupByMonth`、`HistoryRange`(选择器范围与"是否当前")。app 层把账单页拆成状态外壳 `BillsView` + 按月查询的 `MonthBillsList` + 全量搜索的 `HistorySearchList`;统计页拆出按区间查询的 `StatsPeriodContent`;`PeriodSwitcher` 增加点标题、置灰、回到本月;新增 `MonthPickerSheet`。

**Tech Stack:** Swift、SwiftUI、SwiftData、Swift Testing;本地包 `Packages/HappySpendingCore`,工程由 XcodeGen 生成(切分支、合并后 git 钩子会自动重新生成)。

**Spec:** `docs/superpowers/specs/2026-10-22-bills-history-and-performance-design.md`

## Global Constraints

- 最低系统 iOS 26;不引入第三方依赖;数据库结构不变,不做迁移。
- 账单日期统一按 `DayStamp.calendar`(GMT 公历)解读;"现在"用 `DayStamp.stamp(.now)`。
- 业务逻辑放在 `Packages/HappySpendingCore`,用 Swift Testing 测;app 层保持很薄。
- 面向用户的文字一字不差:`回到本月`、`回到今年`、`本月`、`全部`、`搜索备注、分类或金额`、`选择月份`、`选择年份`、`取消`、`完成`、`本月还没有账单`、`这个月没有账单`、`找到 N 笔 · 支出 ¥X`、组标题右侧 `支出 ¥X`。
- 导出菜单保留"导出当月 CSV"和"导出全部 CSV";"导出全部"在点击导出时才读数据。
- 提交信息用英文,结尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 测试命令(仓库根目录):`swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`。开始前 324 个测试全部通过(29 个 suite)。
- app 构建命令(仓库根目录):`xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"`。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都有对应的测试或检查:

1. **月份边界**:月初那一天要算进来,下个月 1 号不能算进来(存储是 GMT 0 点)。→ Task 1 `aMonthQueryReturnsOnlyThatMonthNewestFirst`
2. **"是不是当前月"的边界**:`DateInterval.contains` 包含终点,直接用它会把下个月 1 号算成上个月,导致 › 该置灰时没置灰。→ Task 3 `theFirstDayOfTheNextMonthIsNotInThePreviousMonth`
3. **金额搜索误中**:搜 `147` 不能命中 ¥14.70 和 ¥1470.00。→ Task 2 `monthSearchAlsoMatchesAmounts`、`amountsMatchAcrossMonths`
4. **"没有分类"的查询**:`category == nil` 在数据库里查出来的结果必须和原来在内存里挑的一致(含收入)。→ Task 1 `theUncategorizedQueryFindsEntriesWithoutACategory`
5. **空月份挡住按钮**:翻到没有账的历史月份时,"这个月没有账单"的占位不能挡住 ‹ › 和标题的点击。→ Task 4 Step 7 模拟器检查(界面层,没有单元测试)

---

### Task 1: 各页面的查询

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerQueries.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/LedgerQueriesTests.swift`(新建)

**Interfaces:**
- Consumes: 已有的 `Period.interval(calendar:)`、`LedgerEntry`(`date`、`createdAt`、`category`、`id`)、`PendingCategorization.pending(_:)`、`CategoryRules.addTopLevel(...)`;测试里的 `makeTestContainer()`、`makeDate(...)`、`testCalendar`。
- Produces(`public enum LedgerQueries`,都返回 `FetchDescriptor<LedgerEntry>`):
  - `entries(in period: Period, calendar: Calendar)`:区间内,按 `date` 倒序、同日按 `createdAt` 倒序
  - `uncategorized()`:`category == nil`
  - `recent(limit: Int = 300)`:按 `createdAt` 倒序,最多 `limit` 笔
  - `earliest()`:按 `date` 正序,1 笔
  - `entry(id: UUID)`:1 笔
  - `all()`:按 `date`、`createdAt` 正序(导出全部用)

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/LedgerQueriesTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct LedgerQueriesTests {
    @discardableResult
    private func add(
        _ context: ModelContext, _ y: Int, _ m: Int, _ d: Int,
        createdMinute: Int = 0, kind: EntryKind = .expense, category: LedgerCategory? = nil
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            amountInCents: 1000, kind: kind, date: makeDate(y, m, d), category: category,
            createdAt: makeDate(y, m, d, 12, createdMinute), calendar: testCalendar
        )
        context.insert(entry)
        return entry
    }

    @Test func aMonthQueryReturnsOnlyThatMonthNewestFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 2026, 9, 30)
        let first = add(context, 2026, 10, 1)
        let last = add(context, 2026, 10, 31)
        add(context, 2026, 11, 1)
        try context.save()

        let found = try context.fetch(LedgerQueries.entries(in: .month(makeDate(2026, 10, 15)), calendar: testCalendar))

        #expect(found.map(\.id) == [last.id, first.id])
    }

    @Test func aYearQueryReturnsOnlyThatYear() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        add(context, 2025, 12, 31)
        let first = add(context, 2026, 1, 1)
        let last = add(context, 2026, 12, 31)
        add(context, 2027, 1, 1)
        try context.save()

        let found = try context.fetch(LedgerQueries.entries(in: .year(2026), calendar: testCalendar))

        #expect(found.map(\.id) == [last.id, first.id])
    }

    @Test func sameDayEntriesComeNewestRecordedFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let early = add(context, 2026, 10, 15, createdMinute: 5)
        let late = add(context, 2026, 10, 15, createdMinute: 30)
        try context.save()

        let found = try context.fetch(LedgerQueries.entries(in: .month(makeDate(2026, 10, 1)), calendar: testCalendar))

        #expect(found.map(\.id) == [late.id, early.id])
    }

    @Test func theUncategorizedQueryFindsEntriesWithoutACategory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let pending = add(context, 2026, 10, 15)
        let income = add(context, 2026, 10, 15, kind: .income)
        add(context, 2026, 10, 15, category: food)
        try context.save()

        let found = try context.fetch(LedgerQueries.uncategorized())

        #expect(Set(found.map(\.id)) == [pending.id, income.id])
        #expect(PendingCategorization.pending(found).map(\.id) == [pending.id])
    }

    @Test func theRecentQueryKeepsTheLatestRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entries = (1...5).map { add(context, 2026, 10, $0) }
        try context.save()

        let found = try context.fetch(LedgerQueries.recent(limit: 3))

        #expect(found.map(\.id) == [entries[4].id, entries[3].id, entries[2].id])
    }

    @Test func theEarliestQueryFindsTheOldestEntry() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        #expect(try context.fetch(LedgerQueries.earliest()).isEmpty)

        add(context, 2026, 10, 15)
        let oldest = add(context, 2024, 3, 1)
        add(context, 2025, 1, 1)
        try context.save()

        #expect(try context.fetch(LedgerQueries.earliest()).map(\.id) == [oldest.id])
    }

    @Test func anEntryCanBeLookedUpByID() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = add(context, 2026, 10, 15)
        try context.save()

        #expect(try context.fetch(LedgerQueries.entry(id: entry.id)).map(\.id) == [entry.id])
        #expect(try context.fetch(LedgerQueries.entry(id: UUID())).isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'LedgerQueries' in scope`。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerQueries.swift`:

```swift
import Foundation
import SwiftData

/// 各页面用的查询:只从数据库取要显示的那部分,避免每次刷新都把全部账单读出来再挑。
public enum LedgerQueries {
    /// 某个月或某一年的账:日期新的在前,同一天后记的在前。
    public static func entries(in period: Period, calendar: Calendar) -> FetchDescriptor<LedgerEntry> {
        let interval = period.interval(calendar: calendar)
        let start = interval.start
        let end = interval.end
        return FetchDescriptor(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    /// 还没有分类的账(含收入);再交给 `PendingCategorization.pending` 挑出支出并排序。
    public static func uncategorized() -> FetchDescriptor<LedgerEntry> {
        FetchDescriptor(predicate: #Predicate { $0.category == nil })
    }

    /// 最近记的若干笔(按记账时间倒序),给"常用分类"用。
    public static func recent(limit: Int = 300) -> FetchDescriptor<LedgerEntry> {
        var descriptor = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// 日期最早的一笔,给年月选择器定起始年份。
    public static func earliest() -> FetchDescriptor<LedgerEntry> {
        var descriptor = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// 按 id 找一笔(撤销删除时防止重复恢复)。
    public static func entry(id: UUID) -> FetchDescriptor<LedgerEntry> {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// 全部账单,日期从早到晚(导出全部用,只在点导出时才查)。
    public static func all() -> FetchDescriptor<LedgerEntry> {
        FetchDescriptor(sortBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt)])
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 331 tests in 30 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add per-screen ledger queries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 金额匹配、按月分组、全部历史搜索

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/HistorySearch.swift`
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/BillsLogic.swift`(`search`)
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/HistorySearchTests.swift`(新建)

**Interfaces:**
- Consumes: Task 1 的 `LedgerQueries.uncategorized()`;已有的 `AmountText.cents(from:) throws -> Int`、`Uncategorized.name`、`LedgerCategory`(`name`、`parent`、`children`、`entries`)、`EntryRow`、`CategoryRules.addTopLevel/addSubcategory`。
- Produces:
  - `public enum AmountQuery { public static func range(for query: String) -> Range<Int>? }`:带小数点 → `cents..<cents+1`;整数 → `cents..<cents+100`;解析不了或 ≤ 0 → nil
  - `public struct MonthGroup: Equatable, Identifiable, Sendable { month: Date; rows: [EntryRow]; expenseCents: Int; id: Date }`
  - `extension BillsLogic { public static func groupByMonth(_ rows: [EntryRow], calendar: Calendar) -> [MonthGroup] }`:月份新的在前,组内按日期、记账时间倒序
  - `public enum HistorySearch { public static func search(_ query: String, in context: ModelContext) throws -> [LedgerEntry] }`:规则见 spec §5,去重,按日期、记账时间倒序;空搜索词返回 `[]`
  - `BillsLogic.search` 增加金额匹配

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/HistorySearchTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct HistorySearchTests {
    // MARK: 金额

    @Test func decimalAmountsMatchExactly() {
        for text in ["147.7", "147.70", "¥147.70", " 147.70 "] {
            #expect(AmountQuery.range(for: text) == 14770..<14771, "\(text)")
        }
    }

    @Test func wholeAmountsMatchTheWholeYuan() {
        #expect(AmountQuery.range(for: "147") == 14700..<14800)
        #expect(AmountQuery.range(for: "147元") == 14700..<14800)
    }

    @Test func textThatIsNotAnAmountHasNoRange() {
        for text in ["0", "abc", "", "-5", "示例"] {
            #expect(AmountQuery.range(for: text) == nil, "\(text)")
        }
    }

    // MARK: 本月搜索与分组

    private func row(_ cents: Int, note: String = "", date: Date = makeDate(2026, 10, 15)) -> EntryRow {
        EntryRow(
            date: date, kind: .expense, cents: cents, note: note,
            topCategoryID: nil, topCategoryName: "餐饮", topColorHex: "#000000"
        )
    }

    @Test func monthSearchAlsoMatchesAmounts() {
        let rows = [row(14770), row(1470), row(147000), row(500, note: "147 号店")]
        #expect(BillsLogic.search(rows, query: "147").map(\.cents) == [14770, 500])
    }

    @Test func resultsAreGroupedByMonthNewestFirst() {
        let rows = [
            row(100, date: makeDate(2025, 3, 2)),
            row(200, date: makeDate(2026, 10, 15)),
            row(300, date: makeDate(2025, 3, 20)),
        ]

        let groups = BillsLogic.groupByMonth(rows, calendar: testCalendar)

        #expect(groups.map(\.month) == [makeDate(2026, 10, 1), makeDate(2025, 3, 1)])
        #expect(groups[1].rows.map(\.cents) == [300, 100])
        #expect(groups.map(\.expenseCents) == [200, 400])
    }

    // MARK: 全部历史

    private struct Fixture {
        let context: ModelContext
        let food: LedgerCategory
        let lunch: LedgerCategory
        let transport: LedgerCategory
    }

    private func makeFixture(_ container: ModelContainer) throws -> Fixture {
        let context = container.mainContext
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 0, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let transport = CategoryRules.addTopLevel(
            name: "交通", symbolName: "bus.fill", colorHex: "#0A84FF",
            kind: .expense, sortOrder: 1, in: context
        )
        return Fixture(context: context, food: food, lunch: lunch, transport: transport)
    }

    @discardableResult
    private func add(
        _ context: ModelContext, cents: Int = 1000, note: String = "",
        category: LedgerCategory? = nil, _ y: Int = 2026, _ m: Int = 10, _ d: Int = 15
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            amountInCents: cents, kind: .expense, date: makeDate(y, m, d), note: note,
            category: category, createdAt: makeDate(y, m, d, 12), calendar: testCalendar
        )
        context.insert(entry)
        return entry
    }

    @Test func notesMatchInAnyMonth() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let old = add(f.context, note: "示例小吃", 2024, 1, 1)
        let new = add(f.context, note: "示例小吃二店", 2026, 10, 15)
        add(f.context, note: "别的")
        try f.context.save()

        #expect(try HistorySearch.search("小吃", in: f.context).map(\.id) == [new.id, old.id])
    }

    @Test func aTopLevelCategoryMatchIncludesItsSubcategories() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let food = add(f.context, category: f.food, 2026, 10, 2)
        let lunch = add(f.context, category: f.lunch, 2026, 10, 1)
        add(f.context, category: f.transport)
        try f.context.save()

        #expect(try HistorySearch.search("餐饮", in: f.context).map(\.id) == [food.id, lunch.id])
    }

    @Test func aSubcategoryMatchOnlyIncludesThatSubcategory() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        add(f.context, category: f.food)
        let lunch = add(f.context, category: f.lunch)
        try f.context.save()

        #expect(try HistorySearch.search("午餐", in: f.context).map(\.id) == [lunch.id])
    }

    @Test func searchingUncategorizedFindsEntriesWithoutACategory() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let none = add(f.context)
        add(f.context, category: f.food)
        try f.context.save()

        #expect(try HistorySearch.search("未分类", in: f.context).map(\.id) == [none.id])
    }

    @Test func amountsMatchAcrossMonths() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        let exact = add(f.context, cents: 14770, 2024, 5, 1)
        let sameYuan = add(f.context, cents: 14799, 2026, 10, 15)
        add(f.context, cents: 1470)
        add(f.context, cents: 147000)
        try f.context.save()

        #expect(try HistorySearch.search("147", in: f.context).map(\.id) == [sameYuan.id, exact.id])
        #expect(try HistorySearch.search("147.7", in: f.context).map(\.id) == [exact.id])
    }

    @Test func anEntryMatchingSeveralWaysAppearsOnce() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        add(f.context, note: "餐饮外卖", category: f.food)
        try f.context.save()

        #expect(try HistorySearch.search("餐饮", in: f.context).count == 1)
    }

    @Test func aBlankQueryFindsNothing() throws {
        let container = try makeTestContainer()
        let f = try makeFixture(container)
        add(f.context, note: "示例")
        try f.context.save()

        #expect(try HistorySearch.search("  ", in: f.context).isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'AmountQuery' in scope`(以及 `HistorySearch`、`groupByMonth` 找不到)。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/HistorySearch.swift`:

```swift
import Foundation
import SwiftData

/// 搜索词当金额用时匹配的区间(分,左闭右开)。
public enum AmountQuery {
    /// 带小数点(`147.7`、`147.70`)按精确金额;整数(`147`)按"这个整数元"(¥147.00~¥147.99);
    /// 解析不了或不大于 0 时返回 nil。
    public static func range(for query: String) -> Range<Int>? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cents = try? AmountText.cents(from: text), cents > 0 else { return nil }
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidth.contains(".") ? cents..<(cents + 1) : cents..<(cents + 100)
    }
}

/// 一个月的搜索结果。
public struct MonthGroup: Equatable, Identifiable, Sendable {
    /// 该月 1 日。
    public let month: Date
    public let rows: [EntryRow]
    public let expenseCents: Int
    public var id: Date { month }
}

extension BillsLogic {
    /// 按月分组,月份新的在前;组内日期新的在前,同一天后记的在前。
    public static func groupByMonth(_ rows: [EntryRow], calendar: Calendar) -> [MonthGroup] {
        Dictionary(grouping: rows) { calendar.dateInterval(of: .month, for: $0.date)!.start }
            .map { month, members in
                MonthGroup(
                    month: month,
                    rows: members.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) },
                    expenseCents: members.filter { $0.kind == .expense }.reduce(0) { $0 + $1.cents }
                )
            }
            .sorted { $0.month > $1.month }
    }
}

/// 账单页搜"全部":在所有月份里搜。
public enum HistorySearch {
    /// 备注、一级 / 二级分类名(匹配一级分类时连同它的二级分类)、"未分类"、金额,任一命中即可。
    /// 备注和金额交给数据库查;分类名先在分类列表里找,再取它们的账。去重后按日期、记账时间倒序。
    public static func search(_ query: String, in context: ModelContext) throws -> [LedgerEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var found: [UUID: LedgerEntry] = [:]
        func add(_ entries: [LedgerEntry]) {
            for entry in entries { found[entry.id] = entry }
        }

        add(try context.fetch(FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.note.localizedStandardContains(text) }
        )))

        for category in try context.fetch(FetchDescriptor<LedgerCategory>())
        where category.name.localizedCaseInsensitiveContains(text) {
            add(category.entries)
            if category.parent == nil {
                for child in category.children { add(child.entries) }
            }
        }

        if Uncategorized.name.localizedCaseInsensitiveContains(text) {
            add(try context.fetch(LedgerQueries.uncategorized()))
        }

        if let range = AmountQuery.range(for: text) {
            let low = range.lowerBound
            let high = range.upperBound
            add(try context.fetch(FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.amountInCents >= low && $0.amountInCents < high }
            )))
        }

        return found.values.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }
}
```

在 `Packages/HappySpendingCore/Sources/HappySpendingCore/BillsLogic.swift` 里,把

```swift
    /// 在备注、一级分类名、二级分类名里做不区分大小写的包含匹配。空查询返回全部。
    public static func search(_ rows: [EntryRow], query: String) -> [EntryRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            [row.note, row.topCategoryName, row.subCategoryName ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
```

换成

```swift
    /// 在备注、一级分类名、二级分类名里做不区分大小写的包含匹配;搜索词能当金额时也按金额匹配
    /// (规则见 `AmountQuery`)。空查询返回全部。
    public static func search(_ rows: [EntryRow], query: String) -> [EntryRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        let amount = AmountQuery.range(for: query)
        return rows.filter { row in
            [row.note, row.topCategoryName, row.subCategoryName ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
                || amount?.contains(row.cents) == true
        }
    }
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 343 tests in 31 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: search all history by note, category or amount

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 年月选择器范围与"是否当前"

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/HistoryRange.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/HistoryRangeTests.swift`(新建)

**Interfaces:**
- Consumes: 已有的 `Period.interval(calendar:)`。
- Produces(`public enum HistoryRange`):
  - `years(earliest: Date?, now: Date, calendar: Calendar) -> ClosedRange<Int>`
  - `months(in year: Int, now: Date, calendar: Calendar) -> ClosedRange<Int>`
  - `isCurrent(_ period: Period, now: Date, calendar: Calendar) -> Bool`(左闭右开)

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/HistoryRangeTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct HistoryRangeTests {
    private let now = makeDate(2026, 10, 22)

    @Test func yearsRunFromTheEarliestEntryToThisYear() {
        #expect(HistoryRange.years(earliest: makeDate(2023, 5, 1), now: now, calendar: testCalendar) == 2023...2026)
        #expect(HistoryRange.years(earliest: nil, now: now, calendar: testCalendar) == 2026...2026)
        #expect(HistoryRange.years(earliest: makeDate(2027, 1, 1), now: now, calendar: testCalendar) == 2026...2026)
    }

    @Test func thisYearOnlyOffersMonthsUpToNow() {
        #expect(HistoryRange.months(in: 2026, now: now, calendar: testCalendar) == 1...10)
        #expect(HistoryRange.months(in: 2025, now: now, calendar: testCalendar) == 1...12)
    }

    @Test func theCurrentMonthAndYearAreRecognized() {
        #expect(HistoryRange.isCurrent(.month(makeDate(2026, 10, 1)), now: now, calendar: testCalendar))
        #expect(!HistoryRange.isCurrent(.month(makeDate(2026, 9, 30)), now: now, calendar: testCalendar))
        #expect(HistoryRange.isCurrent(.year(2026), now: now, calendar: testCalendar))
        #expect(!HistoryRange.isCurrent(.year(2025), now: now, calendar: testCalendar))
    }

    /// `DateInterval.contains` 包含终点:不能把下个月 1 号算进上个月。
    @Test func theFirstDayOfTheNextMonthIsNotInThePreviousMonth() {
        let october1 = makeDate(2026, 10, 1)
        #expect(!HistoryRange.isCurrent(.month(makeDate(2026, 9, 15)), now: october1, calendar: testCalendar))
        #expect(!HistoryRange.isCurrent(.year(2025), now: makeDate(2026, 1, 1), calendar: testCalendar))
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'HistoryRange' in scope`。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/HistoryRange.swift`:

```swift
import Foundation

/// 账单页、统计页"查历史"用到的范围计算。
public enum HistoryRange {
    /// 年月选择器可选的年份:最早一笔所在年到今年;没有账时只有今年。
    public static func years(earliest: Date?, now: Date, calendar: Calendar) -> ClosedRange<Int> {
        let thisYear = calendar.component(.year, from: now)
        let first = earliest.map { calendar.component(.year, from: $0) } ?? thisYear
        return min(first, thisYear)...thisYear
    }

    /// 某一年可选的月份:今年只到本月,不能选未来。
    public static func months(in year: Int, now: Date, calendar: Calendar) -> ClosedRange<Int> {
        let components = calendar.dateComponents([.year, .month], from: now)
        return 1...(year == components.year ? (components.month ?? 12) : 12)
    }

    /// `period` 是否就是现在所在的月(或年),用于置灰 › 和显示"回到本月"。
    /// 左闭右开:`DateInterval.contains` 包含终点,不能直接用。
    public static func isCurrent(_ period: Period, now: Date, calendar: Calendar) -> Bool {
        let interval = period.interval(calendar: calendar)
        return now >= interval.start && now < interval.end
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 347 tests in 32 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: compute picker ranges and the current period

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 账单页:按月查询、跳月份、搜全部;其他页面改用小查询

**Files:**
- Modify(整个换成): `HappySpending/Support/PeriodSwitcher.swift`
- Create: `HappySpending/Support/MonthPickerSheet.swift`
- Modify(整个换成): `HappySpending/Bills/EntryRowView.swift`
- Modify(整个换成): `HappySpending/Bills/CSVFile.swift`
- Create: `HappySpending/Bills/PendingEntryRow.swift`
- Create: `HappySpending/Bills/MonthBillsList.swift`
- Create: `HappySpending/Bills/HistorySearchList.swift`
- Modify(整个换成): `HappySpending/Bills/BillsView.swift`
- Modify(整个换成): `HappySpending/RootTabView.swift`
- Modify: `HappySpending/Bills/CategorizeSheet.swift`(一行)
- Modify: `HappySpending/Record/RecordView.swift`(一行)

**Interfaces:**
- Consumes: Task 1~3 的 `LedgerQueries`、`HistorySearch`、`BillsLogic.groupByMonth`、`MonthGroup`、`HistoryRange`;已有的 `PendingCategorization.pending`、`BillsLogic.groupByDay/search/dayTitle/monthTitle`、`Statistics.summary`、`CSVExporter`、`DeletedEntrySnapshot`、`EntryEditSheet(entry:categories:rows:)`、`CategorizeSheet(categories:rows:)`、`ToastView`、`CategoryIconView`。
- Produces:
  - `PeriodSwitcher(title:isNextDisabled:backTitle:onTitleTap:onBack:onPrevious:onNext:)`(后 5 个参数里只有 `onPrevious`、`onNext` 必填,原有调用照常编译)
  - `MonthPickerSheet(current:years:yearOnly:now:onPick:)`
  - `EntryRowView(row:showsDate:)`(`showsDate` 默认 false)
  - `CSVFile(name:rows:)`,`rows` 是 `@MainActor () throws -> [EntryRow]`

界面层没有单元测试;验证是构建通过 + 模拟器走一遍。

- [ ] **Step 1: 期间切换组件和年月选择器**

把 `HappySpending/Support/PeriodSwitcher.swift` 整个换成:

```swift
import SwiftUI

/// 账单页、统计页顶部的"‹ 2026年10月 ›"。点标题可以跳到任意月份,已在当前月时 › 置灰。
struct PeriodSwitcher: View {
    let title: String
    var isNextDisabled: Bool
    /// 不在当前月(或今年)时显示的"回到本月 / 回到今年";nil 时不显示。
    var backTitle: String?
    var onTitleTap: (() -> Void)?
    var onBack: (() -> Void)?
    let onPrevious: () -> Void
    let onNext: () -> Void

    init(
        title: String,
        isNextDisabled: Bool = false,
        backTitle: String? = nil,
        onTitleTap: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) {
        self.title = title
        self.isNextDisabled = isNextDisabled
        self.backTitle = backTitle
        self.onTitleTap = onTitleTap
        self.onBack = onBack
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onPrevious) { Image(systemName: "chevron.left") }
                    .buttonStyle(.glass)
                Spacer()
                Button { onTitleTap?() } label: {
                    HStack(spacing: 4) {
                        Text(title).font(.headline)
                        if onTitleTap != nil {
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(onTitleTap == nil)
                Spacer()
                Button(action: onNext) { Image(systemName: "chevron.right") }
                    .buttonStyle(.glass)
                    .disabled(isNextDisabled)
            }
            if let backTitle, let onBack {
                Button(backTitle, action: onBack)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }
}
```

新建 `HappySpending/Support/MonthPickerSheet.swift`:

```swift
import SwiftUI
import HappySpendingCore

/// 点账单页、统计页标题弹出的年月选择器;统计页年视图只选年份。
struct MonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let years: ClosedRange<Int>
    let yearOnly: Bool
    let now: Date
    let onPick: (Date) -> Void

    @State private var year: Int
    @State private var month: Int

    private let calendar = DayStamp.calendar

    init(current: Date, years: ClosedRange<Int>, yearOnly: Bool, now: Date, onPick: @escaping (Date) -> Void) {
        self.years = years
        self.yearOnly = yearOnly
        self.now = now
        self.onPick = onPick
        let components = DayStamp.calendar.dateComponents([.year, .month], from: current)
        _year = State(initialValue: min(max(components.year ?? years.upperBound, years.lowerBound), years.upperBound))
        _month = State(initialValue: components.month ?? 1)
    }

    /// 今年只能选到本月。
    private var months: ClosedRange<Int> { HistoryRange.months(in: year, now: now, calendar: calendar) }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $year) {
                    ForEach(Array(years), id: \.self) { Text(verbatim: "\($0)年").tag($0) }
                }
                .pickerStyle(.wheel)
                if !yearOnly {
                    Picker("月", selection: $month) {
                        ForEach(Array(months), id: \.self) { Text(verbatim: "\($0)月").tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .padding(.horizontal)
            .onChange(of: year) { month = min(month, months.upperBound) }
            .navigationTitle(yearOnly ? "选择年份" : "选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        // 年视图也保留原来的月份(夹在可选范围内),切回月视图时停在同一个月。
                        let picked = min(month, months.upperBound)
                        if let date = calendar.date(from: DateComponents(year: year, month: picked, day: 1)) {
                            onPick(date)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}
```

- [ ] **Step 2: 账单行显示日期、导出改成点了才取数据**

把 `HappySpending/Bills/EntryRowView.swift` 整个换成:

```swift
import SwiftUI
import HappySpendingCore

struct EntryRowView: View {
    let row: EntryRow
    /// 跨月份的搜索结果里在备注前显示日期(如"3月14日 周五 · 示例小吃")。
    var showsDate = false

    private var caption: String {
        var parts: [String] = []
        if showsDate { parts.append(BillsLogic.dayTitle(row.date, calendar: DayStamp.calendar)) }
        if !row.note.isEmpty { parts.append(row.note) }
        return parts.joined(separator: " · ")
    }

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
                if !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

把 `HappySpending/Bills/CSVFile.swift` 整个换成:

```swift
import SwiftUI
import UniformTypeIdentifiers
import HappySpendingCore

struct CSVFile: Transferable {
    let name: String
    /// 点导出时才取数据:"导出全部"不必在每次刷新页面时把全部账单准备一遍。
    let rows: @MainActor () throws -> [EntryRow]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let rows = try await MainActor.run { try file.rows() }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try CSVExporter.csv(rows).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
```

- [ ] **Step 3: 账单页的三块:待归类入口、按月列表、全部搜索**

新建 `HappySpending/Bills/PendingEntryRow.swift`:

```swift
import SwiftUI

/// 账单页顶部的"待归类 N 笔 ›"。
struct PendingEntryRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Section {
            Button(action: action) {
                HStack {
                    Label("待归类 \(count) 笔", systemImage: "tray.full")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
```

新建 `HappySpending/Bills/MonthBillsList.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

/// 账单页的"本月"模式:只从数据库查所选月份的账。
struct MonthBillsList: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LedgerEntry]

    let month: Date
    let query: String
    let pendingCount: Int
    let isCurrentMonth: Bool
    let onCategorize: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPickMonth: () -> Void
    let onBackToCurrent: () -> Void
    let onEdit: (LedgerEntry) -> Void
    let onDelete: (LedgerEntry) -> Void

    private let calendar = DayStamp.calendar

    init(
        month: Date,
        query: String,
        pendingCount: Int,
        isCurrentMonth: Bool,
        onCategorize: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPickMonth: @escaping () -> Void,
        onBackToCurrent: @escaping () -> Void,
        onEdit: @escaping (LedgerEntry) -> Void,
        onDelete: @escaping (LedgerEntry) -> Void
    ) {
        self.month = month
        self.query = query
        self.pendingCount = pendingCount
        self.isCurrentMonth = isCurrentMonth
        self.onCategorize = onCategorize
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onPickMonth = onPickMonth
        self.onBackToCurrent = onBackToCurrent
        self.onEdit = onEdit
        self.onDelete = onDelete
        _entries = Query(LedgerQueries.entries(in: .month(month), calendar: DayStamp.calendar))
    }

    private var rows: [EntryRow] { entries.map(\.row) }
    private var groups: [DayGroup] {
        BillsLogic.groupByDay(BillsLogic.search(rows, query: query), calendar: calendar)
    }
    private var summary: PeriodSummary { Statistics.summary(rows) }
    private var entriesByID: [UUID: LedgerEntry] {
        Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var monthTitle: String { BillsLogic.monthTitle(month, calendar: calendar) }

    var body: some View {
        List {
            if pendingCount > 0 {
                PendingEntryRow(count: pendingCount, action: onCategorize)
            }
            Section {
                PeriodSwitcher(
                    title: monthTitle,
                    isNextDisabled: isCurrentMonth,
                    backTitle: isCurrentMonth ? nil : "回到本月",
                    onTitleTap: onPickMonth,
                    onBack: onBackToCurrent,
                    onPrevious: onPrevious,
                    onNext: onNext
                )
                .listRowBackground(Color.clear)
                summaryRow
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        EntryRowView(row: row)
                            .onTapGesture { if let entry = entriesByID[row.id] { onEdit(entry) } }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    if let entry = entriesByID[row.id] { onDelete(entry) }
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
            // 占位不接收点击,免得挡住上面的 ‹ › 和标题。
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(isCurrentMonth ? "本月还没有账单" : "这个月没有账单", systemImage: "tray")
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: CSVFile(
                            name: CSVExporter.fileName(for: .month(month), calendar: calendar),
                            rows: { [rows] in rows }
                        ),
                        preview: SharePreview("导出 \(monthTitle)")
                    ) { Label("导出当月 CSV", systemImage: "calendar") }
                    ShareLink(
                        item: CSVFile(
                            name: CSVExporter.fileName(for: nil, calendar: calendar),
                            rows: { [container = context.container] in
                                try container.mainContext.fetch(LedgerQueries.all()).map(\.row)
                            }
                        ),
                        preview: SharePreview("导出全部账单")
                    ) { Label("导出全部 CSV", systemImage: "tray.full") }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
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
}
```

新建 `HappySpending/Bills/HistorySearchList.swift`:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

/// 账单页搜"全部":在所有月份里搜,结果按月份分组。停止输入约 0.3 秒后才查。
struct HistorySearchList: View {
    @Environment(\.modelContext) private var context

    let query: String
    /// 编辑、删除、撤销后由账单页加一,触发重查。
    let revision: Int
    let pendingCount: Int
    let onCategorize: () -> Void
    let onEdit: (LedgerEntry) -> Void
    let onDelete: (LedgerEntry) -> Void

    @State private var results: [LedgerEntry] = []
    @State private var searched = false

    private let calendar = DayStamp.calendar

    private var rows: [EntryRow] { results.map(\.row) }
    private var groups: [MonthGroup] { BillsLogic.groupByMonth(rows, calendar: calendar) }
    private var resultsByID: [UUID: LedgerEntry] {
        Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            if pendingCount > 0 {
                PendingEntryRow(count: pendingCount, action: onCategorize)
            }
            if !results.isEmpty {
                Section {
                    Text("找到 \(results.count) 笔 · 支出 \(Money.display(Statistics.summary(rows).expenseCents))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        EntryRowView(row: row, showsDate: true)
                            .onTapGesture { if let entry = resultsByID[row.id] { onEdit(entry) } }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    if let entry = resultsByID[row.id] {
                                        results.removeAll { $0.id == row.id }
                                        onDelete(entry)
                                    }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(BillsLogic.monthTitle(group.month, calendar: calendar))
                        Spacer()
                        Text("支出 " + Money.display(group.expenseCents)).monospacedDigit()
                    }
                }
            }
        }
        .overlay {
            if searched && results.isEmpty {
                ContentUnavailableView.search(text: query).allowsHitTesting(false)
            }
        }
        .task(id: "\(revision)|\(query)") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = (try? HistorySearch.search(query, in: context)) ?? []
            searched = true
        }
    }
}
```

- [ ] **Step 4: 账单页外壳**

把 `HappySpending/Bills/BillsView.swift` 整个换成:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

/// 账单页的搜索范围。
enum BillsSearchScope: Hashable {
    case month, all
}

struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]
    @Query(LedgerQueries.recent()) private var recent: [LedgerEntry]
    @Query(LedgerQueries.earliest()) private var earliest: [LedgerEntry]

    @State private var month = DayStamp.stamp(.now)
    @State private var query = ""
    @State private var scope = BillsSearchScope.month
    @State private var editing: LedgerEntry?
    @State private var undo: DeletedEntrySnapshot?
    @State private var errorMessage: String?
    @State private var categorizing = false
    @State private var pickingMonth = false
    /// 搜"全部"的结果在编辑、删除、撤销后要重查;每次改动加一。
    @State private var searchRevision = 0

    private let calendar = DayStamp.calendar

    private var now: Date { DayStamp.stamp(.now) }
    /// 所有月份里待归类的笔数。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }
    /// 编辑页、归类面板算"常用分类"用的最近 300 笔。
    private var recentRows: [EntryRow] { recent.map(\.row) }
    private var isCurrentMonth: Bool { HistoryRange.isCurrent(.month(month), now: now, calendar: calendar) }
    private var isSearchingAll: Bool {
        scope == .all && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearchingAll {
                    HistorySearchList(
                        query: query,
                        revision: searchRevision,
                        pendingCount: pendingCount,
                        onCategorize: { categorizing = true },
                        onEdit: { editing = $0 },
                        onDelete: delete
                    )
                } else {
                    MonthBillsList(
                        month: month,
                        query: query,
                        pendingCount: pendingCount,
                        isCurrentMonth: isCurrentMonth,
                        onCategorize: { categorizing = true },
                        onPrevious: { shiftMonth(-1) },
                        onNext: { shiftMonth(1) },
                        onPickMonth: { pickingMonth = true },
                        onBackToCurrent: { month = now },
                        onEdit: { editing = $0 },
                        onDelete: delete
                    )
                }
            }
            .navigationTitle("账单")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索备注、分类或金额")
            .searchScopes($scope) {
                Text("本月").tag(BillsSearchScope.month)
                Text("全部").tag(BillsSearchScope.all)
            }
            .sheet(item: $editing, onDismiss: { searchRevision += 1 }) { entry in
                EntryEditSheet(entry: entry, categories: categories, rows: recentRows)
            }
            .sheet(isPresented: $categorizing) {
                CategorizeSheet(categories: categories, rows: recentRows)
            }
            .sheet(isPresented: $pickingMonth) {
                MonthPickerSheet(
                    current: month,
                    years: HistoryRange.years(earliest: earliest.first?.date, now: now, calendar: calendar),
                    yearOnly: false,
                    now: now
                ) { month = $0 }
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

    private func shiftMonth(_ delta: Int) {
        // 已经是当前月时 › 置灰;这里再拦一次,不翻到未来。
        guard delta < 0 || !isCurrentMonth else { return }
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func delete(_ entry: LedgerEntry) {
        let snapshot = DeletedEntrySnapshot(entry)
        context.delete(entry)
        guard persist() else { return }
        searchRevision += 1
        withAnimation { undo = snapshot }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undo == snapshot { withAnimation { undo = nil } }
        }
    }

    private func restore(_ snapshot: DeletedEntrySnapshot) {
        // 连点两次"撤销"不能造出两笔同 id 的账单。
        guard undo == snapshot,
              (try? context.fetchCount(LedgerQueries.entry(id: snapshot.id))) == 0
        else { return }
        let entry = snapshot.makeEntry(categories: categories)
        context.insert(entry)
        _ = persist()
        searchRevision += 1
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

- [ ] **Step 5: 页签角标、归类面板、记账页改用小查询**

把 `HappySpending/RootTabView.swift` 整个换成:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    /// 只查没有分类的账,再挑出支出,作为账单页签的角标。
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }

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

在 `HappySpending/Bills/CategorizeSheet.swift` 里,把

```swift
    @Query private var entries: [LedgerEntry]
```

换成

```swift
    /// 只查没有分类的账;队列再从中挑出支出并排序。
    @Query(LedgerQueries.uncategorized()) private var entries: [LedgerEntry]
```

在 `HappySpending/Record/RecordView.swift` 里,把

```swift
    @Query(sort: \LedgerEntry.createdAt, order: .reverse) private var entries: [LedgerEntry]
```

换成

```swift
    /// 只查最近 300 笔:常用分类和"上次用过的分类"都只看最近的账。
    @Query(LedgerQueries.recent()) private var entries: [LedgerEntry]
```

- [ ] **Step 6: 构建**

Run: Global Constraints 里的 app 构建命令。
Expected: `** BUILD SUCCEEDED **`,没有 HappySpending 目录下的警告。

- [ ] **Step 7: 模拟器里走一遍**

覆盖安装到模拟器(不要卸载)并启动,打开账单页。如果模拟器里只有本月的账,先在任意一笔的编辑页把日期改到几个月前,造出历史数据。
Expected:
- 默认是当前月,› 置灰,没有"回到本月"。
- 点 ‹ 到上个月:› 可点,标题下出现"回到本月";点"回到本月"回到当前月。
- 点标题弹出年月选择器:年份从最早一笔所在年到今年;今年的未来月份不出现;选一个月点"完成"跳过去。
- 翻到一个没有账的历史月份:显示"这个月没有账单",并且这时 ‹ › 和标题仍然能点(Review Focus 5)。
- 搜索框下有"本月 / 全部":选"全部"输入一个备注里的词,停顿后出现按月分组的结果,每行有日期,顶部是"找到 N 笔 · 支出 ¥X";输入一个金额(如某笔的整数元)也能找到。
- 在"全部"结果里点一笔改分类,关闭后结果更新;左滑删除一笔,底部出现"撤销",点撤销后它回到结果里。
- 清空搜索后回到月份视图;"待归类"入口、角标照常。
- 导出菜单里"导出当月 CSV"和"导出全部 CSV"都能弹出分享面板。

- [ ] **Step 8: 提交**

```bash
git add HappySpending
git commit -m "feat: query bills by month, jump to any month and search all history

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 统计页按所选区间查询、跳月份 / 年份

**Files:**
- Modify(整个换成): `HappySpending/Stats/StatsView.swift`

**Interfaces:**
- Consumes: `LedgerQueries.entries(in:calendar:)`、`LedgerQueries.earliest()`、`HistoryRange`、Task 4 的 `PeriodSwitcher`、`MonthPickerSheet`;已有的 `StatsScope`、`StatsBackground`、`SummaryCard`、`SharesSection`、`TrendSection`、`CategoryDetailView`、`Statistics`。
- Produces: 无新接口。

- [ ] **Step 1: 改统计页**

把 `HappySpending/Stats/StatsView.swift` 整个换成:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct StatsView: View {
    @Query(LedgerQueries.earliest()) private var earliest: [LedgerEntry]
    @State private var scope: StatsScope = .month
    @State private var anchor = DayStamp.stamp(.now)
    @State private var picking = false

    private let calendar = DayStamp.calendar

    private var now: Date { DayStamp.stamp(.now) }
    private var year: Int { calendar.component(.year, from: anchor) }
    private var period: Period { scope == .month ? .month(anchor) : .year(year) }
    private var isCurrent: Bool { HistoryRange.isCurrent(period, now: now, calendar: calendar) }
    private var title: String {
        scope == .month
            ? BillsLogic.monthTitle(anchor, calendar: calendar)
            : "\(year)年"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StatsBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        controls
                        StatsPeriodContent(period: period, anchor: anchor, scope: scope)
                    }
                    .padding()
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CategoryShare.self) { CategoryDetailView(share: $0) }
            .sheet(isPresented: $picking) {
                MonthPickerSheet(
                    current: anchor,
                    years: HistoryRange.years(earliest: earliest.first?.date, now: now, calendar: calendar),
                    yearOnly: scope == .year,
                    now: now
                ) { anchor = $0 }
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Picker("周期", selection: $scope) {
                    ForEach(StatsScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                PeriodSwitcher(
                    title: title,
                    isNextDisabled: isCurrent,
                    backTitle: isCurrent ? nil : (scope == .month ? "回到本月" : "回到今年"),
                    onTitleTap: { picking = true },
                    onBack: { anchor = now },
                    onPrevious: { shift(-1) },
                    onNext: { shift(1) }
                )
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    private func shift(_ delta: Int) {
        // 已经是当前月(或今年)时 › 置灰;这里再拦一次,不翻到未来。
        guard delta < 0 || !isCurrent else { return }
        let component: Calendar.Component = scope == .month ? .month : .year
        anchor = calendar.date(byAdding: component, value: delta, to: anchor) ?? anchor
    }
}

/// 统计页的内容:只从数据库查所选月份或年份的账。
struct StatsPeriodContent: View {
    @Query private var entries: [LedgerEntry]

    let anchor: Date
    let scope: StatsScope

    private let calendar = DayStamp.calendar

    init(period: Period, anchor: Date, scope: StatsScope) {
        self.anchor = anchor
        self.scope = scope
        _entries = Query(LedgerQueries.entries(in: period, calendar: DayStamp.calendar))
    }

    private var rows: [EntryRow] { entries.map(\.row) }
    private var year: Int { calendar.component(.year, from: anchor) }
    private var trend: [TrendPoint] {
        scope == .month
            ? Statistics.dailyTrend(rows, month: anchor, calendar: calendar)
            : Statistics.monthlyTrend(rows, year: year, calendar: calendar)
    }

    var body: some View {
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
}
```

- [ ] **Step 2: 构建**

Run: Global Constraints 里的 app 构建命令。
Expected: `** BUILD SUCCEEDED **`,没有 HappySpending 目录下的警告。

- [ ] **Step 3: 模拟器里看统计页**

覆盖安装并启动,打开统计页。
Expected:
- 月视图:› 置灰;点 ‹ 后出现"回到本月";点标题弹出年月选择器,选好后跳过去。
- 切到年视图:标题是"2026年",› 置灰;点 ‹ 到 2025 年后出现"回到今年";点标题弹出只有年份一列的选择器。
- 饼图、趋势、收入分类和之前一样显示;点支出分类能进入分类详情。

- [ ] **Step 4: 提交**

```bash
git add HappySpending
git commit -m "feat: query stats by period and jump to any month or year

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 性能实测、检查清单、最终验证

**Files:**
- Create(临时,不提交): `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/ZBenchmarkTests.swift`
- Modify: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: Task 1~3 的 Core 接口。
- Produces: 无。

- [ ] **Step 1: 用 5 年数据实测**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/ZBenchmarkTests.swift`(只为测量,跑完删除):

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

/// 临时性能测量,不提交:5 年、每天 10 笔,存在磁盘上的数据库。
@MainActor
struct ZBenchmarkTests {
    @Test func fiveYears() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "bench-\(UUID()).store")
        let schema = Schema([LedgerCategory.self, LedgerEntry.self, MerchantCategory.self])
        let cal = testCalendar
        let start = makeDate(2021, 11, 1)
        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
            let ctx = container.mainContext
            try DefaultCategories.seedIfNeeded(in: ctx)
            let cats = try ctx.fetch(FetchDescriptor<LedgerCategory>()).filter { $0.kind == .expense }
            for i in 0..<18_250 {
                let day = cal.date(byAdding: .day, value: i / 10, to: start)!
                ctx.insert(LedgerEntry(
                    amountInCents: 100 + i % 5000, kind: .expense, date: day, note: "示例\(i % 50)",
                    category: i % 97 == 0 ? nil : cats[i % cats.count], createdAt: day, calendar: cal
                ))
            }
            try ctx.save()
        }
        let ctx = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url)).mainContext
        let clock = ContinuousClock()
        let lastMonth = cal.date(byAdding: .day, value: 18_249 / 10, to: start)!

        let bills = try clock.measure {
            let rows = try ctx.fetch(LedgerQueries.entries(in: .month(lastMonth), calendar: cal)).map(\.row)
            _ = BillsLogic.groupByDay(BillsLogic.search(rows, query: "示例1"), calendar: cal)
            _ = Statistics.summary(rows)
        }
        let pending = try clock.measure {
            _ = PendingCategorization.pending(try ctx.fetch(LedgerQueries.uncategorized())).count
        }
        let recent = try clock.measure { _ = try ctx.fetch(LedgerQueries.recent()).map(\.row) }
        let year = try clock.measure {
            let rows = try ctx.fetch(LedgerQueries.entries(in: .year(2025), calendar: cal)).map(\.row)
            _ = Statistics.shares(rows, kind: .expense)
        }
        let searchNote = try clock.measure { _ = try HistorySearch.search("示例1", in: ctx) }
        let searchAmount = try clock.measure { _ = try HistorySearch.search("47", in: ctx) }

        print("BENCH 5y bills=\(bills) pending=\(pending) recent=\(recent) statsYear=\(year) searchNote=\(searchNote) searchAmount=\(searchAmount)")
    }
}
```

Run: `swift test --package-path Packages/HappySpendingCore --filter ZBenchmarkTests 2>&1 | grep -E "BENCH|error:|passed|failed"`
Expected:账单页一次刷新(`bills` + `pending` + `recent`)合计在 50 毫秒以内;`statsYear` 约等于一年的数据量,不随使用年数增长;两次搜"全部"各在几百毫秒以内(停止输入后只查一次)。把 BENCH 那一行原样记进 ledger。

然后删掉这个文件:`rm Packages/HappySpendingCore/Tests/HappySpendingCoreTests/ZBenchmarkTests.swift`

- [ ] **Step 2: 检查清单**

Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "docs/manual-test-checklist.md"
s = open(p, encoding="utf-8").read()
assert s.count("## 深色模式") == 1
s = s.replace("## 深色模式", """## 账单查历史

- [ ] 账单页默认当前月,› 置灰;翻到历史月份后出现"回到本月"
- [ ] 点标题弹出年月选择器:年份从最早一笔到今年,今年的未来月份不可选
- [ ] 没有账的历史月份显示"这个月没有账单",‹ › 和标题仍可点
- [ ] 搜索"全部":按月分组、每行有日期、顶部"找到 N 笔 · 支出 ¥X";金额(147 / 147.70)也能搜到
- [ ] 在"全部"结果里编辑、删除、撤销后结果随之更新
- [ ] 统计页月 / 年视图:点标题跳转,› 置灰,"回到本月 / 回到今年"
- [ ] "导出当月 CSV""导出全部 CSV"都能导出

## 深色模式""")
open(p, "w", encoding="utf-8").write(s)
EOF
```

Expected: 没有输出。

- [ ] **Step 3: 最终验证**

Run: Global Constraints 里的测试命令,再跑 app 构建命令;`git status --short` 确认临时性能测试文件已经删除、没有提交。
Expected: `✔ Test run with 347 tests in 32 suites passed`;`** BUILD SUCCEEDED **`;没有 HappySpending 目录下的警告;工作区只剩检查清单的改动。

- [ ] **Step 4: 提交**

```bash
git add docs/manual-test-checklist.md
git commit -m "docs: add history browsing checks to the manual checklist

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
