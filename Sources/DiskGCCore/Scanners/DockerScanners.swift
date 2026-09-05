import Foundation

public struct DockerContainerScanner: DiskScanner {
    public let id = ScannerID.dockerContainers

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        let probe = DockerProbe(shell: ctx.shell)
        guard probe.available() else { return [] }
        return try probe.containers().compactMap { container in
            guard !container.isRunning else { return nil }
            let stale = ctx.days(since: container.finishedAt ?? container.createdAt)
            guard stale >= ctx.config.inactiveDays.dockerContainer else { return nil }
            return Candidate(
                scanner: id, tier: ctx.tier(id), group: "Docker containers", id: container.id, label: container.name,
                detail: "\(container.status) \(stale)d ago, \(container.imageRef)", sizeBytes: container.sizeRw, staleDays: stale,
                actions: [.run(command: "docker", arguments: ["rm", container.id])]
            )
        }
    }
}

public struct DockerImageScanner: DiskScanner {
    public let id = ScannerID.dockerImages

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        let probe = DockerProbe(shell: ctx.shell)
        guard probe.available() else { return [] }
        let usedImageIDs = Set(try probe.containers().map(\.imageID))
        let protected = ComposeReferences.collect(roots: ctx.config.projectRoots, fs: ctx.fs)
        return try probe.images().compactMap { image in
            guard !usedImageIDs.contains(image.id), !image.tags.contains(where: protected.protects) else { return nil }
            let shortID = String(image.id.dropFirst("sha256:".count).prefix(12))
            let actions: [Action] = image.dangling
                ? [.run(command: "docker", arguments: ["rmi", image.id])]
                : image.tags.map { .run(command: "docker", arguments: ["rmi", $0]) }
            return Candidate(
                scanner: id, tier: ctx.tier(id), group: "Docker images", id: image.id,
                label: image.dangling ? "<none> \(shortID)" : image.tags.joined(separator: ", "),
                detail: image.dangling ? "dangling" : nil, sizeBytes: image.sizeBytes,
                staleDays: ctx.days(since: image.createdAt), actions: actions
            )
        }
    }
}

public struct DockerBuildCacheScanner: DiskScanner {
    public let id = ScannerID.dockerBuildCache

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        let probe = DockerProbe(shell: ctx.shell)
        guard probe.available() else { return [] }
        let size = try probe.buildCacheBytes()
        guard size > 0 else { return [] }
        return [Candidate(
            scanner: id, tier: ctx.tier(id), group: "Docker build cache", id: "docker-build-cache", label: "build cache", detail: "reclaimable",
            sizeBytes: size, staleDays: 0, actions: [.run(command: "docker", arguments: ["builder", "prune", "-af"])]
        )]
    }
}
