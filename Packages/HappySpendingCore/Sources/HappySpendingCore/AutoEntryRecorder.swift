import Foundation
import SwiftData

public struct AutoEntryResult: Equatable, Sendable {
    public let entryID: UUID
    public let cents: Int
    /// 给快捷指令显示的一句话,例如 "已记 ¥25.00 · 美团"。
    public let message: String
}

public enum AutoEntryRecorder {
    /// 记一笔 Apple Pay 自动账:金额解析失败时抛错、不记账;分类取商户记忆里的,没有就是"未分类"。
    @discardableResult
    public static func record(
        merchant rawMerchant: String,
        amountText: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> AutoEntryResult {
        let cents = try AmountText.cents(from: amountText)
        let merchant = MerchantKey.trimmed(rawMerchant)

        let memory = try context.fetch(FetchDescriptor<MerchantCategory>())
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let categoryID = MerchantMemory.categoryID(for: merchant, memory: memory, categories: categories)
        let category = categoryID.flatMap { id in categories.first { $0.id == id } }

        let entry = LedgerEntry(
            amountInCents: cents,
            kind: .expense,
            date: now,
            note: merchant ?? "",
            category: category,
            createdAt: now,
            calendar: calendar,
            autoSource: .applePay,
            merchant: merchant
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            throw error
        }

        let suffix = merchant.map { " · \($0)" } ?? ""
        return AutoEntryResult(entryID: entry.id, cents: cents, message: "已记 \(Money.display(cents))\(suffix)")
    }
}
