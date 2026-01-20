import AppKit

extension Notification.Name {
    /// Posted when the design system changes
    static let designSystemDidChange = Notification.Name("designSystemDidChange")
}

/// Manages the current design system and provides runtime switching.
///
/// Views observe `designSystemDidChange` notification to update their appearance.
/// Use `ThemeManager.shared` to access the singleton instance.
final class ThemeManager {

    /// Shared singleton instance
    static let shared = ThemeManager()

    /// Current design system
    let currentDesignSystem: DesignSystem = OceanBlueTheme()

    /// Convenience: current colors for the effective appearance
    var colors: DesignSystemColors {
        let appearance = NSApp.effectiveAppearance
        return currentDesignSystem.colors(for: appearance)
    }

    /// Current design system (shorthand)
    var current: DesignSystem {
        currentDesignSystem
    }

    private var appearanceObserver: NSKeyValueObservation?

    private init() {
        observeAppearanceChanges()
    }

    /// Subscribe to design system changes
    /// - Parameter handler: Called when design system or appearance changes
    /// - Returns: Observer token (retain to keep observing)
    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: .designSystemDidChange,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    // MARK: - Appearance Observation

    private func observeAppearanceChanges() {
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            // Re-post notification when system appearance changes
            NotificationCenter.default.post(name: .designSystemDidChange, object: nil)
        }
    }

    // MARK: - Reduce Motion Support

    /// Whether to reduce motion for accessibility
    var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Animation duration respecting reduce motion preference
    func animationDuration(_ base: TimeInterval) -> TimeInterval {
        return reduceMotion ? 0 : base
    }
}

// MARK: - View Theming Helper

extension NSView {

    /// Apply theme and observe for changes.
    ///
    /// Call from `viewDidMoveToWindow()` or similar lifecycle method.
    /// Returns an observer token that must be retained.
    ///
    /// ```swift
    /// private var themeObserver: NSObjectProtocol?
    ///
    /// override func viewDidMoveToWindow() {
    ///     super.viewDidMoveToWindow()
    ///     themeObserver = observeTheme { [weak self] in
    ///         self?.applyTheme()
    ///     }
    /// }
    /// ```
    func observeTheme(_ applyTheme: @escaping () -> Void) -> NSObjectProtocol {
        applyTheme()
        return ThemeManager.shared.observeChanges(applyTheme)
    }
}
