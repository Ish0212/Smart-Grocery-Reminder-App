import SwiftUI

/// Each aisle gets its own color, so items from the same part of the store read as a group.
enum AisleColor {
    private static let known: [String: Color] = [
        "produce": .green, "fruit": .green, "vegetables": .green,
        "dairy": .blue,
        "bakery": .orange, "bread": .orange,
        "meat": .red, "seafood": .red, "fish": .red,
        "frozen": .cyan,
        "beverages": .teal, "drinks": .teal,
        "pantry": .brown, "canned goods": .brown,
        "snacks": .pink,
        "household": .indigo, "cleaning": .indigo,
        "deli": .mint,
        "health": .purple, "personal care": .purple,
    ]

    /// Aisles outside the list above; the same name always lands on the same color.
    private static let palette: [Color] = [.teal, .purple, .indigo, .mint, .pink, .orange, .blue, .cyan]

    static func color(for aisle: String) -> Color? {
        let key = aisle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        if let color = known[key] { return color }
        // String.hashValue changes every launch, so hash the characters directly.
        let hash = key.unicodeScalars.reduce(UInt(5381)) { $0 &* 33 &+ UInt($1.value) }
        return palette[Int(hash % UInt(palette.count))]
    }
}

/// The aisle as a small tinted capsule. The text stays primary so every color stays readable.
struct AisleChip: View {
    let aisle: String

    var body: some View {
        let color = AisleColor.color(for: aisle) ?? .secondary
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(aisle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// A white symbol on a filled rounded square, like the icons in the Settings app.
struct IconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 29

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}
