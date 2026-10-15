import Foundation
import SwiftData

public struct AutoEntryResult: Equatable, Sendable {
    /// 新记的那一笔;被判为重复时是库里已有的那一笔。
    public let entryID: UUID
    public let cents: Int
    /// 给快捷指令显示的一句话,例如 "已记 ¥15.12 · 支付宝"。
    public let message: String
    /// 去重标识相同(单号,或微信的金额 + 分钟),没有新建。
    public let isDuplicate: Bool

    public init(entryID: UUID, cents: Int, message: String, isDuplicate: Bool = false) {
        self.entryID = entryID
        self.cents = cents
        self.message = message
        self.isDuplicate = isDuplicate
    }
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
        let payment = PaymentRecord(source: .applePay, cents: cents, merchant: merchant, note: merchant ?? "")
        return try record(payment, now: now, calendar: calendar, in: context)
    }

    /// 记一笔已经解析好的支出。
    /// 去重标识相同就跳过;分类依次取商户记忆、平台分类映射,都没有就是"未分类"。
    @discardableResult
    public static func record(
        _ payment: PaymentRecord,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> AutoEntryResult {
        let refHash = payment.orderRef.flatMap(OrderRef.hash)
        if let refHash {
            let wanted: String? = refHash
            var descriptor = FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.orderRefHash == wanted }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                return AutoEntryResult(
                    entryID: existing.id,
                    cents: existing.amountInCents,
                    message: "已记过这一笔",
                    isDuplicate: true
                )
            }
        }

        let merchant = payment.merchant.flatMap(MerchantKey.trimmed)
        let memory = try context.fetch(FetchDescriptor<MerchantCategory>())
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())

        var categoryID = MerchantMemory.categoryID(for: merchant, memory: memory, categories: categories)
        if categoryID == nil,
           let ourName = payment.platformCategory.flatMap(PlatformCategoryMap.ourCategoryName(forAlipay:)) {
            categoryID = categories.first {
                $0.parent == nil && $0.kind == .expense && !$0.isArchived && $0.name == ourName
            }?.id
        }
        let category = categoryID.flatMap { id in categories.first { $0.id == id } }

        let entry = LedgerEntry(
            amountInCents: payment.cents,
            kind: .expense,
            date: payment.eventDate ?? now,
            note: payment.note,
            category: category,
            createdAt: now,
            calendar: calendar,
            autoSource: payment.source,
            merchant: merchant,
            orderRefHash: refHash
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            throw error
        }

        let label = merchant ?? (payment.note.isEmpty ? nil : payment.note)
        let suffix = label.map { " · \($0)" } ?? ""
        return AutoEntryResult(
            entryID: entry.id,
            cents: payment.cents,
            message: "已记 \(Money.display(payment.cents))\(suffix)"
        )
    }
}
