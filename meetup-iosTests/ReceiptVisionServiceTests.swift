import Foundation
import Testing
@testable import meetup_ios

@Suite("ReceiptVisionService JSON mapping")
struct ReceiptVisionServiceTests {

    /// The user's real Daily Gather receipt, as the vision LLM should return it.
    /// One entry per printed line item; quantities NOT pre-expanded; the
    /// "(2) Woodford RX" line is a no-price modifier under the Old Fashioned.
    private let dailyGatherJSON = """
    {
      "items": [
        { "name": "Half Dozen Raw Oysters EC", "qty": 1, "unitPrice": 23.00, "lineTotal": 23.00, "isModifier": false },
        { "name": "Brown Sugar Bourbon Tini",  "qty": 2, "unitPrice": 16.00, "lineTotal": 32.00, "isModifier": false },
        { "name": "Drink Special",             "qty": 1, "unitPrice": 10.00, "lineTotal": 10.00, "isModifier": false },
        { "name": "Butcher Burger",            "qty": 1, "unitPrice": 19.00, "lineTotal": 19.00, "isModifier": false },
        { "name": "Friends Having Dinner",     "qty": 2, "unitPrice": 14.00, "lineTotal": 28.00, "isModifier": false },
        { "name": "Old Fashioned",             "qty": 2, "unitPrice": 18.00, "lineTotal": 36.00, "isModifier": false },
        { "name": "(2) Woodford RX",           "qty": 1, "unitPrice": 0.00,  "lineTotal": 0.00,  "isModifier": true }
      ],
      "subtotal": 148.00,
      "tax": 12.22,
      "tip": 0.00,
      "total": 160.22
    }
    """

    @Test("Daily Gather receipt expands quantities and drops modifiers")
    func dailyGatherGroundTruth() throws {
        let data = Data(dailyGatherJSON.utf8)
        let receipt = try ReceiptVisionService.parse(jsonData: data)

        // 1 + 2 + 1 + 1 + 2 + 2 = 9 individual claimable rows (modifier dropped).
        #expect(receipt.items.count == 9)

        // Quantities expanded into individual rows at the unit price.
        let tinis = receipt.items.filter { $0.name == "Brown Sugar Bourbon Tini" }
        #expect(tinis.count == 2)
        #expect(tinis.allSatisfy { $0.price == 16.00 })

        let oldFashioneds = receipt.items.filter { $0.name == "Old Fashioned" }
        #expect(oldFashioneds.count == 2)
        #expect(oldFashioneds.allSatisfy { $0.price == 18.00 })

        let friends = receipt.items.filter { $0.name == "Friends Having Dinner" }
        #expect(friends.count == 2)
        #expect(friends.allSatisfy { $0.price == 14.00 })

        // Single-quantity items appear once.
        #expect(receipt.items.filter { $0.name == "Half Dozen Raw Oysters EC" }.count == 1)
        #expect(receipt.items.filter { $0.name == "Butcher Burger" }.count == 1)
        #expect(receipt.items.filter { $0.name == "Drink Special" }.count == 1)

        // The "(2) Woodford RX" modifier is NOT its own item.
        #expect(!receipt.items.contains { $0.name.contains("Woodford") })

        // Printed totals are trusted verbatim.
        #expect(receipt.subtotal == 148.00)
        #expect(receipt.tax == 12.22)
        #expect(receipt.total == 160.22)

        // The expanded item prices sum to the printed subtotal.
        let itemsSum = receipt.items.reduce(0) { $0 + $1.price }
        #expect(abs(itemsSum - 148.00) < 0.001)
    }

    @Test("derives unit price from line total when unit price is missing")
    func derivesUnitPriceFromLineTotal() throws {
        let json = """
        {
          "items": [
            { "name": "Wings", "qty": 3, "unitPrice": 0, "lineTotal": 30.00, "isModifier": false }
          ],
          "subtotal": 30.00, "tax": 0, "tip": 0, "total": 30.00
        }
        """
        let receipt = try ReceiptVisionService.parse(jsonData: Data(json.utf8))
        #expect(receipt.items.count == 3)
        #expect(receipt.items.allSatisfy { $0.price == 10.00 })
    }

    @Test("zero-priced billable lines are skipped")
    func skipsZeroPricedItems() throws {
        let json = """
        {
          "items": [
            { "name": "Free Water", "qty": 1, "unitPrice": 0, "lineTotal": 0, "isModifier": false },
            { "name": "Coffee", "qty": 1, "unitPrice": 4.00, "lineTotal": 4.00, "isModifier": false }
          ],
          "subtotal": 4.00, "tax": 0, "tip": 0, "total": 4.00
        }
        """
        let receipt = try ReceiptVisionService.parse(jsonData: Data(json.utf8))
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].name == "Coffee")
    }

    @Test("synthesizes subtotal and total when not printed")
    func synthesizesMissingTotals() throws {
        let json = """
        {
          "items": [
            { "name": "Taco", "qty": 2, "unitPrice": 5.00, "lineTotal": 10.00, "isModifier": false }
          ],
          "subtotal": 0, "tax": 1.00, "tip": 2.00, "total": 0
        }
        """
        let receipt = try ReceiptVisionService.parse(jsonData: Data(json.utf8))
        #expect(receipt.subtotal == 10.00)          // summed from items
        #expect(receipt.total == 13.00)             // subtotal + tax + tip
    }

    @Test("clamps invalid quantities to at least one")
    func clampsInvalidQuantity() throws {
        let json = """
        {
          "items": [
            { "name": "Soup", "qty": 0, "unitPrice": 6.00, "lineTotal": 6.00, "isModifier": false }
          ],
          "subtotal": 6.00, "tax": 0, "tip": 0, "total": 6.00
        }
        """
        let receipt = try ReceiptVisionService.parse(jsonData: Data(json.utf8))
        #expect(receipt.items.count == 1)
        #expect(receipt.items[0].price == 6.00)
    }
}
