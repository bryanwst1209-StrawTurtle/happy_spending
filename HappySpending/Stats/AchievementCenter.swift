import SwiftUI
import SwiftData
import HappySpendingCore

/// 成就的检查时机、解锁提示和"看过"红点。
@MainActor
@Observable
final class AchievementCenter {
    private static let seenKey = "achievementsSeenAt"

    /// 顶部的小提示;约 3 秒后自动消失。
    private(set) var toast: String?
    /// 点提示时切到统计页并打开徽章墙。
    var showWall = false
    /// 上次看徽章墙的时间,之后解锁的徽章带红点。
    private(set) var seenAt: Date

    init() {
        seenAt = UserDefaults.standard.object(forKey: Self.seenKey) as? Date ?? .distantPast
    }

    /// 打开 app / 回到前台:先记下今天打开过,再检查。
    func appeared(context: ModelContext, backup: BackupService, now: Date = .now) {
        try? Achievements.recordOpen(in: context, now: now)
        check(context: context, backup: backup, now: now)
    }

    /// 检查并在有新解锁时弹提示;返回这次是否有新解锁。
    @discardableResult
    func check(context: ModelContext, backup: BackupService, now: Date = .now) -> Bool {
        let backedUp = backup.lastExport != nil || backup.lastAutoBackup != nil
        guard let new = try? Achievements.check(in: context, hasBackedUp: backedUp, now: now), !new.isEmpty else { return false }
        let text = new.count == 1 ? "🏆 解锁:\(new[0].name)" : "🏆 解锁了 \(new.count) 个徽章"
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if toast == text { toast = nil } }
        }
        return true
    }

    func dismissToast() {
        withAnimation { toast = nil }
    }

    func markSeen(now: Date = .now) {
        seenAt = now
        UserDefaults.standard.set(now, forKey: Self.seenKey)
    }
}
