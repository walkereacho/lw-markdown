import AppKit

/// Protocol for pane managers (implemented by Split Panes module).
///
/// The split panes module manages:
/// - Multiple panes viewing the same document
/// - Independent active paragraph per pane
/// - Split/unsplit operations
protocol PaneManaging {
    /// Number of panes currently showing.
    var paneCount: Int { get }

    /// Split the current pane horizontally.
    func splitHorizontally()

    /// Split the current pane vertically.
    func splitVertically()

    /// Close the current pane (if more than one).
    func closeCurrentPane()

    /// Get the view for embedding in the window.
    var containerView: NSView { get }
}
