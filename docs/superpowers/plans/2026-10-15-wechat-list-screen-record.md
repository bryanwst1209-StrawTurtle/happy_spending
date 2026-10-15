# 微信支付消息列表屏幕识别记账 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在微信"微信支付"消息列表上按一下,把这一屏所有完整的支付卡片记成支出;微信的去重改为"金额 + 精确到分钟的时间",让列表页和详情页互相认得出同一笔。

**Architecture:** 新增三个 Core 单元——`WeChatPaymentKey`(去重标识)、`TimeLabel`(列表里的相对时间标签换算)、`WeChatListParser`(把列表文字切成卡片)。`PaymentCapture.recordScreenText` 先交给列表解析器,不是列表页再走原来的 `ScreenTextParser`。微信账单详情页改用同一个去重标识。app 层只改帮助页文字和动作描述。

**Tech Stack:** Swift 6、SwiftData、Swift Testing、App Intents;本地包 `Packages/HappySpendingCore`,工程由 XcodeGen 生成。

**Spec:** `docs/superpowers/specs/2026-10-15-wechat-list-screen-record-design.md`(上位:`docs/superpowers/specs/2026-10-15-screen-and-notification-auto-record-design.md`)

## Global Constraints

- 最低系统 iOS 26;不引入任何第三方依赖。
- 业务逻辑放在 `Packages/HappySpendingCore`,用 Swift Testing 测;app 层保持很薄。
- 测试夹具取自真实样本,单号、卡号尾号、商户名换成假值,版式和噪音原样保留。
- 面向用户的文字一字不差地用下面这些(逗号是半角 `,`):
  - `已记过这一笔`
  - `已记 2 笔,共 ¥136.70`
  - `已记 1 笔 ¥81.00,1 笔已记过`
  - `已记 2 笔,共 ¥136.70,1 笔已记过`
  - `这一屏的 2 笔都记过了`
  - `这一屏没有完整的支付记录`
- 微信去重标识格式:`微信|<金额分>|<yyyy-MM-dd HH:mm>`,作为 `PaymentRecord.orderRef` 传入。数据模型不变。
- 支付宝的解析和去重不变。
- 提交信息用英文,结尾带一行 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 测试命令(仓库根目录):`swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`。开始前是 275 个测试全部通过。

## Review Focus

spec 没明说、但最容易让使用者踩坑的输入,每条都在对应任务里有测试:

1. **任何一个"星期X"标签都必须认得出**:认不出时它下面的卡片会沿用上一个标签的时间,悄悄记错日期。→ Task 2 `everyWeekdayResolvesToExactlyOneDayTwoToEightDaysBack`
2. **长得像时间但不合法的行**(`25:00`、`2月30日 12:00`、`13:00 支付`)不能当成时间标签。→ Task 2 `linesThatAreNotWholeValidLabelsAreRejected`
3. **卡片之间的残余行**(自动续费卡片收尾后的"微信代扣""进入商家小程序")不能被当成下一张卡的商户,也不能让下一张卡丢掉时间。→ Task 3 `leftoverLinesBetweenCardsDoNotLeakIntoTheNextCard`
4. **金额为 0 或超上限的卡片**跳过,不崩溃、不影响同屏其他卡片。→ Task 3 `aCardWithAnInvalidAmountIsSkippedAndTheRestAreKept`
5. **"微信支付"标题之上的内容**(状态栏的 `16:40`)不能给顶部截断的卡片提供时间。→ Task 3 `contentAboveTheTitleCannotSupplyATime`

---

### Task 1: 微信去重标识,详情页改用它,重复提示改文案

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/WeChatPaymentKey.swift`
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/ScreenTextParser.swift`(`parseWeChatBill`)
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/AutoEntryRecorder.swift`(重复提示)
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/LedgerEntry.swift`(`orderRefHash` 的注释)
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/WeChatPaymentKeyTests.swift`(新建)
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/ScreenTextParserTests.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentRecorderTests.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentCaptureTests.swift`

**Interfaces:**
- Consumes: 已有的 `PaymentRecord`、`AutoEntryRecorder.record(_:now:calendar:in:)`、测试里的 `testCalendar`、`makeDate`。
- Produces: `public enum WeChatPaymentKey { public static func make(cents: Int, time: Date, calendar: Calendar) -> String }`,返回如 `微信|14770|2026-10-14 18:23`。重复时 `AutoEntryResult.message == "已记过这一笔"`。

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/WeChatPaymentKeyTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct WeChatPaymentKeyTests {
    private func time(_ h: Int, _ m: Int, _ s: Int) -> Date {
        testCalendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: h, minute: m, second: s))!
    }

    @Test func theKeyIsChannelAmountAndMinute() {
        #expect(WeChatPaymentKey.make(cents: 14770, time: time(18, 23, 27), calendar: testCalendar)
                == "微信|14770|2026-10-14 18:23")
    }

    @Test func secondsAreDropped() {
        let early = WeChatPaymentKey.make(cents: 20, time: time(9, 5, 0), calendar: testCalendar)
        let late = WeChatPaymentKey.make(cents: 20, time: time(9, 5, 59), calendar: testCalendar)
        #expect(early == "微信|20|2026-10-14 09:05")
        #expect(late == early)
    }
}
```

在 `ScreenTextParserTests.swift` 里:

把 `parsesTheWeChatMerchantBillPage` 里的这一行

```swift
        #expect(record.orderRef == "4000000000000000000000000000")
```

改成

```swift
        // 时间读出来了:用"金额 + 分钟"作去重标识,和消息列表上的同一笔对得上。
        #expect(record.orderRef == "微信|14770|2026-10-14 18:23")
```

把 `aCleanWeChatDateIsParsed` 整个换成

```swift
    @Test func aCleanWeChatDateIsParsed() throws {
        let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026-10-14 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == date(2026, 10, 14, 17, 37, 40))
        #expect(record.orderRef == "微信|20|2026-10-14 17:37")
    }
```

(`parsesTheWeChatBillPage` 里的 `#expect(record.orderRef == "10000000000000000000000000000000")` **保持不变**:那份样本日期是乱码,要退回单号。)

在 `PaymentRecorderTests.swift` 的 `theSameOrderNumberIsRecordedOnlyOnce` 里,把

```swift
        #expect(second.message == "已记过这一笔(单号相同)")
```

改成

```swift
        #expect(second.message == "已记过这一笔")
```

在 `PaymentCaptureTests.swift` 的 `triggeringTheSameBillTwiceRecordsItOnce` 里做同样的替换。

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'WeChatPaymentKey' in scope`。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/WeChatPaymentKey.swift`:

```swift
import Foundation

/// 微信支付的去重标识:金额 + 精确到分钟的时间。
/// 消息列表和账单详情页都拿得到这两样,同一笔在两处记过都能认出来;
/// 商户不放进来,因为列表页可能认不出商户(样本里瑞幸的商户行没被识别)。
public enum WeChatPaymentKey {
    public static func make(cents: Int, time: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        let stamp = String(
            format: "%04d-%02d-%02d %02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0
        )
        return "微信|\(cents)|\(stamp)"
    }
}
```

在 `ScreenTextParser.swift` 的 `parseWeChatBill` 里,把

```swift
        return .payment(PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "微信",
            eventDate: dateTime(afterAnyLabel: ["转账时间", "支付时间"], in: lines, calendar: calendar),
            orderRef: digits(afterAnyLabel: ["转账单号", "交易单号"], in: lines)
        ))
```

换成

```swift
        // 去重:时间读出来了就用"金额 + 分钟",和消息列表上的同一笔对得上;读不出来退回单号。
        let eventDate = dateTime(afterAnyLabel: ["转账时间", "支付时间"], in: lines, calendar: calendar)
        let orderRef = eventDate.map { WeChatPaymentKey.make(cents: cents, time: $0, calendar: calendar) }
            ?? digits(afterAnyLabel: ["转账单号", "交易单号"], in: lines)

        return .payment(PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "微信",
            eventDate: eventDate,
            orderRef: orderRef
        ))
```

在 `AutoEntryRecorder.swift` 里:
- 把 `message: "已记过这一笔(单号相同)",` 改成 `message: "已记过这一笔",`。
- 把注释 `/// 单号相同,没有新建。` 改成 `/// 去重标识相同(单号,或微信的金额 + 分钟),没有新建。`。
- 把注释 `/// 单号相同就跳过;分类依次取商户记忆、平台分类映射,都没有就是"未分类"。` 改成 `/// 去重标识相同就跳过;分类依次取商户记忆、平台分类映射,都没有就是"未分类"。`。

在 `LedgerEntry.swift` 里,把 `/// 单号的 SHA-256 哈希,只用于"单号相同就跳过";没有单号就是 nil。` 改成 `/// 去重标识(单号,或微信的"金额 + 分钟")的 SHA-256 哈希,只用于跳过重复;没有就是 nil。`。

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 277 tests in 26 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: dedupe WeChat payments by amount and minute

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 消息列表的时间标签

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/TimeLabel.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/TimeLabelTests.swift`(新建)

**Interfaces:**
- Consumes: 已有的 `TextMatch.captures(_:in:)`(internal,返回各捕获组,下标 0 是整段匹配)。
- Produces: `enum TimeLabel { static func resolve(_ line: String, now: Date, calendar: Calendar) -> Date? }`(internal)。整行是时间标签时返回精确到分钟的时间(秒为 0),否则 nil。

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/TimeLabelTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct TimeLabelTests {
    /// 2026-10-15 是星期四。
    private let now = makeDate(2026, 10, 15, 16, 40)

    private func resolve(_ line: String, now: Date? = nil) -> Date? {
        TimeLabel.resolve(line, now: now ?? self.now, calendar: testCalendar)
    }

    @Test func aBareTimeIsToday() {
        #expect(resolve("13:00") == makeDate(2026, 10, 15, 13, 0))
        #expect(resolve(" 9:05 ") == makeDate(2026, 10, 15, 9, 5))
    }

    @Test func yesterdayWithOrWithoutASpace() {
        #expect(resolve("昨天 18:23") == makeDate(2026, 10, 14, 18, 23))
        #expect(resolve("昨天18:23") == makeDate(2026, 10, 14, 18, 23))
    }

    @Test func aWeekdayIsTheMostRecentOneAtLeastTwoDaysBack() {
        #expect(resolve("星期六 11:01") == makeDate(2026, 10, 10, 11, 1))
        #expect(resolve("星期六11:01") == makeDate(2026, 10, 10, 11, 1))
    }

    /// 今天星期四、昨天星期三:"星期四"是 7 天前,"星期三"是 8 天前,都不能落到今天或昨天,也不能认不出。
    @Test func everyWeekdayResolvesToExactlyOneDayTwoToEightDaysBack() throws {
        let expected: [String: Int] = [
            "二": 13, "一": 12, "日": 11, "天": 11, "六": 10, "五": 9, "四": 8, "三": 7,
        ]
        for (name, day) in expected {
            let date = try #require(resolve("星期\(name) 08:00"), "星期\(name)")
            #expect(date == makeDate(2026, 10, day, 8, 0), "星期\(name)")
        }
    }

    @Test func aMonthAndDayIsThisYear() {
        #expect(resolve("10月8日 18:23") == makeDate(2026, 10, 8, 18, 23))
    }

    @Test func aMonthAndDayLaterThanNowIsLastYear() {
        let january = makeDate(2026, 1, 2, 9, 0)
        #expect(resolve("12月30日 18:23", now: january) == makeDate(2025, 12, 30, 18, 23))
    }

    @Test func aFullDateIsTakenAsWritten() {
        #expect(resolve("2025年10月8日 18:23") == makeDate(2025, 10, 8, 18, 23))
    }

    @Test func linesThatAreNotWholeValidLabelsAreRejected() {
        for line in ["25:00", "12:60", "昨天 24:10", "2月30日 12:00", "2026年13月1日 12:00",
                     "13:00 支付", "16:40 \\", "星期八 10:00", "·13.00", "", "账单详情＞"] {
            #expect(resolve(line) == nil, "\(line)")
        }
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'TimeLabel' in scope`。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/TimeLabel.swift`:

```swift
import Foundation

/// 微信消息列表里的时间标签:`13:00`、`昨天 18:23`、`星期六 11:01`、`10月8日 18:23`、`2025年10月8日 18:23`。
enum TimeLabel {
    private static let weekdays: [String: Int] = [
        "日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7,
    ]

    /// 整行是时间标签时,按 `now` 换算成具体时间(精确到分钟);不是就返回 nil。
    static func resolve(_ line: String, now: Date, calendar: Calendar) -> Date? {
        let text = line.trimmingCharacters(in: .whitespaces)
        let today = calendar.startOfDay(for: now)

        if let g = TextMatch.captures("^(\\d{1,2}):(\\d{2})$", in: text) {
            return at(today, g[1], g[2], calendar)
        }
        if let g = TextMatch.captures("^昨天\\s*(\\d{1,2}):(\\d{2})$", in: text) {
            return calendar.date(byAdding: .day, value: -1, to: today).flatMap { at($0, g[1], g[2], calendar) }
        }
        if let g = TextMatch.captures("^星期([一二三四五六日天])\\s*(\\d{1,2}):(\\d{2})$", in: text),
           let weekday = weekdays[g[1]] {
            // 今天显示成时间、昨天显示成"昨天",所以"星期X"是往前 2 到 8 天里的那一天(每个星期X 恰好一次)。
            for back in 2...8 {
                guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
                if calendar.component(.weekday, from: day) == weekday {
                    return at(day, g[2], g[3], calendar)
                }
            }
            return nil
        }
        if let g = TextMatch.captures("^(\\d{4})年(\\d{1,2})月(\\d{1,2})日\\s*(\\d{1,2}):(\\d{2})$", in: text),
           let year = Int(g[1]) {
            return date(year: year, month: g[2], day: g[3], calendar).flatMap { at($0, g[4], g[5], calendar) }
        }
        if let g = TextMatch.captures("^(\\d{1,2})月(\\d{1,2})日\\s*(\\d{1,2}):(\\d{2})$", in: text) {
            // 没写年份就是今年;比现在还晚,说明是去年的。
            let year = calendar.component(.year, from: now)
            guard let thisYear = date(year: year, month: g[1], day: g[2], calendar)
                .flatMap({ at($0, g[3], g[4], calendar) })
            else { return nil }
            if thisYear <= now { return thisYear }
            return date(year: year - 1, month: g[1], day: g[2], calendar).flatMap { at($0, g[3], g[4], calendar) }
        }
        return nil
    }

    /// 校验过的某一天(0 点);不存在的日期(2 月 30 日)返回 nil,而不是被日历进位。
    private static func date(year: Int, month: String, day: String, _ calendar: Calendar) -> Date? {
        guard let m = Int(month), let d = Int(day),
              let value = calendar.date(from: DateComponents(year: year, month: m, day: d))
        else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: value)
        return back.year == year && back.month == m && back.day == d ? value : nil
    }

    private static func at(_ day: Date, _ hour: String, _ minute: String, _ calendar: Calendar) -> Date? {
        guard let h = Int(hour), let m = Int(minute), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 285 tests in 27 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: resolve WeChat message-list time labels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 消息列表解析

**Files:**
- Create: `Packages/HappySpendingCore/Sources/HappySpendingCore/WeChatListParser.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/WeChatListParserTests.swift`(新建)

**Interfaces:**
- Consumes: `TimeLabel.resolve(_:now:calendar:) -> Date?`(Task 2)、`WeChatPaymentKey.make(cents:time:calendar:) -> String`(Task 1)、已有的 `TextMatch.captures`、`AmountText.cents(from:) throws -> Int`、`PaymentRecord`。
- Produces: `public enum WeChatListParser { public static func parse(_ text: String, now: Date, calendar: Calendar) -> [PaymentRecord]? }`。不是消息列表返回 nil;是列表但没有完整卡片返回 `[]`;每笔 `source == .screenText`、`eventDate` 是卡片时间、`orderRef` 是 `WeChatPaymentKey`、`platformCategory == nil`。

- [ ] **Step 1: 写失败的测试**

新建 `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/WeChatListParserTests.swift`:

```swift
import Testing
import Foundation
@testable import HappySpendingCore

struct WeChatListParserTests {
    // MARK: 真实样本(已脱敏)

    /// 样本一:顶部是一张被截断的转账卡(只剩"收款方 / 交易状态 / 查看账单详情"),下面两张完整卡片。
    /// "¥"被识别成"·";"收"是商户 logo 被识别成的字。
    private let sampleOne = """
    16:25 M
    三100
    微信支付
    收款方
    交易状态
    支付成功，对方已收款
    查看账单详情
    昨天18:23
    示例超市
    使用招商银行信用卡（0000）支付
    ·147.70
    账单详情＞
    13:00
    收
    示例小吃
    使用招商银行信用卡（0000）支付
    ·55.00
    账单详情＞
    我的账单
    支付服务
    优惠
    """
    private let sampleOneNow = makeDate(2026, 10, 15, 16, 25)

    /// 样本二:自动续费卡片的商户行没被识别出来,"续费项目""开通账号"跑到了金额前面。
    private let sampleTwo = """
    16:40 \\
    微信支付
    星期六 11:01
    续费项目
    开通账号
    通过招商银行信用卡（0000）自动续费
    · 9.90
    账单详情＞
    示例会员卡每月自动续费
    微信代扣
    对订单有疑惑
    进入商家小程序
    >
    星期六 12:41
    示例小吃
    使用招商银行信用卡（0000）支付
    · 81.00
    账单详情＞
    我账单
    支付服务
    优惠
    """
    private let sampleTwoNow = makeDate(2026, 10, 15, 16, 40)

    private let now = makeDate(2026, 10, 15, 16, 40)

    private func parse(_ text: String, now: Date? = nil) -> [PaymentRecord]? {
        WeChatListParser.parse(text, now: now ?? self.now, calendar: testCalendar)
    }

    // MARK: 真实样本

    @Test func parsesSampleOne() throws {
        let cards = try #require(parse(sampleOne, now: sampleOneNow))
        #expect(cards.count == 2)

        #expect(cards[0].cents == 14770)
        #expect(cards[0].merchant == "示例超市")
        #expect(cards[0].note == "示例超市")
        #expect(cards[0].eventDate == makeDate(2026, 10, 14, 18, 23))
        #expect(cards[0].source == .screenText)
        #expect(cards[0].platformCategory == nil)

        #expect(cards[1].cents == 5500)
        #expect(cards[1].merchant == "示例小吃")
        #expect(cards[1].eventDate == makeDate(2026, 10, 15, 13, 0))
    }

    @Test func parsesSampleTwo() throws {
        let cards = try #require(parse(sampleTwo, now: sampleTwoNow))
        #expect(cards.count == 2)

        #expect(cards[0].cents == 990)
        #expect(cards[0].merchant == nil)
        #expect(cards[0].note == "微信")
        #expect(cards[0].eventDate == makeDate(2026, 10, 10, 11, 1))

        #expect(cards[1].cents == 8100)
        #expect(cards[1].merchant == "示例小吃")
        #expect(cards[1].eventDate == makeDate(2026, 10, 10, 12, 41))
    }

    @Test func cardsCarryTheWeChatKey() throws {
        let cards = try #require(parse(sampleOne, now: sampleOneNow))
        #expect(cards[0].orderRef == "微信|14770|2026-10-14 18:23")
        #expect(cards[1].orderRef == "微信|5500|2026-10-15 13:00")
    }

    // MARK: 卡片边界

    /// 不是识别原文:按录屏里看到的转账卡片版式构造,真机采样后替换。
    @Test func aTransferCardHasNoMerchant() throws {
        let text = """
        微信支付
        昨天 17:37
        微信支付凭证
        使用零钱支付
        ¥0.20
        收款方
        交易状态
        支付成功，对方已收款
        查看账单详情
        """
        let cards = try #require(parse(text))
        #expect(cards.count == 1)
        #expect(cards[0].cents == 20)
        #expect(cards[0].merchant == nil)
        #expect(cards[0].note == "微信")
        #expect(cards[0].eventDate == makeDate(2026, 10, 14, 17, 37))
    }

    @Test func cardsUnderOneTimeLabelShareIt() throws {
        let text = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        示例超市
        使用零钱支付
        ·20.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.merchant) == ["示例小吃", "示例超市"])
        #expect(cards.map(\.eventDate) == [makeDate(2026, 10, 15, 13, 0), makeDate(2026, 10, 15, 13, 0)])
    }

    @Test func leftoverLinesBetweenCardsDoNotLeakIntoTheNextCard() throws {
        let text = """
        微信支付
        11:01
        续费项目
        开通账号
        通过招商银行信用卡（0000）自动续费
        · 9.90
        账单详情＞
        示例会员卡每月自动续费
        微信代扣
        进入商家小程序
        使用零钱支付
        · 3.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.count == 2)
        #expect(cards[1].cents == 300)
        #expect(cards[1].merchant == nil)
        #expect(cards[1].eventDate == makeDate(2026, 10, 15, 11, 1))
    }

    @Test func aCardCutOffAtTheBottomIsSkipped() throws {
        let noAmount = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        14:00
        示例超市
        使用零钱支付
        我的账单
        """
        let noFooter = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        14:00
        示例超市
        使用零钱支付
        ·20.00
        我的账单
        """
        for text in [noAmount, noFooter] {
            let cards = try #require(parse(text))
            #expect(cards.map(\.cents) == [5500])
        }
    }

    @Test func contentAboveTheTitleCannotSupplyATime() throws {
        let text = """
        16:40
        微信支付
        使用零钱支付
        ·30.00
        查看账单详情
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.cents) == [5500])
    }

    @Test func aCardWithAnInvalidAmountIsSkippedAndTheRestAreKept() throws {
        let text = """
        微信支付
        12:00
        示例超市
        使用零钱支付
        ·0.00
        账单详情＞
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.cents) == [5500])
    }

    @Test func aSingleCharacterLineAboveTheMarkerIsNotAMerchant() throws {
        let text = """
        微信支付
        13:00
        收
        使用零钱支付
        ·55.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards[0].merchant == nil)
        #expect(cards[0].note == "微信")
    }

    // MARK: 不该记的

    @Test func cardsWithoutAnExpenseMarkerAreSkipped() throws {
        let text = """
        微信支付
        13:00
        退款到账通知
        退款金额
        ·20.00
        账单详情＞
        """
        #expect(parse(text) == [])
    }

    @Test func onlyCutOffCardsGiveAnEmptyList() throws {
        let text = """
        微信支付
        收款方
        交易状态
        支付成功，对方已收款
        查看账单详情
        昨天18:23
        示例超市
        使用招商银行信用卡（0000）支付
        """
        #expect(parse(text) == [])
    }

    @Test func otherTextIsNotAListPage() {
        let detailPage = """
        账单
        全部账单
        示例超市
        -147.70
        当前状态
        支付成功
        支付时间
        2026年10月14日 18:23:27
        """
        let successPage = "♥支付成功\n示例商户\n¥0.20\n完成"
        let titleWithoutTimes = "微信支付\n已支付 ¥5.00"
        for text in [detailPage, successPage, titleWithoutTimes, "今天天气不错", ""] {
            #expect(parse(text) == nil, "\(text)")
        }
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: cannot find 'WeChatListParser' in scope`。

- [ ] **Step 3: 实现**

新建 `Packages/HappySpendingCore/Sources/HappySpendingCore/WeChatListParser.swift`:

```swift
import Foundation

/// 解析微信"微信支付"消息列表的识别文字。一屏可能有好几张支付卡片,记下其中**完整**的:
/// 上面有时间标签、有金额行、有支出标志,并以"账单详情"收尾。被截断的卡片跳过。
public enum WeChatListParser {
    /// 不是消息列表返回 nil;是列表但没有完整卡片返回空数组。
    public static func parse(_ text: String, now: Date, calendar: Calendar) -> [PaymentRecord]? {
        let all = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 标题之上(状态栏时间等)全部忽略,免得被当成时间标签。
        guard let titleIndex = all.firstIndex(of: "微信支付") else { return nil }
        let lines = Array(all[(titleIndex + 1)...])
        guard lines.contains(where: { TimeLabel.resolve($0, now: now, calendar: calendar) != nil }) else {
            return nil
        }

        var records: [PaymentRecord] = []
        var time: Date?
        var segment: [String] = []
        for line in lines {
            if let label = TimeLabel.resolve(line, now: now, calendar: calendar) {
                time = label
                segment = []
            } else if line.hasPrefix("账单详情") || line.hasPrefix("查看账单详情") {
                // 一段到此结束;第一个时间标签之前的段(顶部截断的卡片)没有时间,跳过。
                if let time, let record = card(segment, time: time, calendar: calendar) {
                    records.append(record)
                }
                // 几笔挨得很近时微信只显示一个时间标签:后面的段沿用当前时间。
                segment = []
            } else {
                segment.append(line)
            }
        }
        // 最后一段没有"账单详情"收尾,是底部截断的卡片,不要。
        return records
    }

    // MARK: 一张卡片

    private static func card(_ lines: [String], time: Date, calendar: Calendar) -> PaymentRecord? {
        guard let markerIndex = lines.firstIndex(where: isExpenseMarker),
              let amountText = lines.lazy.compactMap(amount).first,
              let cents = try? AmountText.cents(from: amountText)
        else { return nil }

        let merchant = markerIndex > 0 ? merchantName(lines[markerIndex - 1]) : nil
        return PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "微信",
            eventDate: time,
            orderRef: WeChatPaymentKey.make(cents: cents, time: time, calendar: calendar)
        )
    }

    /// 支出卡片才有的那一行:"使用…支付"、"通过…自动续费/扣费/支付"、"微信支付凭证"。
    private static func isExpenseMarker(_ line: String) -> Bool {
        if line == "微信支付凭证" { return true }
        if line.hasPrefix("使用") && line.contains("支付") { return true }
        if line.hasPrefix("通过") { return ["自动续费", "扣费", "支付"].contains { line.contains($0) } }
        return false
    }

    /// 整行金额:`· 9.90`、`·147.70`、`¥0.20`、`￥0.20`、`Y0.20`("¥"常被识别成各种圆点)。
    private static func amount(_ line: String) -> String? {
        let normalized = line.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? line
        let symbols = "\u{00A5}\u{FFE5}Y\u{00B7}\u{2022}\u{30FB}\u{FF65}"
        return TextMatch.captures("^[\(symbols)]\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)$", in: normalized)?[1]
    }

    // MARK: 商户

    /// 卡片里的标签和操作行;它们紧挨在下一张卡的支出标志上方时(商户行没识别出来),不能当成商户。
    private static let labels: Set<String> = [
        "续费项目", "开通账号", "收款方", "交易状态", "微信支付凭证", "微信代扣", "对订单有疑惑", "进入商家小程序",
    ]
    private static let decoration = CharacterSet(charactersIn: "•●·・○◦♥★☆■□◆◇—-_:：> \t")

    /// 支出标志的上一行;是标签或操作行、空的,或只有一个字(logo 被识别成的"收")就当没有商户。
    private static func merchantName(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: decoration)
        return value.count <= 1 || labels.contains(value) ? nil : value
    }
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 298 tests in 28 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: parse complete payment cards from the WeChat Pay message list

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 屏幕识别入口接上列表页,一次记多笔并给出合计提示

**Files:**
- Modify: `Packages/HappySpendingCore/Sources/HappySpendingCore/PaymentCapture.swift`
- Test: `Packages/HappySpendingCore/Tests/HappySpendingCoreTests/PaymentCaptureTests.swift`

**Interfaces:**
- Consumes: `WeChatListParser.parse(_:now:calendar:) -> [PaymentRecord]?`(Task 3)、`AutoEntryRecorder.record(_:now:calendar:in:) -> AutoEntryResult`(重复时 `isDuplicate == true`、`message == "已记过这一笔"`,Task 1)、`AutoEntryResult.cents`、`Money.display(_:)`(如 `¥136.70`)。
- Produces: `PaymentCaptureError.noCompleteCard`(`message == "这一屏没有完整的支付记录"`);`PaymentCapture.recordScreenText` 遇到列表页时逐笔记账;`static func listMessage(fresh: [AutoEntryResult], duplicates: Int) -> String`(internal,供测试)。

- [ ] **Step 1: 写失败的测试**

在 `PaymentCaptureTests.swift` 里,紧挨 `theErrorHasAReadableChineseMessage` 之前加入:

```swift
    // MARK: 微信支付消息列表

    private let listNow = makeDate(2026, 10, 15, 16, 25)

    private let wechatList = """
    16:25 M
    微信支付
    收款方
    交易状态
    支付成功，对方已收款
    查看账单详情
    昨天18:23
    示例超市
    使用招商银行信用卡（0000）支付
    ·147.70
    账单详情＞
    13:00
    收
    示例小吃
    使用招商银行信用卡（0000）支付
    ·55.00
    账单详情＞
    我的账单
    """

    /// 同一笔山姆的账单详情页(支付时间和列表上的"昨天18:23"在同一分钟)。
    private let wechatMerchantBill = """
    账单
    全部账单
    示例超市
    -147.70
    当前状态
    支付成功
    支付时间
    2026年10月14日 18:23:27
    交易单号
    4000000000000000000000000000
    """

    @Test func recordsEveryCompleteCardOnTheList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)

        #expect(result.recorded)
        #expect(result.message == "已记 2 笔,共 ¥202.70")
        let saved = try entries(context).sorted { $0.amountInCents > $1.amountInCents }
        #expect(saved.map(\.amountInCents) == [14770, 5500])
        #expect(saved.map(\.note) == ["示例超市", "示例小吃"])
        #expect(saved.map(\.date) == [makeDate(2026, 10, 14), makeDate(2026, 10, 15)])
        #expect(saved.allSatisfy { $0.autoSource == .screenText })
    }

    @Test func pressingTheSameListTwiceRecordsNothingNew() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)
        let again = try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)

        #expect(!again.recorded)
        #expect(again.message == "这一屏的 2 笔都记过了")
        #expect(try entries(context).count == 2)
    }

    @Test func aPaymentRecordedOnItsDetailPageIsSkippedOnTheList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try PaymentCapture.recordScreenText(wechatMerchantBill, now: listNow, calendar: testCalendar, in: context)
        let list = try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)

        #expect(list.recorded)
        #expect(list.message == "已记 1 笔 ¥55.00,1 笔已记过")
        #expect(try entries(context).count == 2)
    }

    @Test func aListWithOneNewCardUsesTheSingleEntryMessage() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let one = "微信支付\n13:00\n示例小吃\n使用零钱支付\n·55.00\n账单详情＞"

        let first = try PaymentCapture.recordScreenText(one, now: listNow, calendar: testCalendar, in: context)
        let second = try PaymentCapture.recordScreenText(one, now: listNow, calendar: testCalendar, in: context)

        #expect(first.message == "已记 ¥55.00 · 示例小吃")
        #expect(second.message == "已记过这一笔")
        #expect(!second.recorded)
    }

    @Test func twoIdenticalCardsOnOneScreenAreRecordedOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let twins = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        """

        let result = try PaymentCapture.recordScreenText(twins, now: listNow, calendar: testCalendar, in: context)

        #expect(result.message == "已记 1 笔 ¥55.00,1 笔已记过")
        #expect(try entries(context).count == 1)
    }

    @Test func aListWithoutCompleteCardsThrows() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cutOff = "微信支付\n收款方\n查看账单详情\n昨天18:23\n示例超市\n使用零钱支付"

        #expect(throws: PaymentCaptureError.noCompleteCard) {
            try PaymentCapture.recordScreenText(cutOff, now: listNow, calendar: testCalendar, in: context)
        }
        #expect(try entries(context).isEmpty)
    }

    @Test func listMessagesForEveryCombination() {
        func fresh(_ cents: Int, _ message: String = "") -> AutoEntryResult {
            AutoEntryResult(entryID: UUID(), cents: cents, message: message)
        }
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100, "已记 ¥81.00 · 示例小吃")], duplicates: 0)
                == "已记 ¥81.00 · 示例小吃")
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100), fresh(5570)], duplicates: 0)
                == "已记 2 笔,共 ¥136.70")
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100)], duplicates: 1)
                == "已记 1 笔 ¥81.00,1 笔已记过")
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100), fresh(5570)], duplicates: 1)
                == "已记 2 笔,共 ¥136.70,1 笔已记过")
        #expect(PaymentCapture.listMessage(fresh: [], duplicates: 1) == "已记过这一笔")
        #expect(PaymentCapture.listMessage(fresh: [], duplicates: 2) == "这一屏的 2 笔都记过了")
    }

    @Test func theNoCompleteCardErrorHasAReadableChineseMessage() {
        #expect(PaymentCaptureError.noCompleteCard.message == "这一屏没有完整的支付记录")
        #expect(PaymentCaptureError.noCompleteCard.errorDescription == "这一屏没有完整的支付记录")
    }
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|✘ Test [a-zA-Z]|Test run" | head -20`
Expected: 编译失败,`error: type 'PaymentCaptureError' has no member 'noCompleteCard'`(以及 `listMessage` 找不到)。

- [ ] **Step 3: 实现**

在 `PaymentCapture.swift` 里,把 `PaymentCaptureError` 整个换成:

```swift
public enum PaymentCaptureError: Error, Equatable, LocalizedError {
    case notPaymentPage
    /// 认出是微信支付消息列表,但这一屏的卡片都被截断了。
    case noCompleteCard

    public var message: String {
        switch self {
        case .notPaymentPage: "没有识别到支付页面"
        case .noCompleteCard: "这一屏没有完整的支付记录"
        }
    }

    public var errorDescription: String? { message }
}
```

把 `recordScreenText` 整个换成:

```swift
    /// 屏幕识别:是用户主动触发的,认不出支付页面时**抛错**,让用户知道没记上。
    /// 先看是不是微信支付消息列表(一屏多笔);不是再按单个支付页解析。
    @discardableResult
    public static func recordScreenText(
        _ text: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> CaptureResult {
        if let cards = WeChatListParser.parse(text, now: now, calendar: calendar) {
            return try recordList(cards, now: now, calendar: calendar, in: context)
        }
        switch ScreenTextParser.parse(text, calendar: calendar) {
        case .payment(let payment):
            return try record(payment, now: now, calendar: calendar, in: context)
        case .ignored(let reason):
            return CaptureResult(message: "已忽略:\(reason)", recorded: false)
        case .unrecognized:
            throw PaymentCaptureError.notPaymentPage
        }
    }

    /// 逐笔记账;中途保存失败就抛错,前面已保存的留着(再按一次会被去重)。
    private static func recordList(
        _ cards: [PaymentRecord],
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) throws -> CaptureResult {
        guard !cards.isEmpty else { throw PaymentCaptureError.noCompleteCard }
        var fresh: [AutoEntryResult] = []
        var duplicates = 0
        for card in cards {
            let result = try AutoEntryRecorder.record(card, now: now, calendar: calendar, in: context)
            if result.isDuplicate { duplicates += 1 } else { fresh.append(result) }
        }
        return CaptureResult(message: listMessage(fresh: fresh, duplicates: duplicates), recorded: !fresh.isEmpty)
    }

    /// 一次记多笔时给快捷指令的一句话。
    static func listMessage(fresh: [AutoEntryResult], duplicates: Int) -> String {
        let total = Money.display(fresh.reduce(0) { $0 + $1.cents })
        switch (fresh.count, duplicates) {
        case (0, 1): return "已记过这一笔"
        case (0, let d): return "这一屏的 \(d) 笔都记过了"
        case (1, 0): return fresh[0].message
        case (let n, 0): return "已记 \(n) 笔,共 \(total)"
        case (1, let d): return "已记 1 笔 \(total),\(d) 笔已记过"
        case (let n, let d): return "已记 \(n) 笔,共 \(total),\(d) 笔已记过"
        }
    }
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run"`
Expected: `✔ Test run with 306 tests in 28 suites passed`,没有警告。

- [ ] **Step 5: 提交**

```bash
git add Packages/HappySpendingCore
git commit -m "feat: record every complete card on the WeChat Pay message list

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 帮助页、动作描述、检查清单、README 与最终验证

**Files:**
- Modify: `HappySpending/Settings/AutoRecordHelpView.swift`(② 第 4 步)
- Modify: `HappySpending/Intents/RecordScreenTextIntent.swift`(动作描述)
- Modify: `docs/manual-test-checklist.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 4 的 `PaymentCapture.recordScreenText`(app 侧调用不变;新错误通过已有的 `catch let error as PaymentCaptureError` 显示 `error.message`)。
- Produces: 无代码接口。

- [ ] **Step 1: 改帮助页和动作描述**

在 `HappySpending/Settings/AutoRecordHelpView.swift` 里,把

```swift
                step(4, "在微信或支付宝里付完款,停在“支付成功”页或“账单详情”页时按一下操作按钮或轻点背面。")
```

换成

```swift
                step(4, "在微信或支付宝里付完款,停在“支付成功”页、“账单详情”页,或微信的“微信支付”消息列表上时,按一下操作按钮或轻点背面。在列表上按会记下这一屏所有完整的支付。")
```

在 `HappySpending/Intents/RecordScreenTextIntent.swift` 里,把

```swift
        "识别微信、支付宝支付成功页或账单详情页上的文字,把这笔支出记下来。通常接在“拍摄屏幕截图”和“提取图像中的文字”后面。"
```

换成

```swift
        "识别微信、支付宝支付成功页、账单详情页或微信支付消息列表上的文字,把支出记下来。通常接在“拍摄屏幕截图”和“提取图像中的文字”后面。"
```

- [ ] **Step 2: 更新检查清单和 README**

Run(仓库根目录):

```bash
python3 -I - <<'EOF'
p = "docs/manual-test-checklist.md"
s = open(p, encoding="utf-8").read()
assert s.count("## 深色模式") == 1
s = s.replace("## 深色模式", """## 微信支付消息列表

必须真机验证的:
- [ ] 1. 在微信支付消息列表上按一下:记下的笔数、金额、日期、商户和屏幕一致,提示文字正确
- [ ] 2. 一张完整的转账卡片("微信支付凭证")的识别文字顺序与构造的夹具一致(采样后补进测试)
- [ ] 3. 一个时间标签下挂两笔支付时,两笔都记上
- [ ] 4. 同一笔先在列表页、再在详情页各按一次(或反过来),只记一笔
- [ ] 5. 再按一次同一屏,提示"这一屏的 N 笔都记过了"
- [ ] 6. 滑到只剩截断卡片的位置按一下,提示"这一屏没有完整的支付记录"
- [ ] 7. 升级前用旧版本记下的微信账:删掉后在列表或详情页重新记一次

## 深色模式""")
open(p, "w", encoding="utf-8").write(s)

p = "README.md"
s = open(p, encoding="utf-8").read()
old = "- 屏幕识别与通知自动入账设计:`docs/superpowers/specs/2026-10-15-screen-and-notification-auto-record-design.md`\n"
assert s.count(old) == 1
s = s.replace(old, old + "- 微信支付消息列表记账设计:`docs/superpowers/specs/2026-10-15-wechat-list-screen-record-design.md`\n")
open(p, "w", encoding="utf-8").write(s)
EOF
```

Expected: 没有输出(两个 `assert` 都通过)。

- [ ] **Step 3: 最终验证**

Run(仓库根目录):

```bash
swift test --package-path Packages/HappySpendingCore 2>&1 | grep -E "error:|warning:|✘|Test run" && xcodegen generate && xcodebuild -project HappySpending.xcodeproj -scheme HappySpending -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*HappySpending/|BUILD"
```

Expected: `✔ Test run with 306 tests in 28 suites passed`;`** BUILD SUCCEEDED **`;没有 HappySpending 目录下的警告。

- [ ] **Step 4: 模拟器里看帮助页**

在模拟器里覆盖安装(不要卸载),打开 设置 → 自动入账。
Expected: "② 在微信/支付宝里直接付款(屏幕识别)"第 4 步是新文字;app 正常启动,已有账单还在。

- [ ] **Step 5: 提交**

```bash
git add HappySpending README.md docs/manual-test-checklist.md
git commit -m "docs: explain message-list recording in the help page, checklist and README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
