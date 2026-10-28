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
    /// 成就解锁记录;旧版本的备份没有这一项(nil,恢复时按空处理)。
    public var achievements: [Unlock]?
    /// 打开过 app 的日子;旧版本的备份没有这一项。
    public var openDays: [Date]?

    public struct Unlock: Codable, Equatable, Sendable {
        public var id: String
        public var unlockedAt: Date
    }
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

public struct RestoreResult: Equatable, Sendable {
    public let entryCount: Int
    /// 分类已不存在、按未分类恢复的笔数。
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
            appearance: appearance,
            achievements: try context.fetch(FetchDescriptor<AchievementUnlock>(sortBy: [SortDescriptor(\.id)]))
                .map { BackupDocument.Unlock(id: $0.id, unlockedAt: $0.unlockedAt) },
            openDays: try context.fetch(FetchDescriptor<OpenDay>(sortBy: [SortDescriptor(\.day)])).map(\.day)
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
            for unlock in try context.fetch(FetchDescriptor<AchievementUnlock>()) { context.delete(unlock) }
            for day in try context.fetch(FetchDescriptor<OpenDay>()) { context.delete(day) }
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

            var seenBadges = Set<String>()
            for item in document.achievements ?? [] where seenBadges.insert(item.id).inserted {
                context.insert(AchievementUnlock(id: item.id, unlockedAt: item.unlockedAt))
            }
            for day in Set(document.openDays ?? []) {
                context.insert(OpenDay(day: day))
            }

            try beforeSave()
            try context.save()
            return RestoreResult(entryCount: document.entries.count, orphanedEntryCount: orphaned)
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: 恢复后的提示

    /// 恢复完成后给用户看的一句话。外观(背景)没换上不算恢复失败:数据已经替换好了。
    public static func restoreMessage(_ result: RestoreResult, appearanceRestored: Bool) -> String {
        var lines = ["已恢复 \(result.entryCount) 笔账"]
        if result.orphanedEntryCount > 0 {
            lines.append("有 \(result.orphanedEntryCount) 笔账的分类已不存在,已归为未分类")
        }
        if !appearanceRestored {
            lines.append("背景设置没能恢复,可以在外观里重新选")
        }
        return lines.joined(separator: "\n")
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
