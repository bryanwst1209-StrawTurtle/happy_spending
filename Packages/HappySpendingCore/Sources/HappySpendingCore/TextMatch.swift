import Foundation

/// 解析器共用的小工具:用正则取第一个匹配的各捕获组。
enum TextMatch {
    /// 返回第一个匹配的各捕获组,下标 0 是整段匹配;没有匹配或正则写错返回 nil。
    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
