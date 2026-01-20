import Foundation

final class CommentPersistence {
    static func commentsFileURL(for documentURL: URL) -> URL {
        let baseName = documentURL.deletingPathExtension().lastPathComponent
        let directory = documentURL.deletingLastPathComponent()
        return directory.appendingPathComponent("\(baseName).comments.json")
    }

    static func load(for documentURL: URL) -> CommentStore {
        let fileURL = commentsFileURL(for: documentURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return CommentStore() }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CommentStore.self, from: data)
        } catch {
            print("Failed to load comments: \(error)")
            return CommentStore()
        }
    }

    static func save(_ store: CommentStore, for documentURL: URL) {
        let fileURL = commentsFileURL(for: documentURL)
        if store.comments.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save comments: \(error)")
        }
    }

    static func hasComments(for documentURL: URL) -> Bool {
        let fileURL = commentsFileURL(for: documentURL)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
