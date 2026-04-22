import SwiftUI

// MARK: - Liquid Glass conditional modifiers (macOS 26+)

/// Applies `.glassEffect()` on macOS 26 (Tahoe) and later;
/// falls back to `.background(.ultraThinMaterial)` on earlier OS versions.
struct AdaptiveGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(in: .rect(cornerRadius: 10))
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

/// Replaces `.background(.ultraThinMaterial)` — on macOS 26+, removes the
/// background entirely so the system Liquid Glass on NavigationSplitView
/// sidebars can show through unobstructed.
struct AdaptiveSidebarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content  // no custom background — let system glass show through
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

/// Applies `.buttonStyle(.glassProminent)` on macOS 26+, falling back to
/// `.buttonStyle(.borderedProminent)` on older OS versions.
struct AdaptiveGlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    /// Glass background on macOS 26+, `.ultraThinMaterial` fallback.
    func adaptiveGlassBackground() -> some View {
        modifier(AdaptiveGlassBackground())
    }

    /// Removes custom sidebar background on macOS 26+ to let system glass work.
    func adaptiveSidebarBackground() -> some View {
        modifier(AdaptiveSidebarBackground())
    }

    /// Prominent glass button style on macOS 26+, bordered prominent fallback.
    func adaptiveGlassButtonStyle() -> some View {
        modifier(AdaptiveGlassButtonStyle())
    }
}
