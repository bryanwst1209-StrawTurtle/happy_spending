public enum KeypadKey: Hashable, Sendable {
    case digit(Int)
    case dot
    case backspace
}

/// 自定义数字键盘的输入状态:整数最多 7 位,小数最多 2 位,不允许前导零。
public struct AmountInput: Equatable, Sendable {
    /// 用户已输入的内容:"" / "0." / "12" / "12.3" / "12.34"。
    public private(set) var text: String

    public init() {
        text = ""
    }

    public init(cents: Int) {
        let clamped = min(max(cents, 0), Money.maxCents)
        text = clamped == 0 ? "" : Money.plain(clamped)
    }

    public var cents: Int {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(parts.first ?? "") ?? 0
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        while fraction.count < 2 { fraction += "0" }
        return whole * 100 + (Int(fraction) ?? 0)
    }

    public var isValid: Bool { cents > 0 }

    public var displayText: String {
        text.isEmpty ? "¥0.00" : "¥" + text
    }

    public mutating func press(_ key: KeypadKey) {
        switch key {
        case .digit(let digit):
            guard (0...9).contains(digit) else { return }
            if let dot = text.firstIndex(of: ".") {
                let decimals = text.distance(from: dot, to: text.endIndex) - 1
                guard decimals < 2 else { return }
                text.append(String(digit))
            } else if text == "0" {
                text = String(digit)
            } else {
                guard text.count < 7 else { return }
                text.append(String(digit))
            }
        case .dot:
            guard !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
        case .backspace:
            if !text.isEmpty { text.removeLast() }
        }
    }
}
