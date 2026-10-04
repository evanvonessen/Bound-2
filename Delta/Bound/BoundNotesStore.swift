import Foundation

/// Fresh local notes, partitioned by Delta's game identifier. No existing Bound saves are opened.
final class BoundNotesStore {
    private let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BoundDeltaNotes", isDirectory: true)) {
        self.directory = directory
    }
    func url(game: String) -> URL? {
        guard !game.isEmpty, game.utf8.count <= 128, game.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return directory.appendingPathComponent(game).appendingPathExtension("txt")
    }
    func read(game: String) throws -> String {
        guard let url = url(game: game) else { throw BoundFriendError.unavailable }
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 16001) ?? Data()
        guard data.count <= 16000, let text = String(data: data, encoding: .utf8) else { throw BoundFriendError.unavailable }
        return text
    }
    func write(_ text: String, game: String) throws {
        guard let url = url(game: game), text.utf8.count <= 16000 else { throw BoundFriendError.unavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
