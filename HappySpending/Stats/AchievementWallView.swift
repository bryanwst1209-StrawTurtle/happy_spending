import SwiftUI
import SwiftData
import HappySpendingCore

/// 徽章墙:按类别分组,已解锁彩色、未解锁灰色带进度;点开看条件。
struct AchievementWallView: View {
    @Environment(\.modelContext) private var context
    @Environment(AchievementCenter.self) private var center
    @Environment(BackupService.self) private var backup
    @Query private var unlocks: [AchievementUnlock]

    @State private var facts = AchievementFacts()
    @State private var detail: Achievement?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var unlockedAt: [String: Date] {
        Dictionary(unlocks.map { ($0.id, $0.unlockedAt) }, uniquingKeysWith: min)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Achievement.Category.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category.title).font(.headline)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Achievement.allCases.filter { $0.category == category }) { badge in
                                Button { detail = badge } label: { tile(badge) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background { AppBackground() }
        .navigationTitle("成就")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let backedUp = backup.lastExport != nil || backup.lastAutoBackup != nil
            facts = (try? Achievements.gather(from: context, hasBackedUp: backedUp, now: .now)) ?? AchievementFacts()
            center.markSeen()
        }
        .sheet(item: $detail) { badge in
            VStack(spacing: 14) {
                icon(badge, unlocked: unlockedAt[badge.rawValue] != nil, size: 72)
                Text(badge.name).font(.title2.weight(.semibold))
                Text(badge.condition).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text(statusText(badge)).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .presentationDetents([.height(300)])
        }
    }

    private func tile(_ badge: Achievement) -> some View {
        let date = unlockedAt[badge.rawValue]
        return VStack(spacing: 6) {
            icon(badge, unlocked: date != nil, size: 56)
            Text(badge.name).font(.subheadline.weight(.medium)).foregroundStyle(date == nil ? .secondary : .primary)
            Text(statusText(badge))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func icon(_ badge: Achievement, unlocked: Bool, size: CGFloat) -> some View {
        Image(systemName: badge.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(unlocked ? .white : .secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(unlocked ? color(badge.category).gradient : Color.secondary.opacity(0.15).gradient))
    }

    private func statusText(_ badge: Achievement) -> String {
        if let date = unlockedAt[badge.rawValue] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日解锁"
            return formatter.string(from: date)
        }
        return Achievements.progress(badge, facts)
    }

    private func color(_ category: Achievement.Category) -> Color {
        switch category {
        case .start: .orange
        case .tidy: .teal
        case .streak: .red
        case .habit: .green
        case .milestone: .purple
        }
    }
}
