# Bill Splitting Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four UX gaps in the bill splitting feature: include all participants in the summary, allow manually adding items, validate items before sharing, and improve receipt price parsing.

**Architecture:** Three source files change (`BillService.swift`, `BillView.swift`, `ReceiptParser.swift`) and two test files are updated alongside each service change. No schema or model changes. No new files.

**Tech Stack:** Swift Testing (`@Test`, `#expect`), SwiftUI `@FocusState`, `NSRegularExpression`, Supabase Swift SDK.

---

### Task 1: Commit the design spec

**Files:**
- Commit: `docs/specs/2026-05-29-bill-splitting-polish-design.md`

- [ ] **Step 1: Commit the spec**

```bash
git add docs/specs/2026-05-29-bill-splitting-polish-design.md
git commit -m "Add bill splitting polish design spec"
```

---

### Task 2: Include all participants in `computeTotals()`

**Files:**
- Modify: `meetup-ios/Services/BillService.swift`
- Modify: `meetup-iosTests/BillComputeTotalsTests.swift`

- [ ] **Step 1: Update the two tests that assert the old exclusion behavior**

In `meetup-iosTests/BillComputeTotalsTests.swift`, replace the `participantWithNoClaimsOmitted` test and `emptyInputs` test:

```swift
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
```

- [ ] **Step 2: Run the updated tests to confirm they fail**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests/BillComputeTotalsTests 2>&1 | tail -20
```

Expected: `participantWithNoClaimsIncluded` and `emptyInputsIncludesParticipants` FAIL (implementation still omits $0 participants).

- [ ] **Step 3: Replace `computeTotals()` in `BillService.swift`**

Find the `return participants.compactMap { p in ... }` block (currently lines 146–159) and replace the entire block with:

```swift
return participants
    .map { p in
        let sub = subtotals[p.userId] ?? 0
        let taxShare = bill.subtotal > 0 ? (sub / bill.subtotal) * bill.tax : 0
        let tipShare = bill.subtotal > 0 ? (sub / bill.subtotal) * bill.tip : 0
        return PersonTotal(
            userId: p.userId,
            displayName: p.displayName ?? "Unknown",
            subtotal: sub,
            taxShare: taxShare,
            tipShare: tipShare,
            total: sub + taxShare + tipShare
        )
    }
    .sorted { $0.total > $1.total }
```

Also remove the now-unused `let billSubtotal = bill.subtotal > 0 ? bill.subtotal : 1` line that preceded it.

- [ ] **Step 4: Run all `BillComputeTotalsTests` to confirm they all pass**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests/BillComputeTotalsTests 2>&1 | tail -20
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add meetup-ios/Services/BillService.swift meetup-iosTests/BillComputeTotalsTests.swift
git commit -m "Include all participants in bill totals, sorted by amount descending"
```

---

### Task 3: Style $0 entries in the summary sheet

**Files:**
- Modify: `meetup-ios/Views/BillView.swift` — `summarySheet`

- [ ] **Step 1: Update the row content inside `summarySheet`'s `ForEach`**

In `BillView.summarySheet`, find the `ForEach(totals, id: \.userId)` row:

```swift
HStack {
    Text(t.displayName)
    Spacer()
    Text(t.total, format: .currency(code: "USD")).bold()
}
```

Replace with:

```swift
HStack {
    VStack(alignment: .leading, spacing: 2) {
        Text(t.displayName)
            .foregroundStyle(t.total == 0 ? .secondary : .primary)
        if t.total == 0 {
            Text("Hasn't claimed yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    Spacer()
    Text(t.total, format: .currency(code: "USD"))
        .bold()
        .foregroundStyle(t.total == 0 ? .secondary : .primary)
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add meetup-ios/Views/BillView.swift
git commit -m "Show all participants in bill summary; $0 entries show 'Hasn't claimed yet'"
```

---

### Task 4: Add "Add Item" button to the preview stage

**Files:**
- Modify: `meetup-ios/Views/BillView.swift` — state properties and `previewView`

- [ ] **Step 1: Add `@FocusState` property to `BillView`**

In `BillView`, after the existing `@State` declarations (after line 24, `@State private var editableItems: [BillItem] = []`), add:

```swift
@FocusState private var focusedItemId: UUID?
```

- [ ] **Step 2: Add `.focused` modifier to the name `TextField` in `previewView`**

In `previewView`, find the `ForEach(editableItems.indices, id: \.self)` block and add `.focused` to the name field:

```swift
ForEach(editableItems.indices, id: \.self) { idx in
    HStack {
        TextField("Item name", text: $editableItems[idx].name)
            .focused($focusedItemId, equals: editableItems[idx].id)
        Spacer()
        TextField("0.00", value: $editableItems[idx].price, format: .currency(code: "USD"))
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .frame(width: 80)
    }
}
.onDelete { editableItems.remove(atOffsets: $0) }
```

- [ ] **Step 3: Add the "Add Item" button as the last row in the items `Section`**

After the `.onDelete` line and before the Section closing brace, add:

```swift
Button {
    let newItem = BillItem(id: UUID(), billId: UUID(), name: "", price: 0, position: editableItems.count)
    editableItems.append(newItem)
    focusedItemId = newItem.id
} label: {
    Label("Add Item", systemImage: "plus")
}
```

- [ ] **Step 4: Build to verify no compile errors**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
git add meetup-ios/Views/BillView.swift
git commit -m "Add 'Add Item' button with auto-focus to bill preview stage"
```

---

### Task 5: Validate items before sharing

**Files:**
- Modify: `meetup-ios/Views/BillView.swift` — computed property and `previewView`

- [ ] **Step 1: Add `canShare` computed property to `BillView`**

After the `myUserId` computed property (line 26), add:

```swift
private var canShare: Bool {
    !editableItems.isEmpty &&
    editableItems.allSatisfy {
        !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.price > 0
    }
}
```

- [ ] **Step 2: Update the Share button in `previewView`**

Find the Share button block:

```swift
Button {
    Task { await shareBill() }
} label: {
    Label("Share with group", systemImage: "person.2.fill")
        .frame(maxWidth: .infinity)
}
.buttonStyle(.glassProminent)
.disabled(isProcessing || editableItems.isEmpty)
.padding()
```

Replace with:

```swift
VStack(spacing: 6) {
    Button {
        Task { await shareBill() }
    } label: {
        Label("Share with group", systemImage: "person.2.fill")
            .frame(maxWidth: .infinity)
    }
    .buttonStyle(.glassProminent)
    .disabled(isProcessing || !canShare)
    if !canShare && !isProcessing {
        Text("Fix items with missing names or $0 prices")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
.padding()
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add meetup-ios/Views/BillView.swift
git commit -m "Validate bill items before sharing — require non-empty names and positive prices"
```

---

### Task 6: Improve price parsing in `ReceiptParser`

**Files:**
- Modify: `meetup-ios/Services/ReceiptParser.swift`
- Modify: `meetup-iosTests/ReceiptParserTests.swift`

- [ ] **Step 1: Add new test cases for the extended price formats**

In `meetup-iosTests/ReceiptParserTests.swift`, add to the `ReceiptParserTests` suite:

```swift
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
```

- [ ] **Step 2: Run the new tests to confirm the first three fail**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests/ReceiptParserTests 2>&1 | tail -30
```

Expected: `dollarSignWholePrice`, `oneDecimalPrice`, and `dollarSignDecimalPrice` FAIL. `bareIntegersExcluded` may already pass.

- [ ] **Step 3: Update the regex in `ReceiptParser.parseText(_:)`**

In `meetup-ios/Services/ReceiptParser.swift`, replace:

```swift
let pricePattern = #"(\d+\.\d{2})"#
let priceRegex = try! NSRegularExpression(pattern: pricePattern)
```

With:

```swift
let pricePattern = #"\$(\d+(?:\.\d{1,2})?)|\b(\d+\.\d{1,2})\b"#
let priceRegex = try! NSRegularExpression(pattern: pricePattern)
```

Group 1 captures `$`-prefixed prices (`$10`, `$10.5`, `$10.50`). Group 2 captures decimal prices without `$` (`10.5`, `10.50`).

- [ ] **Step 4: Update the price extraction inside the `for line in lines` loop**

Find:

```swift
guard let match = priceRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
      let range = Range(match.range(at: 1), in: line),
      let price = Double(line[range]) else { continue }
```

Replace with:

```swift
guard let match = priceRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
let priceStr = Range(match.range(at: 1), in: line).map { String(line[$0]) }
           ?? Range(match.range(at: 2), in: line).map { String(line[$0]) }
guard let priceStr, let price = Double(priceStr), price >= 0.01 else { continue }
```

- [ ] **Step 5: Run all `ReceiptParserTests` to confirm they all pass**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests/ReceiptParserTests 2>&1 | tail -30
```

Expected: all 12 tests PASS.

- [ ] **Step 6: Run the full unit test suite to check for regressions**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests 2>&1 | tail -20
```

Expected: all unit tests PASS.

- [ ] **Step 7: Commit**

```bash
git add meetup-ios/Services/ReceiptParser.swift meetup-iosTests/ReceiptParserTests.swift
git commit -m "Improve receipt price parsing: support $X and X.X formats"
```
