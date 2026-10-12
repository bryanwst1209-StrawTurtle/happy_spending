public enum EntryKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income

    public var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        }
    }
}
