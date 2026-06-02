# Bill Splitting Polish

**Date:** 2026-05-29  
**Status:** Approved — ready for implementation

## Context

The core bill splitting flow (upload receipt → OCR parse → edit items → share with group → realtime checklist) is built and committed. Four specific gaps make it feel unfinished:

1. The summary sheet silently omits participants who haven't claimed anything, making it hard to see who still owes money.
2. There's no way to add an item manually if the parser missed it.
3. No validation prevents sharing a bill with empty item names or $0 prices.
4. The price regex only matches `XX.XX` format, missing prices like `$10` or `10.5`.

## Changes

### 1. Summary includes all participants

**File:** `meetup-ios/Services/BillService.swift` — `computeTotals()`

Change `compactMap` to `map` and remove `guard sub > 0 else { return nil }`. Every participant passed in gets a `PersonTotal` entry; non-claimers have `subtotal = 0, taxShare = 0, tipShare = 0, total = 0`. Sort the result by `total` descending so people with balances appear first.

**File:** `meetup-ios/Views/BillView.swift` — `summarySheet`

Show $0 entries with `.secondary` foreground style and the annotation "Hasn't claimed yet" in a `.caption` label below their name. This makes it immediately obvious who hasn't acted.

### 2. Add items manually in the preview stage

**File:** `meetup-ios/Views/BillView.swift` — `previewView`

Add an "Add Item" button at the bottom of the items `Section` (as a `Button` row, not a trailing toolbar item). Tapping it appends a blank `BillItem(id: UUID(), billId: UUID(), name: "", price: 0, position: editableItems.count)` to `editableItems` and moves keyboard focus to the new row's name field using `@FocusState<UUID?>`.

The existing `.onDelete` swipe already handles removal, so no additional delete UI is needed.

### 3. Input validation before sharing

**File:** `meetup-ios/Views/BillView.swift` — `previewView`

Add a computed property:

```swift
private var canShare: Bool {
    !editableItems.isEmpty &&
    editableItems.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.price > 0 }
}
```

Replace the existing `disabled(isProcessing || editableItems.isEmpty)` with `disabled(isProcessing || !canShare)`.

Add a `.caption` hint below the Share button: "Fix items with missing names or $0 prices" — shown only when `!canShare && !isProcessing`.

### 4. Better price regex in ReceiptParser

**File:** `meetup-ios/Services/ReceiptParser.swift` — `parseText(_:)`

Replace:

```swift
let pricePattern = #"(\d+\.\d{2})"#
```

With:

```swift
let pricePattern = #"\$(\d+(?:\.\d{1,2})?)|\b(\d+\.\d{1,2})\b"#
```

This captures:
- Group 1: `$`-prefixed prices — `$10`, `$10.5`, `$10.50`
- Group 2: decimal prices without `$` — `10.5`, `10.50`

Update the match extraction to try group 1 first, fall back to group 2:

```swift
let priceStr = Range(match.range(at: 1), in: line).map { String(line[$0]) }
           ?? Range(match.range(at: 2), in: line).map { String(line[$0]) }
```

Add a floor filter: skip any price < 0.01 to avoid matching version numbers or quantities.

## Files Modified

| File | Change |
|------|--------|
| `meetup-ios/Services/BillService.swift` | `computeTotals()` — include $0 participants, sort by total desc |
| `meetup-ios/Views/BillView.swift` | Summary $0 styling, Add Item button + focus, `canShare` validation |
| `meetup-ios/Services/ReceiptParser.swift` | Updated price regex + capture group extraction |

No schema changes. No new files.

## Verification

1. **Summary completeness:** Open a bill where one participant hasn't claimed anything. Open "See totals" → that person should appear at the bottom with "$0.00" and "Hasn't claimed yet".
2. **Add item:** In the preview stage after OCR, tap "Add Item" → a blank row appears with focus on the name field. Enter name and price, then share → new item appears in checklist.
3. **Validation:** In the preview stage, leave an item name blank or set price to 0 → Share button is disabled and hint appears.
4. **Price parsing:** Test with a receipt image containing prices like `$8` and `7.5` → those items should appear in the parsed list.
