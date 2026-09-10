import Foundation

public enum Tier: String, Codable, Sendable {
    case auto, ask, off
}

public enum ScannerID: String, Codable, CaseIterable, Sendable {
    case toolCaches = "tool_caches"
    case buildArtifacts = "build_artifacts"
    case xcode
    case jetbrains
    case updaterCaches = "updater_caches"
    case claudeScratch = "claude_scratch"
    case dockerContainers = "docker_containers"
    case dockerImages = "docker_images"
    case dockerBuildCache = "docker_build_cache"
    case dockerVolumes = "docker_volumes"
    case worktrees
}

public enum Action: Equatable, Codable, Sendable {
    case removeDirectory(path: String, root: String)
    case removeContents(path: String, root: String)
    case run(command: String, arguments: [String])
    case worktreeRemove(repo: String, path: String)
    case worktreePrune(repo: String)
}

public struct Candidate: Equatable, Codable, Sendable {
    public var scanner: ScannerID
    public var group: String
    public var id: String
    public var label: String
    public var detail: String?
    public var sizeBytes: Int64
    public var staleDays: Int
    public var tier: Tier
    public var actions: [Action]

    public init(
        scanner: ScannerID, tier: Tier = .auto, group: String, id: String, label: String, detail: String? = nil,
        sizeBytes: Int64, staleDays: Int, actions: [Action]
    ) {
        self.scanner = scanner
        self.group = group
        self.id = id
        self.label = label
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.staleDays = staleDays
        self.tier = tier
        self.actions = actions
    }
}
