import Foundation
import SwiftData

/// 待归类:自动记下、还没有分类的支出。
/// 归好一笔有商户的自动账时,顺带记住商户,并把同商户的其他未分类支出一起归好。
public enum PendingCategorization {
    /// 待归类的账:没有分类的支出,按日期、再按记账时间从早到晚。
    public static func pending(_ entries: [LedgerEntry]) -> [LedgerEntry] {
        entries
            .filter { $0.kind == .expense && $0.category == nil }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    /// 同商户一起归好时的提示,例如"已同时归类 2 笔 示例小吃"。
    public static func notice(count: Int, merchant: String?) -> String {
        let name = merchant.flatMap(MerchantKey.trimmed).map { " \($0)" } ?? ""
        return "已同时归类 \(count) 笔\(name)"
    }
}
