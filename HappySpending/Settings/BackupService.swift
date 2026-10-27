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
            folderName = (try? resolveFolder()).map(Self.displayName) ?? "备份文件夹"
        }
        localPreRestoreBackup = (try? FileManager.default.contentsOfDirectory(
            at: Self.localDirectory, includingPropertiesForKeys: nil
        ))?.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }

    /// "我的 iPhone"的根目录在系统里叫 File Provider Storage,显示成用户认得的名字。
    private static func displayName(_ url: URL) -> String {
        url.lastPathComponent == "File Provider Storage" ? "我的 iPhone" : url.lastPathComponent
    }

    private static var localDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Backups")
    }

    func needsReminder(hasEntries: Bool, now: Date = .now) -> Bool {
        BackupFiles.needsReminder(
            autoBackupOn: isAutoBackupOn, lastExport: lastExport, hasEntries: hasEntries, now: now,
            lastAutoBackup: lastAutoBackup, autoBackupFailing: lastError != nil
        )
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
            folderName = Self.displayName(url)
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
    /// 返回给用户看的结果文字;外观没换上不算失败(数据已经替换好了)。
    func restore(
        _ document: BackupDocument, context: ModelContext, appearance: AppearanceModel, now: Date = .now
    ) throws -> String {
        let current = try Backup.export(from: context, appearance: appearance.backupAppearance, now: now)
        try savePreRestoreBackup(current, now: now)
        let result = try Backup.replace(with: document, in: context)
        let appearanceRestored = (try? appearance.apply(document.appearance)) != nil
        return Backup.restoreMessage(result, appearanceRestored: appearanceRestored)
    }

    /// 恢复前备份:优先写进自动备份文件夹;文件夹失效、写不进去时退回 app 自己的目录(那里保留最近 3 份),
    /// 不会因为文件夹坏了就恢复不了。
    private func savePreRestoreBackup(_ data: Data, now: Date) throws {
        let name = BackupFiles.preRestoreName(at: now, calendar: .current)
        if isAutoBackupOn, let folder = try? resolveFolder(),
           (try? Self.write(data, named: name, into: folder, rotate: false)) != nil {
            return
        }
        let directory = Self.localDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url, options: .atomic)
        localPreRestoreBackup = url
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for old in BackupFiles.preRestoreBackupsToDelete(names) {
            try? FileManager.default.removeItem(at: directory.appending(path: old))
        }
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
