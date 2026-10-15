import Foundation
import CryptoKit

/// 单号只用来判断"是不是同一笔",所以只存哈希,不存原文。
public enum OrderRef {
    /// 去掉所有空白后做 SHA-256,返回 64 位小写十六进制;内容为空返回 nil。
    public static func hash(_ raw: String) -> String? {
        let compact = raw.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }
        return SHA256.hash(data: Data(compact.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
