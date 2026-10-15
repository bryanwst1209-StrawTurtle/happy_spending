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
