# diskgc menu bar app

## Problem

The low-space notification tells you something is wrong and then leaves you alone.
Acting on it means opening a terminal and running `diskgc review`, which walks groups
in a fixed order and offers no way to see what is inside one before saying yes.
The result is that the notification gets dismissed and the disk stays full.

A menu bar app puts the free-space number in view all the time and turns the
ask tier into a list you can open, inspect and act on with one click.

## Scope

A `DiskGCBar` executable target that renders a `MenuBarExtra` popover over the
existing `DiskGCCore` library, a bundling script that assembles `DiskGC.app`, and
the installer changes that make the app — rather than the CLI — own the periodic tick.

The CLI keeps every command it has today. `DiskGCCore` gains two things: a `Runtime`
(extracted from the CLI's `Environment`, so both front ends compose the same world)
and a `CandidateSelection` (grouping and selection logic, kept out of the view so it
can be tested).

## Architecture

```
Package.swift
├── DiskGCCore      library    scanners, Tick, Executor, Runtime, CandidateSelection
├── diskgc          executable CLI, unchanged except install/uninstall
└── DiskGCBar       executable SwiftUI MenuBarExtra over DiskGCCore

Scripts/bundle.sh   assembles .build/DiskGC.app (Info.plist, ad-hoc signature)
```

`DiskGCBar` holds no disk logic. Scanning, tier decisions, path safety and journaling
stay in Core; the app decides only what to draw and what the user picked.

Candidates are already per-item — `Candidate.id` identifies one Docker image or one
worktree, and `Candidate.group` names its section — so expandable groups with per-row
checkboxes need no scanner changes.

### Runtime extraction

`Sources/diskgc/Environment.swift` composes config, state, journal, executor and
`activeCwds`, but lives in the CLI target where the app cannot see it. It moves to
`Sources/DiskGCCore/Runtime/Runtime.swift` and the CLI is repointed at it. Without
this the app would duplicate the `~/.config/diskgc/…` path layout and the two front
ends would drift apart on the first change.

### CandidateSelection

A plain Swift type in Core, no SwiftUI import: groups candidates by `group`, tracks
selected ids, computes per-group tri-state and the selected total, and merges a
selection across a rescan. Tested in `DiskGCCoreTests` alongside the existing suites.

## Popover

```
◯ 42 GB  ← menu bar: symbol + free space, red below warn_free_gb

Safe to clean — 4.2 GB                    [ Clean ]
  npm/uv/go caches, DerivedData, JetBrains
─────────────────────────────────────────────────
Needs your call — 31 GB
▾ ☑ Docker images                          18.4 GB
    ☑ gravitee/am-gw:3.21                   4.2 GB
    ☐ node:22                               0.9 GB
▸ ☐ Docker build cache                      6.1 GB
▾ ☐ Git worktrees                           1.6 GB
    ☐ Fonvo/wt-bp572          34d  0.8 GB      🔒
─────────────────────────────────────────────────
  [ Remove 3 items · up to 23.3 GB ]
  Rescan · config.yaml · Log · Quit
```

The safe section is the auto tier as one button (`clean --all`); those paths rebuild
themselves, so per-item choice would be busywork. Below the target threshold the auto
tier already runs on its own, but above it nothing is reclaimed, which is exactly when
a one-click clean before a large build is useful.

The ask section is per-item. Nothing is selected by default: the checkboxes are the
confirmation, so there is no modal. The button names its own effect and is disabled
while the selection is empty.

The lock icon appears on hover over a worktree row and writes to `state.keptWorktrees`,
the same list `diskgc review`'s `k` key writes, so the worktree stops being offered.

### Docker sizes are upper bounds

`docker images --format {{.Size}}` reports total size including shared layers, so
twelve images on one base count that base twelve times. The button therefore promises
"up to X" and the result line reports what was actually reclaimed, measured from
`DiskSpace.freeBytes` before and after.

## Behaviour

**Freshness.** The popover opens immediately on the last scan, labelled with its age.
Opening it rescans in the background only when that scan is older than ten minutes;
Rescan forces one. A full scan runs `lsof`, `du` and `docker system df` and can take
minutes, so removal never waits for it: Remove stays enabled while a scan is in flight,
and only Clean (the auto tier, which the tick also touches) is disabled.

**Scan cache.** Every scan and tick writes `~/.local/share/diskgc/last-scan.json`. A cold
start shows that snapshot at once and ticks only when it is older than ten minutes;
removed and kept items are dropped from it so they do not reappear after a restart.

**Serialisation.** Tick, Rescan and Keep run through one serial scan queue, so
`state.json` keeps a single writer. Remove and Clean run on a separate queue; the
journal serialises its own appends. Items removed while a scan is running are filtered
out of that scan's result. While the popover is open the timer defers to the next
cycle, so rows never vanish under the pointer.

**Selection across refresh.** Selection is held by `Candidate.id`. Rows that survive a
refresh stay selected, rows that disappeared drop out silently, new rows arrive
unselected, and the button total is recomputed.

**After removal.** Removed rows disappear immediately and free space is re-read from the
filesystem rather than assumed; no rescan follows. A failed
removal leaves its row in place carrying `ExecutionResult.message`.

**Notifications.** `Tick` keeps its logic; `UserNotificationsNotifier` replaces the
message with an actionable one that opens the popover. The alarm fires below
`warn_free_gb`, after the auto tier has already run, so the only useful action left is
reviewing the ask tier — hence one click rather than a second button that would have
nothing to reclaim. If the notification centre refuses authorisation the app falls back
to the existing `OSAScriptNotifier`.

**Errors.** No permission to read `~/Documents` shows a banner linking to System
Settings (`Walker` already reports this). Docker not running marks its groups
unavailable and leaves the rest scanning. Scan errors already travel in `ScanResult.errors`.

## Lifecycle and install

The app starts from the existing LaunchAgent, repointed at the bundle's binary with
`KeepAlive` and a `ThrottleInterval` (a crash loop in a `KeepAlive` agent would
otherwise restart forever), and `StartInterval` dropped because the app owns its timer.
The label is unchanged, so installing replaces the CLI agent rather than adding a second one.

```
swift build -c release
Scripts/bundle.sh          → .build/DiskGC.app
diskgc install             → ~/Applications/DiskGC.app
                           → ~/.local/bin/diskgc
                           → LaunchAgent, reloaded
```

`diskgc uninstall` removes both. `status`, `clean`, `review` and `log` are untouched.

Bundle id `dev.rpo.diskgc`, `LSUIElement` set so there is no Dock icon, SF Symbols for
the menu bar rather than a drawn icon. The app installs to `~/Applications`, which needs
no sudo. macOS will ask for Documents access again, because the request is bound to the
new binary.

## Interface language

English throughout, including the popover, the notifications and the three Polish
strings in `Tick.swift`, whose assertions in `PolicyTests` move with them.

## Testing

`CandidateSelection` and `Runtime` are tested in `DiskGCCoreTests` with the existing
`FakeShell` helpers: grouping, tri-state, selected totals, selection merged across a
rescan, and the config/state/journal paths `Runtime` resolves. The SwiftUI views hold
no logic and are verified by running the built app and clicking through it.

## Out of scope

A config editor in the UI (the footer opens `config.yaml`), usage history or charts,
undo, Sparkle updates, notarisation, and a drawn app icon.
