import SwiftUI
import HappySpendingCore

struct CategoryDetailView: View {
    let share: CategoryShare

    var body: some View {
        List {
            Section {
                HStack {
                    Text("合计")
                    Spacer()
                    Text(Money.display(share.cents)).monospacedDigit()
                }
            }
            Section("二级分类") {
                ForEach(share.children) { child in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(child.name)
                            Spacer()
                            Text(Money.display(child.cents)).monospacedDigit()
                        }
                        ProgressView(value: child.fraction)
                            .tint(Color(hex: share.colorHex))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(share.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
