/// 自动账的来源。目前只有 Apple Pay;做成枚举是因为之后的周期性账单也要标记为自动。
public enum EntrySource: String, Codable, Sendable {
    case applePay
}
