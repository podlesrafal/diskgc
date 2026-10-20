import SwiftUI
import DiskGCCore

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let issue = model.permissionIssue { banner(issue) }
                    autoSection
                    askSection
                    ForEach(model.otherErrors, id: \.self) { error in
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 420)
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(ByteFormat.string(model.free)) free")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(model.isLow ? Color.red : Color.primary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var subtitle: String {
        if let status = model.status { return status }
        guard let at = model.lastScanAt else { return model.scanning ? "scanning…" : "not scanned yet" }
        let minutes = Int(Date().timeIntervalSince(at) / 60)
        let age = minutes < 1 ? "scanned just now" : "scanned \(minutes) min ago"
        return model.scanning ? "\(age) · refreshing" : age
    }

    private func banner(_ issue: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Can't read every project folder").font(.callout.weight(.medium))
            Text(issue).font(.caption).foregroundStyle(.secondary)
            Button("Open Privacy settings") {
                let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
                NSWorkspace.shared.open(URL(string: url)!)
            }
            .buttonStyle(.link)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var autoSection: some View {
        if !model.autoCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Safe to clean").font(.callout.weight(.medium))
                    Spacer()
                    Text(ByteFormat.string(model.autoBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Clean") { model.clean() }.disabled(model.removing)
                }
                Text(model.autoCandidates.map(\.group).uniqued().joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var askSection: some View {
        if model.selection.groups.isEmpty {
            Text(model.scanning ? "Scanning…" : "Nothing needs your call.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Needs your call").font(.callout.weight(.medium))
                    Spacer()
                    Text(ByteFormat.string(model.askBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                ForEach(model.selection.groups, id: \.name) { group in
                    GroupSection(model: model, group: group)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(model.removeTitle) { model.removeSelected() }
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
                .disabled(model.removing || model.selection.selectedCount == 0)
            HStack(spacing: 12) {
                Button(model.scanning ? "Scanning…" : "Rescan") { model.refresh() }.disabled(model.scanning)
                Button("config.yaml") { NSWorkspace.shared.open(URL(fileURLWithPath: model.configPath)) }
                Button("Log") { NSWorkspace.shared.open(URL(fileURLWithPath: model.journalPath)) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(12)
    }
}

struct GroupSection: View {
    @ObservedObject var model: AppModel
    let group: CandidateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    model.toggleExpanded(group.name)
                } label: {
                    Image(systemName: model.expanded.contains(group.name) ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 10)
                }
                .buttonStyle(.plain)
                CheckBox(state: model.state(of: group)) { model.toggle(group: group.name) }
                Text(group.name).font(.callout)
                Spacer()
                Text(ByteFormat.string(group.sizeBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if model.expanded.contains(group.name) {
                ForEach(group.candidates, id: \.id) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        selected: model.selection.selected.contains(candidate.id),
                        failure: model.failures[candidate.id],
                        toggle: { model.toggle(id: candidate.id) },
                        keep: { model.keep(candidate) }
                    )
                }
            }
        }
    }
}

struct CandidateRow: View {
    let candidate: Candidate
    let selected: Bool
    let failure: String?
    let toggle: () -> Void
    let keep: () -> Void
    @SwiftUI.State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                CheckBox(state: selected ? .all : .none, toggle: toggle)
                Text(candidate.label).font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                if candidate.scanner == .worktrees, hovering {
                    Button(action: keep) { Image(systemName: "lock") }
                        .buttonStyle(.plain)
                        .help("Never offer this worktree again")
                }
                if candidate.staleDays > 0 {
                    Text("\(candidate.staleDays)d").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(ByteFormat.string(candidate.sizeBytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure).font(.caption2).foregroundStyle(.red).padding(.leading, 20)
            }
        }
        .padding(.leading, 16)
        .onHover { hovering = $0 }
    }
}

struct CheckBox: View {
    let state: GroupState
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: symbol)
                .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch state {
        case .none: return "square"
        case .some: return "minus.square.fill"
        case .all: return "checkmark.square.fill"
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
