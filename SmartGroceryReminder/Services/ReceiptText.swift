import CoreGraphics

/// One piece of text Vision found, with its box in Vision's normalized coordinates (0...1, origin
/// at the bottom left).
struct TextFragment: Equatable {
    var text: String
    var box: CGRect
}

enum ReceiptText {
    /// Receipt lines, top to bottom. Vision often reports an item's name and its price as separate
    /// pieces; pieces at the same height (within half a typical text height) make one line, read
    /// left to right.
    static func lines(from fragments: [TextFragment]) -> [String] {
        let fragments = fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !fragments.isEmpty else { return [] }
        let heights = fragments.map(\.box.height).sorted()
        let tolerance = heights[heights.count / 2] / 2

        var rows: [(midY: CGFloat, fragments: [TextFragment])] = []
        for fragment in fragments.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.indices.last, abs(rows[last].midY - fragment.box.midY) <= tolerance {
                rows[last].fragments.append(fragment)
                let count = CGFloat(rows[last].fragments.count)
                rows[last].midY += (fragment.box.midY - rows[last].midY) / count
            } else {
                rows.append((fragment.box.midY, [fragment]))
            }
        }
        return rows.map { row in
            row.fragments
                .sorted { $0.box.minX < $1.box.minX }
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
    }
}
