import Foundation

/// A purchase read from a receipt.
struct ReceiptItem: Equatable {
    var name: String
    var price: Decimal?
    var quantity: Int
}

/// Turns receipt lines into purchases. Receipts differ by store, so this works on the patterns most
/// share: an item line ends in a price (maybe followed by tax-flag letters), totals and payment
/// lines name themselves, and a quantity or weight line refines the item just above it.
enum ReceiptParser {
    static func parse(lines: [String]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []
        // A line with a name but no price: the next line may be its quantity or weight with the price.
        var pendingName: String?

        for raw in lines {
            let line = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !line.isEmpty, !hasSkipWord(line) else {
                pendingName = nil
                continue
            }

            if let count = quantity(in: line) ?? (isWeight(line) ? 1 : nil) {
                let found = price(in: line)
                // Only with a price: a department header ("PRODUCE") above a weight line isn't an item.
                if let name = pendingName, let found, !found.negative {
                    add(ReceiptItem(name: name, price: found.value, quantity: count), to: &items)
                } else if quantity(in: line) != nil, let last = items.indices.last {
                    items[last].quantity = count
                }
                pendingName = nil
                continue
            }

            guard let found = price(in: line) else {
                pendingName = cleanName(line)?.name
                continue
            }
            let previousName = pendingName
            pendingName = nil
            guard !found.negative else { continue }
            if let cleaned = cleanName(found.namePart) {
                add(ReceiptItem(name: cleaned.name, price: found.value, quantity: cleaned.quantity), to: &items)
            } else if found.namePart.isEmpty, let name = previousName {
                // The name on one line and its price alone on the next.
                add(ReceiptItem(name: name, price: found.value, quantity: 1), to: &items)
            }
        }
        return items
    }

    /// The same product on two lines is one purchase with both quantities.
    private static func add(_ item: ReceiptItem, to items: inout [ReceiptItem]) {
        if let index = items.firstIndex(where: { $0.name == item.name }) {
            items[index].quantity += item.quantity
        } else {
            items.append(item)
        }
    }

    // MARK: - Line patterns

    /// Summary, payment and fee lines start or end with one of these ("TOTAL 31.03", "VISA ****
    /// 1234", "BAG FEE 0.10", "YOU SAVED 1.50"). Only the first and last words are checked, so a
    /// product that merely contains one ("GREETING CARD", "CASHEW MIX") is kept.
    private static let leadingSkipWords: Set<String> = [
        "total", "subtotal", "tax", "balance", "change", "cash", "visa", "mastercard", "amex",
        "debit", "credit", "card", "tender", "due", "payment", "savings", "discount", "coupon",
        "points", "auth", "approved", "thank", "receipt", "you", "ebt", "crv", "deposit", "refund",
    ]
    private static let trailingSkipWords: Set<String> = [
        "total", "subtotal", "tax", "due", "change", "savings", "saved", "discount", "coupon",
        "deposit", "fee", "refund", "crv",
    ]

    private static func hasSkipWord(_ line: String) -> Bool {
        let words = line.lowercased().split { !$0.isLetter }.map(String.init)
        guard let first = words.first, let last = words.last else { return false }
        return leadingSkipWords.contains(first) || trailingSkipWords.contains(last)
    }

    /// `name  [-]$1,29[-] [F]` at the end of the line. A minus on either side marks a discount.
    private static let pricePattern = try! NSRegularExpression(
        pattern: #"^(.*?)\s*(-?)\$?(\d{1,4}[.,]\d{2})(-?)(?:\s+[A-Z*]{1,2})?$"#
    )

    private static func price(in line: String) -> (namePart: String, value: Decimal?, negative: Bool)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pricePattern.firstMatch(in: line, range: range),
              let name = Range(match.range(at: 1), in: line),
              let amount = Range(match.range(at: 3), in: line) else { return nil }
        let negative = match.range(at: 2).length > 0 || match.range(at: 4).length > 0
        let value = Decimal(string: line[amount].replacingOccurrences(of: ",", with: "."))
        return (String(line[name]), value, negative)
    }

    /// `2 @ 1.99`, `2 x 1.99`, `3 EA`: how many of the item there were.
    private static let quantityPattern = try! NSRegularExpression(
        pattern: #"^(\d{1,3})\s*(?:@|[xX](?=\s*\d)|EA\b)"#
    )

    private static func quantity(in line: String) -> Int? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = quantityPattern.firstMatch(in: line, range: range),
              let count = Range(match.range(at: 1), in: line) else { return nil }
        return Int(line[count])
    }

    /// `1.52 lb @ 1.99/lb`: a weighed item's detail line.
    private static let weightPattern = try! NSRegularExpression(
        pattern: #"^\d+[.,]\d+\s*(?:lbs?|kg|oz)\b"#, options: .caseInsensitive
    )

    private static func isWeight(_ line: String) -> Bool {
        weightPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    // MARK: - Names

    private static let abbreviations: [String: String] = [
        "ORG": "Organic", "BNLS": "Boneless", "SKNLS": "Skinless", "GAL": "Gallon", "CHKN": "Chicken",
        "BRST": "Breast", "WHL": "Whole", "GRN": "Green", "LG": "Large", "SM": "Small", "PK": "Pack",
    ]

    private static let sizeCode = try! NSRegularExpression(
        pattern: #"^\d+(?:[.,]\d+)?(?:OZ|LB|LBS|CT|G|KG|ML|L|PK)$"#, options: .caseInsensitive
    )

    /// The readable name and a leading quantity (`2 AVOCADOS`): SKU numbers and trailing size
    /// codes dropped, abbreviations spelled out, title case. `nil` without at least two letters.
    static func cleanName(_ raw: String) -> (name: String, quantity: Int)? {
        var tokens = raw.split(separator: " ").map(String.init)
        var quantity = 1
        if let first = tokens.first, first.count <= 2, let count = Int(first), count > 0,
           tokens.count > 1, tokens[1].contains(where: \.isLetter) {
            quantity = count
            tokens.removeFirst()
        }
        // SKU / PLU codes anywhere.
        tokens.removeAll { $0.count >= 4 && $0.allSatisfy(\.isNumber) }
        while let last = tokens.last,
              sizeCode.firstMatch(in: last, range: NSRange(last.startIndex..., in: last)) != nil {
            tokens.removeLast()
        }
        let words = tokens.map { token -> String in
            if let expanded = abbreviations[token.uppercased()] { return expanded }
            guard token.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return token.lowercased() }
            return token.prefix(1).uppercased() + token.dropFirst().lowercased()
        }
        let name = words.joined(separator: " ")
        guard name.filter(\.isLetter).count >= 2 else { return nil }
        return (String(name.prefix(500)), quantity)
    }
}
