import Foundation

public struct ComposeReferences: Equatable {
    public var exact: Set<String>
    public var repositories: Set<String>

    public init(exact: Set<String> = [], repositories: Set<String> = []) {
        self.exact = exact
        self.repositories = repositories
    }

    public static func collect(roots: [String], fs: FileManager, maxDepth: Int = 8) -> ComposeReferences {
        var references = ComposeReferences()
        for root in roots {
            for file in composeFiles(under: root, depth: 0, maxDepth: maxDepth, fs: fs) {
                guard let data = fs.contents(atPath: file) else { continue }
                references.add(contentsOf: String(decoding: data, as: UTF8.self))
            }
        }
        return references
    }

    static func composeFiles(under dir: String, depth: Int, maxDepth: Int, fs: FileManager) -> [String] {
        guard depth <= maxDepth else { return [] }
        var files: [String] = []
        for entry in Walker.entries(of: dir) {
            let path = "\(dir)/\(entry.name)"
            if !entry.isDirectory, isComposeFile(entry.name) {
                files.append(path)
            } else if entry.isDirectory, !BuildArtifactScanner.names.contains(entry.name), entry.name != ".git" {
                files += composeFiles(under: path, depth: depth + 1, maxDepth: maxDepth, fs: fs)
            }
        }
        return files
    }

    static func isComposeFile(_ name: String) -> Bool {
        (name.hasPrefix("docker-compose") || name.hasPrefix("compose")) && (name.hasSuffix(".yml") || name.hasSuffix(".yaml"))
    }

    public mutating func add(contentsOf yaml: String) {
        for line in yaml.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("image:") else { continue }
            var value = trimmed.dropFirst("image:".count).trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]).trimmingCharacters(in: .whitespaces) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { continue }
            add(reference: value)
        }
    }

    public mutating func add(reference: String) {
        if reference.contains("$") {
            let repository = reference.split(separator: "$").first.map(String.init) ?? ""
            let cleaned = repository.hasSuffix(":") ? String(repository.dropLast()) : repository
            if !cleaned.isEmpty { repositories.insert(cleaned) }
            return
        }
        exact.insert(Self.normalize(reference))
    }

    public func protects(_ ref: String) -> Bool {
        let normalized = Self.normalize(ref)
        if exact.contains(normalized) { return true }
        let repository = Self.repository(of: normalized)
        return repositories.contains { repository == $0 || repository.hasPrefix($0) }
    }

    public static func normalize(_ ref: String) -> String {
        let lastSlash = ref.lastIndex(of: "/") ?? ref.startIndex
        return ref[lastSlash...].contains(":") ? ref : ref + ":latest"
    }

    public static func repository(of ref: String) -> String {
        let lastSlash = ref.lastIndex(of: "/") ?? ref.startIndex
        guard let colon = ref[lastSlash...].firstIndex(of: ":") else { return ref }
        return String(ref[..<colon])
    }
}
