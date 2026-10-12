import Foundation
import SwiftData

public enum CategoryError: Error, Equatable {
    case parentMustBeTopLevel
}

public enum CategoryRules {
    @discardableResult
    public static func addTopLevel(
        name: String,
        symbolName: String,
        colorHex: String,
        kind: EntryKind,
        sortOrder: Int,
        in context: ModelContext
    ) -> LedgerCategory {
        let category = LedgerCategory(
            name: name, symbolName: symbolName, colorHex: colorHex,
            kind: kind, sortOrder: sortOrder
        )
        context.insert(category)
        return category
    }

    /// 二级分类继承一级分类的类型和颜色。
    @discardableResult
    public static func addSubcategory(
        name: String,
        symbolName: String = "tag.fill",
        under parent: LedgerCategory,
        in context: ModelContext
    ) throws -> LedgerCategory {
        guard parent.parent == nil else { throw CategoryError.parentMustBeTopLevel }
        let category = LedgerCategory(
            name: name, symbolName: symbolName, colorHex: parent.colorHex,
            kind: parent.kind, sortOrder: parent.children.count, parent: parent
        )
        context.insert(category)
        return category
    }

    /// 决定记账表单当前应选中的分类:
    /// 当前选择仍然有效(类型一致且未归档)就保留;否则用上次用过的同类型分类;再不行取排序第一的一级分类。
    public static func resolveSelection(
        current: UUID?,
        kind: EntryKind,
        categories: [LedgerCategory],
        lastUsed: LedgerCategory?
    ) -> UUID? {
        let active = categories.filter { !$0.isArchived && $0.kind == kind }
        if let current, active.contains(where: { $0.id == current }) { return current }
        if let lastUsed, !lastUsed.isArchived, lastUsed.kind == kind { return lastUsed.id }
        return active
            .filter { $0.parent == nil }
            .min { $0.sortOrder < $1.sortOrder }?
            .id
    }

    /// 归档;归档一级分类时,二级分类一并归档。
    public static func archive(_ category: LedgerCategory) {
        category.isArchived = true
        for child in category.children {
            child.isArchived = true
        }
    }
}
