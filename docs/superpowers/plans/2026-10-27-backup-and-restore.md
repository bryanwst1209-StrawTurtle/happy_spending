# 备份与恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完整备份文件(账单、分类含图标、商户记忆、外观),设置里能导出、从备份整体替换恢复(先存恢复前备份)、每天自动备份到用户选的文件夹并只保留 7 份。

**Architecture:** Core 新增 `Backup`(文档结构、编码、解码与检查、预览、原子替换)和 `BackupFiles`(文件名、轮换、何时自动备份、何时提醒),都是可测的纯逻辑或内存数据库操作。app 层新增 `BackupService`(书签、文件读写、恢复流程)、`BackupFile`(分享用)、`BackupSection`(设置页一节),`AppearanceModel` 加备份读写,`RootTabView` 在回到前台时触发自动备份并显示提醒角标。

**Tech Stack:** Swift、SwiftUI、SwiftData、Swift Testing;本地包 `Packages/HappySpendingCore`,工程由 XcodeGen 生成(切分支后 git 钩子自动重新生成)。

**Spec:** `docs/superpowers/specs/2026-10-27-backup-and-restore-design.md`

## Global Constraints

- 最低系统 iOS 26;不引入第三方依赖;数据模型不变,不做迁移。
- 账单日期按现有约定(当天 GMT 0 点),恢复时用 `DayStamp.calendar` 原样写回。
- 业务逻辑放在 Core,用 Swift Testing + 内存数据库测;app 层保持很薄。
- 面向用户的文字一字不差:`备份与恢复`、`导出备份`、`从备份恢复`、`选择自动备份文件夹`、`更换文件夹`、`重新选择文件夹`、`关闭自动备份`、`导出恢复前备份`、`恢复这个备份?`、`替换现有数据`、`这不是 Happy Spending 的备份文件`、`这个备份来自更新版本的 app,请先升级再恢复`、`备份文件已损坏`、`已恢复 N 笔账`、`有 N 笔账的分类已不存在,已归为未分类`、`恢复失败,数据未改动`。
- 文件名:自动备份 `HappySpending 备份 yyyy-MM-dd.json`;手动导出 `HappySpending 备份 yyyy-MM-dd HHmmss.json`;恢复前备份 `HappySpending 恢复前备份 yyyy-MM-dd HHmmss.json`。文件名里的日期按用户本地日历。
- 提交信息用英文,结尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 测试命令(仓库根目录):`swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`。开始前 365 个测试全部通过(34 个 suite)。
- app 构建命令:`xcodegen generate --quiet && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"`。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都有对应的测试或检查:

1. **恢复失败不能丢数据**:替换中途出错时,原来的账单、分类、商户记忆必须原样还在。→ Task 2 `aFailureDuringReplaceKeepsTheOriginalData`
2. **轮换只删自己的自动备份**:恢复前备份、手动导出的备份、用户自己放的文件都不能被删。→ Task 3 `rotationOnlyDeletesOldAutoBackups`
3. **二级分类的上级是二级分类**(手改过的文件)要被拒绝,不能恢复出三层分类。→ Task 1 `aSubcategoryWhoseParentIsASubcategoryIsCorrupted`
4. **日期往返**:账单日期、记账时间、商户记忆时间恢复后完全一致,不会因为时区挪一天。→ Task 2 `restoringIntoAnEmptyStoreReproducesEverything`
5. **同一天开两次 app** 不能写两份自动备份,也不能并发写同一个文件。→ Task 3 `autoBackupRunsOncePerLocalDay` + Task 4 的 `isBackingUp` 防重入

---

### Task 1: 备份文档、导出、读取与检查、预览

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/Backup.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BackupTests.swift`(新建)

**Interfaces:**
- Consumes: 已有的 `LedgerEntry`、`LedgerCategory`、`MerchantCategory`、`EntryKind`、`LedgerQueries.all()`、`CategoryRules.addTopLevel/addSubcategory/archive`;测试里的 `makeTestContainer()`、`makeDate(...)`、`testCalendar`。
- Produces:
  - `public struct BackupDocument: Codable, Equatable, Sendable`(字段见 spec §2;嵌套 `Category`、`Entry`、`Memory`、`Appearance`;`static appID = "HappySpending"`、`static currentVersion = 1`;`Appearance.init(choice:opacity:image:)`)
  - `public enum BackupError: Error, Equatable, LocalizedError { case notABackup, tooNew, corrupted; var message: String }`
  - `public struct BackupPreview: Equatable, Sendable { createdAt, entryCount, categoryCount, firstDate: Date?, lastDate: Date?, orphanedEntryCount }`
  - `public enum Backup`:`makeDocument(from:appearance:now:) throws -> BackupDocument`、`encode(_:) throws -> Data`、`export(from:appearance:now:) throws -> Data`、`decode(_:) throws -> BackupDocument`(含 §4 的检查)、`preview(of:) -> BackupPreview`

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BackupTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct BackupTests {
    private let now = makeDate(2026, 10, 27, 9, 12)
    private let appearance = BackupDocument.Appearance(choice: "preset:dusk", opacity: 0.55, image: Data([1, 2, 3]))

    /// 一套有代表性的数据:一级/二级/归档分类、带图标的分类、手动账、自动账、商户记忆。
    private struct Sample {
        let food: LedgerCategory
        let lunch: LedgerCategory
        let old: LedgerCategory
        let manual: LedgerEntry
        let auto: LedgerEntry
    }

    @discardableResult
    private func fill(_ context: ModelContext) throws -> Sample {
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A", kind: .expense, sortOrder: 0, in: context
        )
        food.iconData = Data([9, 8, 7])
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let old = CategoryRules.addTopLevel(
            name: "旧分类", symbolName: "tag.fill", colorHex: "#8E8E93", kind: .income, sortOrder: 1, in: context
        )
        CategoryRules.archive(old)
        let manual = LedgerEntry(
            amountInCents: 1234, kind: .expense, date: makeDate(2026, 3, 1), note: "手动",
            category: lunch, createdAt: makeDate(2026, 3, 1, 12, 30), calendar: testCalendar
        )
        let auto = LedgerEntry(
            amountInCents: 5500, kind: .expense, date: makeDate(2026, 10, 26), note: "示例小吃",
            category: nil, createdAt: makeDate(2026, 10, 26, 18, 5), calendar: testCalendar,
            autoSource: .screenText, merchant: "示例小吃", orderRefHash: "abc123"
        )
        context.insert(manual)
        context.insert(auto)
        context.insert(MerchantCategory(merchantKey: "示例小吃", categoryID: food.id, updatedAt: makeDate(2026, 10, 1)))
        try context.save()
        return Sample(food: food, lunch: lunch, old: old, manual: manual, auto: auto)
    }

    // MARK: 导出

    @Test func theDocumentCapturesEverything() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let s = try fill(context)

        let document = try Backup.makeDocument(from: context, appearance: appearance, now: now)

        #expect(document.app == "HappySpending")
        #expect(document.formatVersion == 1)
        #expect(document.createdAt == now)
        #expect(document.categories.count == 3)
        let lunch = try #require(document.categories.first { $0.id == s.lunch.id })
        #expect(lunch.parentID == s.food.id)
        #expect(document.categories.first { $0.id == s.food.id }?.iconData == Data([9, 8, 7]))
        #expect(document.categories.first { $0.id == s.old.id }?.isArchived == true)
        let auto = try #require(document.entries.first { $0.id == s.auto.id })
        #expect(auto.autoSource == "screenText")
        #expect(auto.merchant == "示例小吃")
        #expect(auto.orderRefHash == "abc123")
        #expect(auto.categoryID == nil)
        #expect(document.entries.first { $0.id == s.manual.id }?.categoryID == s.lunch.id)
        #expect(document.merchantMemory.map(\.merchantKey) == ["示例小吃"])
        #expect(document.appearance == appearance)
    }

    @Test func encodingAndDecodingRoundTrips() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        try fill(context)
        let document = try Backup.makeDocument(from: context, appearance: appearance, now: now)

        let decoded = try Backup.decode(try Backup.encode(document))

        #expect(decoded == document)
    }

    @Test func theFileIsReadableJSONWithTheAppMarker() throws {
        let container = try makeTestContainer()
        let data = try Backup.export(from: container.mainContext, appearance: appearance, now: now)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains(#""app":"HappySpending""#))
        #expect(text.contains(#""formatVersion":1"#))
        #expect(text.contains("2026-10-27T09:12:00"))
    }

    // MARK: 拒绝

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func validObject() throws -> [String: Any] {
        let container = try makeTestContainer()
        try fill(container.mainContext)
        let data = try Backup.export(from: container.mainContext, appearance: appearance, now: now)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func somethingThatIsNotABackupIsRejected() throws {
        var other = try validObject()
        other["app"] = "SomethingElse"
        var missing = try validObject()
        missing.removeValue(forKey: "entries")
        for data in [Data("不是 JSON".utf8), Data("[]".utf8), json(["hello": 1]), json(other), json(missing)] {
            #expect(throws: BackupError.notABackup) { try Backup.decode(data) }
        }
    }

    @Test func aBackupFromANewerAppIsRejected() throws {
        var object = try validObject()
        object["formatVersion"] = 2
        #expect(throws: BackupError.tooNew) { try Backup.decode(json(object)) }
    }

    @Test func duplicateIDsAreCorrupted() throws {
        var entries = try validObject()
        let entryList = entries["entries"] as! [[String: Any]]
        entries["entries"] = entryList + [entryList[0]]
        var categories = try validObject()
        let categoryList = categories["categories"] as! [[String: Any]]
        categories["categories"] = categoryList + [categoryList[0]]

        for object in [entries, categories] {
            #expect(throws: BackupError.corrupted) { try Backup.decode(json(object)) }
        }
    }

    @Test func aSubcategoryWithAMissingParentIsCorrupted() throws {
        var object = try validObject()
        var list = object["categories"] as! [[String: Any]]
        let index = list.firstIndex { $0["parentID"] != nil }!
        list[index]["parentID"] = UUID().uuidString
        object["categories"] = list
        #expect(throws: BackupError.corrupted) { try Backup.decode(json(object)) }
    }

    @Test func aSubcategoryWhoseParentIsASubcategoryIsCorrupted() throws {
        var object = try validObject()
        var list = object["categories"] as! [[String: Any]]
        let sub = list.first { $0["parentID"] != nil }!
        var grandchild = sub
        grandchild["id"] = UUID().uuidString
        grandchild["parentID"] = sub["id"]
        list.append(grandchild)
        object["categories"] = list
        #expect(throws: BackupError.corrupted) { try Backup.decode(json(object)) }
    }

    @Test func anUnknownKindIsCorrupted() throws {
        var object = try validObject()
        var list = object["entries"] as! [[String: Any]]
        list[0]["kind"] = "transfer"
        object["entries"] = list
        #expect(throws: BackupError.corrupted) { try Backup.decode(json(object)) }
    }

    @Test func errorsHaveReadableChineseMessages() {
        #expect(BackupError.notABackup.message == "这不是 Happy Spending 的备份文件")
        #expect(BackupError.tooNew.message == "这个备份来自更新版本的 app,请先升级再恢复")
        #expect(BackupError.corrupted.message == "备份文件已损坏")
    }

    // MARK: 预览

    @Test func thePreviewSummarizesTheBackup() throws {
        let container = try makeTestContainer()
        try fill(container.mainContext)
        var document = try Backup.makeDocument(from: container.mainContext, appearance: appearance, now: now)
        document.entries[0].categoryID = UUID()

        let preview = Backup.preview(of: document)

        #expect(preview.createdAt == now)
        #expect(preview.entryCount == 2)
        #expect(preview.categoryCount == 3)
        #expect(preview.firstDate == makeDate(2026, 3, 1))
        #expect(preview.lastDate == makeDate(2026, 10, 26))
        #expect(preview.orphanedEntryCount == 1)
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'BackupDocument' in scope`(以及 `Backup`、`BackupError` 找不到)。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/Backup.swift`:

```swift
import Foundation
import SwiftData

/// 备份文件的内容(见 docs/superpowers/specs/2026-10-27-backup-and-restore-design.md §2)。
public struct BackupDocument: Codable, Equatable, Sendable {
    public static let appID = "HappySpending"
    /// 格式版本:数据结构变了就加一,旧版本 app 读到更新的版本会拒绝。
    public static let currentVersion = 1

    public struct Category: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var symbolName: String
        public var iconData: Data?
        public var colorHex: String
        public var kind: String
        public var sortOrder: Int
        public var isArchived: Bool
        public var parentID: UUID?
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var id: UUID
        public var amountInCents: Int
        public var kind: String
        public var date: Date
        public var createdAt: Date
        public var note: String
        public var categoryID: UUID?
        public var autoSource: String?
        public var merchant: String?
        public var orderRefHash: String?
    }

    public struct Memory: Codable, Equatable, Sendable {
        public var merchantKey: String
        public var categoryID: UUID
        public var updatedAt: Date
    }

    public struct Appearance: Codable, Equatable, Sendable {
        /// `BackgroundChoice.stored` 的文字。
        public var choice: String
        public var opacity: Double
        /// "我的图片"(处理好的 JPEG);没有就是 nil。
        public var image: Data?

        public init(choice: String, opacity: Double, image: Data?) {
            self.choice = choice
            self.opacity = opacity
            self.image = image
        }
    }

    public var app: String
    public var formatVersion: Int
    public var createdAt: Date
    public var categories: [Category]
    public var entries: [Entry]
    public var merchantMemory: [Memory]
    public var appearance: Appearance
}

public enum BackupError: Error, Equatable, LocalizedError {
    case notABackup
    case tooNew
    case corrupted

    public var message: String {
        switch self {
        case .notABackup: "这不是 Happy Spending 的备份文件"
        case .tooNew: "这个备份来自更新版本的 app,请先升级再恢复"
        case .corrupted: "备份文件已损坏"
        }
    }

    public var errorDescription: String? { message }
}

/// 恢复前给用户看的摘要。
public struct BackupPreview: Equatable, Sendable {
    public let createdAt: Date
    public let entryCount: Int
    public let categoryCount: Int
    public let firstDate: Date?
    public let lastDate: Date?
    /// 指向不存在分类的账单笔数,恢复后归为未分类。
    public let orphanedEntryCount: Int
}

public enum Backup {
    /// 日期存 ISO 8601(带毫秒),方便人看,也不受时区影响。
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    // MARK: 导出

    public static func makeDocument(
        from context: ModelContext, appearance: BackupDocument.Appearance, now: Date
    ) throws -> BackupDocument {
        // 排序要稳定:同一个 sortOrder 的分类再按名字排。
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        ))
        let entries = try context.fetch(LedgerQueries.all())
        let memory = try context.fetch(FetchDescriptor<MerchantCategory>(sortBy: [SortDescriptor(\.merchantKey)]))
        return BackupDocument(
            app: BackupDocument.appID,
            formatVersion: BackupDocument.currentVersion,
            createdAt: now,
            categories: categories.map {
                BackupDocument.Category(
                    id: $0.id, name: $0.name, symbolName: $0.symbolName, iconData: $0.iconData,
                    colorHex: $0.colorHex, kind: $0.kindRaw, sortOrder: $0.sortOrder,
                    isArchived: $0.isArchived, parentID: $0.parent?.id
                )
            },
            entries: entries.map {
                BackupDocument.Entry(
                    id: $0.id, amountInCents: $0.amountInCents, kind: $0.kindRaw, date: $0.date,
                    createdAt: $0.createdAt, note: $0.note, categoryID: $0.category?.id,
                    autoSource: $0.autoSourceRaw, merchant: $0.merchant, orderRefHash: $0.orderRefHash
                )
            },
            merchantMemory: memory.map {
                BackupDocument.Memory(merchantKey: $0.merchantKey, categoryID: $0.categoryID, updatedAt: $0.updatedAt)
            },
            appearance: appearance
        )
    }

    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateStyle.format(date))
        }
        return try encoder.encode(document)
    }

    public static func export(
        from context: ModelContext, appearance: BackupDocument.Appearance, now: Date
    ) throws -> Data {
        try encode(makeDocument(from: context, appearance: appearance, now: now))
    }

    // MARK: 读取与检查

    private struct Header: Decodable {
        let app: String?
        let formatVersion: Int?
    }

    /// 读取并检查备份文件(spec §4);任何一条不通过都抛 `BackupError`。
    public static func decode(_ data: Data) throws -> BackupDocument {
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.app == BackupDocument.appID,
              let version = header.formatVersion
        else { throw BackupError.notABackup }
        guard version <= BackupDocument.currentVersion else { throw BackupError.tooNew }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return try dateStyle.parse(text)
        }
        guard let document = try? decoder.decode(BackupDocument.self, from: data) else {
            throw BackupError.notABackup
        }
        try validate(document)
        return document
    }

    private static func validate(_ document: BackupDocument) throws {
        let categoryIDs = document.categories.map(\.id)
        let entryIDs = document.entries.map(\.id)
        guard Set(categoryIDs).count == categoryIDs.count, Set(entryIDs).count == entryIDs.count else {
            throw BackupError.corrupted
        }
        let byID = Dictionary(uniqueKeysWithValues: document.categories.map { ($0.id, $0) })
        for category in document.categories {
            guard EntryKind(rawValue: category.kind) != nil else { throw BackupError.corrupted }
            // 只有两级:二级分类的上级必须存在,而且本身是一级分类。
            if let parentID = category.parentID {
                guard let parent = byID[parentID], parent.parentID == nil else { throw BackupError.corrupted }
            }
        }
        guard document.entries.allSatisfy({ EntryKind(rawValue: $0.kind) != nil }) else {
            throw BackupError.corrupted
        }
    }

    // MARK: 预览

    public static func preview(of document: BackupDocument) -> BackupPreview {
        let categoryIDs = Set(document.categories.map(\.id))
        let dates = document.entries.map(\.date)
        return BackupPreview(
            createdAt: document.createdAt,
            entryCount: document.entries.count,
            categoryCount: document.categories.count,
            firstDate: dates.min(),
            lastDate: dates.max(),
            orphanedEntryCount: document.entries.filter { id in
                id.categoryID.map { !categoryIDs.contains($0) } ?? false
            }.count
        )
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 376 tests in 35 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: backup document export, validation and preview

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 原子替换恢复

**Files:**
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/Backup.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BackupTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `Backup`、`BackupDocument`、测试辅助 `fill`、`appearance`、`now`;已有的 `LedgerEntry.init(id:amountInCents:kind:date:note:category:createdAt:calendar:autoSource:merchant:orderRefHash:)`、`LedgerCategory.init(id:name:symbolName:colorHex:kind:sortOrder:parent:iconData:)`、`DayStamp.calendar`。
- Produces:
  - `public struct RestoreResult: Equatable, Sendable { entryCount: Int; orphanedEntryCount: Int }`
  - `public static func replace(with document: BackupDocument, in context: ModelContext) throws -> RestoreResult`(一次 `save()`;出错 `rollback()` 后抛出)
  - `static func replace(with:in:beforeSave:)`(internal,测试用来在保存前注入失败)

- [ ] **Step 1: 写失败的测试**

在 `BackupTests.swift` 里,紧挨 `    // MARK: 预览` 之前加入:

```swift
    // MARK: 替换

    private func snapshot(_ context: ModelContext) throws -> BackupDocument {
        try Backup.makeDocument(from: context, appearance: appearance, now: now)
    }

    @Test func restoringIntoAnEmptyStoreReproducesEverything() throws {
        let source = try makeTestContainer()
        try fill(source.mainContext)
        let document = try snapshot(source.mainContext)

        let target = try makeTestContainer()
        let result = try Backup.replace(with: document, in: target.mainContext)

        #expect(result == RestoreResult(entryCount: 2, orphanedEntryCount: 0))
        #expect(try snapshot(target.mainContext) == document)
    }

    @Test func restoringReplacesWhatWasThere() throws {
        let source = try makeTestContainer()
        try fill(source.mainContext)
        let document = try snapshot(source.mainContext)

        let target = try makeTestContainer()
        let context = target.mainContext
        let stray = CategoryRules.addTopLevel(
            name: "要被替换掉", symbolName: "tag.fill", colorHex: "#000000", kind: .expense, sortOrder: 0, in: context
        )
        context.insert(LedgerEntry(amountInCents: 1, kind: .expense, date: makeDate(2026, 1, 1), category: stray, calendar: testCalendar))
        context.insert(MerchantCategory(merchantKey: "旧商户", categoryID: stray.id))
        try context.save()

        try Backup.replace(with: document, in: context)

        #expect(try snapshot(context) == document)
    }

    @Test func entriesPointingAtMissingCategoriesBecomeUncategorized() throws {
        let source = try makeTestContainer()
        let s = try fill(source.mainContext)
        var document = try snapshot(source.mainContext)
        let index = document.entries.firstIndex { $0.id == s.manual.id }!
        document.entries[index].categoryID = UUID()
        document.merchantMemory[0].categoryID = UUID()

        let target = try makeTestContainer()
        let result = try Backup.replace(with: document, in: target.mainContext)

        #expect(result.orphanedEntryCount == 1)
        let restored = try target.mainContext.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == s.manual.id }
        #expect(restored?.category == nil)
        #expect(try target.mainContext.fetch(FetchDescriptor<MerchantCategory>()).isEmpty)
    }

    struct InjectedFailure: Error {}

    @Test func aFailureDuringReplaceKeepsTheOriginalData() throws {
        let original = try makeTestContainer()
        let context = original.mainContext
        try fill(context)
        let before = try snapshot(context)

        let other = try makeTestContainer()
        let otherContext = other.mainContext
        let replacement = CategoryRules.addTopLevel(
            name: "别的", symbolName: "tag.fill", colorHex: "#000000", kind: .expense, sortOrder: 0, in: otherContext
        )
        otherContext.insert(LedgerEntry(amountInCents: 9, kind: .expense, date: makeDate(2026, 1, 1), category: replacement, calendar: testCalendar))
        try otherContext.save()
        let document = try snapshot(otherContext)

        #expect(throws: InjectedFailure.self) {
            try Backup.replace(with: document, in: context, beforeSave: { throw InjectedFailure() })
        }
        #expect(try snapshot(context) == before)
    }

```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: type 'Backup' has no member 'replace'`(以及 `RestoreResult` 找不到)。

- [ ] **Step 3: 实现**

在 `Backup.swift` 里,紧挨 `    // MARK: 预览` 之前加入:

```swift
    // MARK: 替换

    /// 整体替换:删掉现有的账单、分类、商户记忆,换成备份里的,一次保存;出错就全部撤回再抛出。
    /// 指向不存在分类的账单按未分类恢复,指向不存在分类的商户记忆丢弃。
    @discardableResult
    public static func replace(with document: BackupDocument, in context: ModelContext) throws -> RestoreResult {
        try replace(with: document, in: context, beforeSave: {})
    }

    static func replace(
        with document: BackupDocument, in context: ModelContext, beforeSave: () throws -> Void
    ) throws -> RestoreResult {
        do {
            for entry in try context.fetch(FetchDescriptor<LedgerEntry>()) { context.delete(entry) }
            for memory in try context.fetch(FetchDescriptor<MerchantCategory>()) { context.delete(memory) }
            let oldCategories = try context.fetch(FetchDescriptor<LedgerCategory>())
            for category in oldCategories where category.parent != nil { context.delete(category) }
            for category in oldCategories where category.parent == nil { context.delete(category) }

            // 先建一级分类,再建二级分类(上级已经存在)。
            var categories: [UUID: LedgerCategory] = [:]
            let ordered = document.categories.filter { $0.parentID == nil } + document.categories.filter { $0.parentID != nil }
            for item in ordered {
                let category = LedgerCategory(
                    id: item.id, name: item.name, symbolName: item.symbolName, colorHex: item.colorHex,
                    kind: EntryKind(rawValue: item.kind) ?? .expense, sortOrder: item.sortOrder,
                    parent: item.parentID.flatMap { categories[$0] }, iconData: item.iconData
                )
                category.isArchived = item.isArchived
                context.insert(category)
                categories[item.id] = category
            }

            var orphaned = 0
            for item in document.entries {
                let category = item.categoryID.flatMap { categories[$0] }
                if item.categoryID != nil && category == nil { orphaned += 1 }
                let entry = LedgerEntry(
                    id: item.id, amountInCents: item.amountInCents,
                    kind: EntryKind(rawValue: item.kind) ?? .expense, date: item.date, note: item.note,
                    category: category, createdAt: item.createdAt, calendar: DayStamp.calendar,
                    merchant: item.merchant, orderRefHash: item.orderRefHash
                )
                // 原样保留来源文字,以后新增的来源取值旧版本也不会丢。
                entry.autoSourceRaw = item.autoSource
                context.insert(entry)
            }

            for item in document.merchantMemory where categories[item.categoryID] != nil {
                context.insert(MerchantCategory(merchantKey: item.merchantKey, categoryID: item.categoryID, updatedAt: item.updatedAt))
            }

            try beforeSave()
            try context.save()
            return RestoreResult(entryCount: document.entries.count, orphanedEntryCount: orphaned)
        } catch {
            context.rollback()
            throw error
        }
    }

```

在文件末尾(`BackupPreview` 定义之后、`public enum Backup` 之前)加入:

```swift
public struct RestoreResult: Equatable, Sendable {
    public let entryCount: Int
    /// 分类已不存在、按未分类恢复的笔数。
    public let orphanedEntryCount: Int
}

```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 380 tests in 35 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: restore a backup by replacing all data atomically

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 备份文件名、轮换、何时自动备份、何时提醒

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/BackupFiles.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BackupFilesTests.swift`(新建)

**Interfaces:**
- Consumes: 测试里的 `makeDate`、`testCalendar`。
- Produces(`public enum BackupFiles`):
  - `autoName(for: Date, calendar: Calendar) -> String`、`manualName(at:calendar:)`、`preRestoreName(at:calendar:)`
  - `autoBackupsToDelete(_ names: [String], keep: Int = 7) -> [String]`
  - `needsAutoBackup(lastAutoBackup: Date?, now: Date, calendar: Calendar) -> Bool`
  - `needsReminder(autoBackupOn: Bool, lastExport: Date?, hasEntries: Bool, now: Date) -> Bool`

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/BackupFilesTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct BackupFilesTests {
    private let at = makeDate(2026, 10, 27, 9, 5) + 7

    @Test func fileNamesFollowTheAgreedFormats() {
        #expect(BackupFiles.autoName(for: at, calendar: testCalendar) == "HappySpending 备份 2026-10-27.json")
        #expect(BackupFiles.manualName(at: at, calendar: testCalendar) == "HappySpending 备份 2026-10-27 090507.json")
        #expect(BackupFiles.preRestoreName(at: at, calendar: testCalendar) == "HappySpending 恢复前备份 2026-10-27 090507.json")
    }

    @Test func rotationOnlyDeletesOldAutoBackups() {
        let autos = (19...27).map { "HappySpending 备份 2026-10-\($0).json" }
        let others = [
            "HappySpending 恢复前备份 2026-10-01 120000.json",
            "HappySpending 备份 2026-10-01 120000.json",
            "我的笔记.txt",
        ]

        let deleted = BackupFiles.autoBackupsToDelete((autos + others).shuffled())

        #expect(Set(deleted) == ["HappySpending 备份 2026-10-19.json", "HappySpending 备份 2026-10-20.json"])
    }

    @Test func nothingIsDeletedWithSevenOrFewer() {
        let autos = (21...27).map { "HappySpending 备份 2026-10-\($0).json" }
        #expect(BackupFiles.autoBackupsToDelete(autos).isEmpty)
    }

    @Test func autoBackupRunsOncePerLocalDay() {
        let now = makeDate(2026, 10, 27, 9, 0)
        #expect(BackupFiles.needsAutoBackup(lastAutoBackup: nil, now: now, calendar: testCalendar))
        #expect(!BackupFiles.needsAutoBackup(lastAutoBackup: makeDate(2026, 10, 27, 0, 1), now: now, calendar: testCalendar))
        #expect(BackupFiles.needsAutoBackup(lastAutoBackup: makeDate(2026, 10, 26, 23, 59), now: now, calendar: testCalendar))
    }

    @Test func theReminderAppearsOnlyWhenBackupsAreNeglected() {
        let now = makeDate(2026, 10, 27)
        let recent = makeDate(2026, 10, 1)
        let longAgo = makeDate(2026, 9, 1)

        #expect(!BackupFiles.needsReminder(autoBackupOn: true, lastExport: nil, hasEntries: true, now: now))
        #expect(!BackupFiles.needsReminder(autoBackupOn: false, lastExport: recent, hasEntries: true, now: now))
        #expect(BackupFiles.needsReminder(autoBackupOn: false, lastExport: longAgo, hasEntries: true, now: now))
        #expect(BackupFiles.needsReminder(autoBackupOn: false, lastExport: nil, hasEntries: true, now: now))
        #expect(!BackupFiles.needsReminder(autoBackupOn: false, lastExport: nil, hasEntries: false, now: now))
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'BackupFiles' in scope`。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/BackupFiles.swift`:

```swift
import Foundation

/// 备份文件的命名与轮换规则(spec §2、§6)。文件名里的日期按用户本地日历。
public enum BackupFiles {
    /// 自动备份的文件名;轮换只认这种格式,别的文件一律不动。
    private static let autoPattern = #"^HappySpending 备份 \d{4}-\d{2}-\d{2}\.json$"#

    public static func autoName(for date: Date, calendar: Calendar) -> String {
        "HappySpending 备份 \(day(date, calendar)).json"
    }

    /// 手动导出总是带时间,和自动备份区分开,也不会被轮换删掉。
    public static func manualName(at date: Date, calendar: Calendar) -> String {
        "HappySpending 备份 \(day(date, calendar)) \(time(date, calendar)).json"
    }

    public static func preRestoreName(at date: Date, calendar: Calendar) -> String {
        "HappySpending 恢复前备份 \(day(date, calendar)) \(time(date, calendar)).json"
    }

    /// 文件夹里该删掉的旧自动备份:只保留最新的 `keep` 份,其他文件不管。
    public static func autoBackupsToDelete(_ names: [String], keep: Int = 7) -> [String] {
        let autos = names
            .filter { $0.range(of: autoPattern, options: .regularExpression) != nil }
            .sorted(by: >)
        return Array(autos.dropFirst(keep))
    }

    /// 本地日期的"今天"还没自动备份过。
    public static func needsAutoBackup(lastAutoBackup: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastAutoBackup else { return true }
        return !calendar.isDate(lastAutoBackup, inSameDayAs: now)
    }

    /// 没开自动备份,且超过 30 天没手动导出(或有账单却从没导出过)。
    public static func needsReminder(autoBackupOn: Bool, lastExport: Date?, hasEntries: Bool, now: Date) -> Bool {
        guard !autoBackupOn else { return false }
        guard let lastExport else { return hasEntries }
        return now.timeIntervalSince(lastExport) > 30 * 24 * 3600
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func time(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 385 tests in 36 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: backup file naming, rotation and reminder rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: app 层:外观读写、备份服务、设置页、自动备份触发与提醒

**Files:**
- Modify: `HappySpending/Support/Appearance.swift`(`AppearanceModel` 加两个成员)
- Create: `HappySpending/Settings/BackupService.swift`
- Create: `HappySpending/Settings/BackupSection.swift`
- Modify: `HappySpending/Settings/SettingsView.swift`
- Modify(整个换成): `HappySpending/RootTabView.swift`
- Modify: `HappySpending/HappySpendingApp.swift`

**Interfaces:**
- Consumes: Task 1~3 的 `Backup`、`BackupDocument`、`BackupError`、`BackupPreview`、`RestoreResult`、`BackupFiles`;已有的 `AppearanceModel`、`BackgroundChoice(stored:)`、`BackgroundImageStore`、`LedgerQueries.earliest()/uncategorized()`、`PendingCategorization.pending`、`appRowBackground()`。
- Produces: `BackupService`(`@MainActor @Observable`)、`BackupFile: Transferable`、`BackupSection: View`;`AppearanceModel.backupAppearance`、`AppearanceModel.apply(_:)`。

界面层没有单元测试;验证是构建通过 + 模拟器走一遍。

- [ ] **Step 1: 外观的备份读写**

在 `HappySpending/Support/Appearance.swift` 里,把

```swift
    /// 删除存下来的图片;正在用它时退回默认。
```

换成

```swift
    /// 备份用:当前的外观设置,连同"我的图片"。
    var backupAppearance: BackupDocument.Appearance {
        BackupDocument.Appearance(choice: choice.stored, opacity: opacity, image: store.load())
    }

    /// 恢复备份时换上备份里的外观设置;认不出的背景选择按默认处理。
    func apply(_ backup: BackupDocument.Appearance) throws {
        if let data = backup.image {
            try store.save(data)
            image = UIImage(data: data)
        } else {
            try store.remove()
            image = nil
        }
        opacity = min(max(backup.opacity, 0.1), 1)
        choice = BackgroundChoice(stored: backup.choice)
    }

    /// 删除存下来的图片;正在用它时退回默认。
```

- [ ] **Step 2: 备份服务**

新建 `HappySpending/Settings/BackupService.swift`:

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HappySpendingCore

/// 备份与恢复:导出、恢复(整体替换,先存恢复前备份)、每天自动备份到用户选的文件夹。
@MainActor
@Observable
final class BackupService {
    private enum Key {
        static let folder = "backupFolderBookmark"
        static let lastAuto = "lastAutoBackupAt"
        static let lastExport = "lastBackupExportAt"
        static let lastError = "lastAutoBackupError"
    }

    private let defaults = UserDefaults.standard
    /// 自动备份文件夹的名字;nil 表示没开自动备份。
    private(set) var folderName: String?
    private(set) var lastAutoBackup: Date?
    private(set) var lastExport: Date?
    /// 上次自动备份失败的原因;成功后清空。
    private(set) var lastError: String?
    /// 没设置文件夹时,恢复前备份存在 app 自己的目录里,可以从设置页再导出。
    private(set) var localPreRestoreBackup: URL?
    /// 防止同时写两份(启动和回到前台几乎同时触发)。
    private var isBackingUp = false

    var isAutoBackupOn: Bool { folderName != nil }

    init() {
        lastAutoBackup = defaults.object(forKey: Key.lastAuto) as? Date
        lastExport = defaults.object(forKey: Key.lastExport) as? Date
        lastError = defaults.string(forKey: Key.lastError)
        if defaults.data(forKey: Key.folder) != nil {
            folderName = (try? resolveFolder())?.lastPathComponent ?? "备份文件夹"
        }
        localPreRestoreBackup = (try? FileManager.default.contentsOfDirectory(
            at: Self.localDirectory, includingPropertiesForKeys: nil
        ))?.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }

    private static var localDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Backups")
    }

    func needsReminder(hasEntries: Bool, now: Date = .now) -> Bool {
        BackupFiles.needsReminder(autoBackupOn: isAutoBackupOn, lastExport: lastExport, hasEntries: hasEntries, now: now)
    }

    // MARK: 导出

    func exportData(context: ModelContext, appearance: AppearanceModel, now: Date = .now) throws -> Data {
        let data = try Backup.export(from: context, appearance: appearance.backupAppearance, now: now)
        lastExport = now
        defaults.set(now, forKey: Key.lastExport)
        return data
    }

    // MARK: 自动备份

    func chooseFolder(_ url: URL, context: ModelContext, appearance: AppearanceModel) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Key.folder)
            folderName = url.lastPathComponent
            setError(nil)
        } catch {
            setError("无法使用这个文件夹:\(error.localizedDescription)")
            return
        }
        await backUp(context: context, appearance: appearance, now: .now)
    }

    func turnOffAutoBackup() {
        defaults.removeObject(forKey: Key.folder)
        folderName = nil
        setError(nil)
    }

    func autoBackupIfNeeded(context: ModelContext, appearance: AppearanceModel, now: Date = .now) async {
        guard isAutoBackupOn,
              BackupFiles.needsAutoBackup(lastAutoBackup: lastAutoBackup, now: now, calendar: .current)
        else { return }
        await backUp(context: context, appearance: appearance, now: now)
    }

    private func backUp(context: ModelContext, appearance: AppearanceModel, now: Date) async {
        guard !isBackingUp else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            let data = try Backup.export(from: context, appearance: appearance.backupAppearance, now: now)
            let folder = try resolveFolder()
            let name = BackupFiles.autoName(for: now, calendar: .current)
            try await Task.detached { try Self.write(data, named: name, into: folder, rotate: true) }.value
            lastAutoBackup = now
            defaults.set(now, forKey: Key.lastAuto)
            setError(nil)
        } catch {
            setError("自动备份失败:\(error.localizedDescription)")
        }
    }

    private func setError(_ message: String?) {
        lastError = message
        defaults.set(message, forKey: Key.lastError)
    }

    private func resolveFolder() throws -> URL {
        guard let bookmark = defaults.data(forKey: Key.folder) else { throw CocoaError(.fileNoSuchFile) }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Key.folder)
            }
        }
        return url
    }

    /// 写进文件夹;`rotate` 时只保留最近 7 份自动备份(只删本 app 的自动备份文件)。
    nonisolated private static func write(_ data: Data, named name: String, into folder: URL, rotate: Bool) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        try data.write(to: folder.appending(path: name), options: .atomic)
        guard rotate else { return }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        for old in BackupFiles.autoBackupsToDelete(names) {
            try? FileManager.default.removeItem(at: folder.appending(path: old))
        }
    }

    // MARK: 恢复

    func inspect(_ url: URL) throws -> (document: BackupDocument, preview: BackupPreview) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let document = try Backup.decode(Data(contentsOf: url))
        return (document, Backup.preview(of: document))
    }

    /// 先存恢复前备份(失败就停下,什么都不动),再整体替换,最后换上备份里的外观。
    func restore(
        _ document: BackupDocument, context: ModelContext, appearance: AppearanceModel, now: Date = .now
    ) throws -> RestoreResult {
        let current = try Backup.export(from: context, appearance: appearance.backupAppearance, now: now)
        let name = BackupFiles.preRestoreName(at: now, calendar: .current)
        if isAutoBackupOn, let folder = try? resolveFolder() {
            try Self.write(current, named: name, into: folder, rotate: false)
        } else {
            let directory = Self.localDirectory
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: name)
            try current.write(to: url, options: .atomic)
            localPreRestoreBackup = url
        }
        let result = try Backup.replace(with: document, in: context)
        try appearance.apply(document.appearance)
        return result
    }
}

/// 分享面板里的备份文件:点了才生成数据。
struct BackupFile: Transferable {
    let name: String
    let data: @MainActor () throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let data = try await MainActor.run { try file.data() }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
```

- [ ] **Step 3: 设置页的"备份与恢复"**

新建 `HappySpending/Settings/BackupSection.swift`:

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HappySpendingCore

/// 设置页的"备份与恢复":导出、从备份恢复、自动备份文件夹。
struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppearanceModel.self) private var appearance
    @Environment(BackupService.self) private var backup
    @Query(LedgerQueries.earliest()) private var anyEntry: [LedgerEntry]

    private enum Picking { case backupFile, folder }

    private struct PendingRestore: Identifiable {
        let id = UUID()
        let document: BackupDocument
        let preview: BackupPreview
    }

    @State private var picking: Picking?
    @State private var pending: PendingRestore?
    @State private var message: String?

    var body: some View {
        Section {
            ShareLink(
                item: BackupFile(
                    name: BackupFiles.manualName(at: .now, calendar: .current),
                    data: { [context, appearance, backup] in
                        try backup.exportData(context: context, appearance: appearance)
                    }
                ),
                preview: SharePreview("Happy Spending 备份")
            ) {
                Label("导出备份", systemImage: "square.and.arrow.up")
            }
            .appRowBackground()

            Button { picking = .backupFile } label: {
                Label("从备份恢复", systemImage: "arrow.counterclockwise")
            }
            .appRowBackground()

            if let folder = backup.folderName {
                VStack(alignment: .leading, spacing: 4) {
                    Label("自动备份到「\(folder)」", systemImage: "clock.arrow.circlepath")
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let error = backup.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .appRowBackground()
                Button(backup.lastError == nil ? "更换文件夹" : "重新选择文件夹") { picking = .folder }
                    .appRowBackground()
                Button("关闭自动备份", role: .destructive) { backup.turnOffAutoBackup() }
                    .appRowBackground()
            } else {
                Button { picking = .folder } label: {
                    Label("选择自动备份文件夹", systemImage: "folder.badge.plus")
                }
                .appRowBackground()
            }

            if !backup.isAutoBackupOn, let local = backup.localPreRestoreBackup {
                ShareLink(item: local) {
                    Label("导出恢复前备份", systemImage: "clock.badge.exclamationmark")
                }
                .appRowBackground()
            }
        } header: {
            HStack(spacing: 6) {
                Text("备份与恢复")
                if backup.needsReminder(hasEntries: !anyEntry.isEmpty) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                }
            }
        } footer: {
            Text("自动备份每天第一次打开 app 时写一份,只保留最近 7 份。恢复会整体替换现有数据,替换前会先自动存一份恢复前备份。")
        }
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: picking == .folder ? [.folder] : [.json]
        ) { result in
            let kind = picking
            picking = nil
            guard case .success(let url) = result else { return }
            switch kind {
            case .folder:
                Task { await backup.chooseFolder(url, context: context, appearance: appearance) }
            case .backupFile:
                do {
                    let (document, preview) = try backup.inspect(url)
                    pending = PendingRestore(document: document, preview: preview)
                } catch let error as BackupError {
                    message = error.message
                } catch {
                    message = BackupError.notABackup.message
                }
            case nil:
                break
            }
        }
        .alert(
            "恢复这个备份?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { item in
            Button("替换现有数据", role: .destructive) { restore(item.document) }
            Button("取消", role: .cancel) {}
        } message: { item in
            Text(previewText(item.preview))
        }
        .alert(
            message ?? "",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("好") {}
        }
    }

    private var statusText: String {
        guard let last = backup.lastAutoBackup else { return "还没有自动备份过" }
        return "上次自动备份:" + last.formatted(.relative(presentation: .named))
    }

    private func previewText(_ preview: BackupPreview) -> String {
        var lines = ["备份时间:" + preview.createdAt.formatted(date: .numeric, time: .shortened),
                     "共 \(preview.entryCount) 笔账、\(preview.categoryCount) 个分类"]
        if let first = preview.firstDate, let last = preview.lastDate {
            lines.append("账单日期:" + first.formatted(date: .numeric, time: .omitted)
                         + " ~ " + last.formatted(date: .numeric, time: .omitted))
        }
        lines.append("现有数据会被替换,替换前会先自动存一份恢复前备份。")
        return lines.joined(separator: "\n")
    }

    private func restore(_ document: BackupDocument) {
        do {
            let result = try backup.restore(document, context: context, appearance: appearance)
            var text = "已恢复 \(result.entryCount) 笔账"
            if result.orphanedEntryCount > 0 {
                text += "\n有 \(result.orphanedEntryCount) 笔账的分类已不存在,已归为未分类"
            }
            message = text
        } catch {
            message = "恢复失败,数据未改动"
        }
    }
}
```

在 `HappySpending/Settings/SettingsView.swift` 里,把

```swift
                AppearanceSection()
```

换成

```swift
                AppearanceSection()
                BackupSection()
```

- [ ] **Step 4: 自动备份触发、页签提醒、注入**

把 `HappySpending/RootTabView.swift` 整个换成:

```swift
import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppearanceModel.self) private var appearance
    @Environment(BackupService.self) private var backup

    /// 只查没有分类的账,再挑出支出,作为账单页签的角标。
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]
    @Query(LedgerQueries.earliest()) private var anyEntry: [LedgerEntry]

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }

    var body: some View {
        TabView {
            Tab("记账", systemImage: "plus.circle.fill") { RecordView() }
            Tab("账单", systemImage: "list.bullet.rectangle") { BillsView() }
                .badge(pendingCount)
            Tab("统计", systemImage: "chart.pie.fill") { StatsView() }
            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }
                .badge(backup.needsReminder(hasEntries: !anyEntry.isEmpty) ? Text("!") : nil)
        }
        // 每天第一次打开或回到前台时自动备份(没开自动备份时什么也不做)。
        .task { await backup.autoBackupIfNeeded(context: context, appearance: appearance) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await backup.autoBackupIfNeeded(context: context, appearance: appearance) }
        }
    }
}
```

在 `HappySpending/HappySpendingApp.swift` 里,把

```swift
    @State private var appearance = AppearanceModel()
```

换成

```swift
    @State private var appearance = AppearanceModel()
    @State private var backup = BackupService()
```

再把

```swift
                .environment(appearance)
```

换成

```swift
                .environment(appearance)
                .environment(backup)
```

(spec §3 写的是"小红点";页签角标只能显示文字,这里用"!",设置页那一节的标题旁仍是红点。)

- [ ] **Step 5: 构建**

Run: Global Constraints 里的 app 构建命令。
Expected: `** BUILD SUCCEEDED **`,没有 HappySpending 目录下的警告。

- [ ] **Step 6: 模拟器里走一遍**

覆盖安装到模拟器并启动(模拟器里已有账单)。
Expected:
- 设置页签有"!",设置页"备份与恢复"标题旁有红点。
- 点"导出备份",分享面板里选"存储到文件",存到"我的 iPhone";之后"!"和红点消失。
- 点"选择自动备份文件夹",在"我的 iPhone"里新建并选一个文件夹:立刻生成一份 `HappySpending 备份 <今天>.json`,设置页显示"自动备份到「…」"和"上次自动备份:…"。
- 在记账页随手记一笔,然后"从备份恢复"选刚才导出的文件:弹出"恢复这个备份?",显示笔数和日期范围;点"替换现有数据"后提示"已恢复 N 笔账",刚记的那笔消失,背景不变;自动备份文件夹里多了一份"恢复前备份"。
- 用"文件"app 删掉自动备份文件夹,改系统日期到明天后回到 app:设置页显示红色的"自动备份失败…"和"重新选择文件夹"。
- 改回系统日期。

- [ ] **Step 7: 提交**

```bash
git add HappySpending
git commit -m "feat: export, restore and daily auto backup in settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 文档与最终验证

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-10-27-backup-and-restore-design.md`(§2 手动导出文件名)

**Interfaces:** 无。

- [ ] **Step 1: 文档**

Run(仓库根目录):

```bash
python3 -I - <<'EOF'
def rep(p, old, new):
    s = open(p, encoding="utf-8").read()
    assert s.count(old) == 1, (p, old)
    open(p, "w", encoding="utf-8").write(s.replace(old, new))

rep("docs/manual-test-checklist.md", "## 深色模式", """## 备份与恢复

- [ ] 导出备份:分享面板能存到"文件",文件名带日期和时间
- [ ] 从备份恢复:预览显示笔数和日期范围;替换后数据、分类图标、商户记忆、背景都和备份一致;另存了一份恢复前备份
- [ ] 选错文件(随便一个 JSON、图片改名的 .json)提示"这不是 Happy Spending 的备份文件",数据不变
- [ ] 自动备份:选文件夹后立刻生成今天的备份;第二天打开 app 再生成一份;超过 7 份时只删最旧的自动备份,恢复前备份和别的文件不动
- [ ] 删掉备份文件夹后,设置页显示失败原因和"重新选择文件夹",不弹窗
- [ ] 没开自动备份、超过 30 天没导出时,设置页签有"!",导出一次后消失
- [ ] 删掉 app 重装,从"文件"里的备份恢复,所有数据回来

## 深色模式""")

rep("README.md",
    "- 待归类设计:`docs/superpowers/specs/2026-10-16-pending-categorization-design.md`\n",
    "- 待归类设计:`docs/superpowers/specs/2026-10-16-pending-categorization-design.md`\n"
    "- 备份与恢复设计:`docs/superpowers/specs/2026-10-27-backup-and-restore-design.md`\n")

rep("docs/superpowers/specs/2026-10-27-backup-and-restore-design.md",
    "一个 JSON 文本文件,文件名 `HappySpending 备份 yyyy-MM-dd.json`(自动备份同一天只有一份,手动导出同一天重名时加时间 `yyyy-MM-dd HHmmss`)。",
    "一个 JSON 文本文件。自动备份的文件名是 `HappySpending 备份 yyyy-MM-dd.json`(同一天只有一份);手动导出总是带时间 `HappySpending 备份 yyyy-MM-dd HHmmss.json`,既不会重名,也不会被自动备份的轮换删掉。")
EOF
```

Expected: 没有输出。

- [ ] **Step 2: 最终验证**

Run: Global Constraints 里的测试命令,再跑 app 构建命令。
Expected: `✔ Test run with 385 tests in 36 suites passed`;`** BUILD SUCCEEDED **`;没有 HappySpending 目录下的警告。

- [ ] **Step 3: 提交**

```bash
git add README.md docs
git commit -m "docs: backup checklist, README link and file naming note

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
