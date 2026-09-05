import Foundation

public struct JournalEntry: Codable, Equatable {
    public var at: Date
    public var scanner: ScannerID
    public var id: String
    public var label: String
    public var sizeBytes: Int64
    public var action: String
    public var dryRun: Bool
    public var ok: Bool
    public var error: String?

    public init(at: Date, scanner: ScannerID, id: String, label: String, sizeBytes: Int64, action: String, dryRun: Bool, ok: Bool, error: String?) {
        self.at = at
        self.scanner = scanner
        self.id = id
        self.label = label
        self.sizeBytes = sizeBytes
        self.action = action
        self.dryRun = dryRun
        self.ok = ok
        self.error = error
    }
}

public final class Journal {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func append(_ entry: JournalEntry) throws {
        let fs = FileManager.default
        try fs.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if !fs.fileExists(atPath: path) { fs.createFile(atPath: path, contents: nil) }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: JSONCoding.encoder.encode(entry) + Data("\n".utf8))
    }

    public func read(limit: Int) throws -> [JournalEntry] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").filter { !$0.isEmpty }
        return try lines.suffix(limit).map { try JSONCoding.decoder.decode(JournalEntry.self, from: Data($0.utf8)) }
    }
}
