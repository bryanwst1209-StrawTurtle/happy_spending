import SwiftUI
import SwiftData
import PhotosUI
import HappySpendingCore

struct CategoryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [LedgerCategory]
    @Bindable var category: LedgerCategory

    @State private var draftName: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingAddSub = false
    @State private var newSubName = ""
    @State private var errorMessage: String?

    init(category: LedgerCategory) {
        self.category = category
        _draftName = State(initialValue: category.name)
    }

    private var activeChildren: [LedgerCategory] {
        category.children.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    CategoryIconView(
                        symbolName: category.symbolName, colorHex: category.colorHex,
                        iconData: category.iconData, size: 56
                    )
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text("上传图标")
                    }
                }
                if category.iconData != nil {
                    Button("还原默认图标", role: .destructive) {
                        category.iconData = nil
                        save()
                    }
                }
            } footer: {
                Text("图标会被裁成正方形并缩小到 128×128 像素,原图不能超过 10 MB。")
            }

            Section("名称") {
                TextField("名称", text: $draftName)
                    .onSubmit(rename)
                Button("保存名称", action: rename)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines) == category.name)
            }

            if category.parent == nil {
                Section("二级分类") {
                    ForEach(activeChildren, id: \.id) { child in
                        NavigationLink {
                            CategoryEditView(category: child)
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIconView(
                                    symbolName: child.symbolName, colorHex: child.colorHex,
                                    iconData: child.iconData, size: 30
                                )
                                Text(child.name)
                            }
                        }
                    }
                    Button("新增二级分类") {
                        newSubName = ""
                        showingAddSub = true
                    }
                }
            }

            Section {
                Button("归档这个分类", role: .destructive, action: archive)
            } footer: {
                Text("归档后不再出现在记账页,已有账单保持不变,可以在分类管理里恢复。")
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { Task { await loadIcon() } }
        .alert("新增二级分类", isPresented: $showingAddSub) {
            TextField("分类名称", text: $newSubName)
            Button("取消", role: .cancel) {}
            Button("添加", action: addSubcategory)
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

    private func loadIcon() async {
        guard let item = pickerItem else { return }
        defer { pickerItem = nil }
        let processed: Data
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CategoryIconError.unreadable
            }
            processed = try CategoryIcon.process(data)
        } catch let error as CategoryIconError {
            errorMessage = error.message
            return
        } catch {
            errorMessage = CategoryIconError.unreadable.message
            return
        }
        category.iconData = processed
        save()
    }

    private func rename() {
        do {
            try CategoryRules.rename(category, to: draftName, among: categories)
            draftName = category.name
            try context.save()
        } catch let error as CategoryNameError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSubcategory() {
        do {
            try CategoryRules.createSubcategory(name: newSubName, under: category, in: context)
            try context.save()
        } catch let error as CategoryNameError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive() {
        CategoryRules.archive(category)
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
