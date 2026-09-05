# diskgc — design

Date: 2026-09-05

## Problem

The machine (MacBook Pro M4 Pro, 494 GB APFS container) runs out of disk space repeatedly.
An inventory on 2026-09-05 found 23 GB free and roughly 100 GB of regenerable data:
stopped Docker containers and unused images (~30 GB), build artifacts inside git worktrees
(`node_modules`, `target`, `.angular`, `.nx`; ~20 GB), package-manager caches (uv 11 GB,
yarn 6 GB, go 3 GB, pnpm 2 GB), caches of uninstalled IDE versions (JetBrains 2026.1, 7 GB),
Xcode DerivedData and old iOS DeviceSupport (9 GB), updater caches (4 GB) and Claude Code
scratchpads (1 GB).

`diskgc` reclaims this continuously and safely, with the user deciding about anything
that is not trivially regenerable.

## Decisions taken with the user

- Tool caches and build artifacts are removed automatically.
- Docker resources and git worktrees are only removed after the user confirms.
- Private files, `~/.m2`, and the Claude Desktop VM bundles are never touched.
- Implementation language is Swift (SwiftPM package). The core is a library so a later
  menu-bar app can reuse it. Phase 1 is a CLI plus a LaunchAgent.

## Tiers

| Tier | Scanners | Trigger |
|---|---|---|
| `auto` | tool caches, build artifacts, Xcode, JetBrains, updater caches, Claude scratchpads | only under pressure: free space below `target_free_gb` (default 60). Candidates are removed most-stale-first until the target is reached. |
| `ask` | Docker containers, images, build cache, volumes; git worktrees | a macOS notification summarises reclaimable size; the user decides in `diskgc review`. |
| `never` | configured paths, anything outside a scanner's root | never, including manual commands. |

Auto runs only under pressure on purpose: deleting `node_modules` of an idle worktree while
200 GB are free only costs a rebuild.

## Scanners

Every scanner produces `Candidate` values: an identity (path or Docker resource id), a
human label, the group it belongs to, size in bytes, staleness in days, the tier, and the
action needed to remove it. Scanners do not invent data: they shell out to `du`, `git`,
`docker`, `xcrun`, `lsof` and parse the output.

### Auto tier

**tool_caches** — fixed list, each with a probe path and an action:

| Name | Path | Action |
|---|---|---|
| uv | `~/.cache/uv` | remove directory contents (equivalent to `uv cache clean`, no PATH dependency under launchd) |
| yarn-berry | `~/.yarn/berry/cache` | remove directory contents |
| pnpm | `~/Library/pnpm/store` | `pnpm store prune` |
| npm | `~/.npm/_cacache` | remove directory contents |
| go-mod | `~/go/pkg/mod` (or `GOMODCACHE`) | `go clean -modcache` (module files are read-only) |

Staleness is the age of the newest entry in the directory. Size is `du -sk`.

**build_artifacts** — walk `project_roots` (default `~/Documents/Projects`) to depth 12
(Maven multi-module trees nest `target` directories up to 11 levels deep),
skipping `.git` and never descending into a matched directory. A directory named
`node_modules`, `target`, `.angular`, `.nx`, `dist`, `build`, `.next` or `.gradle` is a
candidate only when all of these hold:

1. it lies inside a git work tree (nearest ancestor containing `.git`),
2. git ignores it (`git check-ignore -q`), which separates `build/` artifacts from `build/`
   scripts,
3. the work tree has been inactive for at least `inactive_days.build_artifacts` (default 7),
   measured as the mtime of the work tree's git `index` file (`git rev-parse --git-dir`),
4. no running process has its working directory inside the work tree (`lsof -d cwd`),
   which protects trees served by a dev server.

Action: recursive delete.

**xcode** — `~/Library/Developer/Xcode/DerivedData/<project>` directories whose mtime is
older than `inactive_days.derived_data` (default 14); `~/Library/Developer/Xcode/iOS DeviceSupport/<model> <version>`
directories that are not the newest version for their model. Action: recursive delete.

**jetbrains** — `~/Library/Caches/JetBrains/<product><version>` and
`~/Library/Logs/JetBrains/<product><version>` whose newest top-level entry is older than
`inactive_days.jetbrains` (default 30). Action: recursive delete.

**updater_caches** — `~/Library/Caches/*.ShipIt`, `~/Library/Caches/*-updater`,
`~/Library/Application Support/com.docker.install`, entries older than 7 days.
Action: recursive delete.

**claude_scratch** — session directories under `/private/tmp/claude-<uid>/<project>/<session>`
whose mtime is older than `inactive_days.claude_scratch` (default 14). If a session contains
a git worktree (a `.git` file) with uncommitted or untracked changes the session is skipped.
Action: recursive delete, then `git worktree prune` in every parent repository referenced
by a removed worktree.

### Ask tier

**docker_containers** — containers in state `exited`, `created` or `dead` whose
`State.FinishedAt` is older than `inactive_days.docker_container` (default 3). Size is
`SizeRw` from `docker ps -as`. Action: `docker rm <id>`. One group.

**docker_images** — images not used by any container (running or stopped) and not
referenced by an `image:` line in any `docker-compose*.yml` / `compose*.yml` under
`project_roots` (matched on `repository:tag`, untagged means `latest`). Dangling images are
always candidates. Action: `docker rmi <id>`. One group.

**docker_build_cache** — total from `docker builder du`. Action: `docker builder prune -af`.

**docker_volumes** — `docker volume ls --filter dangling=true`. Sizes from
`docker system df -v`. Action: `docker volume rm <name>`. Reviewed one by one because
names reveal databases.

Groups are recomputed before each group is reviewed, so removing containers makes their
images and volumes eligible in the same session.

**worktrees** — for every repository under `project_roots` (a `.git` directory, depth ≤ 4,
not inside `node_modules`), `git worktree list --porcelain`. A linked worktree (never the
main checkout) is a candidate when:

1. `git status --porcelain` is empty (no modified, staged or untracked files),
2. it has been inactive for at least `inactive_days.worktree` (default 21), by index mtime,
3. no running process has its working directory inside it.

Removing a worktree removes neither the branch nor its commits; only uncommitted changes
could be lost, and rule 1 excludes that. Action: `git worktree remove <path>` without
`--force`, ever. The user can mark a worktree "keep" during review; it is then excluded
until the mark is cleared.

Registered worktrees whose directory no longer exists are pruned automatically: the
worktree scanner emits an `auto`-tier candidate per repository (`git worktree prune` removes
only bookkeeping).

## Safety

All destructive work goes through one `Executor`:

- a filesystem candidate must be a real directory (not a symlink), must have at least four
  path components, must lie under the root its scanner declared, must not equal that root,
  and must not lie under a `never` path;
- Docker actions always name explicit ids; `docker system prune` is never used;
- git actions never pass `--force`;
- every action is written to the journal before it runs, with a `dryRun` flag;
- `--dry-run` is available on every command that deletes.

Deletions are permanent (no Trash): the candidates are regenerable by definition, and a
`node_modules` in the Trash frees nothing.

## Pressure loop

`diskgc tick` (run by launchd):

1. Read free space of the data volume.
2. If the size cache is older than `rescan_hours` (default 6) or missing, rescan all
   scanners; otherwise reuse cached sizes for unchanged paths (key: path + mtime).
3. While free space is below `target_free_gb` and auto candidates remain, remove the next
   candidate (ordered by staleness descending, then size descending) and re-read free
   space.
4. If the total size of ask candidates is at least `notify_min_gb` (default 5) and the last
   notification is older than `notify_cooldown_hours` (default 24), post a notification:
   `diskgc: 28 GB do przejrzenia (Docker 24 GB, worktree 4 GB). Uruchom: diskgc review`.

The process lowers its own I/O priority (launchd `ProcessType: Background`, `Nice: 10`).

## CLI

| Command | Behaviour |
|---|---|
| `diskgc status [--rescan] [--json]` | free space, candidates per tier and group with sizes |
| `diskgc tick [--dry-run]` | the pressure loop above |
| `diskgc clean [--dry-run] [--scanner name] [--all]` | run the auto tier now; `--all` ignores the pressure target and removes every stale candidate |
| `diskgc review [--dry-run]` | interactive walk through ask groups in the order containers, images, volumes, build cache, worktrees. Containers, images and build cache are decided per group (`y` remove all, `n` skip, `l` list, `q` quit); volumes and worktrees are decided item by item (`y`, `n`, `k` keep forever for worktrees, `q`). |
| `diskgc install` / `diskgc uninstall` | copy the binary to `~/.local/bin/diskgc`, write and load `~/Library/LaunchAgents/dev.rpo.diskgc.plist` (StartInterval 1800, RunAtLoad), create a default config if missing |
| `diskgc log [--limit n]` | print the journal |

Output is plain text tables; `--json` on `status` is for the future menu-bar app.

## Files

- Config `~/.config/diskgc/config.yaml` (YAML via Yams). Missing file means defaults.
- State `~/.local/share/diskgc/state.json`: size cache, last notification per group, kept
  worktrees.
- Journal `~/.local/share/diskgc/journal.jsonl`: timestamp, scanner, label, size, action,
  dryRun, result.
- Logs `~/Library/Logs/diskgc/`.

Default config:

```yaml
target_free_gb: 60
notify_min_gb: 5
notify_cooldown_hours: 24
rescan_hours: 6
project_roots:
  - ~/Documents/Projects
inactive_days:
  build_artifacts: 7
  worktree: 21
  docker_container: 3
  derived_data: 14
  jetbrains: 30
  claude_scratch: 14
scanners:
  tool_caches: auto
  build_artifacts: auto
  xcode: auto
  jetbrains: auto
  updater_caches: auto
  claude_scratch: auto
  docker_containers: ask
  docker_images: ask
  docker_build_cache: ask
  docker_volumes: ask
  worktrees: ask
never:
  - ~/.m2
  - ~/Library/Application Support/Claude
```

Any scanner may be set to `auto`, `ask` or `off` in the config.

## Package layout

```
Package.swift                     swift-tools 6.0, Swift 5 language mode
Sources/DiskGCCore/
  Model/        Candidate, Tier, Group, Action
  Config/       Config (Codable, defaults, YAML loading)
  Shell/        ShellRunner protocol, ProcessShell, argument-level API
  FS/           SizeProbe (du), DiskSpace (statfs), PathSafety, Walker
  Git/          GitProbe (toplevel, git-dir, check-ignore, status, worktree list)
  Docker/       DockerProbe (ps, images, volumes, builder du, compose references)
  Scanners/     one type per scanner, all conforming to Scanner
  Policy/       PressurePlanner (ordering, stop condition)
  Executor/     Executor (safety checks, actions, journal)
  State/        State, Journal
  System/       Notifier (osascript), LaunchAgent (plist), ProcessCwd (lsof)
Sources/diskgc/ ArgumentParser commands
Tests/DiskGCCoreTests/
```

Dependencies: `swift-argument-parser`, `Yams`. Nothing else.

## Testing

- Unit tests use a `FakeShell` that returns recorded `docker`/`git`/`lsof` output, and
  temporary directories for filesystem scanners. Git scanners are also tested against a
  real temporary repository with a linked worktree, created in the test.
- `PathSafety` and `Executor` refusal paths are tested exhaustively (symlink, short path,
  outside root, equals root, under never).
- Final verification is `diskgc status --rescan` and `diskgc tick --dry-run` on the real
  machine, compared with the inventory table from 2026-09-05.

## Out of scope (phase 1)

iOS simulators and Android AVDs, browser caches, personal files (`~/Downloads`), the
menu-bar app. The core library is shaped so that the menu-bar app is a thin consumer of
`status --json` data and the same executor.
