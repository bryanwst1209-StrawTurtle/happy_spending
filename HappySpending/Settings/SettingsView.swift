import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CategoryManagementView()
                    } label: {
                        Label("分类管理", systemImage: "square.grid.2x2")
                    }
                    .appRowBackground()
                    NavigationLink {
                        AutoRecordHelpView()
                    } label: {
                        Label("自动入账", systemImage: "wand.and.stars")
                    }
                    .appRowBackground()
                }
                AppearanceSection()
                BackupSection()
            }
            .appListBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
