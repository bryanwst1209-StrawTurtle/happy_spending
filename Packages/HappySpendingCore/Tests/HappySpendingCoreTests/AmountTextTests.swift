import Testing
@testable import HappySpendingCore

struct AmountTextTests {
    @Test(arguments: [
        ("25", 2500),
        ("25.5", 2550),
        ("25.50", 2550),
        ("¥25.00", 2500),
        ("￥25", 2500),
        ("25元", 2500),
        ("RMB 25.5", 2550),
        ("cny25", 2500),
        ("CNY 1,234.56", 123456),
        ("1,234.56", 123456),
        ("１，２３４．５６", 123456),
        ("２５", 2500),
        ("  25.00  ", 2500),
        ("25.", 2500),
        (".5", 50),
        ("+25", 2500),
        ("0.01", 1),
        ("9999999.99", 999_999_999),
    ])
    func parsesCommonFormats(text: String, cents: Int) throws {
        #expect(try AmountText.cents(from: text) == cents)
    }

    @Test(arguments: [
        ("25.004", 2500),
        ("25.005", 2501),
        ("25.994", 2599),
        ("25.995", 2600),
        ("0.005", 1),
    ])
    func roundsToTheNearestCentHalfUp(text: String, cents: Int) throws {
        #expect(try AmountText.cents(from: text) == cents)
    }

    @Test(arguments: ["", "   ", "abc", "1.2.3", "1e3", "¥", "元", "--5", "25-", "12abc", "$25.00x"])
    func rejectsTextThatIsNotAnAmount(text: String) {
        #expect(throws: AmountError.invalidAmount) { try AmountText.cents(from: text) }
    }

    @Test(arguments: ["25,00", "12,50", "12,5", "1,23", "1,2345", "1,234,56", ",25", "25,", "1,,234", "1,234,5.00"])
    func aCommaThatIsNotAThousandsSeparatorIsNotSilentlyDropped(text: String) {
        #expect(throws: AmountError.invalidAmount) { try AmountText.cents(from: text) }
    }

    @Test(arguments: [("1,234", 123400), ("12,345.67", 1234567), ("1,234,567.89", 123456789), ("999,999", 99999900), ("+1,000", 100000)])
    func commasThatFormThousandsGroupsStillWork(text: String, cents: Int) throws {
        #expect(try AmountText.cents(from: text) == cents)
    }

    @Test(arguments: ["0", "0.00", "-5", "-0.5", "0.004", "0.001", "-0"])
    func rejectsZeroAndNegativeAmounts(text: String) {
        #expect(throws: AmountError.notAnExpense) { try AmountText.cents(from: text) }
    }

    @Test(arguments: ["10000000", "9999999.995", "1234567890123", "99999999999999999999999999999999999999"])
    func rejectsAmountsOverTheCap(text: String) {
        #expect(throws: AmountError.tooLarge) { try AmountText.cents(from: text) }
    }

    @Test func theCapItselfIsAccepted() throws {
        #expect(try AmountText.cents(from: "9999999.99") == Money.maxCents)
    }

    @Test func errorsHaveReadableChineseMessages() {
        #expect(AmountError.invalidAmount.message == "无法识别金额")
        #expect(AmountError.notAnExpense.message == "金额必须大于 0")
        #expect(AmountError.tooLarge.message == "金额超过 9,999,999.99")
        #expect(AmountError.invalidAmount.errorDescription == "无法识别金额")
    }
}
