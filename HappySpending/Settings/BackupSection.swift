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

    /// 选的是备份文件还是文件夹。文件选择器关闭时会先把 isPresented 置为 false 再回调结果,
    /// 所以这个值要和"是否显示"分开存,不能在关闭时被清掉。
    @State private var picking = Picking.backupFile
    @State private var isImporting = false
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

            Button { pick(.backupFile) } label: {
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
                Button(backup.lastError == nil ? "更换文件夹" : "重新选择文件夹") { pick(.folder) }
                    .appRowBackground()
                Button("关闭自动备份", role: .destructive) { backup.turnOffAutoBackup() }
                    .appRowBackground()
            } else {
                Button { pick(.folder) } label: {
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
            isPresented: $isImporting,
            allowedContentTypes: picking == .folder ? [.folder] : [.json]
        ) { result in
            guard case .success(let url) = result else { return }
            switch picking {
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

    private func pick(_ kind: Picking) {
        picking = kind
        isImporting = true
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
