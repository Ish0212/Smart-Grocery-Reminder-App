import SwiftUI

/// Liquid Glass on iOS 26, the closest older style before it (the pattern IceCubesApp uses).
/// The compiler check keeps an older Xcode, which lacks the glass APIs, building.
extension View {
    /// The main action on a screen: opaque, tinted glass.
    @ViewBuilder
    func prominentGlassButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    /// A secondary action: clear glass.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
        #else
        buttonStyle(.bordered)
        #endif
    }

    /// Shrinks the glass tab bar while the list scrolls down, leaving more room for content.
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
