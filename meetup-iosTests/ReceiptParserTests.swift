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

    @Test("credit card fee is parsed as surcharge, not an item")
    func creditCardFeeAsSurcharge() {
        let lines = [
            "Salad          12.00",
            "Credit Card Fee 0.48",
            "Total          12.48",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.surcharge == 0.48)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].name == "Salad")
    }

    @Test("empty input produces zero receipt")
    func emptyInput() {
        let receipt = ReceiptParser.parseText([])
        #expect(receipt.items.isEmpty)
        #expect(receipt.subtotal == 0)
        #expect(receipt.tax == 0)
        #expect(receipt.tip == 0)
        #expect(receipt.surcharge == 0)
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

    @Test("item name line followed by price line is paired")
    func pairsItemNameWithStandalonePriceLine() {
        let lines = [
            "French Toast",
            "$14.00",
            "Subtotal",
            "$14.00",
            "Tax",
            "$1.24",
            "Total",
            "$15.24",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].name == "French Toast")
        #expect(receipt.items[0].price == 14.00)
        #expect(receipt.subtotal == 14.00)
        #expect(receipt.tax == 1.24)
        #expect(receipt.total == 15.24)
    }

    @Test("split OCR item quantity followed by line total is expanded")
    func expandsSplitQuantityItemWithStandaloneTotalLine() {
        let lines = [
            "2 Breakfast Tacos",
            "$18.00",
            "Subtotal $18.00",
            "Total $18.00",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 2)
        #expect(receipt.items.allSatisfy { $0.name == "Breakfast Tacos" })
        #expect(receipt.items.allSatisfy { $0.price == 9.00 })
        #expect(receipt.subtotal == 18.00)
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

    @Test("dollar-sign whole-dollar prices are parsed")
    func dollarSignWholePrice() {
        let lines = [
            "Mimosa  $8",
            "Tax     $0.64",
            "Total   $8.64",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].price == 8.0)
        #expect(receipt.tax == 0.64)
        #expect(receipt.total == 8.64)
    }

    @Test("one-decimal prices without dollar sign are parsed")
    func oneDecimalPrice() {
        let lines = [
            "Juice   7.5",
            "Tax     0.6",
            "Total   8.1",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].price == 7.5)
    }

    @Test("dollar-sign decimal prices are parsed")
    func dollarSignDecimalPrice() {
        let lines = [
            "Burger  $12.50",
            "Total   $12.50",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].price == 12.50)
    }

    @Test("bare integers without dollar sign are not parsed as prices")
    func bareIntegersExcluded() {
        let lines = [
            "Table 2",
            "Espresso  3.50",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].price == 3.50)
    }

    @Test("last price on a line wins for totals and surcharge percentages")
    func lastPriceWinsWhenLineContainsPercentOrUnitPrice() {
        let lines = [
            "Gls STARR PINOT NOIR (2 @21.00) 42.00",
            "Credit Card",
            "$1.87",
            "Surcharge (2.67%)",
            "Credit Card Surcharge (2.67%) $1.87",
            "Total $43.87",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].price == 42.00)
        #expect(receipt.surcharge == 1.87)
        #expect(receipt.total == 43.87)
    }

    @Test("tip suggestions and post-total promo prices are ignored")
    func ignoresTipSuggestionsAndPostTotalPromos() {
        let lines = [
            "Fight Milk $19.00",
            "Subtotal $19.00",
            "Tax $1.69",
            "Total $20.69",
            "$7 mini martinis!",
            "Tip Suggestions",
            "18% $3.42",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].name == "Fight Milk")
        #expect(receipt.tip == 0)
        #expect(receipt.total == 20.69)
    }

    @Test("receipt lines with x quantity prefixes are expanded")
    func expandsXQuantityPrefixes() {
        let lines = [
            "4x Raj Spiced Old Fashioned $76.00",
            "Subtotal $76.00",
            "Total $76.00",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 4)
        #expect(receipt.items.allSatisfy { $0.name == "Raj Spiced Old Fashioned" })
        #expect(receipt.items.allSatisfy { $0.price == 19.00 })
    }

    @Test("Daily Gather bar receipt: inline (N @ U) quantities and modifier sub-line")
    func parsesDailyGatherReceipt() {
        // Inline "(N @ U.UU" annotations have NO separate column total here, so
        // the line total must be N * U (never the bare unit price). "(2) Woodford RX"
        // is a priceless modifier of Old Fashioned and must not become an item.
        let lines = [
            "Half Dozen Raw Oysters EC  23.00",
            "Brown Sugar Bourbon Tini (2 @16.00",
            "Drink Special  10.00",
            "Butcher Burger  19.00",
            "Friends Having Dinner (2 @14.00",
            "Old Fashioned (2 @18.00",
            "(2) Woodford RX",
            "Subtotal  148.00",
            "Tax  12.22",
            "Total  160.22",
        ]
        let receipt = ReceiptParser.parseText(lines)

        // 1 + 2 + 1 + 1 + 2 + 2 = 9 expanded units
        #expect(receipt.items.count == 9)

        func total(_ name: String) -> Double {
            receipt.items.filter { $0.name == name }.reduce(0) { $0 + $1.price }
        }
        #expect(total("Half Dozen Raw Oysters EC") == 23.00)
        #expect(total("Brown Sugar Bourbon Tini") == 32.00)
        #expect(total("Drink Special") == 10.00)
        #expect(total("Butcher Burger") == 19.00)
        #expect(total("Friends Having Dinner") == 28.00)
        #expect(total("Old Fashioned") == 36.00)

        // Friends Having Dinner is a real shareable item — present, not dropped
        #expect(receipt.items.contains { $0.name == "Friends Having Dinner" })
        #expect(receipt.items.filter { $0.name == "Friends Having Dinner" }.count == 2)
        #expect(receipt.items.allSatisfy { $0.name == "Brown Sugar Bourbon Tini" ? $0.price == 16.00 : true })

        // Modifier sub-line must not appear as an item
        #expect(!receipt.items.contains { $0.name.contains("Woodford") })

        #expect(receipt.subtotal == 148.00)
        #expect(receipt.tax == 12.22)
        #expect(receipt.total == 160.22)
    }

    @Test("real receipt summary with non-cash total and payment tip")
    func parsesNonCashPaymentReceiptSummary() {
        let lines = [
            "1x Captain Coconut Mussels $39.00",
            "1x Kashmiri Rogan Josh $28.00",
            "1x Garlic Naan $5.00",
            "1x Bombay Lamb Biryani $29.00",
            "Subtotal $101.00",
            "Tax $8.96",
            "Total (Cash) $109.96",
            "Total (Non-Cash) $113.26",
            "Payment Amount $113.26",
            "Tip $17.00",
            "Payment Total $130.26",
        ]
        let receipt = ReceiptParser.parseText(lines)
        #expect(receipt.items.count == 4)
        #expect(receipt.subtotal == 101.00)
        #expect(receipt.tax == 8.96)
        #expect(receipt.tip == 17.00)
        #expect(receipt.total == 130.26)
    }
}
