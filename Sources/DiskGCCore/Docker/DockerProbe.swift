import Foundation

public struct DockerContainer: Equatable {
    public var id: String
    public var name: String
    public var status: String
    public var finishedAt: Date?
    public var createdAt: Date?
    public var sizeRw: Int64
    public var imageID: String
    public var imageRef: String

    public var isRunning: Bool { status == "running" || status == "paused" || status == "restarting" }
}

public struct DockerImage: Equatable {
    public var id: String
    public var tags: [String]
    public var sizeBytes: Int64
    public var createdAt: Date?

    public var dangling: Bool { tags.isEmpty }
}

public struct DockerVolume: Equatable {
    public var name: String
    public var sizeBytes: Int64
    public var links: Int
    public var anonymous: Bool

    public var unused: Bool { links == 0 }
}

public struct DockerProbe {
    let shell: ShellRunner

    public init(shell: ShellRunner) {
        self.shell = shell
    }

    public func available() -> Bool {
        (try? shell.run("docker", ["info", "--format", "{{.ServerVersion}}"], cwd: nil))?.succeeded ?? false
    }

    public static let inspectTemplate = "{{.Id}}\t{{.State.Status}}\t{{.State.FinishedAt}}\t{{.Created}}\t{{.SizeRw}}\t{{.Name}}\t{{.Config.Image}}\t{{.Image}}"

    public func containers() throws -> [DockerContainer] {
        let ids = try shell.run("docker", ["ps", "-aq", "--no-trunc"], cwd: nil).stdout.split(separator: "\n").map(String.init)
        guard !ids.isEmpty else { return [] }
        let result = try shell.run("docker", ["inspect", "--size", "--format", Self.inspectTemplate] + ids, cwd: nil)
        return result.stdout.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8 else { return nil }
            return DockerContainer(
                id: fields[0], name: fields[5].hasPrefix("/") ? String(fields[5].dropFirst()) : fields[5], status: fields[1],
                finishedAt: Self.date(fields[2]), createdAt: Self.date(fields[3]),
                sizeRw: Int64(fields[4]) ?? 0, imageID: fields[7], imageRef: fields[6]
            )
        }
    }

    public func images() throws -> [DockerImage] {
        let result = try shell.run("docker", ["images", "-a", "--no-trunc", "--format", "{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"], cwd: nil)
        var order: [String] = []
        var byID: [String: DockerImage] = [:]
        for line in result.stdout.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 else { continue }
            let id = fields[0]
            if byID[id] == nil {
                order.append(id)
                byID[id] = DockerImage(id: id, tags: [], sizeBytes: HumanSize.bytes(fields[3]), createdAt: Self.date(fields[4]))
            }
            if fields[1] != "<none>", fields[2] != "<none>" {
                byID[id]?.tags.append("\(fields[1]):\(fields[2])")
            }
        }
        return order.compactMap { byID[$0] }
    }

    struct VolumeRow: Decodable {
        var name: String
        var size: String
        var links: String
        var labels: String

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case size = "Size"
            case links = "Links"
            case labels = "Labels"
        }
    }

    public static let anonymousLabel = "com.docker.volume.anonymous"

    public func volumes() throws -> [DockerVolume] {
        let result = try shell.run("docker", ["system", "df", "-v", "--format", "{{json .Volumes}}"], cwd: nil)
        guard let data = result.stdout.data(using: .utf8),
              let rows = try? JSONDecoder().decode([VolumeRow].self, from: data) else { return [] }
        return rows.map { row in
            DockerVolume(
                name: row.name, sizeBytes: HumanSize.bytes(row.size), links: Int(row.links) ?? 0,
                anonymous: row.labels.contains(Self.anonymousLabel)
            )
        }
    }

    struct DfRow: Decodable {
        var type: String
        var reclaimable: String

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case reclaimable = "Reclaimable"
        }
    }

    public func buildCacheBytes() throws -> Int64 {
        let result = try shell.run("docker", ["system", "df", "--format", "{{json .}}"], cwd: nil)
        for line in result.stdout.split(separator: "\n") {
            guard let row = try? JSONDecoder().decode(DfRow.self, from: Data(line.utf8)), row.type == "Build Cache" else { continue }
            return HumanSize.bytes(row.reclaimable)
        }
        return 0
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let imageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    public static func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("0001-") || trimmed.isEmpty || trimmed == "<nil>" { return nil }
        if trimmed.count > 10, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 10)] == "T" {
            var normalized = trimmed
            if let dot = normalized.firstIndex(of: "."), let z = normalized.lastIndex(of: "Z") {
                normalized.removeSubrange(dot..<z)
            }
            return isoFormatter.date(from: normalized)
        }
        let parts = trimmed.split(separator: " ").prefix(3).joined(separator: " ")
        return imageDateFormatter.date(from: parts)
    }
}
