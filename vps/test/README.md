# vps/test — Docker harness for setup-vps.sh

Disposable Docker environments that exercise `vps/setup-vps.sh` across the
scenarios that matter for a real VPS install.

## Running

```bash
cd vps/test
./run-tests.sh              # all scenarios
./run-tests.sh 01           # just the fresh-install scenario
./run-tests.sh resume       # just the resume scenario
```

First run takes ~5–10 min (Ubuntu base + apt downloads + installer scripts).
Subsequent runs reuse layer cache and finish in ~2 min.

## Requirements

- Docker Desktop (macOS/Windows) or rootful Docker (Linux)
- ~2 GB free disk for image layers
- Internet access (installers download from upstream)
- For **scenario 04 only**: Linux host with `--privileged` and
  `--cgroupns=host` support. On Docker Desktop for Mac the runner detects
  the missing capability and emits `SKIP` instead of failing.

## How it tests the local code

`setup-vps.sh` hardcoded the dotfiles repo URL to GitHub. To test the
local working tree, the harness:

1. Mounts the repo root at `/dotfiles-src:ro` inside the container.
2. Sets `DOTFILES_REPO_URL=file:///dotfiles-src` (a recent addition to
   `setup-vps.sh`).
3. Invokes `bash /dotfiles-src/vps/setup-vps.sh` from the mount.

**Caveat:** `git clone file://...` clones from `HEAD`, not the working
tree. Commit (or stash + pop later) before running the harness if you
want uncommitted edits exercised inside the container.

## Scenarios

| # | Name                  | Image    | What it checks |
|---|-----------------------|----------|----------------|
| 01 | fresh-minimal         | minimal  | Clean install with all infra disabled; dotfiles, NVM, UV, Bun, Claude, zsh symlinks |
| 02 | rerun-success         | minimal  | Run twice; second run is idempotent and emits "already installed" for every component |
| 03 | resume-partial        | minimal  | Pre-seeded state file; resume path skips done steps and finishes the rest |
| 04 | full-systemd          | systemd  | All components = y in a privileged systemd container; UFW, fail2ban, Docker, swap all active |

## Layout

```
vps/test/
├── README.md             # this file
├── Dockerfile.minimal    # ubuntu:24.04 + curl/ca/sudo/git
├── Dockerfile.systemd    # jrei/systemd-ubuntu:24.04
├── run-tests.sh          # orchestrator
├── lib/assert.sh         # PASS/FAIL helpers used by scenarios
└── scenarios/
    ├── 01-fresh-minimal.sh
    ├── 02-rerun-success.sh
    ├── 03-resume-partial.sh
    └── 04-full-systemd.sh
```

## Debugging a failed scenario

Each scenario writes its full script log to `/tmp/<container-name>.log` and
cleans up the file on exit. To preserve a log for inspection, comment out
the `rm -f "$LOG_FILE"` line in the `cleanup()` function of the relevant
scenario before re-running.

The container is also removed on exit. To poke around inside a failed
container, comment out the `docker rm -f "$CONTAINER"` line in `cleanup()`
and `docker exec -it <container-name> bash` after the run.

## Adding a new scenario

1. Drop a `scenarios/NN-name.sh` script that sources `lib/assert.sh`.
2. Use one of the existing scenarios as a template — set `CONTAINER`,
   define cleanup, run the script, assert outcomes, call `print_summary`.
3. The orchestrator picks it up automatically on the next `./run-tests.sh`.
