import Foundation

public struct XcodeScanner: DiskScanner {
    public let id = ScannerID.xcode

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        derivedData(ctx) + deviceSupport(ctx)
    }

    func derivedData(_ ctx: ScanContext) -> [Candidate] {
        let root = "\(ctx.home)/Library/Developer/Xcode/DerivedData"
        return Walker.subdirectories(of: root, fs: ctx.fs).compactMap { path in
            let stale = ctx.days(since: Walker.newestEntryDate(in: path, fs: ctx.fs))
            guard stale >= ctx.config.inactiveDays.derivedData else { return nil }
            return Candidate(
                scanner: id, tier: ctx.tier(id), group: "Xcode", id: path, label: "DerivedData/" + (path as NSString).lastPathComponent,
                detail: ctx.display(path), sizeBytes: ctx.size(of: path), staleDays: stale,
                actions: [.removeDirectory(path: path, root: root)]
            )
        }
    }

    func deviceSupport(_ ctx: ScanContext) -> [Candidate] {
        let root = "\(ctx.home)/Library/Developer/Xcode/iOS DeviceSupport"
        let dirs = Walker.subdirectories(of: root, fs: ctx.fs)
        let byModel = Dictionary(grouping: dirs) { path in
            String((path as NSString).lastPathComponent.split(separator: " ").first ?? "")
        }
        return byModel.values.flatMap { paths -> [Candidate] in
            let sorted = paths.sorted { Self.version(of: $0).lexicographicallyPrecedes(Self.version(of: $1)) }
            return sorted.dropLast().map { path in
                Candidate(
                    scanner: id, tier: ctx.tier(id), group: "Xcode", id: path, label: "iOS DeviceSupport/" + (path as NSString).lastPathComponent,
                    detail: "superseded by " + (sorted.last! as NSString).lastPathComponent,
                    sizeBytes: ctx.size(of: path), staleDays: ctx.days(since: Walker.modificationDate(path, fs: ctx.fs)),
                    actions: [.removeDirectory(path: path, root: root)]
                )
            }
        }.sorted { $0.id < $1.id }
    }

    static func version(of path: String) -> [Int] {
        let parts = (path as NSString).lastPathComponent.split(separator: " ")
        guard parts.count > 1 else { return [] }
        return parts[1].split(separator: ".").map { Int($0) ?? 0 }
    }
}
