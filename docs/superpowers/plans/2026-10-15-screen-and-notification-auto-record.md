# 屏幕识别与通知自动入账 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供两个快捷指令动作:"记一笔(屏幕识别)"解析微信/支付宝支付页的识别文字,"记一笔(通知)"解析微信/支付宝的支付通知,把支出自动记进来。

**Architecture:** 解析与入账逻辑全部放进 `HappySpendingCore`,用 `swift test` 在 Mac 上测:统一的 `PaymentRecord`/`ParseOutcome`、通知解析器、屏幕文字解析器、支付宝分类映射、重构后的 `AutoEntryRecorder`(商户记忆 → 分类映射 → 未分类,单号相同跳过)、对快捷指令友好的 `PaymentCapture`。app 层只加两个只转调 Core 的 `AppIntent`,并更新设置页帮助页。**测试用例直接取自作者提供的真实样本**(敏感部分已替换成假值)。

**Tech Stack:** Swift 6.3, SwiftData, App Intents, CryptoKit, Swift Testing。

**Spec:** `docs/superpowers/specs/2026-10-15-screen-and-notification-auto-record-design.md`(上位文档:`2026-10-13-apple-pay-auto-record-design.md`、`2026-10-10-bookkeeping-app-design.md`)

## Global Constraints

- 最低系统 **iOS 26**;无后端、无网络请求、**无第三方依赖**(CryptoKit 是系统库)。
- **只记支出**:账单页金额带 `+` 是收入,忽略;通知里"收入"忽略;微信的已退款、收款等通知忽略/认不出。
- **解析锚定关键词和整句模式,不依赖行号**:状态栏时间、电量、操作按钮的提示这类噪音行不能影响结果。
- 支付宝通知:标题含"交易提醒",正文匹配 `你有一笔 <金额> 元的支出`,**不取正文里其他数字**(如"领 2 元小荷包")。微信通知:标题含"微信支付",正文匹配 `已支付 ¥<金额>`。两种都没有商户名,备注分别为"支付宝""微信支付"。
- 屏幕页面三种:微信·支付成功页、微信·账单详情页、支付宝·账单详情页。判断顺序:微信账单页 → 支付宝账单页 → 微信成功页。
- 日期取页面上的支付时间(`eventDate`),读不出就取触发时刻;时间日期里夹杂识别错误(如 `2026·10 514E 17:37:40`)时 `eventDate` 为空。
- 去重**只保留一条**:单号(哈希)相同就跳过;没有单号不去重;不做基于时间或跨来源的去重。
- 分类优先级:商户记忆 → 支付宝分类映射(只对屏幕识别的支付宝账单页)→ 未分类。映射目标必须是**未归档的支出一级分类**。
- 屏幕识别认不出页面:抛错"没有识别到支付页面";通知认不出或被忽略:安静成功返回,不报错。
- **不保存**图片、识别出的原文、通知的标题和正文;只保存金额、商户、备注、日期、来源和单号哈希(SHA-256)。
- 新增字段都是可选的,`EntrySource` 只多两个取值,依靠 SwiftData 轻量迁移。
- 命名沿用:`LedgerEntry`、`LedgerCategory`。
- 测试用 Swift Testing;SwiftData 测试用内存容器,**测试里必须一直持有 `ModelContainer`**。
- Core 命令都用 `swift test --package-path Packages/HappySpendingCore`;仓库根目录是 `/Users/strawturtle/Desktop/Develop/Self/Self IOS App/happy_spending`;工作在分支 `screen-notification-record` 上。
- 提交信息末尾带上本次会话给出的 `Co-Authored-By` 署名行。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都在对应任务里有测试:

1. **识别文字里的噪音和乱码**:状态栏时间、电量、操作按钮的提示行、日期乱码、商户被打码成 `**` 或全是符号。→ Task 4
2. **金额的怪写法**:正文里有第二个促销金额、减号的各种写法(`-`、`−`、`－`、带空格)、`¥`/`￥`/`Y`、千分位、超上限、为 0。→ Task 3、Task 4
3. **不是支付的文字**:聊天消息标题、其他 app 的通知、随手截图的文字、收入、退款、只有部分关键词的页面。→ Task 3、Task 4、Task 5
4. **单号去重**:同一单号第二次跳过、不同单号不跳过、没有单号不跳过;撤销删除后单号哈希还在。→ Task 1、Task 2
5. **分类优先级和失效目标**:记忆优先于映射;映射目标被改名或归档时落空;映射不会选到收入分类。→ Task 2

---

### Task 1: 数据模型:来源、单号哈希、PaymentRecord

**Files:**
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/EntrySource.swift`
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerEntry.swift`
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/DeletedEntrySnapshot.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/PaymentRecord.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/OrderRef.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentModelTests.swift`

**Interfaces:**
- Consumes: 已有的 `LedgerEntry`、`makeTestContainer()`、`makeDate`
- Produces:
  - `EntrySource` 新增 `screenText`、`notification`
  - `LedgerEntry.orderRefHash: String?`;`init(... merchant:, orderRefHash: String? = nil)`(新参数放在最后)
  - `DeletedEntrySnapshot.orderRefHash`,`makeEntry` 带回
  - `struct PaymentRecord: Equatable, Sendable { source, cents, merchant, note, eventDate, orderRef, platformCategory }`
  - `enum ParseOutcome: Equatable, Sendable { case payment(PaymentRecord), ignored(String), unrecognized }`
  - `enum OrderRef { static func hash(_ raw: String) -> String? }`(去掉所有空白后做 SHA-256,返回 64 位小写十六进制;空白串返回 nil)

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentModelTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PaymentModelTests {
    @Test func newSourcesHaveStableRawValues() {
        #expect(EntrySource.screenText.rawValue == "screenText")
        #expect(EntrySource.notification.rawValue == "notification")
        #expect(EntrySource.applePay.rawValue == "applePay")
    }

    @Test func entriesStartWithoutAnOrderRefHash() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 15))
        context.insert(entry)

        #expect(entry.orderRefHash == nil)
    }

    @Test func orderRefHashSurvivesASaveAndFetch() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(LedgerEntry(
            amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 15),
            autoSource: .screenText, orderRefHash: "abc123"
        ))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(fetched.count == 1)
        #expect(fetched[0].orderRefHash == "abc123")
        #expect(fetched[0].autoSource == .screenText)
        #expect(fetched[0].isAuto)
    }

    @Test func restoringADeletedEntryKeepsItsOrderRefHash() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let original = LedgerEntry(
            amountInCents: 1512, kind: .expense, date: makeDate(2026, 10, 14),
            note: "示例商户", autoSource: .screenText, merchant: "示例商户", orderRefHash: "deadbeef"
        )
        context.insert(original)

        let snapshot = DeletedEntrySnapshot(original)
        context.delete(original)
        let restored = snapshot.makeEntry(categories: [])

        #expect(restored.orderRefHash == "deadbeef")
        #expect(restored.autoSource == .screenText)
        #expect(restored.merchant == "示例商户")
    }

    // MARK: OrderRef

    @Test func orderRefHashIsA64CharLowercaseHexDigest() throws {
        let hash = try #require(OrderRef.hash("10000000000000000000000000000000"))
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func orderRefHashIgnoresWhitespace() {
        #expect(OrderRef.hash("1000 0000 0000") == OrderRef.hash("100000000000"))
        #expect(OrderRef.hash(" 100000000000\n") == OrderRef.hash("100000000000"))
    }

    @Test func differentOrderRefsHaveDifferentHashes() {
        #expect(OrderRef.hash("100000000001") != OrderRef.hash("100000000002"))
    }

    @Test func blankOrderRefsHaveNoHash() {
        #expect(OrderRef.hash("") == nil)
        #expect(OrderRef.hash("   \n ") == nil)
    }

    // MARK: PaymentRecord

    @Test func paymentRecordDefaultsAreEmpty() {
        let record = PaymentRecord(source: .notification, cents: 1512, note: "支付宝")
        #expect(record.merchant == nil)
        #expect(record.eventDate == nil)
        #expect(record.orderRef == nil)
        #expect(record.platformCategory == nil)
        #expect(record.note == "支付宝")
    }

    @Test func parseOutcomesCompareByValue() {
        let record = PaymentRecord(source: .screenText, cents: 20, note: "微信")
        #expect(ParseOutcome.payment(record) == .payment(record))
        #expect(ParseOutcome.ignored("收入") == .ignored("收入"))
        #expect(ParseOutcome.ignored("收入") != .unrecognized)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter PaymentModelTests`
Expected: 编译失败,报 `type 'EntrySource' has no member 'screenText'`(以及 `OrderRef`、`PaymentRecord` 等)。

- [ ] **Step 3: 写实现**

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/EntrySource.swift`:

```swift
/// 自动账的来源。账单行上都显示同一个"自动"标记。
public enum EntrySource: String, Codable, Sendable {
    /// Apple Pay("钱包 → 交易"自动化)。
    case applePay
    /// 微信、支付宝的支付页:用户触发"拍摄屏幕截图 → 提取文字"后交给 app 解析。
    case screenText
    /// 微信、支付宝的支付通知("收到通知时"自动化)。
    case notification
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/OrderRef.swift`:

```swift
import Foundation
import CryptoKit

/// 单号只用来判断"是不是同一笔",所以只存哈希,不存原文。
public enum OrderRef {
    /// 去掉所有空白后做 SHA-256,返回 64 位小写十六进制;内容为空返回 nil。
    public static func hash(_ raw: String) -> String? {
        let compact = raw.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }
        return SHA256.hash(data: Data(compact.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/PaymentRecord.swift`:

```swift
import Foundation

/// 解析器统一的输出:从通知、屏幕文字里提取出的一笔支出。不入库。
public struct PaymentRecord: Equatable, Sendable {
    public let source: EntrySource
    /// 金额,整数分,大于 0。
    public let cents: Int
    /// 商户名;没有就是 nil。
    public let merchant: String?
    /// 账单备注:有商户用商户名,没有就用渠道名("微信""支付宝""微信支付")。
    public let note: String
    /// 页面上的支付时间;读不出就是 nil(入账时取触发时刻)。
    public let eventDate: Date?
    /// 单号原文(写库前会做哈希)。
    public let orderRef: String?
    /// 支付宝账单页上的分类名,如"日用百货"。
    public let platformCategory: String?

    public init(
        source: EntrySource,
        cents: Int,
        merchant: String? = nil,
        note: String,
        eventDate: Date? = nil,
        orderRef: String? = nil,
        platformCategory: String? = nil
    ) {
        self.source = source
        self.cents = cents
        self.merchant = merchant
        self.note = note
        self.eventDate = eventDate
        self.orderRef = orderRef
        self.platformCategory = platformCategory
    }
}

public enum ParseOutcome: Equatable, Sendable {
    /// 识别出一笔支出。
    case payment(PaymentRecord)
    /// 认得出,但不该记(收入等),附原因。
    case ignored(String)
    /// 认不出是支付通知或支付页面。
    case unrecognized
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
    /// 单号的 SHA-256 哈希,只用于"单号相同就跳过";没有单号就是 nil。
    public var orderRefHash: String?

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
        merchant: String? = nil,
        orderRefHash: String? = nil
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
        self.orderRefHash = orderRefHash
    }
}
```

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/DeletedEntrySnapshot.swift`:

```swift
import Foundation

/// 删除一笔账之前的快照,用于"撤销"重新建回这一笔。
/// 自动账的来源、商户和单号哈希也要带回来,否则撤销后它会变成手动账(丢掉"自动"标记和分类记忆)。
public struct DeletedEntrySnapshot: Equatable, Sendable {
    public let id: UUID
    public let amountInCents: Int
    public let kind: EntryKind
    public let date: Date
    public let createdAt: Date
    public let note: String
    public let categoryID: UUID?
    public let autoSourceRaw: String?
    public let merchant: String?
    public let orderRefHash: String?

    public init(_ entry: LedgerEntry) {
        id = entry.id
        amountInCents = entry.amountInCents
        kind = entry.kind
        date = entry.date
        createdAt = entry.createdAt
        note = entry.note
        categoryID = entry.category?.id
        autoSourceRaw = entry.autoSourceRaw
        merchant = entry.merchant
        orderRefHash = entry.orderRefHash
    }

    /// 用快照重新建一笔账(还没插入上下文)。分类按 ID 在 `categories` 里找,找不到就是未分类。
    public func makeEntry(categories: [LedgerCategory]) -> LedgerEntry {
        let entry = LedgerEntry(
            id: id,
            amountInCents: amountInCents,
            kind: kind,
            date: date,
            note: note,
            category: categories.first { $0.id == categoryID },
            createdAt: createdAt,
            calendar: DayStamp.calendar,
            merchant: merchant,
            orderRefHash: orderRefHash
        )
        entry.autoSourceRaw = autoSourceRaw
        return entry
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(198 个),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add payment sources, orderRefHash, PaymentRecord and ParseOutcome"
```

---

### Task 2: 支付宝分类映射与入账重构

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/PlatformCategoryMap.swift`
- Replace: `Packages/HappySpendingCore/Sources/HappySpendingCore/AutoEntryRecorder.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentRecorderTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `PaymentRecord`、`OrderRef`、`LedgerEntry.orderRefHash`;已有的 `MerchantMemory`、`MerchantKey`、`CategoryRules`、`AmountText`、`Money`
- Produces:
  - `enum PlatformCategoryMap { static let alipay: [String: String]; static func ourCategoryName(forAlipay name: String) -> String? }`
  - `AutoEntryResult.isDuplicate: Bool`(init 里新增,放在最后)
  - `AutoEntryRecorder.record(_ payment: PaymentRecord, now: Date = .now, calendar: Calendar = .current, in context: ModelContext) throws -> AutoEntryResult`
  - 现有的 `record(merchant:amountText:now:calendar:in:)` 保留,内部转成 `PaymentRecord(source: .applePay, ...)`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentRecorderTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PaymentRecorderTests {
    private let now = makeDate(2026, 10, 15, 9, 30)

    private func makeCategories(_ context: ModelContext) throws -> (daily: LedgerCategory, food: LedgerCategory, lunch: LedgerCategory, salary: LedgerCategory) {
        let daily = CategoryRules.addTopLevel(
            name: "日用", symbolName: "basket.fill", colorHex: "#34C759",
            kind: .expense, sortOrder: 0, in: context
        )
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 1, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let salary = CategoryRules.addTopLevel(
            name: "工资", symbolName: "banknote.fill", colorHex: "#30D158",
            kind: .income, sortOrder: 0, in: context
        )
        return (daily, food, lunch, salary)
    }

    private func entries(_ context: ModelContext) throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    // MARK: 映射表

    @Test func theAlipayMapCoversTheDocumentedCategories() {
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "日用百货") == "日用")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "餐饮美食") == "餐饮")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "交通出行") == "交通")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "服饰装扮") == "服饰")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "爱车养车") == "汽车")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "酒店旅游") == "旅游")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "医疗健康") == "医疗")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "住房物业") == "居住")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "数码电器") == "购物")
    }

    @Test func unknownAlipayCategoriesHaveNoMapping() {
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "充值缴费") == nil)
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "") == nil)
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "日用") == nil)
    }

    // MARK: 记账

    @Test func recordsANotificationPaymentWithItsSourceAndNote() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(source: .notification, cents: 1512, note: "支付宝")

        let result = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.amountInCents == 1512)
        #expect(entry.kind == .expense)
        #expect(entry.note == "支付宝")
        #expect(entry.merchant == nil)
        #expect(entry.autoSource == .notification)
        #expect(entry.category == nil)
        #expect(entry.date == makeDate(2026, 10, 15))
        #expect(entry.createdAt == now)
        #expect(entry.orderRefHash == nil)
        #expect(result.entryID == entry.id)
        #expect(result.cents == 1512)
        #expect(!result.isDuplicate)
        #expect(result.message == "已记 ¥15.12 · 支付宝")
    }

    @Test func theMessageNamesTheMerchantWhenThereIsOne() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(source: .screenText, cents: 20, merchant: "示例商户", note: "示例商户")

        let result = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(result.message == "已记 ¥0.20 · 示例商户")
        #expect(try entries(context).first?.merchant == "示例商户")
    }

    @Test func theEventDateWinsOverTheTriggerTime() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(
            source: .screenText, cents: 1512, note: "支付宝",
            eventDate: makeDate(2026, 10, 14, 14, 9)
        )

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.date == makeDate(2026, 10, 14))
    }

    @Test func withoutAnEventDateTheTriggerDayIsUsed() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 20, note: "微信"),
            now: now, calendar: testCalendar, in: context
        )

        #expect(try entries(context).first?.date == makeDate(2026, 10, 15))
    }

    // MARK: 单号去重

    @Test func theSameOrderNumberIsRecordedOnlyOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(
            source: .screenText, cents: 20, merchant: "示例商户", note: "示例商户",
            orderRef: "10000000000000000000000000000000"
        )

        let first = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)
        let second = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).count == 1)
        #expect(!first.isDuplicate)
        #expect(second.isDuplicate)
        #expect(second.entryID == first.entryID)
        #expect(second.message == "已记过这一笔(单号相同)")
    }

    @Test func differentOrderNumbersAreBothRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        for ref in ["10000000000000000000000000000001", "10000000000000000000000000000002"] {
            try AutoEntryRecorder.record(
                PaymentRecord(source: .screenText, cents: 20, note: "微信", orderRef: ref),
                now: now, calendar: testCalendar, in: context
            )
        }

        #expect(try entries(context).count == 2)
    }

    @Test func paymentsWithoutAnOrderNumberAreNeverDeduplicated() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(source: .screenText, cents: 20, note: "微信")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)
        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).count == 2)
    }

    @Test func theStoredHashIsTheHashNotTheRawOrderNumber() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let raw = "10000000000000000000000000000000"

        try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 20, note: "微信", orderRef: raw),
            now: now, calendar: testCalendar, in: context
        )

        let stored = try #require(try entries(context).first?.orderRefHash)
        #expect(stored == OrderRef.hash(raw))
        #expect(stored != raw)
    }

    // MARK: 分类优先级

    @Test func merchantMemoryIsUsedFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, food, _, _) = try makeCategories(context)
        try MerchantMemory.learn(merchant: "示例商户", categoryID: food.id, in: context)
        let payment = PaymentRecord(
            source: .screenText, cents: 1512, merchant: "示例商户", note: "示例商户",
            platformCategory: "日用百货"
        )

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category === food)
        #expect(entry.category !== daily)
    }

    @Test func theAlipayCategoryMapIsUsedWhenThereIsNoMemory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, _, _, _) = try makeCategories(context)
        let payment = PaymentRecord(
            source: .screenText, cents: 1512, merchant: "示例商户", note: "示例商户",
            platformCategory: "日用百货"
        )

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category === daily)
    }

    @Test func theMapAppliesEvenWithoutAMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, food, _, _) = try makeCategories(context)
        let payment = PaymentRecord(source: .screenText, cents: 3000, note: "支付宝", platformCategory: "餐饮美食")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category === food)
    }

    @Test func aMappingTargetThatIsArchivedFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, _, _, _) = try makeCategories(context)
        CategoryRules.archive(daily)
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "日用百货")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func aMappingTargetThatWasRenamedFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, _, _, _) = try makeCategories(context)
        daily.name = "家居"
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "日用百货")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func theMapNeverPicksAnIncomeCategoryWithTheSameName() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        CategoryRules.addTopLevel(
            name: "日用", symbolName: "gift.fill", colorHex: "#FFD60A",
            kind: .income, sortOrder: 0, in: context
        )
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "日用百货")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func anUnmappedPlatformCategoryIsUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try makeCategories(context)
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "充值缴费")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    // MARK: 学习

    @Test func aScreenEntryWithAMerchantCanLearnFromAnEdit() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, food, _, _) = try makeCategories(context)
        try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 1512, merchant: "示例商户", note: "示例商户"),
            now: now, calendar: testCalendar, in: context
        )
        let entry = try #require(try entries(context).first)

        entry.category = food
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)

        #expect(learned)
    }

    @Test func aNotificationEntryHasNoMerchantSoItNeverLearns() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, food, _, _) = try makeCategories(context)
        try AutoEntryRecorder.record(
            PaymentRecord(source: .notification, cents: 1512, note: "支付宝"),
            now: now, calendar: testCalendar, in: context
        )
        let entry = try #require(try entries(context).first)

        entry.category = food
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)

        #expect(!learned)
    }

    // MARK: Apple Pay 入口仍然可用

    @Test func theApplePayEntryPointStillWorks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try AutoEntryRecorder.record(
            merchant: "  美团 ", amountText: "¥25.50", now: now, calendar: testCalendar, in: context
        )

        let entry = try #require(try entries(context).first)
        #expect(entry.autoSource == .applePay)
        #expect(entry.merchant == "美团")
        #expect(entry.note == "美团")
        #expect(entry.amountInCents == 2550)
        #expect(result.message == "已记 ¥25.50 · 美团")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter PaymentRecorderTests`
Expected: 编译失败,报 `cannot find 'PlatformCategoryMap' in scope`(以及 `record(_:...)` 不存在)。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/PlatformCategoryMap.swift`:

```swift
import Foundation

/// 平台自带分类 → 我们的一级分类名。只收确定的;对应关系以真机上看到的支付宝分类名为准,可以增补。
public enum PlatformCategoryMap {
    public static let alipay: [String: String] = [
        "日用百货": "日用",
        "餐饮美食": "餐饮",
        "交通出行": "交通",
        "服饰装扮": "服饰",
        "爱车养车": "汽车",
        "酒店旅游": "旅游",
        "医疗健康": "医疗",
        "住房物业": "居住",
        "数码电器": "购物",
    ]

    public static func ourCategoryName(forAlipay name: String) -> String? {
        alipay[name]
    }
}
```

Replace `Packages/HappySpendingCore/Sources/HappySpendingCore/AutoEntryRecorder.swift`:

```swift
import Foundation
import SwiftData

public struct AutoEntryResult: Equatable, Sendable {
    /// 新记的那一笔;被判为重复时是库里已有的那一笔。
    public let entryID: UUID
    public let cents: Int
    /// 给快捷指令显示的一句话,例如 "已记 ¥15.12 · 支付宝"。
    public let message: String
    /// 单号相同,没有新建。
    public let isDuplicate: Bool

    public init(entryID: UUID, cents: Int, message: String, isDuplicate: Bool = false) {
        self.entryID = entryID
        self.cents = cents
        self.message = message
        self.isDuplicate = isDuplicate
    }
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
        let payment = PaymentRecord(source: .applePay, cents: cents, merchant: merchant, note: merchant ?? "")
        return try record(payment, now: now, calendar: calendar, in: context)
    }

    /// 记一笔已经解析好的支出。
    /// 单号相同就跳过;分类依次取商户记忆、平台分类映射,都没有就是"未分类"。
    @discardableResult
    public static func record(
        _ payment: PaymentRecord,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> AutoEntryResult {
        let refHash = payment.orderRef.flatMap(OrderRef.hash)
        if let refHash {
            let wanted: String? = refHash
            var descriptor = FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.orderRefHash == wanted }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                return AutoEntryResult(
                    entryID: existing.id,
                    cents: existing.amountInCents,
                    message: "已记过这一笔(单号相同)",
                    isDuplicate: true
                )
            }
        }

        let merchant = payment.merchant.flatMap(MerchantKey.trimmed)
        let memory = try context.fetch(FetchDescriptor<MerchantCategory>())
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())

        var categoryID = MerchantMemory.categoryID(for: merchant, memory: memory, categories: categories)
        if categoryID == nil,
           let ourName = payment.platformCategory.flatMap(PlatformCategoryMap.ourCategoryName(forAlipay:)) {
            categoryID = categories.first {
                $0.parent == nil && $0.kind == .expense && !$0.isArchived && $0.name == ourName
            }?.id
        }
        let category = categoryID.flatMap { id in categories.first { $0.id == id } }

        let entry = LedgerEntry(
            amountInCents: payment.cents,
            kind: .expense,
            date: payment.eventDate ?? now,
            note: payment.note,
            category: category,
            createdAt: now,
            calendar: calendar,
            autoSource: payment.source,
            merchant: merchant,
            orderRefHash: refHash
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            throw error
        }

        let label = merchant ?? (payment.note.isEmpty ? nil : payment.note)
        let suffix = label.map { " · \($0)" } ?? ""
        return AutoEntryResult(
            entryID: entry.id,
            cents: payment.cents,
            message: "已记 \(Money.display(payment.cents))\(suffix)"
        )
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(218 个,原有 AutoEntryRecorderTests 全部仍然通过),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: generalize AutoEntryRecorder with order-ref dedupe and Alipay category mapping"
```

---

### Task 3: 通知解析器

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/TextMatch.swift`
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/NotificationPaymentParser.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/NotificationPaymentParserTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `PaymentRecord`、`ParseOutcome`;已有的 `AmountText.cents(from:)`
- Produces:
  - 内部工具 `TextMatch.captures(_ pattern: String, in text: String) -> [String]?`(第一个匹配的各捕获组,下标 0 是整段匹配)
  - `enum NotificationPaymentParser { static func parse(title: String, body: String) -> ParseOutcome }`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/NotificationPaymentParserTests.swift`:

```swift
import Testing
@testable import HappySpendingCore

struct NotificationPaymentParserTests {
    private func payment(_ outcome: ParseOutcome) -> PaymentRecord? {
        if case .payment(let record) = outcome { return record }
        return nil
    }

    // MARK: 支付宝(真实样本:交易提醒 / 你有一笔 15.12 元的支出,领 2 元小荷包支付红包。)

    @Test func parsesTheRealAlipayNotification() throws {
        let outcome = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "你有一笔 15.12 元的支出,领 2 元小荷包支付红包。"
        )

        let record = try #require(payment(outcome))
        #expect(record.cents == 1512)
        #expect(record.source == .notification)
        #expect(record.note == "支付宝")
        #expect(record.merchant == nil)
        #expect(record.eventDate == nil)
        #expect(record.orderRef == nil)
        #expect(record.platformCategory == nil)
    }

    @Test func parsesTheAlipayNotificationWithFullWidthPunctuationAndNoSpaces() throws {
        let outcome = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "你有一笔15.12元的支出，领2元小荷包支付红包。"
        )
        #expect(payment(outcome)?.cents == 1512)
    }

    @Test func thePromotionalAmountIsNeverTaken() throws {
        let promoFirst = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "领 2 元小荷包。你有一笔 15.12 元的支出,另有 9 元优惠"
        )
        #expect(payment(promoFirst)?.cents == 1512)

        let bigPromo = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "你有一笔 0.50 元的支出,领 100 元红包"
        )
        #expect(payment(bigPromo)?.cents == 50)
    }

    @Test func alipayIncomeIsIgnored() {
        let outcome = NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔 100.00 元的收入。")
        #expect(outcome == .ignored("收入"))
    }

    @Test func parsesAlipayAmountsWithThousandsSeparators() {
        let outcome = NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔1,234.50元的支出")
        #expect(payment(outcome)?.cents == 123450)
    }

    @Test func theTitleMayHaveSurroundingWhitespace() {
        let outcome = NotificationPaymentParser.parse(title: " 交易提醒\n", body: "你有一笔 15.12 元的支出")
        #expect(payment(outcome)?.cents == 1512)
    }

    @Test func anAlipayNotificationOfAnotherKindIsUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "你的账单已出,请及时还款") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "") == .unrecognized)
    }

    @Test func aZeroOrOversizedAlipayAmountIsUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔 0 元的支出") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔 10000000 元的支出") == .unrecognized)
    }

    // MARK: 微信(真实样本:微信支付 / 已支付 ¥147.70)

    @Test func parsesTheRealWeChatNotification() throws {
        let outcome = NotificationPaymentParser.parse(title: "微信支付", body: "已支付 ¥147.70")

        let record = try #require(payment(outcome))
        #expect(record.cents == 14770)
        #expect(record.source == .notification)
        #expect(record.note == "微信支付")
        #expect(record.merchant == nil)
    }

    @Test func parsesTheWeChatNotificationInOtherSpellings() {
        #expect(payment(NotificationPaymentParser.parse(title: "微信支付", body: "已支付￥147.70"))?.cents == 14770)
        #expect(payment(NotificationPaymentParser.parse(title: "微信支付", body: "已支付 ¥ 1,147.70"))?.cents == 114770)
        #expect(payment(NotificationPaymentParser.parse(title: "微信支付", body: "已支付 ¥5"))?.cents == 500)
    }

    @Test func otherWeChatPaymentNotificationsAreUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "微信支付", body: "已退款 ¥10.00") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "微信支付", body: "收款到账 ¥10.00") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "微信支付", body: "") == .unrecognized)
    }

    // MARK: 不是支付通知

    @Test func aChatMessageThatMentionsPayingIsNotARecord() {
        #expect(NotificationPaymentParser.parse(title: "张三", body: "已支付 ¥5") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "张三", body: "你有一笔 5 元的支出") == .unrecognized)
    }

    @Test func otherAppsAndEmptyTitlesAreUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "美团", body: "已支付 ¥25.00") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "", body: "已支付 ¥25.00") == .unrecognized)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter NotificationPaymentParserTests`
Expected: 编译失败,报 `cannot find 'NotificationPaymentParser' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/TextMatch.swift`:

```swift
import Foundation

/// 解析器共用的小工具:用正则取第一个匹配的各捕获组。
enum TextMatch {
    /// 返回第一个匹配的各捕获组,下标 0 是整段匹配;没有匹配或正则写错返回 nil。
    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
```

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/NotificationPaymentParser.swift`:

```swift
import Foundation

/// 解析微信、支付宝的支付通知。两种通知都只有金额,没有商户名。
/// 认不出的(其他 app、聊天消息、退款等)一律是 `.unrecognized`,由调用方安静地忽略。
public enum NotificationPaymentParser {
    private static let amount = #"([0-9][0-9,]*(?:\.[0-9]+)?)"#

    public static func parse(title: String, body: String) -> ParseOutcome {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? body

        if title.contains("交易提醒") { return alipay(body) }
        if title.contains("微信支付") { return wechat(body) }
        return .unrecognized
    }

    /// `你有一笔 15.12 元的支出,领 2 元小荷包支付红包。`:锚定整句取金额,不取后面的促销数字。
    private static func alipay(_ body: String) -> ParseOutcome {
        guard let groups = TextMatch.captures(#"你有一笔\s*"# + amount + #"\s*元的(支出|收入)"#, in: body) else {
            return .unrecognized
        }
        if groups[2] == "收入" { return .ignored("收入") }
        guard let cents = try? AmountText.cents(from: groups[1]) else { return .unrecognized }
        return .payment(PaymentRecord(source: .notification, cents: cents, note: "支付宝"))
    }

    /// `已支付 ¥147.70`
    private static func wechat(_ body: String) -> ParseOutcome {
        guard let groups = TextMatch.captures(#"已支付\s*[¥￥]\s*"# + amount, in: body) else {
            return .unrecognized
        }
        guard let cents = try? AmountText.cents(from: groups[1]) else { return .unrecognized }
        return .payment(PaymentRecord(source: .notification, cents: cents, note: "微信支付"))
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(231 个),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add notification payment parser for Alipay and WeChat"
```

---

### Task 4: 屏幕文字解析器

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/ScreenTextParser.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/ScreenTextParserTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `PaymentRecord`、`ParseOutcome`;Task 2 的 `PlatformCategoryMap.alipay`;Task 3 的 `TextMatch`;已有的 `AmountText`
- Produces: `enum ScreenTextParser { static func parse(_ text: String, calendar: Calendar = .current) -> ParseOutcome }`

测试夹具是作者三个真实页面的识别文字,**单号、卡号尾号、商户名已替换成假值**,版式、噪音行(状态栏时间、电量、操作按钮提示)和识别错误原样保留。

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/ScreenTextParserTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct ScreenTextParserTests {
    private let cal = testCalendar

    // MARK: 真实样本(已脱敏)

    /// 微信·支付成功页:`♥支付成功` 是图标被识别成了符号,商户名被打码。
    private let wechatSuccess = """
    17:374
    三100
    ♥支付成功
    •（**双）
    ¥0.20
    完成
    """

    /// 微信·账单详情页:日期被识别成了乱码 `2026·10 514E 17:37:40`。
    private let wechatBill = """
    17:38 M
    账单
    ミ分100
    全部账单
    扫二维码付款-给示例商户
    -0.20
    当前状态
    支付成功
    收款方备注
    二维码收款
    支付方式
    零钱
    转账时间
    2026·10 514E 17:37:40
    转账单号
    10000000000000000000000000000000
    账单服务
    对订单有疑惑
    申请电子凭证
    收款方服务
    向收款方留言
    发起群收款
    本服务由财付通提供
    """

    /// 支付宝·账单详情页:顶部混着状态栏和操作按钮的提示("截图识别 / 按住启用")。
    private let alipayBill = """
    截图识别
    17:37 1
    • 分100.
    <
    按住启用
    *截图识别文字
    支付时间
    付款方式
    支付奖励
    交易详情
    账单详情
    淘
    示例商户**店
    -15.12
    自动扣款成功
    2026-10-14 14:09:55
    招商银行信用卡（0000）＞
    v 立即领取2积分
    示例商品名称
    更多、
    共1件
    账单管理
    账单分类
    标签
    已解锁“日用百货”贴纸，去兑换好礼
    日用百货＞
    请选择＞
    使用记账本，查看自定义分类、标签统计
    计入收支
    备注
    添加＞
    查看往来记录
    """

    private func payment(_ outcome: ParseOutcome) -> PaymentRecord? {
        if case .payment(let record) = outcome { return record }
        return nil
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    // MARK: 微信·支付成功页

    @Test func parsesTheWeChatSuccessPage() throws {
        let record = try #require(payment(ScreenTextParser.parse(wechatSuccess, calendar: cal)))

        #expect(record.cents == 20)
        #expect(record.source == .screenText)
        #expect(record.merchant == "（**双）")
        #expect(record.note == "（**双）")
        #expect(record.eventDate == nil)
        #expect(record.orderRef == nil)
        #expect(record.platformCategory == nil)
    }

    @Test func theWeChatSuccessPageWithoutAMerchantLineUsesTheChannelName() throws {
        let record = try #require(payment(ScreenTextParser.parse("支付成功\n¥0.20\n完成", calendar: cal)))
        #expect(record.cents == 20)
        #expect(record.merchant == nil)
        #expect(record.note == "微信")
    }

    @Test func theWeChatSuccessPageAcceptsOtherCurrencySymbols() {
        for symbol in ["￥", "Y", "¥ "] {
            let text = "支付成功\n示例商户\n\(symbol)12.50\n完成"
            #expect(payment(ScreenTextParser.parse(text, calendar: cal))?.cents == 1250, "symbol \(symbol)")
        }
    }

    @Test func aWeChatSuccessPageWithoutTheDoneButtonIsUnrecognized() {
        #expect(ScreenTextParser.parse("支付成功\n示例商户\n¥0.20", calendar: cal) == .unrecognized)
    }

    // MARK: 微信·账单详情页

    @Test func parsesTheWeChatBillPage() throws {
        let record = try #require(payment(ScreenTextParser.parse(wechatBill, calendar: cal)))

        #expect(record.cents == 20)
        #expect(record.source == .screenText)
        #expect(record.merchant == "示例商户")
        #expect(record.note == "示例商户")
        #expect(record.orderRef == "10000000000000000000000000000000")
        #expect(record.platformCategory == nil)
    }

    @Test func aGarbledWeChatDateLeavesTheEventDateEmpty() throws {
        let record = try #require(payment(ScreenTextParser.parse(wechatBill, calendar: cal)))
        #expect(record.eventDate == nil)
    }

    @Test func aCleanWeChatDateIsParsed() throws {
        let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026-10-14 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == date(2026, 10, 14, 17, 37, 40))
    }

    @Test func aChineseFormattedWeChatDateIsParsed() throws {
        let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026年10月14日 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == date(2026, 10, 14, 17, 37, 40))
    }

    @Test func anImpossibleDateIsRejectedNotRolledOver() throws {
        let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026-02-30 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == nil)
    }

    @Test func aFullyMaskedWeChatPayeeHasNoMerchant() throws {
        let text = wechatBill.replacingOccurrences(of: "扫二维码付款-给示例商户", with: "扫二维码付款-给●")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.merchant == nil)
        #expect(record.note == "微信")
    }

    @Test func theWeChatPaymentTimeLabelIsAlsoAccepted() throws {
        let text = wechatBill
            .replacingOccurrences(of: "转账时间", with: "支付时间")
            .replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026-10-14 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == date(2026, 10, 14, 17, 37, 40))
    }

    @Test func aWeChatBillWithoutAnOrderNumberStillParses() throws {
        let text = wechatBill.replacingOccurrences(of: "转账单号\n10000000000000000000000000000000\n", with: "")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.orderRef == nil)
        #expect(record.cents == 20)
    }

    // MARK: 支付宝·账单详情页

    @Test func parsesTheAlipayBillPage() throws {
        let record = try #require(payment(ScreenTextParser.parse(alipayBill, calendar: cal)))

        #expect(record.cents == 1512)
        #expect(record.source == .screenText)
        #expect(record.merchant == "示例商户**店")
        #expect(record.note == "示例商户**店")
        #expect(record.eventDate == date(2026, 10, 14, 14, 9, 55))
        #expect(record.platformCategory == "日用百货")
        #expect(record.orderRef == nil)
    }

    @Test func theNoiseLinesOnTopDoNotBreakTheAlipayPage() throws {
        let noisy = "17:37\n100\n截图识别\n按住启用\n" + alipayBill
        let record = try #require(payment(ScreenTextParser.parse(noisy, calendar: cal)))
        #expect(record.cents == 1512)
        #expect(record.merchant == "示例商户**店")
    }

    @Test func theAlipayCategoryIsFoundWhereverItSits() throws {
        let text = alipayBill.replacingOccurrences(of: "日用百货＞", with: "餐饮美食>")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.platformCategory == "餐饮美食")
    }

    @Test func aSentenceThatMerelyMentionsACategoryIsNotTheCategory() throws {
        let text = alipayBill.replacingOccurrences(of: "日用百货＞\n", with: "")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.platformCategory == nil)
    }

    @Test func anUnknownAlipayCategoryHasNone() throws {
        let text = alipayBill.replacingOccurrences(of: "日用百货＞", with: "某个新分类＞")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.platformCategory == nil)
    }

    @Test func theAlipayMerchantIsNilWhenTheLineAboveTheAmountIsJustNavigation() throws {
        let text = alipayBill.replacingOccurrences(of: "示例商户**店", with: "账单详情")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.merchant == nil)
        #expect(record.note == "支付宝")
        #expect(record.cents == 1512)
    }

    @Test func anAlipayOrderNumberAfterItsLabelIsRead() throws {
        let text = alipayBill.replacingOccurrences(of: "查看往来记录", with: "订单号\n20000000000000000000\n查看往来记录")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.orderRef == "20000000000000000000")
    }

    // MARK: 金额的写法

    @Test func minusSignsInAllTheirSpellingsAreExpenses() {
        for minus in ["-", "−", "－", "- ", "－ "] {
            let text = wechatBill.replacingOccurrences(of: "-0.20", with: "\(minus)0.20")
            #expect(payment(ScreenTextParser.parse(text, calendar: cal))?.cents == 20, "minus \(minus)")
        }
    }

    @Test func aPlusSignIsIncomeAndIgnored() {
        let wechat = wechatBill.replacingOccurrences(of: "-0.20", with: "+0.20")
        let alipay = alipayBill.replacingOccurrences(of: "-15.12", with: "+15.12")
        #expect(ScreenTextParser.parse(wechat, calendar: cal) == .ignored("收入"))
        #expect(ScreenTextParser.parse(alipay, calendar: cal) == .ignored("收入"))
    }

    @Test func thousandsSeparatorsAndAnOversizedAmount() {
        let thousands = alipayBill.replacingOccurrences(of: "-15.12", with: "-1,234.56")
        #expect(payment(ScreenTextParser.parse(thousands, calendar: cal))?.cents == 123456)

        let huge = alipayBill.replacingOccurrences(of: "-15.12", with: "-99999999.00")
        #expect(ScreenTextParser.parse(huge, calendar: cal) == .unrecognized)

        let zero = alipayBill.replacingOccurrences(of: "-15.12", with: "-0.00")
        #expect(ScreenTextParser.parse(zero, calendar: cal) == .unrecognized)
    }

    @Test func aBillPageWithoutAnAmountLineIsUnrecognized() {
        let text = wechatBill.replacingOccurrences(of: "-0.20\n", with: "")
        #expect(ScreenTextParser.parse(text, calendar: cal) == .unrecognized)
    }

    // MARK: 不是支付页面

    @Test func randomScreenTextIsUnrecognized() {
        #expect(ScreenTextParser.parse("", calendar: cal) == .unrecognized)
        #expect(ScreenTextParser.parse("   \n\n  ", calendar: cal) == .unrecognized)
        #expect(ScreenTextParser.parse("今天天气不错\n明天见", calendar: cal) == .unrecognized)
        #expect(ScreenTextParser.parse("17:37\n100\n截图识别\n按住启用", calendar: cal) == .unrecognized)
    }

    @Test func aChatThatMentionsAnAmountIsNotAPaymentPage() {
        #expect(ScreenTextParser.parse("张三\n我转给你 ¥100.00\n收到了吗", calendar: cal) == .unrecognized)
    }

    @Test func aWeChatBillMissingItsTimeLabelFallsThroughToUnrecognized() {
        let text = wechatBill
            .replacingOccurrences(of: "转账时间\n2026·10 514E 17:37:40\n", with: "")
        #expect(ScreenTextParser.parse(text, calendar: cal) == .unrecognized)
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter ScreenTextParserTests`
Expected: 编译失败,报 `cannot find 'ScreenTextParser' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/ScreenTextParser.swift`:

```swift
import Foundation

/// 解析"提取图像中的文字"识别出的微信、支付宝支付页文字。
/// 规则锚定关键词而不是行号,所以状态栏时间、电量、操作按钮的提示这类噪音行不影响结果。
public enum ScreenTextParser {
    private enum Page {
        case wechatBill, alipayBill, wechatSuccess
    }

    public static func parse(_ text: String, calendar: Calendar = .current) -> ParseOutcome {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        switch detectPage(lines) {
        case .wechatBill: return parseWeChatBill(lines, calendar: calendar)
        case .alipayBill: return parseAlipayBill(lines, calendar: calendar)
        case .wechatSuccess: return parseWeChatSuccess(lines)
        case nil: return .unrecognized
        }
    }

    // MARK: 判断是哪种页面

    /// 判断顺序:微信账单页 → 支付宝账单页 → 微信成功页。
    private static func detectPage(_ lines: [String]) -> Page? {
        func has(_ keyword: String) -> Bool { lines.contains { $0.contains(keyword) } }

        if has("当前状态") && (has("转账时间") || has("支付时间")) { return .wechatBill }
        if (has("账单详情") || has("交易详情")) && (has("付款方式") || has("支付时间")) { return .alipayBill }
        if has("支付成功") && lines.contains("完成") && !has("当前状态") { return .wechatSuccess }
        return nil
    }

    // MARK: 微信·支付成功页

    /// `支付成功` / `<商户>` / `¥0.20` / `完成`
    private static func parseWeChatSuccess(_ lines: [String]) -> ParseOutcome {
        guard let amountIndex = lines.firstIndex(where: { currencyAmount($0) != nil }),
              let amountText = currencyAmount(lines[amountIndex]),
              let cents = try? AmountText.cents(from: amountText)
        else { return .unrecognized }

        var merchant: String?
        if let statusIndex = lines.firstIndex(where: { $0.contains("支付成功") }), statusIndex < amountIndex {
            merchant = lines[(statusIndex + 1)..<amountIndex].lazy.compactMap(cleanMerchant).first
        }
        return .payment(PaymentRecord(
            source: .screenText, cents: cents, merchant: merchant, note: merchant ?? "微信"
        ))
    }

    // MARK: 微信·账单详情页

    private static func parseWeChatBill(_ lines: [String], calendar: Calendar) -> ParseOutcome {
        guard let signed = firstSignedAmount(lines) else { return .unrecognized }
        if signed.isIncome { return .ignored("收入") }
        guard let cents = try? AmountText.cents(from: signed.digits) else { return .unrecognized }

        // `扫二维码付款-给X`:取"给"后面的收款方。
        let merchant = lines.lazy.compactMap { line -> String? in
            guard let groups = TextMatch.captures("^.+?[-－—–]给(.+)$", in: line) else { return nil }
            return cleanMerchant(groups[1])
        }.first

        return .payment(PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "微信",
            eventDate: dateTime(afterAnyLabel: ["转账时间", "支付时间"], in: lines, calendar: calendar),
            orderRef: digits(afterAnyLabel: ["转账单号", "交易单号"], in: lines)
        ))
    }

    // MARK: 支付宝·账单详情页

    private static func parseAlipayBill(_ lines: [String], calendar: Calendar) -> ParseOutcome {
        guard let signed = firstSignedAmount(lines) else { return .unrecognized }
        if signed.isIncome { return .ignored("收入") }
        guard let cents = try? AmountText.cents(from: signed.digits) else { return .unrecognized }

        // 商户是金额的上一行;如果那一行只是导航文字就当没有商户。
        let merchant = signed.index > 0 ? cleanMerchant(lines[signed.index - 1]) : nil

        // 支付宝分类:整行(去掉结尾的 >)恰好是某个已知分类名,不依赖位置。
        let platformCategory = lines.lazy.compactMap { line -> String? in
            let name = line.trimmingCharacters(in: CharacterSet(charactersIn: ">＞›) "))
            return PlatformCategoryMap.alipay[name] != nil ? name : nil
        }.first

        return .payment(PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "支付宝",
            eventDate: alipayDateTime(in: lines, calendar: calendar),
            orderRef: digits(afterAnyLabel: ["订单号"], in: lines),
            platformCategory: platformCategory
        ))
    }

    // MARK: 金额行

    /// 统一全角/半角,并把各种减号归成 `-`。
    private static func normalized(_ line: String) -> String {
        (line.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? line)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    /// `¥0.20` / `￥0.20` / `Y0.20` 这样的整行金额,返回数字部分。
    private static func currencyAmount(_ line: String) -> String? {
        TextMatch.captures("^[\u{00A5}\u{FFE5}Y]\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)$", in: normalized(line))?[1]
    }

    private struct SignedAmount {
        let index: Int
        let isIncome: Bool
        let digits: String
    }

    /// 第一行形如 `-15.12` / `+15.12` 的整行金额。
    private static func firstSignedAmount(_ lines: [String]) -> SignedAmount? {
        for (index, line) in lines.enumerated() {
            if let groups = TextMatch.captures("^([+-])\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)$", in: normalized(line)) {
                return SignedAmount(index: index, isIncome: groups[1] == "+", digits: groups[2])
            }
        }
        return nil
    }

    // MARK: 商户

    private static let decoration = CharacterSet(charactersIn: "•●·・○◦♥★☆■□◆◇—-_:： \t")
    private static let navigationWords: Set<String> = ["<", "‹", "账单详情", "交易详情", "详情", "账单"]

    /// 去掉两端的圆点、符号;空串或纯导航文字返回 nil。
    private static func cleanMerchant(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: decoration)
        return value.isEmpty || navigationWords.contains(value) ? nil : value
    }

    // MARK: 时间与单号

    /// 在标签所在行或它的下一行里找日期时间。
    private static func dateTime(afterAnyLabel labels: [String], in lines: [String], calendar: Calendar) -> Date? {
        for (index, line) in lines.enumerated() where labels.contains(where: { line.contains($0) }) {
            let candidates = [line] + (index + 1 < lines.count ? [lines[index + 1]] : [])
            for candidate in candidates {
                if let date = parseDateTime(candidate, calendar: calendar) { return date }
            }
        }
        return nil
    }

    /// 支付宝的时间没有固定标签,直接找 `yyyy-MM-dd HH:mm:ss`。
    private static func alipayDateTime(in lines: [String], calendar: Calendar) -> Date? {
        for line in lines {
            if let groups = TextMatch.captures("(\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}:\\d{2})", in: line),
               let date = parseDateTime(groups[1], calendar: calendar) {
                return date
            }
        }
        return nil
    }

    /// 允许日期里夹杂几个非数字字符(`2026年10月14日 17:37:40`),并**校验**每一项:
    /// 识别错误产生的不可能的日期返回 nil,而不是被日历悄悄进位成别的日子。
    private static func parseDateTime(_ text: String, calendar: Calendar) -> Date? {
        let pattern = "(\\d{4})\\D{1,3}(\\d{1,2})\\D{1,3}(\\d{1,2})\\D{0,3}(\\d{1,2}):(\\d{2})(?::(\\d{2}))?"
        guard let g = TextMatch.captures(pattern, in: text),
              let year = Int(g[1]), let month = Int(g[2]), let day = Int(g[3]),
              let hour = Int(g[4]), let minute = Int(g[5])
        else { return nil }
        let second = Int(g[6]) ?? 0

        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }

        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
    }

    /// 标签下一行(或标签行自身)里的数字串,至少 10 位才算单号。
    private static func digits(afterAnyLabel labels: [String], in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() where labels.contains(where: { line.contains($0) }) {
            let candidates = [line] + (index + 1 < lines.count ? [lines[index + 1]] : [])
            for candidate in candidates {
                let value = candidate.filter(\.isNumber)
                if value.count >= 10 { return value }
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(257 个),没有警告。如果某个样本相关的测试失败,先确认是解析规则的问题还是测试夹具和真实样本不一致,**不要为了让测试过而放宽规则**。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add screen text parser for WeChat and Alipay payment pages"
```

---

### Task 5: PaymentCapture:给快捷指令用的入口

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/PaymentCapture.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentCaptureTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `AutoEntryRecorder.record(_:...)`;Task 3 的 `NotificationPaymentParser`;Task 4 的 `ScreenTextParser`
- Produces:
  - `struct CaptureResult: Equatable, Sendable { let message: String; let recorded: Bool }`
  - `enum PaymentCaptureError: Error, Equatable, LocalizedError { case notPaymentPage; var message: String }`
  - `enum PaymentCapture { static func recordNotification(title:body:now:calendar:in:) throws -> CaptureResult; static func recordScreenText(_ text:now:calendar:in:) throws -> CaptureResult }`

- [ ] **Step 1: 写失败的测试**

Create `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentCaptureTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PaymentCaptureTests {
    private let now = makeDate(2026, 10, 15, 9, 30)

    private let wechatSuccess = "17:374\n三100\n♥支付成功\n•（**双）\n¥0.20\n完成"
    private let alipayBill = """
    17:37 1
    账单详情
    交易详情
    支付时间
    付款方式
    示例商户**店
    -15.12
    自动扣款成功
    2026-10-14 14:09:55
    日用百货＞
    """

    private func entries(_ context: ModelContext) throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    // MARK: 通知

    @Test func anAlipayNotificationIsRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "交易提醒", body: "你有一笔 15.12 元的支出,领 2 元小荷包支付红包。",
            now: now, calendar: testCalendar, in: context
        )

        #expect(result.recorded)
        #expect(result.message == "已记 ¥15.12 · 支付宝")
        let entry = try #require(try entries(context).first)
        #expect(entry.autoSource == .notification)
        #expect(entry.amountInCents == 1512)
    }

    @Test func aWeChatNotificationIsRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "微信支付", body: "已支付 ¥147.70", now: now, calendar: testCalendar, in: context
        )

        #expect(result.recorded)
        #expect(result.message == "已记 ¥147.70 · 微信支付")
    }

    @Test func anIncomeNotificationIsQuietlyIgnored() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "交易提醒", body: "你有一笔 100.00 元的收入。", now: now, calendar: testCalendar, in: context
        )

        #expect(!result.recorded)
        #expect(result.message == "已忽略:收入")
        #expect(try entries(context).isEmpty)
    }

    @Test func anUnrelatedNotificationIsQuietlyIgnoredWithoutAnError() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "张三", body: "晚上吃什么", now: now, calendar: testCalendar, in: context
        )

        #expect(!result.recorded)
        #expect(result.message == "已忽略:不是支付通知")
        #expect(try entries(context).isEmpty)
    }

    // MARK: 屏幕识别

    @Test func aWeChatSuccessPageIsRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordScreenText(wechatSuccess, now: now, calendar: testCalendar, in: context)

        #expect(result.recorded)
        #expect(result.message == "已记 ¥0.20 · （**双）")
        let entry = try #require(try entries(context).first)
        #expect(entry.autoSource == .screenText)
        #expect(entry.date == makeDate(2026, 10, 15))
    }

    @Test func theAlipayBillUsesItsPageTimeAndCategoryMap() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let daily = CategoryRules.addTopLevel(
            name: "日用", symbolName: "basket.fill", colorHex: "#34C759",
            kind: .expense, sortOrder: 0, in: context
        )

        let result = try PaymentCapture.recordScreenText(alipayBill, now: now, calendar: testCalendar, in: context)

        #expect(result.recorded)
        let entry = try #require(try entries(context).first)
        #expect(entry.date == makeDate(2026, 10, 14))
        #expect(entry.category === daily)
        #expect(entry.merchant == "示例商户**店")
    }

    @Test func aScreenWithoutAPaymentPageIsAnError() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        #expect(throws: PaymentCaptureError.notPaymentPage) {
            try PaymentCapture.recordScreenText("今天天气不错", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: PaymentCaptureError.notPaymentPage) {
            try PaymentCapture.recordScreenText("", now: now, calendar: testCalendar, in: context)
        }
        #expect(try entries(context).isEmpty)
    }

    @Test func anIncomeScreenIsIgnoredNotAnError() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let income = alipayBill.replacingOccurrences(of: "-15.12", with: "+15.12")

        let result = try PaymentCapture.recordScreenText(income, now: now, calendar: testCalendar, in: context)

        #expect(!result.recorded)
        #expect(result.message == "已忽略:收入")
        #expect(try entries(context).isEmpty)
    }

    @Test func triggeringTheSameBillTwiceRecordsItOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let bill = """
        当前状态
        转账时间
        2026-10-14 17:37:40
        扫二维码付款-给示例商户
        -0.20
        转账单号
        10000000000000000000000000000000
        """

        let first = try PaymentCapture.recordScreenText(bill, now: now, calendar: testCalendar, in: context)
        let second = try PaymentCapture.recordScreenText(bill, now: now, calendar: testCalendar, in: context)

        #expect(first.recorded)
        #expect(!second.recorded)
        #expect(second.message == "已记过这一笔(单号相同)")
        #expect(try entries(context).count == 1)
    }

    @Test func theErrorHasAReadableChineseMessage() {
        #expect(PaymentCaptureError.notPaymentPage.message == "没有识别到支付页面")
        #expect(PaymentCaptureError.notPaymentPage.errorDescription == "没有识别到支付页面")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore --filter PaymentCaptureTests`
Expected: 编译失败,报 `cannot find 'PaymentCapture' in scope`。

- [ ] **Step 3: 写实现**

Create `Packages/HappySpendingCore/Sources/HappySpendingCore/PaymentCapture.swift`:

```swift
import Foundation
import SwiftData

public struct CaptureResult: Equatable, Sendable {
    /// 给快捷指令显示的一句话。
    public let message: String
    /// 是否新记了一笔。
    public let recorded: Bool
}

public enum PaymentCaptureError: Error, Equatable, LocalizedError {
    case notPaymentPage

    public var message: String {
        switch self {
        case .notPaymentPage: "没有识别到支付页面"
        }
    }

    public var errorDescription: String? { message }
}

/// 快捷指令动作调用的入口:解析文字、记账、决定给用户什么反馈。
public enum PaymentCapture {
    /// 通知:在后台自动运行,所以认不出或被忽略时**安静地成功返回**,不抛错,避免无关通知弹出错误。
    @discardableResult
    public static func recordNotification(
        title: String,
        body: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> CaptureResult {
        switch NotificationPaymentParser.parse(title: title, body: body) {
        case .payment(let payment):
            return try record(payment, now: now, calendar: calendar, in: context)
        case .ignored(let reason):
            return CaptureResult(message: "已忽略:\(reason)", recorded: false)
        case .unrecognized:
            return CaptureResult(message: "已忽略:不是支付通知", recorded: false)
        }
    }

    /// 屏幕识别:是用户主动触发的,认不出支付页面时**抛错**,让用户知道没记上。
    @discardableResult
    public static func recordScreenText(
        _ text: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> CaptureResult {
        switch ScreenTextParser.parse(text, calendar: calendar) {
        case .payment(let payment):
            return try record(payment, now: now, calendar: calendar, in: context)
        case .ignored(let reason):
            return CaptureResult(message: "已忽略:\(reason)", recorded: false)
        case .unrecognized:
            throw PaymentCaptureError.notPaymentPage
        }
    }

    private static func record(
        _ payment: PaymentRecord,
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) throws -> CaptureResult {
        let result = try AutoEntryRecorder.record(payment, now: now, calendar: calendar, in: context)
        return CaptureResult(message: result.message, recorded: !result.isDuplicate)
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore`
Expected: 全部 PASS(267 个),没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: add PaymentCapture entry points for notifications and screen text"
```

---

### Task 6: app 层:两个快捷指令动作与帮助页

**Files:**
- Create: `HappySpending/Intents/RecordScreenTextIntent.swift`
- Create: `HappySpending/Intents/RecordNotificationIntent.swift`
- Replace: `HappySpending/Settings/AutoRecordHelpView.swift`

**Interfaces:**
- Consumes: Core 的 `PaymentCapture.recordScreenText` / `recordNotification`、`PaymentCaptureError.message`、`AmountError.message`;已有的 `SharedModelContainer.shared`、`AutoRecordError`(定义在 `RecordApplePayIntent.swift`)
- Produces: 快捷指令动作"记一笔(屏幕识别)"(参数 `text`)和"记一笔(通知)"(参数 `notificationTitle`、`notificationBody`)

界面和动作没有自动化测试(动作只转调 Core,逻辑已被测);验证方式是编译 + 检查动作元数据 + 模拟器迁移与帮助页 + 真机清单(Task 7)。

- [ ] **Step 1: 屏幕识别动作**

Create `HappySpending/Intents/RecordScreenTextIntent.swift`:

```swift
import AppIntents
import SwiftData
import HappySpendingCore

/// 快捷指令动作"记一笔(屏幕识别)":接收"提取图像中的文字"识别出的整段文字,
/// 解析微信、支付宝的支付页并记一笔支出。通常挂在操作按钮或轻点背面上。
struct RecordScreenTextIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔(屏幕识别)"
    static var description = IntentDescription(
        "识别微信、支付宝支付成功页或账单详情页上的文字,把这笔支出记下来。通常接在“拍摄屏幕截图”和“提取图像中的文字”后面。"
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$text)")
    }

    @Parameter(title: "屏幕文字")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let result = try PaymentCapture.recordScreenText(
                text, in: SharedModelContainer.shared.mainContext
            )
            return .result(value: result.message)
        } catch let error as PaymentCaptureError {
            throw AutoRecordError(message: error.message)
        } catch let error as AmountError {
            throw AutoRecordError(message: error.message)
        } catch {
            throw AutoRecordError(message: "记账失败:\(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: 通知动作**

Create `HappySpending/Intents/RecordNotificationIntent.swift`:

```swift
import AppIntents
import SwiftData
import HappySpendingCore

/// 快捷指令动作"记一笔(通知)":接收微信、支付宝支付通知的标题和正文并记一笔支出。
/// 由"收到通知时"自动化在后台调用,所以认不出的通知会安静地忽略,不报错。
struct RecordNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔(通知)"
    static var description = IntentDescription(
        "把微信、支付宝的支付通知记为一笔支出。通常由快捷指令里“收到通知时”的自动化调用,标题和正文接触发器给出的通知标题和通知正文。"
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$notificationTitle) \(\.$notificationBody)")
    }

    @Parameter(title: "通知标题")
    var notificationTitle: String

    @Parameter(title: "通知正文")
    var notificationBody: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let result = try PaymentCapture.recordNotification(
                title: notificationTitle,
                body: notificationBody,
                in: SharedModelContainer.shared.mainContext
            )
            return .result(value: result.message)
        } catch let error as AmountError {
            throw AutoRecordError(message: error.message)
        } catch {
            throw AutoRecordError(message: "记账失败:\(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 3: 更新帮助页**

Replace `HappySpending/Settings/AutoRecordHelpView.swift`:

```swift
import SwiftUI

struct AutoRecordHelpView: View {
    var body: some View {
        List {
            Section {
                Text("三种方式帮你自动记支出,账单里都带“自动”标记:刷钱包里的卡(Apple Pay)、在微信/支付宝里直接付款(屏幕识别)、在其他 app 里用微信/支付宝付款(通知)。每种设置一次就行。")
            } header: {
                Text("它做什么")
            }

            Section("① 刷钱包里的卡(Apple Pay)") {
                step(1, "打开系统的“快捷指令”app,切到底部的“自动化”。")
                step(2, "点右上角“+”,新建“个人自动化”,选择“钱包”下面的“交易”。")
                step(3, "选择要监控的卡,点“下一步”。")
                step(4, "添加操作,搜索“记一笔”,选择“记一笔(Apple Pay)”。")
                step(5, "把“商户”和“金额”两个参数分别设成触发器给出的“商户”和“金额”。")
                step(6, "运行方式选“立即运行”(不同系统版本这个选项的位置不同,可能在选好触发器之后,也可能是最后一页的“运行前先询问”开关,关掉它)。")
            }

            Section {
                step(1, "在“快捷指令”里新建一个普通快捷指令(不是自动化)。")
                step(2, "依次添加操作:“拍摄屏幕截图”→“提取图像中的文字”→“记一笔(屏幕识别)”,把“屏幕文字”参数设成上一步提取出的文字。")
                step(3, "把它设成操作按钮(设置 → 操作按钮 → 快捷指令),或轻点背面(设置 → 辅助功能 → 触控 → 轻点背面)。")
                step(4, "在微信或支付宝里付完款,停在“支付成功”页或“账单详情”页时按一下操作按钮或轻点背面。")
                Text("在微信、支付宝里直接付款时,这两个 app 在前台,系统不会发通知,所以要用这个办法。整个过程不会往相册里留图片。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("② 在微信/支付宝里直接付款(屏幕识别)")
            }

            Section {
                step(1, "在“快捷指令”的“自动化”里新建个人自动化,选择“通知”,来自“支付宝”,加筛选:标题 包含 交易提醒。")
                step(2, "再建一个,来自“微信”,加筛选:标题 包含 微信支付。")
                step(3, "运行方式选“立即运行”。添加操作“记一笔(通知)”,把“通知标题”和“通知正文”接触发器给出的通知标题和通知正文。")
                step(4, "这两个 app 的系统通知要开着,并且至少显示在“锁屏”或“通知中心”之一,只选“横幅”不行。")
                Text("这类通知里只有金额、没有商户名,所以账会先归“未分类”,需要你事后手动归类。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("③ 在其他 app 里用微信/支付宝付款(通知)")
            }

            Section("分类怎么来的") {
                Text("有商户名的账,你在账单里改过分类并保存后,app 会记住这个商户,以后同一商户直接用这个分类。支付宝账单页自带的分类(如“日用百货”)会按对应关系预填。其余先归“未分类”。")
            }

            Section("能覆盖什么") {
                Label("钱包里的卡刷卡付款(Apple Pay)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("微信、支付宝的支付(屏幕识别或通知)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("实体卡直接刷卡、银行 app 的通知:暂不支持", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }

            Section("隐私") {
                Text("app 不保存截图、识别出的原文和通知内容,只记下金额、商户、日期等解析结果。文字识别在手机本地进行。")
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

- [ ] **Step 4: 重新生成工程、编译并检查动作元数据**

新增了两个文件,**必须**重新生成工程才会被收进去。注意:`xcodegen generate` 会覆盖你在 Xcode 里手动选的签名团队,生成后要到 Xcode 的 Signing & Capabilities 里**重新选一次个人团队**(Bryan Wang (Personal Team))。Run(仓库根目录):

```bash
xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'platform=iOS Simulator,id=DB2215EB-B088-47B2-9466-8DDD8E7C3277' -derivedDataPath .superpowers/dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: `** BUILD SUCCEEDED **`,没有 `error:`。
然后确认三个动作都进了元数据:

```bash
python3 -I - <<'EOF'
import json
d = json.load(open(".superpowers/dd/Build/Products/Debug-iphonesimulator/HappySpending.app/Metadata.appintents/extract.actionsdata"))
for name, a in d["actions"].items():
    print(name, "| openAppWhenRun:", a.get("openAppWhenRun"), "| params:", [(p["name"], p.get("isOptional")) for p in a["parameters"]])
EOF
```

Expected: 输出三行 `RecordApplePayIntent`、`RecordScreenTextIntent`(参数 `text`,必填)、`RecordNotificationIntent`(参数 `notificationTitle`、`notificationBody`,必填),`openAppWhenRun` 都是 False。

- [ ] **Step 5: 模拟器验证迁移与帮助页**

模拟器里装着上一个版本(有账单、分类、Apple Pay 的自动账结构)。**不要卸载**,直接覆盖安装再启动,用 iOS 模拟器工具 `launch`(设备 `DB2215EB-B088-47B2-9466-8DDD8E7C3277`,绝对路径 `<仓库>/.superpowers/dd/Build/Products/Debug-iphonesimulator/HappySpending.app`)。
Expected:
- 正常启动、不闪退;之前的账单、分类、自定义图标都还在(新增的可选字段 `orderRefHash` 靠轻量迁移)。
- 设置 → 自动入账:能看到三个分组(① 钱包 ② 屏幕识别 ③ 通知),各自的步骤、"能覆盖什么"和"隐私"。
注意:模拟器截图总是滞后一步,每次操作后多拍一张再看,**坐标按 402×874 的点坐标算**(截图显示尺寸是 920×2000,要乘以 0.437)。

- [ ] **Step 6: 提交**

```bash
git add HappySpending
git commit -m "feat: add screen-recognition and notification intents and update the help page"
```

---

### Task 7: 检查清单、README 与最终验证

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
s = s.replace("## 深色模式", """## 屏幕识别与通知自动入账(微信、支付宝)

模拟器里能看的:
- [ ] 用新版本覆盖旧版本安装后不闪退,已有账单、分类、自动账都还在
- [ ] 设置 → 自动入账:能看到三个分组(① 钱包 ② 屏幕识别 ③ 通知)、"能覆盖什么"、"隐私"

必须真机验证的(依赖快捷指令、操作按钮、相册和微信支付宝):
- [ ] 1. 操作按钮和轻点背面都能运行"屏幕识别"快捷指令;操作按钮弹出的提示是否会被截进图里(已知会,解析对噪音有容错)
- [ ] 2. "拍摄屏幕截图"运行后,相册和"最近删除"里**都没有新增图片**
- [ ] 3. 微信支付成功页、微信账单页、支付宝账单页的识别文字顺序和格式与样本一致;换一个商户、换一种支付方式后依然能解析
- [ ] 4. 支付宝**支付成功页**的识别文字(采集样本,用于补规则)
- [ ] 5. 通知的两个触发(或合并成一个):筛选生效、立即运行、锁屏时也能运行
- [ ] 6. 在其他 app 里用微信支付或支付宝付款,通知到达后自动入账,账单里是"未分类"、备注是"微信支付"或"支付宝"
- [ ] 7. 在微信、支付宝里直接付款确实**没有**通知(预期行为,由屏幕识别覆盖)
- [ ] 8. 支付宝账单页的分类映射生效("日用百货"记为"日用")
- [ ] 9. 在同一个微信账单页连续触发两次,第二次提示"已记过这一笔"
- [ ] 10. 收入、退款类页面和通知被忽略,不会记成支出
- [ ] 11. 在快捷指令里手动运行"记一笔(屏幕识别)",文字填"今天天气不错":提示"没有识别到支付页面",没有新账
- [ ] 12. 在快捷指令里手动运行"记一笔(通知)",标题填"张三"、正文填"晚上吃什么":安静成功返回"已忽略:不是支付通知",没有新账
- [ ] 删除一笔屏幕识别的账再点"撤销":恢复后仍带"自动"标记,再触发同一个账单页仍提示"已记过这一笔"

## 深色模式""")
open(p, "w", encoding="utf-8").write(s)

p = "README.md"
s = open(p, encoding="utf-8").read()
old = "- Apple Pay 自动入账设计:`docs/superpowers/specs/2026-10-13-apple-pay-auto-record-design.md`\n"
assert s.count(old) == 1
s = s.replace(old, old + "- 屏幕识别与通知自动入账设计:`docs/superpowers/specs/2026-10-15-screen-and-notification-auto-record-design.md`\n")
open(p, "w", encoding="utf-8").write(s)
EOF
```

- [ ] **Step 2: 最终验证**

Run(仓库根目录):

```bash
swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run" && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: 267 个测试全部通过,没有警告;`** BUILD SUCCEEDED **`。

- [ ] **Step 3: 提交**

```bash
git add README.md docs/manual-test-checklist.md
git commit -m "docs: add screen-recognition and notification checklist and README link"
```
