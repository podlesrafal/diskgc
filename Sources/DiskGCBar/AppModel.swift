import Foundation
import DiskGCCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var free: Int64 = 0
    @Published private(set) var target: Int64 = 0
    @Published private(set) var warn: Int64 = 0
    @Published private(set) var autoCandidates: [Candidate] = []
    @Published private(set) var selection = CandidateSelection()
    @Published private(set) var errors: [String] = []
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var lastScanAt: Date?
    @Published private(set) var status: String?
    @Published private(set) var scanning = false
    @Published private(set) var removing = false
    @Published var expanded: Set<String> = []

    static let rescanAfter: TimeInterval = 10 * 60

    let configPath: String
    let journalPath: String
    private let engine: Engine
    private var dismissedDuringScan: Set<String> = []

    init(engine: Engine, configPath: String, journalPath: String) {
        self.engine = engine
        self.configPath = configPath
        self.journalPath = journalPath
    }

    var busy: Bool { scanning || removing }

    var isStale: Bool {
        guard let lastScanAt else { return true }
        return Date().timeIntervalSince(lastScanAt) >= Self.rescanAfter
    }

    var autoBytes: Int64 { autoCandidates.reduce(0) { $0 + $1.sizeBytes } }

    var askBytes: Int64 { selection.groups.reduce(0) { $0 + $1.sizeBytes } }

    var isLow: Bool { warn > 0 && free < warn }

    var menuBarTitle: String { "\(ByteFormat.gigabytes(free)) GB" }

    var permissionIssue: String? { errors.first { $0.contains("no permission to read") } }

    // Docker reports image sizes with shared layers counted per image, so a selection that
    // includes them can only promise an upper bound.
    var removeTitle: String {
        let picked = selection.selectedCandidates
        let size = ByteFormat.string(selection.selectedBytes)
        let bound = picked.contains { $0.scanner.rawValue.hasPrefix("docker") } ? "up to " : ""
        return "Remove \(picked.count) \(picked.count == 1 ? "item" : "items") · \(bound)\(size)"
    }

    var otherErrors: [String] { errors.filter { !$0.contains("no permission to read") } }

    func start() {
        engine.restore { [weak self] outcome in
            guard let self else { return }
            if case .success(let snapshot?) = outcome, lastScanAt == nil { show(snapshot) }
            if isStale { tick() }
        }
    }

    func refreshIfStale() {
        if isStale { refresh() }
    }

    func refresh() {
        guard !scanning else { return }
        beginScan()
        engine.scan { [weak self] in self?.finishScan($0) }
    }

    func tick() {
        guard !busy else { return }
        beginScan()
        engine.tick { [weak self] in self?.finishScan($0) }
    }

    func clean() {
        execute(autoCandidates)
    }

    func removeSelected() {
        execute(selection.selectedCandidates)
    }

    func keep(_ candidate: Candidate) {
        dismiss([candidate.id])
        engine.keep(worktree: candidate.id) { _ in }
    }

    func state(of group: CandidateGroup) -> GroupState {
        selection.state(ofGroup: group.name)
    }

    func toggle(id: String) {
        selection.toggle(id: id)
    }

    func toggle(group: String) {
        selection.toggle(group: group)
    }

    func toggleExpanded(_ group: String) {
        if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) }
    }

    private func execute(_ candidates: [Candidate]) {
        guard !removing, !candidates.isEmpty else { return }
        removing = true
        status = nil
        failures = [:]
        engine.execute(candidates) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success(let done):
                free = done.free
                failures = Dictionary(uniqueKeysWithValues: done.results.filter { !$0.ok }.map { ($0.candidate.id, $0.message) })
                let removed = Set(done.results.filter(\.ok).map(\.candidate.id))
                dismiss(removed)
                engine.forget(removed)
                status = "Freed \(ByteFormat.string(done.freed))"
            case .failure(let error):
                errors = [String(describing: error)]
            }
            removing = false
        }
    }

    private func dismiss(_ ids: Set<String>) {
        if scanning { dismissedDuringScan.formUnion(ids) }
        autoCandidates.removeAll { ids.contains($0.id) }
        selection.update(candidates: selection.groups.flatMap(\.candidates).filter { !ids.contains($0.id) })
    }

    private func beginScan() {
        scanning = true
        dismissedDuringScan = []
    }

    private func finishScan(_ outcome: Result<ScanOutcome, Error>) {
        switch outcome {
        case .success(var scan):
            scan.candidates.removeAll { dismissedDuringScan.contains($0.id) }
            show(scan)
        case .failure(let error):
            errors = [String(describing: error)]
        }
        dismissedDuringScan = []
        scanning = false
    }

    private func show(_ scan: ScanOutcome) {
        free = scan.free
        target = scan.target
        warn = scan.warn
        autoCandidates = scan.auto
        selection.update(candidates: scan.ask)
        errors = scan.errors
        lastScanAt = scan.at
    }
}
