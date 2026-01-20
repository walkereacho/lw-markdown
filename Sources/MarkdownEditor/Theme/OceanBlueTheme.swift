import AppKit

/// Bright coastal design system - airy, professional, readable.
///
/// Light blues, sky/sea palette. Optimized for focused writing with editorial feel.
/// Primary accent: Ocean Blue (#0284C7)
final class OceanBlueTheme: DesignSystem {

    let name = "Ocean Blue"

    // MARK: - Typography

    let fontFamily = "New York"

    func uiFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        // Use New York for an editorial, readable feel
        if let font = NSFont(name: "NewYork-Regular", size: size) {
            return NSFontManager.shared.convert(font, toHaveTrait: fontTrait(for: weight))
        }
        // Try alternative New York name
        if let font = NSFont(name: "New York", size: size) {
            return NSFontManager.shared.convert(font, toHaveTrait: fontTrait(for: weight))
        }
        // Fallback to system serif
        if #available(macOS 11.0, *) {
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private func fontTrait(for weight: NSFont.Weight) -> NSFontTraitMask {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return .boldFontMask
        default:
            return []
        }
    }

    var monoFont: NSFont {
        return NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    // MARK: - Spacing Scale

    let spacingXS: CGFloat = 4
    let spacingSM: CGFloat = 8
    let spacingMD: CGFloat = 12
    let spacingLG: CGFloat = 16
    let spacingXL: CGFloat = 24

    // MARK: - Corner Radii

    let radiusSM: CGFloat = 4
    let radiusMD: CGFloat = 8
    let radiusLG: CGFloat = 12

    // MARK: - Animation Timing

    let animationFast: TimeInterval = 0.15
    let animationNormal: TimeInterval = 0.25

    // MARK: - Colors

    func colors(for appearance: NSAppearance) -> DesignSystemColors {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? darkColors : lightColors
    }

    // MARK: - Light Appearance Colors (Primary for this theme)

    private var lightColors: DesignSystemColors {
        DesignSystemColors(
            // Shell
            shellBackground: NSColor(hex: "#FFFFFF"),
            shellSecondaryBackground: NSColor(hex: "#F0F7FF"),
            shellBorder: NSColor(hex: "#D1E3F6"),
            shellDivider: NSColor(hex: "#E1EDF8"),

            // Tab Bar
            tabBarBackground: NSColor(hex: "#F7FAFC"),
            tabActiveBackground: NSColor(hex: "#FFFFFF"),
            tabHoverBackground: NSColor(hex: "#EDF4FA"),
            tabText: NSColor(hex: "#64748B"),
            tabActiveText: NSColor(hex: "#0C4A6E"),
            tabDirtyIndicator: NSColor(hex: "#F97316"),

            // Sidebar
            sidebarBackground: NSColor(hex: "#F0F7FF"),
            sidebarItemHover: NSColor(hex: "#E0EFFF"),
            sidebarItemSelected: NSColor(hex: "#DBEAFE"),
            sidebarText: NSColor(hex: "#334155"),
            sidebarSecondaryText: NSColor(hex: "#64748B"),
            sidebarIcon: NSColor(hex: "#0284C7"),

            // Accents
            accentPrimary: NSColor(hex: "#0284C7"),
            accentSecondary: NSColor(hex: "#38BDF8"),
            accentGlow: NSColor(hex: "#38BDF8", alpha: 0.2)
        )
    }

    // MARK: - Dark Appearance Colors

    private var darkColors: DesignSystemColors {
        DesignSystemColors(
            // Shell
            shellBackground: NSColor(hex: "#0C1929"),
            shellSecondaryBackground: NSColor(hex: "#132F4C"),
            shellBorder: NSColor(hex: "#1E4976"),
            shellDivider: NSColor(hex: "#1A3A5C"),

            // Tab Bar
            tabBarBackground: NSColor(hex: "#0C1929"),
            tabActiveBackground: NSColor(hex: "#164E73"),
            tabHoverBackground: NSColor(hex: "#0F3A5C"),
            tabText: NSColor(hex: "#7DD3FC"),
            tabActiveText: NSColor(hex: "#E0F2FE"),
            tabDirtyIndicator: NSColor(hex: "#FB923C"),

            // Sidebar
            sidebarBackground: NSColor(hex: "#0F2942"),
            sidebarItemHover: NSColor(hex: "#164E73"),
            sidebarItemSelected: NSColor(hex: "#1E5A8A"),
            sidebarText: NSColor(hex: "#BAE6FD"),
            sidebarSecondaryText: NSColor(hex: "#7DD3FC"),
            sidebarIcon: NSColor(hex: "#38BDF8"),

            // Accents
            accentPrimary: NSColor(hex: "#38BDF8"),
            accentSecondary: NSColor(hex: "#7DD3FC"),
            accentGlow: NSColor(hex: "#38BDF8", alpha: 0.3)
        )
    }

    // MARK: - Shadows

    func shadow(style: ShadowStyle) -> NSShadow {
        let shadow = NSShadow()

        switch style {
        case .subtle:
            shadow.shadowColor = NSColor(hex: "#0284C7", alpha: 0.08)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2

        case .medium:
            shadow.shadowColor = NSColor(hex: "#0284C7", alpha: 0.15)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 6

        case .glow:
            shadow.shadowColor = NSColor(hex: "#38BDF8", alpha: 0.4)
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.shadowBlurRadius = 8
        }

        return shadow
    }
}
