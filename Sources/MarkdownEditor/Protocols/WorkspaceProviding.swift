import Foundation

/// Represents a file or folder in the workspace.
struct FileTreeNode {
    let url: URL
    let isDirectory: Bool
    let children: [FileTreeNode]?

    var name: String {
        url.lastPathComponent
    }
}

/// Protocol for workspace providers (implemented by Sidebar module).
///
/// The sidebar module manages:
/// - Mounted workspace directories
/// - File tree enumeration
/// - File watching for external changes
/// - Quick open (Cmd+P) functionality
protocol WorkspaceProviding {
    /// Currently mounted workspace root, if any.
    var workspaceRoot: URL? { get }

    /// Mount a directory as the workspace.
    func mountWorkspace(at url: URL) throws

    /// Unmount current workspace.
    func unmountWorkspace()

    /// Get file tree for current workspace.
    func fileTree() -> FileTreeNode?

    /// Callback when a file changes externally.
    var onFileChanged: ((URL) -> Void)? { get set }

    /// Search files by name pattern for quick open.
    func searchFiles(matching pattern: String) -> [URL]
}
