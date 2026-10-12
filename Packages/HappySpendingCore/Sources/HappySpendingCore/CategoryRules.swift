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

    /// 归档;归档一级分类时,二级分类一并归档。
    public static func archive(_ category: LedgerCategory) {
        category.isArchived = true
        for child in category.children {
            child.isArchived = true
        }
    }
}
