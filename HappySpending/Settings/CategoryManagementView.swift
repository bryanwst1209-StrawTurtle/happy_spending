import SwiftUI
import SwiftData
import HappySpendingCore

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var kind: EntryKind = .expense
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var errorMessage: String?

    private var inKind: [LedgerCategory] { categories.filter { $0.kind == kind } }
    private var tops: [LedgerCategory] { inKind.filter { $0.parent == nil && !$0.isArchived } }
    /// 已归档:一级分类,以及父分类仍在使用中的二级分类(父分类已归档的随父分类一起恢复)。
    private var archived: [LedgerCategory] {
        inKind.filter { $0.isArchived && ($0.parent == nil || $0.parent?.isArchived == false) }
    }

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $kind) {
                    ForEach(EntryKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(tops, id: \.id) { top in
                    NavigationLink(value: top) { row(top) }
                    ForEach(activeChildren(of: top), id: \.id) { child in
                        NavigationLink(value: child) { row(child) }
                            .padding(.leading, 28)
                    }
                }
            } footer: {
                if tops.isEmpty { Text("还没有分类,点右上角的 + 新增。") }
            }

            if !archived.isEmpty {
                Section("已归档") {
                    ForEach(archived, id: \.id) { category in
                        HStack {
                            row(category)
                            Spacer()
                            Button("恢复") { restore(category) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("分类管理")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: LedgerCategory.self) { CategoryEditView(category: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("新增一级分类", isPresented: $showingAdd) {
            TextField("分类名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("添加", action: addTopLevel)
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ category: LedgerCategory) -> some View {
        HStack(spacing: 12) {
            CategoryIconView(
                symbolName: category.symbolName, colorHex: category.colorHex,
                iconData: category.iconData, size: 34
            )
            Text(category.name)
        }
    }

    private func activeChildren(of top: LedgerCategory) -> [LedgerCategory] {
        top.children.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func addTopLevel() {
        do {
            try CategoryRules.createTopLevel(name: newName, kind: kind, among: categories, in: context)
            try context.save()
        } catch let error as CategoryNameError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ category: LedgerCategory) {
        do {
            try CategoryRules.restore(category)
            try context.save()
        } catch CategoryError.parentArchived {
            errorMessage = "请先恢复它的一级分类"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
