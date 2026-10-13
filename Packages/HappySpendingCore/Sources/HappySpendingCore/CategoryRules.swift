import Foundation
import SwiftData

public enum CategoryError: Error, Equatable {
    case parentMustBeTopLevel
    case parentArchived
}

public enum CategoryNameError: Error, Equatable {
    case empty
    case tooLong
    case duplicate

    public var message: String {
        switch self {
        case .empty: "名称不能为空"
        case .tooLong: "名称最多 \(CategoryRules.maxNameLength) 个字"
        case .duplicate: "已有同名分类(可能在已归档里)"
        }
    }
}

public enum CategoryRules {
    public static let maxNameLength = 10

    // MARK: 预置分类和测试使用的直接创建(不校验名称)

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

    // MARK: 名称校验

    /// 去掉首尾空白后校验名称并返回。`siblings` 是同一个父分类下的所有分类
    /// (一级分类则是同类型的所有一级分类),包括已归档的;`excluding` 是正在被改名的分类自己。
    public static func validatedName(
        _ raw: String,
        among siblings: [LedgerCategory],
        excluding: LedgerCategory? = nil
    ) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CategoryNameError.empty }
        guard name.count <= maxNameLength else { throw CategoryNameError.tooLong }
        let isDuplicate = siblings.contains { sibling in
            sibling !== excluding
                && sibling.name.compare(name, options: [.caseInsensitive]) == .orderedSame
        }
        guard !isDuplicate else { throw CategoryNameError.duplicate }
        return name
    }

    private static func siblings(
        of parent: LedgerCategory?,
        kind: EntryKind,
        in categories: [LedgerCategory]
    ) -> [LedgerCategory] {
        if let parent { return parent.children }
        return categories.filter { $0.parent == nil && $0.kind == kind }
    }

    // MARK: 管理界面使用

    /// 新增一级分类:图标用默认 SF Symbol,颜色从调色板按顺序取,排在同类型的最后。
    @discardableResult
    public static func createTopLevel(
        name: String,
        kind: EntryKind,
        among categories: [LedgerCategory],
        in context: ModelContext
    ) throws -> LedgerCategory {
        let existing = siblings(of: nil, kind: kind, in: categories)
        let validated = try validatedName(name, among: existing)
        let category = LedgerCategory(
            name: validated, symbolName: "tag.fill",
            colorHex: CategoryPalette.color(at: existing.count),
            kind: kind, sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(category)
        return category
    }

    /// 新增二级分类:继承一级分类的类型和颜色,排在它所有二级分类的最后。
    @discardableResult
    public static func createSubcategory(
        name: String,
        under parent: LedgerCategory,
        in context: ModelContext
    ) throws -> LedgerCategory {
        guard parent.parent == nil else { throw CategoryError.parentMustBeTopLevel }
        let validated = try validatedName(name, among: parent.children)
        let category = LedgerCategory(
            name: validated, symbolName: "tag.fill", colorHex: parent.colorHex,
            kind: parent.kind,
            sortOrder: (parent.children.map(\.sortOrder).max() ?? -1) + 1,
            parent: parent
        )
        context.insert(category)
        return category
    }

    /// 改名;名称不合法时抛错,原名称保持不变。
    public static func rename(
        _ category: LedgerCategory,
        to raw: String,
        among categories: [LedgerCategory]
    ) throws {
        let existing = siblings(of: category.parent, kind: category.kind, in: categories)
        category.name = try validatedName(raw, among: existing, excluding: category)
    }

    // MARK: 归档与恢复

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

    /// 恢复;恢复一级分类时二级分类一并恢复;父分类已归档的二级分类不能单独恢复。
    public static func restore(_ category: LedgerCategory) throws {
        if let parent = category.parent {
            guard !parent.isArchived else { throw CategoryError.parentArchived }
            category.isArchived = false
        } else {
            category.isArchived = false
            for child in category.children {
                child.isArchived = false
            }
        }
    }
}
