import Testing
import SwiftData
@testable import HappySpendingCore

@MainActor
struct DefaultCategoriesTests {
    /// 必须一直持有容器:容器一释放,里面的分类对象就会失效。
    private struct Seeded {
        let container: ModelContainer
        let all: [LedgerCategory]
    }

    private func seeded() throws -> Seeded {
        let container = try makeTestContainer()
        try DefaultCategories.seedIfNeeded(in: container.mainContext)
        let all = try container.mainContext.fetch(FetchDescriptor<LedgerCategory>())
        return Seeded(container: container, all: all)
    }

    private func tops(_ categories: [LedgerCategory], _ kind: EntryKind) -> [LedgerCategory] {
        categories.filter { $0.parent == nil && $0.kind == kind }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func childNames(of top: LedgerCategory) -> [String] {
        top.children.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
    }

    @Test func expenseTopLevelsAreTheAuthorsOnesFirstThenTheGenericOnes() throws {
        let store = try seeded()
        #expect(tops(store.all, .expense).map(\.name) == [
            "日用", "餐饮", "交通", "宠物", "娱乐", "游戏", "旅游", "汽车", "其他", "服饰",
            "购物", "居住", "医疗",
        ])
    }

    @Test func incomeCategoriesAreUnchanged() throws {
        let store = try seeded()
        #expect(tops(store.all, .income).map(\.name) == ["工资", "奖金", "其他收入"])
        #expect(store.all.filter { $0.kind == .income && $0.parent != nil }.isEmpty)
    }

    @Test func subcategoriesMatchTheSpec() throws {
        let store = try seeded()
        let byName = Dictionary(uniqueKeysWithValues: tops(store.all, .expense).map { ($0.name, $0) })

        #expect(childNames(of: byName["游戏"]!) == ["原神", "ZZZ", "steam", "暴雪"])
        #expect(childNames(of: byName["娱乐"]!) == ["电影"])
        #expect(childNames(of: byName["汽车"]!) == ["停车费", "加油"])
        #expect(childNames(of: byName["餐饮"]!) == ["早餐", "午餐", "晚餐", "零食"])
        #expect(childNames(of: byName["交通"]!) == ["公交地铁", "打车"])
        #expect(childNames(of: byName["购物"]!) == ["数码"])
        #expect(childNames(of: byName["居住"]!) == ["房租", "水电燃气", "网费"])
        #expect(childNames(of: byName["医疗"]!) == ["药品", "诊疗"])
        for name in ["日用", "宠物", "旅游", "其他", "服饰"] {
            #expect(childNames(of: byName[name]!).isEmpty)
        }
    }

    @Test func noSiblingsShareAName() throws {
        let store = try seeded()
        var seen = Set<String>()
        for category in store.all {
            let key = "\(category.kind.rawValue)|\(category.parent?.name ?? "-")|\(category.name)"
            #expect(seen.insert(key).inserted, "重复的分类:\(key)")
        }
    }

    @Test func seededCategoriesRespectTheTwoLevelRule() throws {
        let store = try seeded()
        let subs = store.all.filter { $0.parent != nil }
        #expect(!subs.isEmpty)
        #expect(subs.allSatisfy { $0.parent?.parent == nil })
        #expect(subs.allSatisfy { $0.kind == $0.parent?.kind })
        #expect(store.all.allSatisfy { !$0.name.isEmpty && !$0.isArchived })
    }

    @Test func subcategoriesInheritTheirParentsColor() throws {
        let store = try seeded()
        #expect(store.all.filter { $0.parent != nil }.allSatisfy { $0.colorHex == $0.parent?.colorHex })
    }

    @Test func sortOrdersAreUniqueAmongSiblings() throws {
        let store = try seeded()
        for kind in EntryKind.allCases {
            let orders = tops(store.all, kind).map(\.sortOrder)
            #expect(Set(orders).count == orders.count)
        }
    }
}
