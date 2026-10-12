import Foundation

public enum EntryDate {
    /// 记账页的默认日期:没被用户明确选过、并且已经不是今天时,换成现在;否则保持不变。
    /// 用来处理 app 被挂起过夜后,第二天早上默认日期还停在昨天的情况。
    public static func refreshedDefault(
        current: Date,
        isUserChosen: Bool,
        now: Date,
        calendar: Calendar
    ) -> Date {
        guard !isUserChosen, !calendar.isDate(current, inSameDayAs: now) else { return current }
        return now
    }
}
