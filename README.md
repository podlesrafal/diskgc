# diskgc

Reclaims disk space on a developer Mac. Tool caches and build artifacts are removed
automatically when free space drops below a target; Docker resources and git worktrees are
only removed after you confirm them in an interactive review.

## Install

```bash
swift build -c release
.build/release/diskgc install
```

`install` copies the binary to `~/.local/bin/diskgc`, writes a default config to
`~/.config/diskgc/config.yaml` and loads a LaunchAgent that runs `diskgc tick` every
30 minutes (and once right away). `diskgc uninstall` removes the agent.

The first run under launchd makes macOS ask whether `diskgc` may access your Documents
folder (project roots live there); the scan blocks until you click Allow. If you decline,
`diskgc status` reports the missing permission and the project scanners find nothing.
Grant it once in System Settings > Privacy & Security > Files and Folders (or Full Disk
Access) for `~/.local/bin/diskgc`. Reinstalling a rebuilt binary may trigger the prompt again.

## Commands

| Command | What it does |
|---|---|
| `diskgc status [--rescan] [--verbose] [--json]` | free space and reclaimable candidates per tier |
| `diskgc tick [--dry-run]` | one pressure cycle: remove auto candidates until the target is reached, notify about the ask tier |
| `diskgc clean [--dry-run] [--all] [--scanner name]` | run the auto tier now; `--all` ignores the target |
| `diskgc review [--dry-run]` | walk through Docker containers, images, volumes, build cache and idle worktrees |
| `diskgc log [--limit n]` | journal of every planned and performed action |
| `diskgc install` / `diskgc uninstall` | manage the LaunchAgent |

## Tiers

**auto** (only while free space is below `target_free_gb`, most stale first):

- tool caches: uv, yarn berry, npm, pnpm store (`pnpm store prune`), go module cache (`go clean -modcache`)
- build artifacts (`node_modules`, `target`, `.angular`, `.nx`, `dist`, `build`, `.next`, `.gradle`) that git ignores, in work trees idle for 7+ days and not the working directory of any running process
- Xcode DerivedData idle 14+ days and superseded iOS DeviceSupport versions
- JetBrains caches and logs of versions idle 30+ days
- updater caches (`*.ShipIt`, `*-updater`, `com.docker.install`) older than 7 days
- Claude Code scratchpads under `/private/tmp/claude-<uid>` idle 14+ days (skipped when they hold a worktree with uncommitted changes)
- stale worktree registrations (`git worktree prune`)

**ask** (macOS notification, then `diskgc review`):

- Docker containers stopped for 3+ days, images not used by any container and not referenced by a compose file under your project roots, dangling volumes, build cache
- linked git worktrees that are clean and idle for 21+ days (`git worktree remove`, never `--force`)

**never**: `~/.m2`, `~/Library/Application Support/Claude`, everything outside the roots each scanner declares.

## Config

`~/.config/diskgc/config.yaml`; every key is optional.

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
scanners:          # auto | ask | off
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

State (size cache, kept worktrees, last notification) lives in `~/.local/share/diskgc/state.json`,
the journal in `~/.local/share/diskgc/journal.jsonl`, launchd output in `~/Library/Logs/diskgc/`.

## Safety

Every deletion goes through one executor that refuses symlinks, paths shallower than four
components, paths outside the scanner's root or equal to it, and anything under `never`.
Docker actions always name explicit ids. Every action is journaled before it runs.

## Development

```bash
swift test
```
