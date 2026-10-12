import Foundation
import SwiftData

public enum DefaultCategories {
    private struct Spec {
        let name: String
        let symbol: String
        let color: String
        let children: [String]
    }

    private static let expense: [Spec] = [
        Spec(name: "餐饮", symbol: "fork.knife", color: "#FF9F0A", children: ["早餐", "午餐", "晚餐", "零食"]),
        Spec(name: "交通", symbol: "car.fill", color: "#0A84FF", children: ["公交地铁", "打车", "加油"]),
        Spec(name: "购物", symbol: "bag.fill", color: "#FF375F", children: ["日用", "服饰", "数码"]),
        Spec(name: "居住", symbol: "house.fill", color: "#30B0C7", children: ["房租", "水电燃气", "网费"]),
        Spec(name: "娱乐", symbol: "gamecontroller.fill", color: "#BF5AF2", children: ["电影", "游戏", "旅行"]),
        Spec(name: "医疗", symbol: "cross.case.fill", color: "#FF453A", children: ["药品", "诊疗"]),
        Spec(name: "其他", symbol: "ellipsis.circle.fill", color: "#8E8E93", children: []),
    ]

    private static let income: [Spec] = [
        Spec(name: "工资", symbol: "banknote.fill", color: "#30D158", children: []),
        Spec(name: "奖金", symbol: "gift.fill", color: "#FFD60A", children: []),
        Spec(name: "其他收入", symbol: "plus.circle.fill", color: "#64D2FF", children: []),
    ]

    /// 只在库里还没有任何分类时写入预置分类。返回是否写入了数据。
    @discardableResult
    public static func seedIfNeeded(in context: ModelContext) throws -> Bool {
        guard try context.fetchCount(FetchDescriptor<LedgerCategory>()) == 0 else { return false }

        let groups: [(EntryKind, [Spec])] = [(.expense, expense), (.income, income)]
        for (kind, specs) in groups {
            for (index, spec) in specs.enumerated() {
                let top = CategoryRules.addTopLevel(
                    name: spec.name, symbolName: spec.symbol, colorHex: spec.color,
                    kind: kind, sortOrder: index, in: context
                )
                for child in spec.children {
                    try CategoryRules.addSubcategory(name: child, under: top, in: context)
                }
            }
        }
        try context.save()
        return true
    }
}
