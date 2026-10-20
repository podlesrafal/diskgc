import Foundation

public struct ScanSnapshot: Codable, Equatable {
    public var at: Date
    public var candidates: [Candidate]
    public var errors: [String]

    public init(at: Date, candidates: [Candidate], errors: [String]) {
        self.at = at
        self.candidates = candidates
        self.errors = errors
    }

    public func isFresh(maxAge: TimeInterval, now: Date) -> Bool {
        now.timeIntervalSince(at) < maxAge
    }

    public static func load(from path: String) -> ScanSnapshot? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONCoding.decoder.decode(ScanSnapshot.self, from: data)
    }

    public func save(to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public static func forget(_ ids: Set<String>, at path: String) throws {
        guard !ids.isEmpty, var snapshot = load(from: path) else { return }
        snapshot.candidates.removeAll { ids.contains($0.id) }
        try snapshot.save(to: path)
    }
}
