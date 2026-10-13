import Foundation
import SwiftData

/// "记住我的选择":商户到分类的记忆。同一个 `merchantKey` 只保留一条。
@Model
public final class MerchantCategory {
    /// 归一化后的商户名,见 `MerchantKey.normalize(_:)`。
    public var merchantKey: String
    /// 指向一级或二级分类。用 ID 而不是关系,避免给分类加反向关系;使用时再按 ID 查分类。
    public var categoryID: UUID
    public var updatedAt: Date

    public init(merchantKey: String, categoryID: UUID, updatedAt: Date = .now) {
        self.merchantKey = merchantKey
        self.categoryID = categoryID
        self.updatedAt = updatedAt
    }
}
