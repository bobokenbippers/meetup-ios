import Testing
@testable import meetup_ios

@Suite("ReceiptParser.parseText")
struct ReceiptParserTests {

    @Test("items are extracted from non-summary lines")
    func extractsItems() {
        let lines = [
            "Avocado Toast  12.00",
            "Latte           5.50",
            "Subtotal       17.50",
            "Tax             1.40",
            "Total          18.90",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 2)
        #expect(receipt.items[0].name == "Avocado Toast")
        #expect(receipt.items[0].price == 12.00)
        #expect(receipt.items[1].name == "Latte")
        #expect(receipt.items[1].price == 5.50)
    }

    @Test("explicit subtotal, tax, tip, total are parsed")
    func parsesSummaryLines() {
        let lines = [
            "Burger         18.00",
            "Fries           4.00",
            "Subtotal       22.00",
            "Tax             1.76",
            "Tip             4.40",
            "Total          28.16",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.subtotal == 22.00)
        #expect(receipt.tax == 1.76)
        #expect(receipt.tip == 4.40)
        #expect(receipt.total == 28.16)
    }

    @Test("subtotal inferred from items when absent")
    func inferredSubtotal() {
        let lines = [
            "Pancakes        9.00",
            "OJ              4.00",
            "Tax             1.04",
            "Total          14.04",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.subtotal == 13.00)
        #expect(receipt.tax == 1.04)
        #expect(receipt.total == 14.04)
    }

    @Test("total inferred from subtotal + tax + tip when absent")
    func inferredTotal() {
        let lines = [
            "Salad           8.00",
            "Subtotal        8.00",
            "Tax             0.64",
            "Tip             1.60",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.total == 10.24)
    }

    @Test("grand total wins over smaller total line")
    func grandTotalWins() {
        let lines = [
            "Coffee          4.00",
            "Total           4.32",
            "Grand Total     4.32",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.total == 4.32)
        #expect(receipt.items.count == 1)
    }

    @Test("payment method lines are excluded from items")
    func paymentLinesExcluded() {
        let lines = [
            "Eggs Benedict  14.00",
            "Visa            14.32",
            "Cash            14.32",
            "Change           0.00",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].name == "Eggs Benedict")
    }

    @Test("empty input produces zero receipt")
    func emptyInput() {
        let receipt = ReceiptParser.parseText([])
        #expect(receipt.items.isEmpty)
        #expect(receipt.subtotal == 0)
        #expect(receipt.tax == 0)
        #expect(receipt.tip == 0)
        #expect(receipt.total == 0)
    }

    @Test("lines without a price are ignored")
    func linesWithoutPrice() {
        let lines = [
            "Thank you for visiting!",
            "Espresso        3.50",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].price == 3.50)
    }

    @Test("HST and GST are treated as tax variants")
    func hstGstRecognised() {
        let lines = [
            "Poutine        12.00",
            "HST             1.56",
            "Total          13.56",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.tax == 1.56)
        #expect(receipt.items.count == 1)
    }

    @Test("service charge is treated as tip")
    func serviceChargeAsTip() {
        let lines = [
            "Steak          35.00",
            "Service Charge  5.25",
            "Total          40.25",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.tip == 5.25)
        #expect(receipt.items.count == 1)
    }
}
