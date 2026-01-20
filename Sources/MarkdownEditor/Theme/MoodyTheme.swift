import AppKit

/// Dark-first/Moody design system implementation.
///
/// Deep backgrounds, subtle glows, atmospheric. Optimized for focused writing.
/// Primary accent: Violet (#8B5CF6)
final class MoodyTheme: DesignSystem {

    let name = "Moody"

    // MARK: - Typography

    let fontFamily = "SF Mono"

    func uiFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        // Use SF Mono for a distinctive code-editor feel
        if let font = NSFont(name: "SF Mono", size: size) {
            return NSFontManager.shared.convert(font, toHaveTrait: fontTrait(for: weight))
        }
        // Fallback to monospace system font
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
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

    // MARK: - Dark Appearance Colors (Primary)

    private var darkColors: DesignSystemColors {
        DesignSystemColors(
            // Shell
            shellBackground: NSColor(hex: "#0D0D0D"),
            shellSecondaryBackground: NSColor(hex: "#161616"),
            shellBorder: NSColor(hex: "#2A2A2A"),
            shellDivider: NSColor(hex: "#1F1F1F"),

            // Tab Bar
            tabBarBackground: NSColor(hex: "#0D0D0D"),
            tabActiveBackground: NSColor(hex: "#1E1E1E"),
            tabHoverBackground: NSColor(hex: "#1A1A1A"),
            tabText: NSColor(hex: "#8A8A8A"),
            tabActiveText: NSColor(hex: "#E5E5E5"),
            tabDirtyIndicator: NSColor(hex: "#F97316"),

            // Sidebar
            sidebarBackground: NSColor(hex: "#111111"),
            sidebarItemHover: NSColor(hex: "#1A1A1A"),
            sidebarItemSelected: NSColor(hex: "#1F1F1F"),
            sidebarText: NSColor(hex: "#A3A3A3"),
            sidebarSecondaryText: NSColor(hex: "#6B7280"),
            sidebarIcon: NSColor(hex: "#6B7280"),

            // Quick Open
            quickOpenBackground: NSColor(hex: "#0D0D0D"),
            quickOpenInputBackground: NSColor(hex: "#1A1A1A"),
            quickOpenResultHover: NSColor(hex: "#1F1F1F"),
            quickOpenResultSelected: NSColor(hex: "#252525"),

            // Accents
            accentPrimary: NSColor(hex: "#8B5CF6"),
            accentSecondary: NSColor(hex: "#A78BFA"),
            accentGlow: NSColor(hex: "#8B5CF6", alpha: 0.3)
        )
    }

    // MARK: - Light Appearance Colors (Secondary)

    private var lightColors: DesignSystemColors {
        DesignSystemColors(
            // Shell
            shellBackground: NSColor(hex: "#FAFAFA"),
            shellSecondaryBackground: NSColor(hex: "#FFFFFF"),
            shellBorder: NSColor(hex: "#E5E5E5"),
            shellDivider: NSColor(hex: "#EBEBEB"),

            // Tab Bar
            tabBarBackground: NSColor(hex: "#F5F5F5"),
            tabActiveBackground: NSColor(hex: "#FFFFFF"),
            tabHoverBackground: NSColor(hex: "#EFEFEF"),
            tabText: NSColor(hex: "#737373"),
            tabActiveText: NSColor(hex: "#171717"),
            tabDirtyIndicator: NSColor(hex: "#EA580C"),

            // Sidebar
            sidebarBackground: NSColor(hex: "#F5F5F5"),
            sidebarItemHover: NSColor(hex: "#EBEBEB"),
            sidebarItemSelected: NSColor(hex: "#E5E5E5"),
            sidebarText: NSColor(hex: "#404040"),
            sidebarSecondaryText: NSColor(hex: "#737373"),
            sidebarIcon: NSColor(hex: "#737373"),

            // Quick Open
            quickOpenBackground: NSColor(hex: "#FAFAFA"),
            quickOpenInputBackground: NSColor(hex: "#FFFFFF"),
            quickOpenResultHover: NSColor(hex: "#F5F5F5"),
            quickOpenResultSelected: NSColor(hex: "#EBEBEB"),

            // Accents
            accentPrimary: NSColor(hex: "#7C3AED"),
            accentSecondary: NSColor(hex: "#8B5CF6"),
            accentGlow: NSColor(hex: "#7C3AED", alpha: 0.2)
        )
    }

    // MARK: - Shadows

    func shadow(style: ShadowStyle) -> NSShadow {
        let shadow = NSShadow()

        switch style {
        case .subtle:
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.1)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2

        case .medium:
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 6

        case .glow:
            shadow.shadowColor = NSColor(hex: "#8B5CF6", alpha: 0.4)
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.shadowBlurRadius = 8
        }

        return shadow
    }
}
