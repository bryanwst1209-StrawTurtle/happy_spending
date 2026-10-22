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
