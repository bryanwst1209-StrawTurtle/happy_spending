import Foundation
import SwiftData

/// 待归类:自动记下、还没有分类的支出。
/// 归好一笔有商户的自动账时,顺带记住商户,并把同商户的其他未分类支出一起归好。
public enum PendingCategorization {
    /// 待归类的账:没有分类的支出,按日期、再按记账时间从早到晚。
    public static func pending(_ entries: [LedgerEntry]) -> [LedgerEntry] {
        entries
            .filter { $0.kind == .expense && $0.category == nil }
            // 一次记好几笔时日期和记账时间都相同,再按 id 排,保证每次打开顺序一样。
            .sorted { ($0.date, $0.createdAt, $0.id.uuidString) < ($1.date, $1.createdAt, $1.id.uuidString) }
    }

    /// 把一笔账归到分类。是有商户的自动支出、且归到支出分类时,记住"商户 → 分类",
    /// 并把同商户的其他未分类支出一起归好。一次保存;失败时撤回本次所有改动再抛错。
    /// 返回一起归好的**其他**笔数。
    @discardableResult
    public static func assign(
        _ entry: LedgerEntry,
        to category: LedgerCategory,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Int {
        do {
            entry.category = category
            var others = 0
            if entry.isAuto, entry.kind == .expense, category.kind == .expense,
               let merchant = entry.merchant.flatMap(MerchantKey.trimmed) {
                try MerchantMemory.learn(
                    merchant: merchant, categoryID: MerchantMemory.topLevel(of: category).id, in: context, now: now
                )
                others = try backfill(sameMerchantAs: entry, in: context)
            }
            try context.save()
            return others
        } catch {
            context.rollback()
            throw error
        }
    }

    /// 把与 `entry` 同商户(忽略大小写、多余空白)、还没分类的其他支出设成 `entry` 分类的**一级分类**
    /// (和商户记忆一致);不保存。`entry` 没有分类、没有商户,或分类不是支出分类时什么也不做。返回改了几笔。
    @discardableResult
    public static func backfill(sameMerchantAs entry: LedgerEntry, in context: ModelContext) throws -> Int {
        guard let category = entry.category, category.kind == .expense,
              let merchant = entry.merchant.flatMap(MerchantKey.trimmed)
        else { return 0 }
        let key = MerchantKey.normalize(merchant)
        let matches = try context.fetch(FetchDescriptor<LedgerEntry>()).filter {
            $0.id != entry.id
                && $0.kind == .expense
                && $0.category == nil
                && $0.merchant.flatMap(MerchantKey.trimmed).map(MerchantKey.normalize) == key
        }
        let topLevel = MerchantMemory.topLevel(of: category)
        for match in matches { match.category = topLevel }
        return matches.count
    }

    /// 同商户一起归好时的提示,例如"已同时归类 2 笔 示例小吃"。
    public static func notice(count: Int, merchant: String?) -> String {
        let name = merchant.flatMap(MerchantKey.trimmed).map { " \($0)" } ?? ""
        return "已同时归类 \(count) 笔\(name)"
    }
}
