import AppKit

/// Contract for all design systems - swap entire aesthetics by conforming.
///
/// Design systems define typography, spacing, colors, radii, and animations.
/// Implement this protocol to create new themes (Moody, Editorial, Minimal, etc.)
protocol DesignSystem {
    var name: String { get }

    // MARK: - Typography

    /// Primary font family name (e.g., "SF Pro", "Inter")
    var fontFamily: String { get }

    /// Create a UI font with specified size and weight
    func uiFont(size: CGFloat, weight: NSFont.Weight) -> NSFont

    /// Monospace font for code
    var monoFont: NSFont { get }

    // MARK: - Spacing Scale

    /// Extra small spacing: 4pt
    var spacingXS: CGFloat { get }

    /// Small spacing: 8pt
    var spacingSM: CGFloat { get }

    /// Medium spacing: 12pt
    var spacingMD: CGFloat { get }

    /// Large spacing: 16pt
    var spacingLG: CGFloat { get }

    /// Extra large spacing: 24pt
    var spacingXL: CGFloat { get }

    // MARK: - Color Palette

    /// Returns appearance-aware color tokens
    func colors(for appearance: NSAppearance) -> DesignSystemColors

    // MARK: - Corner Radii

    /// Small radius: 4pt
    var radiusSM: CGFloat { get }

    /// Medium radius: 8pt
    var radiusMD: CGFloat { get }

    /// Large radius: 12pt
    var radiusLG: CGFloat { get }

    // MARK: - Animation Timing

    /// Fast animation: 0.15s
    var animationFast: TimeInterval { get }

    /// Normal animation: 0.25s
    var animationNormal: TimeInterval { get }

    // MARK: - Shadows

    /// Create shadow for given style
    func shadow(style: ShadowStyle) -> NSShadow
}

/// Shadow intensity levels
enum ShadowStyle {
    case subtle
    case medium
    case glow
}

/// All color tokens for a design system.
///
/// Returned by `DesignSystem.colors(for:)` to provide appearance-aware colors.
struct DesignSystemColors {

    // MARK: - Shell

    /// Primary background for the window shell
    let shellBackground: NSColor

    /// Elevated surface background
    let shellSecondaryBackground: NSColor

    /// Border color for shell elements
    let shellBorder: NSColor

    /// Hairline divider color
    let shellDivider: NSColor

    // MARK: - Tab Bar

    /// Tab bar background
    let tabBarBackground: NSColor

    /// Active tab background
    let tabActiveBackground: NSColor

    /// Tab hover background
    let tabHoverBackground: NSColor

    /// Inactive tab text color
    let tabText: NSColor

    /// Active tab text color
    let tabActiveText: NSColor

    /// Dirty indicator color (unsaved changes)
    let tabDirtyIndicator: NSColor

    // MARK: - Sidebar

    /// Sidebar background
    let sidebarBackground: NSColor

    /// Sidebar item hover background
    let sidebarItemHover: NSColor

    /// Sidebar item selected background
    let sidebarItemSelected: NSColor

    /// Sidebar primary text color
    let sidebarText: NSColor

    /// Sidebar secondary text color
    let sidebarSecondaryText: NSColor

    /// Sidebar icon tint
    let sidebarIcon: NSColor

    // MARK: - Quick Open

    /// Quick open panel background
    let quickOpenBackground: NSColor

    /// Quick open search input background
    let quickOpenInputBackground: NSColor

    /// Quick open result hover background
    let quickOpenResultHover: NSColor

    /// Quick open result selected background
    let quickOpenResultSelected: NSColor

    // MARK: - Accents

    /// Primary accent color
    let accentPrimary: NSColor

    /// Secondary accent color
    let accentSecondary: NSColor

    /// Glow color for highlights/effects
    let accentGlow: NSColor
}

// MARK: - NSColor Hex Extension

extension NSColor {

    /// Create color from hex string (e.g., "#0D0D0D" or "0D0D0D")
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }

    /// Create color from hex with alpha component
    convenience init(hex: String, alpha: CGFloat) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
