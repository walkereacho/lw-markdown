import AppKit
import Highlightr

/// Service wrapper for syntax highlighting using Highlightr.
/// Provides NSAttributedString output for code blocks with per-language coloring.
final class SyntaxHighlighter {

    /// Shared instance for convenience.
    static let shared = SyntaxHighlighter()

    /// The underlying Highlightr instance.
    private let highlightr: Highlightr?

    /// Cache for highlighted code to avoid repeated highlighting.
    /// Key: "\(language):\(code.hashValue)", Value: highlighted attributed string
    private var cache: [String: NSAttributedString] = [:]

    /// Maximum cache size to prevent memory bloat.
    private let maxCacheSize = 100

    /// Current theme name being used.
    private(set) var currentThemeName: String = "atom-one-dark"

    // MARK: - Initialization

    init() {
        self.highlightr = Highlightr()

        // Set initial theme based on system appearance
        updateThemeForAppearance()

        // Observe appearance changes
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }

    // MARK: - Theme Management

    /// Updates the highlight.js theme to match the current system appearance.
    func updateThemeForAppearance() {
        let appearance = NSApp.effectiveAppearance
        let isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let themeName = isDarkMode ? "atom-one-dark" : "github"
        setTheme(themeName)
    }

    /// Sets a specific highlight.js theme.
    /// - Parameter name: The theme name (e.g., "atom-one-dark", "github", "monokai")
    func setTheme(_ name: String) {
        highlightr?.setTheme(to: name)
        currentThemeName = name
        clearCache()
    }

    /// Returns available theme names.
    var availableThemes: [String] {
        highlightr?.availableThemes() ?? []
    }

    @objc private func appearanceDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateThemeForAppearance()
        }
    }

    // MARK: - Highlighting

    /// Highlights code with the specified language.
    /// - Parameters:
    ///   - code: The source code to highlight.
    ///   - language: The language identifier (e.g., "swift", "python", "javascript").
    ///               If nil or unknown, returns plain monospace text.
    /// - Returns: An attributed string with syntax highlighting applied, or nil if highlighting failed.
    func highlight(code: String, language: String?) -> NSAttributedString? {
        guard let highlightr = highlightr else {
            return nil
        }

        // Normalize language identifier
        let normalizedLanguage = normalizeLanguage(language)

        // Check cache
        let cacheKey = "\(normalizedLanguage ?? "plain"):\(code.hashValue)"
        if let cached = cache[cacheKey] {
            return cached
        }

        // Perform highlighting
        let highlighted: NSAttributedString?
        if let lang = normalizedLanguage {
            highlighted = highlightr.highlight(code, as: lang, fastRender: true)
        } else {
            // No language specified - use auto-detection or plain text
            highlighted = highlightr.highlight(code, fastRender: true)
        }

        // Cache result
        if let result = highlighted {
            cacheResult(result, forKey: cacheKey)
        }

        return highlighted
    }

    /// Checks if a language is supported for syntax highlighting.
    /// - Parameter language: The language identifier to check.
    /// - Returns: True if the language is supported.
    func isLanguageSupported(_ language: String?) -> Bool {
        guard let lang = language, !lang.isEmpty else {
            return false
        }
        let normalized = normalizeLanguage(lang)
        return normalized != nil && highlightr?.supportedLanguages().contains(normalized!) == true
    }

    /// Returns list of supported languages.
    var supportedLanguages: [String] {
        highlightr?.supportedLanguages() ?? []
    }

    // MARK: - Cache Management

    /// Clears the highlighting cache.
    func clearCache() {
        cache.removeAll()
    }

    private func cacheResult(_ result: NSAttributedString, forKey key: String) {
        // Evict oldest entries if cache is full
        if cache.count >= maxCacheSize {
            // Simple eviction: remove half the cache
            let keysToRemove = Array(cache.keys.prefix(maxCacheSize / 2))
            for k in keysToRemove {
                cache.removeValue(forKey: k)
            }
        }
        cache[key] = result
    }

    // MARK: - Language Normalization

    /// Normalizes language identifiers to Highlightr-compatible names.
    /// Handles common aliases and variations.
    private func normalizeLanguage(_ language: String?) -> String? {
        guard let lang = language?.lowercased().trimmingCharacters(in: .whitespaces), !lang.isEmpty else {
            return nil
        }

        // Map common aliases to Highlightr language names
        let aliases: [String: String] = [
            "js": "javascript",
            "ts": "typescript",
            "py": "python",
            "rb": "ruby",
            "sh": "bash",
            "shell": "bash",
            "zsh": "bash",
            "yml": "yaml",
            "objc": "objectivec",
            "objective-c": "objectivec",
            "c++": "cpp",
            "c#": "csharp",
            "cs": "csharp",
            "md": "markdown",
            "dockerfile": "docker",
            "make": "makefile"
        ]

        return aliases[lang] ?? lang
    }
}
