import Foundation

public struct State: Codable, Equatable {
    public var sizes: [String: SizeEntry]
    public var lastNotifiedAt: Date?
    public var lastWarnedAt: Date?
    public var keptWorktrees: [String]

    public init(sizes: [String: SizeEntry] = [:], lastNotifiedAt: Date? = nil, lastWarnedAt: Date? = nil, keptWorktrees: [String] = []) {
        self.sizes = sizes
        self.lastNotifiedAt = lastNotifiedAt
        self.lastWarnedAt = lastWarnedAt
        self.keptWorktrees = keptWorktrees
    }

    public static func load(from path: String) -> State {
        guard let data = FileManager.default.contents(atPath: path),
              let state = try? JSONCoding.decoder.decode(State.self, from: data) else { return State() }
        return state
    }

    public func save(to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

public enum JSONCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
