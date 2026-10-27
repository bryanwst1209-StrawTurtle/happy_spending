import Testing
import Foundation
@testable import HappySpendingCore

struct BackupFilesTests {
    private let at = makeDate(2026, 10, 27, 9, 5) + 7

    @Test func fileNamesFollowTheAgreedFormats() {
        #expect(BackupFiles.autoName(for: at, calendar: testCalendar) == "HappySpending 备份 2026-10-27.json")
        #expect(BackupFiles.manualName(at: at, calendar: testCalendar) == "HappySpending 备份 2026-10-27 090507.json")
        #expect(BackupFiles.preRestoreName(at: at, calendar: testCalendar) == "HappySpending 恢复前备份 2026-10-27 090507.json")
    }

    @Test func rotationOnlyDeletesOldAutoBackups() {
        let autos = (19...27).map { "HappySpending 备份 2026-10-\($0).json" }
        let others = [
            "HappySpending 恢复前备份 2026-10-01 120000.json",
            "HappySpending 备份 2026-10-01 120000.json",
            "我的笔记.txt",
        ]

        let deleted = BackupFiles.autoBackupsToDelete((autos + others).shuffled())

        #expect(Set(deleted) == ["HappySpending 备份 2026-10-19.json", "HappySpending 备份 2026-10-20.json"])
    }

    @Test func nothingIsDeletedWithSevenOrFewer() {
        let autos = (21...27).map { "HappySpending 备份 2026-10-\($0).json" }
        #expect(BackupFiles.autoBackupsToDelete(autos).isEmpty)
    }

    @Test func autoBackupRunsOncePerLocalDay() {
        let now = makeDate(2026, 10, 27, 9, 0)
        #expect(BackupFiles.needsAutoBackup(lastAutoBackup: nil, now: now, calendar: testCalendar))
        #expect(!BackupFiles.needsAutoBackup(lastAutoBackup: makeDate(2026, 10, 27, 0, 1), now: now, calendar: testCalendar))
        #expect(BackupFiles.needsAutoBackup(lastAutoBackup: makeDate(2026, 10, 26, 23, 59), now: now, calendar: testCalendar))
    }

    @Test func theReminderAppearsOnlyWhenBackupsAreNeglected() {
        let now = makeDate(2026, 10, 27)
        let recent = makeDate(2026, 10, 1)
        let longAgo = makeDate(2026, 9, 1)

        #expect(!BackupFiles.needsReminder(autoBackupOn: true, lastExport: nil, hasEntries: true, now: now))
        #expect(!BackupFiles.needsReminder(autoBackupOn: false, lastExport: recent, hasEntries: true, now: now))
        #expect(BackupFiles.needsReminder(autoBackupOn: false, lastExport: longAgo, hasEntries: true, now: now))
        #expect(BackupFiles.needsReminder(autoBackupOn: false, lastExport: nil, hasEntries: true, now: now))
        #expect(!BackupFiles.needsReminder(autoBackupOn: false, lastExport: nil, hasEntries: false, now: now))
    }

    /// 系统日历选了日本历、佛历时,文件名仍按公历写,轮换才不会把最新的当成最旧的删掉。
    @Test func fileNamesAlwaysUseGregorianYears() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = testCalendar.timeZone
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = testCalendar.timeZone
        for calendar in [japanese, buddhist] {
            #expect(BackupFiles.autoName(for: at, calendar: calendar) == "HappySpending 备份 2026-10-27.json")
            #expect(BackupFiles.manualName(at: at, calendar: calendar) == "HappySpending 备份 2026-10-27 090507.json")
        }
    }

    /// 本地的恢复前备份保留最近 3 份;只认恢复前备份,别的文件不动。
    @Test func onlyTheThreeNewestPreRestoreBackupsAreKept() {
        let pre = (21...25).map { "HappySpending 恢复前备份 2026-10-\($0) 120000.json" }
        let others = ["HappySpending 备份 2026-10-01.json", "说明.txt"]

        let deleted = BackupFiles.preRestoreBackupsToDelete((pre + others).shuffled())

        #expect(Set(deleted) == ["HappySpending 恢复前备份 2026-10-21 120000.json", "HappySpending 恢复前备份 2026-10-22 120000.json"])
    }

    /// 开着自动备份、但一直失败(文件夹失效、网盘断开)超过 3 天,也要提醒。
    @Test func aFailingAutoBackupIsRemindedAfterThreeDays() {
        let now = makeDate(2026, 10, 27)
        func remind(lastAuto: Date?, failing: Bool) -> Bool {
            BackupFiles.needsReminder(
                autoBackupOn: true, lastExport: nil, hasEntries: true, now: now,
                lastAutoBackup: lastAuto, autoBackupFailing: failing
            )
        }
        #expect(!remind(lastAuto: makeDate(2026, 10, 20), failing: false))
        #expect(!remind(lastAuto: makeDate(2026, 10, 25), failing: true))
        #expect(remind(lastAuto: makeDate(2026, 10, 20), failing: true))
        #expect(remind(lastAuto: nil, failing: true))
    }
}
