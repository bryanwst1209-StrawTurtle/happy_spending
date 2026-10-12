import Testing
@testable import HappySpendingCore

struct AmountInputTests {
    private func typed(_ keys: [KeypadKey]) -> AmountInput {
        var input = AmountInput()
        for key in keys { input.press(key) }
        return input
    }

    @Test func typesDigitsAndTwoDecimals() {
        let input = typed([.digit(1), .digit(2), .dot, .digit(3), .digit(4)])
        #expect(input.text == "12.34")
        #expect(input.cents == 1234)
    }

    @Test func thirdDecimalIsIgnored() {
        let input = typed([.digit(1), .dot, .digit(2), .digit(3), .digit(4)])
        #expect(input.text == "1.23")
        #expect(input.cents == 123)
    }

    @Test func leadingZerosCollapse() {
        #expect(typed([.digit(0), .digit(0), .digit(5)]).text == "5")
        #expect(typed([.digit(0), .digit(0)]).text == "0")
    }

    @Test func dotFirstProducesZeroDot() {
        let input = typed([.dot])
        #expect(input.text == "0.")
        #expect(input.cents == 0)
        #expect(!input.isValid)
    }

    @Test func secondDotIsIgnored() {
        let input = typed([.digit(1), .dot, .digit(2), .dot, .digit(3)])
        #expect(input.text == "1.23")
    }

    @Test func integerPartIsCappedAtSevenDigits() {
        let input = typed(Array(repeating: .digit(9), count: 8))
        #expect(input.text == "9999999")
        #expect(input.cents == 999_999_900)
    }

    @Test func largestAmountEqualsTheCapAndRejectsMore() {
        var input = typed(Array(repeating: .digit(9), count: 7) + [.dot, .digit(9), .digit(9)])
        #expect(input.cents == Money.maxCents)
        input.press(.digit(9))
        #expect(input.text == "9999999.99")
    }

    @Test func backspaceOnEmptyDoesNothing() {
        var input = AmountInput()
        input.press(.backspace)
        #expect(input.text == "")
        #expect(input.cents == 0)
    }

    @Test func backspaceCanRemoveTheDot() {
        var input = typed([.digit(1), .digit(2), .dot])
        input.press(.backspace)
        #expect(input.text == "12")
    }

    @Test func partialDecimalsArePadded() {
        #expect(typed([.digit(1), .digit(2), .dot]).cents == 1200)
        #expect(typed([.digit(1), .digit(2), .dot, .digit(3)]).cents == 1230)
        #expect(typed([.dot, .digit(5)]).cents == 50)
    }

    @Test func zeroAmountIsNotValid() {
        #expect(!AmountInput().isValid)
        #expect(!typed([.digit(0), .dot, .digit(0), .digit(0)]).isValid)
        #expect(typed([.dot, .digit(0), .digit(1)]).isValid)
    }

    @Test func displayTextShowsWhatWasTyped() {
        #expect(AmountInput().displayText == "¥0.00")
        #expect(typed([.digit(1), .digit(2), .dot]).displayText == "¥12.")
    }

    @Test func initFromCentsRoundTrips() {
        let input = AmountInput(cents: 2350)
        #expect(input.text == "23.50")
        #expect(input.cents == 2350)
        #expect(AmountInput(cents: 0).text == "")
        #expect(AmountInput(cents: Money.maxCents).cents == Money.maxCents)
    }
}
