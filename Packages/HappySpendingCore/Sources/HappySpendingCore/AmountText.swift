import Foundation

public enum AmountError: Error, Equatable, LocalizedError {
    case invalidAmount
    case notAnExpense
    case tooLarge

    public var message: String {
        switch self {
        case .invalidAmount: "无法识别金额"
        case .notAnExpense: "金额必须大于 0"
        case .tooLarge: "金额超过 9,999,999.99"
        }
    }

    public var errorDescription: String? { message }
}

/// 把快捷指令传来的金额文本解析成整数分。快捷指令传出的是数字还是带符号的文本要等真机验证,
/// 所以两种都要能处理。
public enum AmountText {
    /// 最多接受的整数位数;超过它直接判为过大,避免 Decimal 溢出。
    private static let maxIntegerDigits = 12

    public static func cents(from text: String) throws -> Int {
        var s = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        for token in ["¥", "\u{FFE5}", "元", "cny", "rmb"] {
            s = s.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        s = String(s.filter { !$0.isWhitespace })

        // 逗号只有在构成合法的千分位分组时才去掉(`1,234.56`)。否则它可能是某些地区的小数逗号
        // (`25,00` 是 25 元),直接丢掉会把金额放大 100 倍且没有任何提示,宁可拒绝。
        if s.contains(",") {
            guard s.range(of: #"^[+-]?\d{1,3}(,\d{3})+(\.\d*)?$"#, options: .regularExpression) != nil else {
                throw AmountError.invalidAmount
            }
            s = s.replacingOccurrences(of: ",", with: "")
        }

        guard s.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil else {
            throw AmountError.invalidAmount
        }

        let negative = s.hasPrefix("-")
        if s.hasPrefix("+") || s.hasPrefix("-") { s.removeFirst() }
        if s.hasPrefix(".") { s = "0" + s }
        if s.hasSuffix(".") { s.removeLast() }

        let integerDigits = s.split(separator: ".", omittingEmptySubsequences: false).first?.count ?? 0
        guard integerDigits <= maxIntegerDigits else {
            throw negative ? AmountError.notAnExpense : AmountError.tooLarge
        }

        guard let decimal = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw AmountError.invalidAmount
        }

        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)

        if negative || rounded <= 0 { throw AmountError.notAnExpense }
        if rounded > Decimal(Money.maxCents) { throw AmountError.tooLarge }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
