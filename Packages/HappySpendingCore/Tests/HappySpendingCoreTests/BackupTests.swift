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
