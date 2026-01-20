import Foundation

/// Manages the currently mounted workspace.
///
/// A workspace is a directory containing files the user is working with.
/// Only one workspace can be mounted at a time.
final class WorkspaceManager: WorkspaceProviding {

    /// Currently mounted workspace root.
    private(set) var workspaceRoot: URL?

    /// Cached file tree (rebuilt on mount and file changes).
    private var cachedTree: FileTreeNode?

    /// Callback when file changes externally.
    var onFileChanged: ((URL) -> Void)?

    /// File watcher for the workspace.
    private var fileWatcher: FileWatcher?

    // MARK: - WorkspaceProviding

    func mountWorkspace(at url: URL) throws {
        // Validate it's a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceError.notADirectory
        }

        // Unmount previous workspace
        unmountWorkspace()

        workspaceRoot = url
        cachedTree = nil

        // Start watching
        fileWatcher = FileWatcher()
        fileWatcher?.onFileChanged = { [weak self] changedURL in
            self?.handleFileChange(changedURL)
        }
        fileWatcher?.onFileCreated = { [weak self] changedURL in
            self?.handleFileChange(changedURL)
        }
        fileWatcher?.onFileDeleted = { [weak self] changedURL in
            self?.handleFileChange(changedURL)
        }
        fileWatcher?.watchWorkspace(at: url)
    }

    func unmountWorkspace() {
        fileWatcher?.stopWatchingWorkspace()
        fileWatcher = nil
        workspaceRoot = nil
        cachedTree = nil
    }

    func fileTree() -> FileTreeNode? {
        guard let root = workspaceRoot else { return nil }

        if let cached = cachedTree {
            return cached
        }

        // Build filtered tree; if root has no markdown files, return empty root node
        if let tree = buildFileTree(at: root) {
            cachedTree = tree
        } else {
            // Return root with empty children if no markdown files found
            cachedTree = FileTreeNode(url: root, isDirectory: true, children: [])
        }
        return cachedTree
    }

    func searchFiles(matching pattern: String) -> [URL] {
        guard let root = workspaceRoot else { return [] }

        var matches: [URL] = []
        let lowercasePattern = pattern.lowercased()

        enumerateFiles(in: root) { url in
            // Only include markdown files
            guard url.pathExtension.lowercased() == "md" else { return }
            if url.lastPathComponent.lowercased().contains(lowercasePattern) {
                matches.append(url)
            }
        }

        return matches.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Private

    private func buildFileTree(at url: URL) -> FileTreeNode? {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDirectory {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let children = contents
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { buildFileTree(at: $0) }

            // Only include directories that contain markdown files
            guard !children.isEmpty else { return nil }

            return FileTreeNode(url: url, isDirectory: true, children: children)
        } else {
            // Only include markdown files
            guard url.pathExtension.lowercased() == "md" else { return nil }

            return FileTreeNode(url: url, isDirectory: false, children: nil)
        }
    }

    private func enumerateFiles(in directory: URL, handler: (URL) -> Void) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory {
                handler(fileURL)
            }
        }
    }

    private func handleFileChange(_ url: URL) {
        // Invalidate cache
        cachedTree = nil
        onFileChanged?(url)
    }
}

enum WorkspaceError: LocalizedError {
    case notADirectory

    var errorDescription: String? {
        switch self {
        case .notADirectory:
            return "The specified path is not a directory."
        }
    }
}
