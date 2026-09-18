# diskgc

Reclaims disk space on a developer Mac. Tool caches and build artifacts are removed
automatically when free space drops below a target; Docker resources and git worktrees are
only removed after you confirm them, either in the menu bar app or in an interactive
review on the command line.

`DiskGC.app` sits in the menu bar showing free space, cleans the auto tier on a timer, and
opens a popover listing everything that needs your call, grouped and expandable, so you can
tick the exact images or worktrees to remove.

## Install

```bash
swift build -c release
Scripts/bundle.sh
.build/release/diskgc install
```

`bundle.sh` assembles `.build/DiskGC.app` around the built binary and signs it ad-hoc.
`install` copies that bundle to `~/Applications`, copies the CLI to `~/.local/bin/diskgc`,
writes a default config to `~/.config/diskgc/config.yaml` and loads a LaunchAgent that keeps
the app running from login. The app owns the 30-minute cycle, so there is no scheduled CLI
tick any more. `diskgc uninstall` removes the agent and the installed app.

The first run under launchd makes macOS ask whether the app may access your Documents
folder (project roots live there); the scan blocks until you click Allow. If you decline,
`diskgc status` reports the missing permission and the project scanners find nothing.
Grant it once in System Settings > Privacy & Security > Files and Folders (or Full Disk
Access) for `DiskGC.app` (and for `~/.local/bin/diskgc` if you also use the CLI). The popover
shows a banner with a link to the setting while the permission is missing. Reinstalling a
rebuilt binary may trigger the prompt again.

## Commands

| Command | What it does |
|---|---|
| `diskgc status [--rescan] [--verbose] [--json]` | free space and reclaimable candidates per tier |
| `diskgc tick [--dry-run]` | one pressure cycle by hand; the app runs this on its own every 30 min |
| `diskgc clean [--dry-run] [--all] [--scanner name]` | run the auto tier now; `--all` ignores the target |
| `diskgc review [--dry-run]` | walk through stale build artifacts, Docker containers, images, build cache, anonymous volumes and idle worktrees |
| `diskgc log [--limit n]` | journal of every planned and performed action |
| `diskgc install [--app path]` / `diskgc uninstall` | install or remove the app, the CLI and the LaunchAgent |

## Tiers

**auto** (only while free space is below `target_free_gb`, most stale first):

- tool caches: uv, yarn berry, npm, pnpm store (`pnpm store prune`), go module cache (`go clean -modcache`);
  when the CLI is not installed the store is cleared directly, read-only cache trees included
- build artifacts (`node_modules`, `target`, `.next`, `.gradle`, `.venv`, `__pycache__`, `.terraform`, `Pods`,
  `.turbo`, `dist`, `build`, `out`, `coverage` and friends) that git ignores, last written 7+ days ago, inside a
  git work tree that is not the working directory of any running process. Staleness is the artifact's own age -
  a repo whose git index you touched today can still hold a `node_modules` nobody has rebuilt in a month
- Xcode DerivedData idle 14+ days and superseded iOS DeviceSupport versions
- JetBrains caches and logs of versions idle 30+ days
- updater caches (`*.ShipIt`, `*-updater`, `com.docker.install`) older than 7 days
- Claude Code scratchpads under `/private/tmp/claude-<uid>` idle 14+ days (skipped when they hold a worktree with uncommitted changes)
- stale worktree registrations (`git worktree prune`)

**ask** (macOS notification, then `diskgc review`):

- Docker containers stopped for 3+ days, images not used by any container and not referenced by a compose file under your project roots, build cache
- linked git worktrees that are clean and idle for 21+ days (`git worktree remove`, never `--force`)
- build artifacts that are stale themselves but sit in a repo you are still working in - the auto tier will not
  touch those on its own
- anonymous Docker volumes (`com.docker.volume.anonymous`) that no container uses

**never**: named Docker volumes (a name means someone meant to keep it - remove those yourself with
`docker volume rm`), build artifacts outside a git work tree (nothing proves they are regenerable), `~/.m2`,
`~/Library/Application Support/Claude`, everything outside the roots each scanner declares. Volumes stay in the
ask tier even if the config sets `docker_volumes: auto`.

## Config

`~/.config/diskgc/config.yaml`; every key is optional.

```yaml
target_free_gb: 60
warn_free_gb: 15
warn_cooldown_hours: 3
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

`warn_free_gb` is the low-space alarm: whenever a tick ends below it you get a notification
naming what is left, what the auto tier reclaimed and which actions failed, repeated every
`warn_cooldown_hours`. `notify_min_gb` is unrelated to free space - it only decides how much
has to sit in the ask tier before diskgc nudges you, and it stays quiet while the low-space
alarm is active. Clicking either notification opens the popover.

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
