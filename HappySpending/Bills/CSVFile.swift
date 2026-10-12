import SwiftUI
import UniformTypeIdentifiers
import HappySpendingCore

struct CSVFile: Transferable {
    let name: String
    let rows: [EntryRow]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try CSVExporter.csv(file.rows).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
