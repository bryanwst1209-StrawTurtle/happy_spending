import Testing
@testable import HappySpendingCore

struct MoneyTests {
    @Test func plainAlwaysHasTwoDecimals() {
        #expect(Money.plain(0) == "0.00")
        #expect(Money.plain(5) == "0.05")
        #expect(Money.plain(1234) == "12.34")
        #expect(Money.plain(2350) == "23.50")
    }

    @Test func displayHasSymbolAndGrouping() {
        #expect(Money.display(123456) == "¥1,234.56")
        #expect(Money.display(Money.maxCents) == "¥9,999,999.99")
        #expect(Money.display(0) == "¥0.00")
    }

    @Test func negativeValuesKeepTheirSign() {
        #expect(Money.plain(-1234) == "-12.34")
        #expect(Money.display(-50) == "-¥0.50")
    }

    @Test func maxCentsIsNineMillionNineHundredNinetyNineThousandNineHundredNinetyNinePointNinetyNine() {
        #expect(Money.maxCents == 999_999_999)
    }
}
