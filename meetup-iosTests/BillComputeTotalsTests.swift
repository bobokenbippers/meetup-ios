import Testing
import Foundation
@testable import meetup_ios

@Suite("BillService.computeTotals")
struct BillComputeTotalsTests {

    private func makeBill(subtotal: Double, tax: Double, tip: Double) -> Bill {
        Bill(
            id: UUID(),
            meetupId: UUID(),
            createdBy: UUID(),
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            total: subtotal + tax + tip,
            createdAt: Date()
        )
    }

    private func makeItem(billId: UUID, price: Double) -> BillItem {
        BillItem(id: UUID(), billId: billId, name: "Item", price: price, position: 0)
    }

    private func makeReceipt(tax: Double, tip: Double, surcharge: Double = 0) -> Receipt {
        Receipt(
            id: UUID(),
            meetupId: UUID(),
            placeName: "Test Cafe",
            payerUserId: UUID(),
            totalAmount: 20 + tax + tip + surcharge,
            tax: tax,
            tip: tip,
            surcharge: surcharge,
            photoUrl: nil,
            createdAt: Date()
        )
    }

    private func makeReceiptItem(receiptId: UUID, price: Double) -> BillItem {
        BillItem(id: UUID(), receiptId: receiptId, name: "Item", price: price, position: 0)
    }

    private func makeClaim(itemId: UUID, userId: UUID) -> BillItemClaim {
        BillItemClaim(id: UUID(), billItemId: itemId, userId: userId, createdAt: Date())
    }

    private func makeParticipant(userId: UUID, name: String) -> MeetupParticipant {
        MeetupParticipant(
            meetupId: UUID(),
            userId: userId,
            status: "accepted",
            lat: nil, lng: nil, bearing: nil, etaSeconds: nil,
            locationUpdatedAt: nil,
            profiles: .init(displayName: name, phoneE164: nil)
        )
    }

    @Test("single item claimed by one person")
    func singleClaim() throws {
        let userId = UUID()
        let bill = makeBill(subtotal: 20, tax: 1.60, tip: 4)
        let item = makeItem(billId: bill.id, price: 20)
        let claim = makeClaim(itemId: item.id, userId: userId)
        let participant = makeParticipant(userId: userId, name: "Alice")

        let totals = BillService.computeTotals(
            bill: bill, items: [item], claims: [claim], participants: [participant]
        )

        #expect(totals.count == 1)
        let total = try #require(totals.first)
        #expect(total.subtotal == 20)
        #expect(total.taxShare == 1.60)
        #expect(total.tipShare == 4)
        #expect(total.total == 25.60)
        #expect(total.displayName == "Alice")
    }

    @Test("item split evenly between two people")
    func splitEvenly() {
        let aliceId = UUID()
        let bobId = UUID()
        let bill = makeBill(subtotal: 30, tax: 2.40, tip: 6)
        let item = makeItem(billId: bill.id, price: 30)
        let claims = [
            makeClaim(itemId: item.id, userId: aliceId),
            makeClaim(itemId: item.id, userId: bobId),
        ]
        let participants = [
            makeParticipant(userId: aliceId, name: "Alice"),
            makeParticipant(userId: bobId, name: "Bob"),
        ]

        let totals = BillService.computeTotals(
            bill: bill, items: [item], claims: claims, participants: participants
        )

        #expect(totals.count == 2)
        for total in totals {
            #expect(total.subtotal == 15)
            #expect(total.taxShare == 1.20)
            #expect(total.tipShare == 3)
            #expect(total.total == 19.20)
        }
    }

    @Test("tax and tip distributed proportionally")
    func proportionalTaxTip() throws {
        let aliceId = UUID()
        let bobId = UUID()
        let bill = makeBill(subtotal: 40, tax: 3.20, tip: 8)
        let cheapItem = makeItem(billId: bill.id, price: 10)
        let expensiveItem = makeItem(billId: bill.id, price: 30)
        let claims = [
            makeClaim(itemId: cheapItem.id, userId: aliceId),
            makeClaim(itemId: expensiveItem.id, userId: bobId),
        ]
        let participants = [
            makeParticipant(userId: aliceId, name: "Alice"),
            makeParticipant(userId: bobId, name: "Bob"),
        ]

        let totals = BillService.computeTotals(
            bill: bill, items: [cheapItem, expensiveItem], claims: claims, participants: participants
        )
        let alice = try #require(totals.first(where: { $0.displayName == "Alice" }))
        let bob = try #require(totals.first(where: { $0.displayName == "Bob" }))

        // Alice has 1/4 of subtotal → 1/4 of tax and tip
        #expect(abs(alice.taxShare - 0.80) < 0.001)
        #expect(abs(alice.tipShare - 2.00) < 0.001)
        // Bob has 3/4 of subtotal
        #expect(abs(bob.taxShare - 2.40) < 0.001)
        #expect(abs(bob.tipShare - 6.00) < 0.001)
    }

    @Test("unclaimed items are not included in totals")
    func unclaimedItemsExcluded() {
        let userId = UUID()
        let bill = makeBill(subtotal: 20, tax: 1.60, tip: 0)
        let claimedItem = makeItem(billId: bill.id, price: 20)
        let unclaimedItem = makeItem(billId: bill.id, price: 10)
        let claim = makeClaim(itemId: claimedItem.id, userId: userId)
        let participant = makeParticipant(userId: userId, name: "Alice")

        let totals = BillService.computeTotals(
            bill: bill,
            items: [claimedItem, unclaimedItem],
            claims: [claim],
            participants: [participant]
        )

        #expect(totals.count == 1)
        #expect(totals[0].subtotal == 20)
    }

    @Test("participant with no claims appears with zero total")
    func participantWithNoClaimsIncluded() throws {
        let aliceId = UUID()
        let bobId = UUID()
        let bill = makeBill(subtotal: 15, tax: 1.20, tip: 3)
        let item = makeItem(billId: bill.id, price: 15)
        let claim = makeClaim(itemId: item.id, userId: aliceId)
        let participants = [
            makeParticipant(userId: aliceId, name: "Alice"),
            makeParticipant(userId: bobId, name: "Bob"),
        ]

        let totals = BillService.computeTotals(
            bill: bill, items: [item], claims: [claim], participants: participants
        )

        #expect(totals.count == 2)
        let alice = try #require(totals.first(where: { $0.displayName == "Alice" }))
        let bob = try #require(totals.first(where: { $0.displayName == "Bob" }))
        #expect(alice.total == 19.20)
        #expect(bob.total == 0)
        #expect(bob.subtotal == 0)
    }

    @Test("all participants included even with no items or claims")
    func emptyInputsIncludesParticipants() {
        let bill = makeBill(subtotal: 0, tax: 0, tip: 0)
        let participant = makeParticipant(userId: UUID(), name: "Alice")

        let totals = BillService.computeTotals(
            bill: bill, items: [], claims: [], participants: [participant]
        )

        #expect(totals.count == 1)
        #expect(totals[0].displayName == "Alice")
        #expect(totals[0].total == 0)
    }

    @Test("receipt totals expose tax and tip shares")
    func receiptTotalsExposeTaxAndTipShares() throws {
        let aliceId = UUID()
        let bobId = UUID()
        let receipt = makeReceipt(tax: 2, tip: 4)
        let aliceItem = makeReceiptItem(receiptId: receipt.id, price: 5)
        let bobItem = makeReceiptItem(receiptId: receipt.id, price: 15)
        let claims = [
            makeClaim(itemId: aliceItem.id, userId: aliceId),
            makeClaim(itemId: bobItem.id, userId: bobId),
        ]
        let participants = [
            makeParticipant(userId: aliceId, name: "Alice"),
            makeParticipant(userId: bobId, name: "Bob"),
        ]

        let totalsByReceipt = BillService.computeReceiptTotals(
            receipts: [receipt],
            items: [receipt.id: [aliceItem, bobItem]],
            claims: claims,
            participants: participants
        )

        let totals = try #require(totalsByReceipt[receipt.id])
        let alice = try #require(totals.first(where: { $0.displayName == "Alice" }))
        let bob = try #require(totals.first(where: { $0.displayName == "Bob" }))

        #expect(abs(alice.taxShare - 0.50) < 0.001)
        #expect(abs(alice.tipShare - 1.00) < 0.001)
        #expect(abs(alice.total - 6.50) < 0.001)
        #expect(abs(bob.taxShare - 1.50) < 0.001)
        #expect(abs(bob.tipShare - 3.00) < 0.001)
        #expect(abs(bob.total - 19.50) < 0.001)
    }

    @Test("unclaimed receipt items keep their tax and tip unassigned")
    func unclaimedReceiptItemsKeepFeesUnassigned() throws {
        let aliceId = UUID()
        let receipt = makeReceipt(tax: 2, tip: 4)
        let claimedItem = makeReceiptItem(receiptId: receipt.id, price: 5)
        let unclaimedItem = makeReceiptItem(receiptId: receipt.id, price: 15)
        let participant = makeParticipant(userId: aliceId, name: "Alice")

        let totalsByReceipt = BillService.computeReceiptTotals(
            receipts: [receipt],
            items: [receipt.id: [claimedItem, unclaimedItem]],
            claims: [makeClaim(itemId: claimedItem.id, userId: aliceId)],
            participants: [participant]
        )

        let alice = try #require(totalsByReceipt[receipt.id]?.first)

        #expect(abs(alice.taxShare - 0.50) < 0.001)
        #expect(abs(alice.tipShare - 1.00) < 0.001)
        #expect(abs(alice.total - 6.50) < 0.001)
    }
}
