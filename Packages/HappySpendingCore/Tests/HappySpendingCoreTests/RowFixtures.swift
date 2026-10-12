import Foundation
@testable import HappySpendingCore

/// 同一个名字在同一次测试进程里总是得到同一个 UUID。
func stableID(_ name: String) -> UUID {
    let suffix = UInt64(truncatingIfNeeded: name.hashValue) & 0xFFFF_FFFF_FFFF
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", suffix))!
}

func makeRow(
    cents: Int,
    kind: EntryKind = .expense,
    on date: Date,
    top: String = "餐饮",
    topID: UUID? = nil,
    sub: String? = nil,
    subID: UUID? = nil,
    note: String = "",
    createdAt: Date? = nil
) -> EntryRow {
    EntryRow(
        date: date,
        createdAt: createdAt,
        kind: kind,
        cents: cents,
        note: note,
        topCategoryID: topID ?? stableID(top),
        topCategoryName: top,
        topColorHex: "#FF9F0A",
        subCategoryID: sub.map { subID ?? stableID($0) },
        subCategoryName: sub
    )
}
