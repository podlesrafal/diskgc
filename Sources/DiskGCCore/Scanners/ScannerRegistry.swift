import Foundation

public struct ScanResult: Equatable {
    public var candidates: [Candidate]
    public var errors: [String]

    public init(candidates: [Candidate] = [], errors: [String] = []) {
        self.candidates = candidates
        self.errors = errors
    }
}

public enum ScannerRegistry {
    public static let all: [DiskScanner] = [
        ToolCacheScanner(), BuildArtifactScanner(), XcodeScanner(), JetBrainsScanner(), UpdaterCacheScanner(), ClaudeScratchScanner(),
        DockerContainerScanner(), DockerImageScanner(), DockerBuildCacheScanner(), DockerVolumeScanner(), WorktreeScanner(),
    ]

    public static func scan(_ ctx: ScanContext, only: Set<ScannerID>? = nil, scanners: [DiskScanner] = all) -> ScanResult {
        var result = ScanResult()
        for scanner in scanners {
            guard ctx.tier(scanner.id) != .off, only?.contains(scanner.id) ?? true else { continue }
            do {
                result.candidates += try scanner.scan(ctx)
            } catch {
                result.errors.append("\(scanner.id.rawValue): \(error)")
            }
        }
        return result
    }
}
