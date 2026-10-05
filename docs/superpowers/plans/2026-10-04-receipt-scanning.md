# Receipt Scanning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Photograph a receipt; Vision reads it on the device; the person corrects the results; then the app checks off matching list items and adds the rest as already bought.

**Architecture:** Pure stages: `ReceiptText.rows(from:)` (text fragments → lines) → `ReceiptParser.parse(lines:)` (lines → items) → `ReceiptMatcher.match` (items → list items). A thin `VisionTextRecognizer` sits behind a `TextRecognizer` protocol and runs off the main actor, with the photo's orientation. A `ReceiptReviewModel` drives the review UI, and `AppState.applyReceipt` writes the changes.

**Tech Stack:** Swift 5 mode, SwiftUI, PhotosUI, Vision, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-04-receipt-scanning-design.md`

## Global Constraints

- No Mac: tests run in CI (PR-only), so open a draft PR at Task 0.
- Recognition happens on the device only. The photo is never stored or uploaded, and prices are never persisted.
- Titles follow the rules' limits: non-empty, 500 characters at most. Trim names and skip empty ones.
- A check-off never un-checks: build the completion patch directly, and only for items that are still open. Never call `toggleItem`.
- Vision's `perform` runs off the main actor.
- The orientation is passed to Vision.

## Review Focus

1. **Portrait camera photo (EXIF orientation):** rows, not columns. Pinned in Task 3 by a test on a rotated bitmap.
2. **Scanning the same receipt twice:** items stay checked off, and the additions are duplicated. The duplication is accepted and noted in the README. Pinned in Task 4 ("already done is ignored").
3. **Two receipt lines with the same match:** only the first claims the list item (greedy, in receipt order). Pinned in Task 5.
4. **A photo that can't be decoded** (`UIImage`/`cgImage` is nil): shows the "couldn't read that photo" state. Pinned in Task 5 (the model's `failed` state).
5. **Vision returns nothing:** the "No items found" state, not a crash. Pinned in Task 5.

---

### Task 0: Branch, draft PR, ledger

### Task 1: `ReceiptText` + `ReceiptParser`

**Files:** Create `Services/ReceiptText.swift` and `Services/ReceiptParser.swift`. Tests: `ReceiptTextTests.swift`, `ReceiptParserTests.swift`.

**Produces:**
- `struct TextFragment { text: String; box: CGRect }`;
- `enum ReceiptText { static func lines(from: [TextFragment]) -> [String] }`;
- `struct ReceiptItem: Equatable { name: String; price: Decimal?; quantity: Int }`;
- `enum ReceiptParser { static func parse(lines: [String]) -> [ReceiptItem] }`.

**Parser decisions:**
- Price regex at the end of the line: `(-?)\$?(\d{1,4}[.,]\d{2})(-?)` followed by optional flags `(\s+[A-Z*]{1,2})?$`.
- A minus sign on either side means a discount, so the line is skipped.
- Comma decimals become `.` before `Decimal(string:)`.
- A leading integer of 1–2 digits followed by a space and letters is the quantity (`2 BANANAS 1.98` → quantity 2).
- A leading run of 4 or more digits is a SKU and is dropped.
- A quantity line matches `^(\d{1,3})\s*(@|x|X|EA)\b`, and a weight line matches `^\d+[.,]\d+\s*(lb|kg|oz)\b` (case-insensitive). Both modify or skip the previous item and are never items themselves.

**Fixture:** a realistic receipt containing a store header, address, phone, date and time, about 10 items (with a SKU, abbreviations, flags, `$`, a comma decimal, a quantity line, a weight line and a coupon), then subtotal, tax, total, VISA, change and a thank-you line.

- [ ] Write the tests, implement, and commit. CI runs in the batch push.

### Task 2: `ReceiptMatcher`

**Produces:** `enum ReceiptMatcher { static func match(_ item: ReceiptItem, in open: [GroceryItem]) -> GroceryItem?; static func words(_ s: String) -> Set<String> }`.

- [ ] Tests:
  - "Organic Bananas" matches "Bananas";
  - "Milk 2% Gal" matches "Milk";
  - "Bread" matches neither "Butter" nor "Breadcrumbs" (matching is on whole words);
  - the item with the most shared words wins;
  - stop words alone never match;
  - an empty list matches nothing.
- [ ] Implement and commit.

### Task 3: `TextRecognizer` + Vision, with orientation

**Files:** Create `Services/TextRecognizer.swift`. Test: `VisionTextRecognizerTests.swift`.

**Produces:** `protocol TextRecognizer { func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [TextFragment] }`, `struct VisionTextRecognizer: TextRecognizer`, and `extension CGImagePropertyOrientation { init(_ uiOrientation: UIImage.Orientation) }`.

- [ ] Implement:
  - `withCheckedThrowingContinuation` + `DispatchQueue.global(qos: .userInitiated).async`;
  - `VNImageRequestHandler(cgImage:orientation:)`;
  - `VNRecognizeTextRequest` with `.accurate`, `usesLanguageCorrection = false`, `recognitionLanguages = ["en-US"]`;
  - each observation becomes a `TextFragment(topCandidates(1).first.string, boundingBox)`.
- [ ] Tests:
  - render two lines of black text on white, at about 1000×400 px, with `UIGraphicsImageRenderer`, then recognise them;
  - rotate the bitmap 90° clockwise, pass `.right`, and expect the same lines in the same order through `ReceiptText.lines`;
  - the `UIImage.Orientation` mapping, for all 8 cases.
  - Skip only if Vision throws. An empty result fails the test.

### Task 4: `AppState.applyReceipt`

**Produces:** `enum ReceiptDecision: Equatable { case checkOff(itemId: String), addBought(name: String), skip }` and `struct ReceiptResult: Equatable { checkedOff: Int; added: Int }`. In AppState: `@discardableResult func applyReceipt(_ decisions: [ReceiptDecision]) async -> ReceiptResult`.

- [ ] Tests:
  - a check-off sends a completion-only patch with your uid;
  - an add creates an item completed by you;
  - a skip does nothing;
  - a check-off of an item that's already done is ignored and not counted;
  - an empty name is skipped.
- [ ] Implement: check-off uses the `ItemPatch` completion path (local apply, then `update`); add uses `upsert`. Commit.

### Task 5: Review model, UI, plist

**Files:** Create `Views/ReceiptScanView.swift` (`ReceiptReviewModel` + views) and `SmartGroceryReminderTests/ReceiptReviewModelTests.swift`. Modify `Views/ShoppingListView.swift` (toolbar) and `Info.plist`.

**Produces:** `@MainActor final class ReceiptReviewModel: ObservableObject`:
- `enum Phase { case reading, ready, empty, failed }`;
- `@Published var phase`, `@Published var rows: [Row]`;
- `struct Row: Identifiable { id; var name: String; price: Decimal?; match: GroceryItem?; var action: Action }`;
- `enum Action { checkOff, add, skip }`;
- `init(recognizer: TextRecognizer)`;
- `func read(_ image: UIImage?, openItems: [GroceryItem]) async`;
- `var decisions: [ReceiptDecision]`.

- [ ] Tests, with a fake recognizer:
  - default actions;
  - greedy claiming so two lines can't take the same item;
  - empty → `.empty`;
  - a nil image or one without `cgImage` → `.failed`;
  - a recognizer error → `.failed`;
  - `decisions` uses the edited names, a check-off whose row is switched to add uses that name, and skip leaves it out.
- [ ] **UI:** a toolbar `Menu` labelled "Scan Receipt" (`doc.text.viewfinder`) with "Take Photo" (only if `UIImagePickerController.isSourceTypeAvailable(.camera)`, through a `UIViewControllerRepresentable` camera picker) and "Choose Photo" (`PhotosPicker`, `loadTransferable(type: Data.self)`). Then a review sheet: `Form` rows with a `TextField`, the price, and a `Picker` for the action; Apply / Cancel; and the empty and failed states with a "Try Another Photo" button.
- [ ] `Info.plist`: `NSCameraUsageDescription`.
- [ ] Commit, push, CI.

### Task 6: Docs

- [ ] `privacy-label.md` gets a note; `site/privacy.html` gets a sentence; the README gets a "Receipt scanning" section listing the pipeline and the parser rules, noting that scanning the same receipt twice adds the unmatched items again.

### Task 7: Final review, fix pass, merge on green.
