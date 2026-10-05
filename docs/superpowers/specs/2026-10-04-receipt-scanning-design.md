# Receipt Scanning: Design

Date: 2026-10-04. This is item 3 of the pre-launch roadmap, after the reliability suite (PR #14) and offline editing (PR #15).

## Goal

After shopping, a person photographs the receipt. The app reads the purchased items on the device, lets them correct what it read, and then updates the list in two ways:
- it checks off the list items they bought;
- it adds the other purchases as already bought.

Both count as "bought by you", so the unload reminder at home knows what's in the car.

For the resume, this shows image processing (Vision OCR, grouping text into rows by bounding box) and data parsing (receipt-line heuristics, fuzzy matching against the list), plus a correction UI.

## Flow

1. On the list, a toolbar button **Scan Receipt** (`doc.text.viewfinder`) offers **Take Photo** (only where a camera exists) and **Choose Photo** (`PhotosPicker`).
2. The **Review Receipt** sheet shows "Reading receipt…" while Vision runs. Then it shows one row per item it found:
   - an editable name;
   - the price as read, in grey;
   - an action picker: **Check off "<list item>"** when it matches an open list item, otherwise **Add as bought**; plus **Skip**.
   - The default is check-off when there's a match, otherwise add as bought.
3. **Apply** carries out the decisions and closes the sheet. If nothing was found: "No items found. Try a flatter, well-lit photo." with a button to try again.

## Components

- **`ReceiptText` (`Services/ReceiptText.swift`):** a pure function that groups text observations into rows.
  - Each `TextFragment` is `{ text, box: CGRect }` in Vision's normalised coordinates, with the origin at the bottom left.
  - Fragments whose vertical midpoints are within half the median fragment height of each other share a row.
  - Rows run top to bottom, and fragments within a row run left to right, joined with a space.
  - Receipts often put the name and the price in separate observations; grouping rejoins them.
- **`ReceiptParser` (`Services/ReceiptParser.swift`):** `parse(lines: [String]) -> [ReceiptItem]`, where `ReceiptItem` is `{ name, price: Decimal?, quantity: Int }`. It is pure.
  - **Item line:** text, then a price `\d+[.,]\d{2}`, optionally followed by tax or flag letters (`A`, `F`, `T`, `N`, `*`, or `B`). The name is everything before the price.
  - **Skipped lines:** any line containing, as a whole word, a summary or payment keyword: total, subtotal, tax, balance, change, cash, visa, mastercard, amex, debit, credit, card, tender, due, payment, savings, discount, coupon, points, auth, approved, member, thank, receipt. Also lines with a negative price (`-1.00` or `1.00-`), and lines that look like a date, time or phone number but have no item name.
  - **Name cleanup:**
    - drop leading SKU or PLU numbers (4 or more digits) and trailing unit or size codes left after the price is removed;
    - collapse spaces;
    - expand a short list of abbreviations (`ORG` → Organic, `BNLS` → Boneless, `SKNLS` → Skinless, `GAL` → gallon, `CHKN` → Chicken, `BRST` → Breast, `WHL` → Whole, `GRN` → Green, `LG` → Large, `SM` → Small, `PK` → pack);
    - title-case the result.
    - A name needs at least 2 letters.
  - **Quantity lines:** a line like `2 @ 0.99`, `2 x 0.99` or `3 EA` sets the quantity of the item on the previous line and isn't an item itself. A weight line like `1.23 lb @ 0.59/lb` belongs to the previous item and is skipped.
  - **Duplicates:** the same name appearing again on separate lines is merged by adding the quantities together.
- **`ReceiptMatcher` (`Services/ReceiptMatcher.swift`):** `match(_ item: ReceiptItem, in open: [GroceryItem]) -> GroceryItem?`, which is pure.
  - Normalise by lowercasing, keeping only letters and spaces, and dropping a trailing "s" from words of 4 or more letters. Ignore stop words such as "organic", "large", "small", "fresh", "pack" and "gallon".
  - It's a match when every significant word of the list item appears among the receipt item's words ("Bananas" matches "Organic Bananas"), or the other way round.
  - When several items match, the one with the most shared words wins, and earlier items in the list win a tie.
  - Each list item is matched at most once per receipt; the caller tracks which ones are used.
- **`TextRecognizer` protocol, `VisionTextRecognizer` (`Services/TextRecognizer.swift`):** `recognize(_ image: CGImage) async throws -> [TextFragment]`.
  - Uses `VNRecognizeTextRequest` with `.accurate`, language correction off (receipts are codes, not prose), and `en-US`.
  - Runs on the device only; the photo is never stored or uploaded.
- **`AppState.applyReceipt(_ decisions: [ReceiptDecision])`:** `ReceiptDecision` is `.checkOff(itemId)`, `.addBought(name)` or `.skip`.
  - A check-off sends the completion patch from PR #15, and only for items that are still open.
  - An add-as-bought upserts `GroceryItem(title:, isCompleted: true, completedBy: me)`.
  - It returns the counts, which a confirmation shows ("Checked off 3, added 2").
- **UI (`Views/ReceiptScanView.swift`):** a `ReceiptReviewModel` (`@MainActor ObservableObject`) runs recognition and parsing, then builds rows with their default actions. The views are thin.
- **`Info.plist`:** `NSCameraUsageDescription` is "Take a photo of a receipt to check off what you bought. The photo stays on your iPhone." `PhotosPicker` needs no permission.
- **Privacy docs:** a note in `docs/app-store/privacy-label.md` and `site/privacy.html` that receipt photos are read on the device and not kept. The label doesn't change.

## Testing

- `ReceiptTextTests`: name and price fragments on one row are joined in order; rows are ordered top to bottom; a slight tilt still groups correctly.
- `ReceiptParserTests`, using a realistic sample receipt as fixture lines:
  - items are extracted with their prices;
  - totals, tax, payment, date and phone lines are skipped;
  - a quantity line attaches to its item;
  - a weight line is skipped;
  - a negative or discount line is skipped;
  - SKUs are stripped;
  - abbreviations are expanded;
  - flag letters after the price are ignored;
  - a comma decimal works;
  - duplicates merge.
- `ReceiptMatcherTests`: a plural or extra adjective still matches; an unrelated item doesn't; the most shared words wins; stop words alone never match.
- `ReceiptReviewModelTests`: a fake recognizer produces default actions (check off when matched, otherwise add); two receipt lines never claim the same list item; an empty result gives the "no items" state.
- `AppState` tests: `applyReceipt` checks off with your `completedBy` through a completion-only patch; adds bought items as completed by you; skips; ignores a check-off of an item that's already done.
- `VisionTextRecognizerTests`: render "MILK 3.49" into an image and recognise it in the simulator, expecting "MILK" and "3.49". If Vision can't run in this simulator, the test calls `XCTSkip`, and the skip is visible in the CI log.

## Out of scope

- Live camera scanning (VisionKit `DataScannerViewController`). A still photo is enough.
- Saving receipts or prices, or spending history.
- Store-specific formats, or machine-learning models beyond Vision's built-in text recognition.
- Languages other than English, or currencies without two decimal places.
