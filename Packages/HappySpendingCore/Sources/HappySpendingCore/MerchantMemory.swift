import Foundation
import SwiftData

public enum MerchantKey {
    /// 去首尾空白、连续空白(含换行、制表符、全角空格)合并为一个空格、忽略大小写。
    public static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    /// 商户原名:只去首尾空白;为空返回 nil。
    public static func trimmed(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// "记住我的选择":商户到分类的记忆。**只记到一级分类**:归到"餐饮 · 午餐"时记住的是"餐饮"。
public enum MerchantMemory {
    /// 记忆里该商户对应的一级分类 ID。以前记成二级分类的旧记忆按它的一级分类算;
    /// 分类不存在、一级分类已归档或不是支出分类时返回 nil。
    public static func categoryID(
        for merchant: String?,
        memory: [MerchantCategory],
        categories: [LedgerCategory]
    ) -> UUID? {
        guard let merchant else { return nil }
        let key = MerchantKey.normalize(merchant)
        guard !key.isEmpty,
              let remembered = memory.first(where: { $0.merchantKey == key }),
              let category = categories.first(where: { $0.id == remembered.categoryID })
        else { return nil }
        let top = topLevel(of: category)
        guard top.kind == .expense, !top.isArchived else { return nil }
        return top.id
    }

    /// 二级分类的一级分类;本身就是一级分类时返回自己。
    public static func topLevel(of category: LedgerCategory) -> LedgerCategory {
        category.parent ?? category
    }

    /// 记下"这个商户 → 这个分类";同一个商户已有记忆时更新,不新增第二条。
    @discardableResult
    public static func learn(
        merchant: String,
        categoryID: UUID,
        in context: ModelContext,
        now: Date = .now
    ) throws -> MerchantCategory {
        let key = MerchantKey.normalize(merchant)
        var descriptor = FetchDescriptor<MerchantCategory>(
            predicate: #Predicate { $0.merchantKey == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.categoryID = categoryID
            existing.updatedAt = now
            return existing
        }
        let created = MerchantCategory(merchantKey: key, categoryID: categoryID, updatedAt: now)
        context.insert(created)
        return created
    }

    /// 编辑一笔账并改了分类后调用。只有同时满足这些条件才学习:
    /// 是自动账、商户非空、保存后分类非空、分类与保存前不同。返回是否学习了。
    @discardableResult
    public static func learnFromEdit(
        entry: LedgerEntry,
        previousCategoryID: UUID?,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Bool {
        // 自动账只记支出,所以只学习"支出账 → 支出分类"。把自动账改成收入类型时不学,
        // 否则这个商户以后的支出都会落进收入分类。
        guard entry.isAuto,
              entry.kind == .expense,
              let merchant = entry.merchant.flatMap(MerchantKey.trimmed),
              let category = entry.category,
              category.kind == .expense,
              category.id != previousCategoryID
        else { return false }
        try learn(merchant: merchant, categoryID: topLevel(of: category).id, in: context, now: now)
        return true
    }
}
