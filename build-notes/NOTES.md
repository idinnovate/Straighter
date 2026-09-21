# Build notes: first IronFox 156.0 arm64 build

A record of the first successful build of this fork (unmodified IronFox at `v156.0`),
what it took, and what to do differently next time. Nothing in here is a secret; keep
it that way (no IPs, keys, passphrases, or tokens) because this repo may be public.

## Result

| Item | Value |
|---|---|
| Base | IronFox `v156.0` (commit `d43fd712`), branch `my-browser` |
| Output | `ironfox-nightly-156.0-arm64-v8a-debug-signed.apk` (157 MB) |
| SHA-256 | `aac3509e6625227256eb6af789d80925f95332027e494388208f82a6b389cd17` |
| State | Unmodified IronFox, **debug-signed**, **no Safe Browsing** (no Google API key). Test build only, not for publishing |

## Environment that worked

- DigitalOcean Basic droplet: 8 vCPU, 16 GiB RAM, 320 GB disk, Ubuntu 24.04 LTS host, $0.143/h.
- Docker from Ubuntu's `docker.io` package (29.1.3).
- Image built from the repo's own `Dockerfile` (Fedora 44, clang 22.1.8, Go `yq` 4.53.3).
- Repo mounted at `/app` in the container; build run by `run_docker_build.sh` inside `tmux`.
- **Swap: 16 GB + 32 GB swap files were added mid-build** (see "Memory" below).

## Timings (UTC, 2026-09-20)

| Stage | Duration |
|---|---|
| Docker image build | about 3.5 min |
| `get_sources.sh` | about 9 min |
| `prebuild.sh` | about 1 min |
| `build.sh arm64` | **4 h 22 min** (18:17 to 22:39) |

Within `build.sh`: the parallel compile took about 57 minutes on 8 vCPUs; the rest was
the `libxul.so` link and Android (Gradle) packaging. Total droplet uptime by the time the
APK was copied off was about 11 hours, mostly idle after the build finished. Destroy
the droplet as soon as the artifact is safe.

## How to reproduce

1. Fresh Ubuntu droplet with at least 16 GiB RAM (32 GiB or more is better, see below).
2. `sudo apt-get install -y docker.io git tmux`; add your user to the `docker` group.
3. Clone the fork, check out the release tag/branch.
4. Copy `run_docker_build.sh` to the droplet and start it in `tmux`:
   `tmux new-session -d -s dbuild "bash ~/run_docker_build.sh"`.
5. Follow `~/build-docker.status` and `~/build-docker.log`.
6. The APK appears in `outputs/apk/` inside the repo directory.

The script mirrors upstream's `scripts/run-docker.sh` flow but is unattended: it builds
the image, creates the container, trusts the mounted directory for git
(`safe.directory`), then runs `get_sources`, `prebuild`, and `build arm64`, stopping at
the first failure and writing a status file.

## Problems hit and how they were resolved

### Native Ubuntu build (abandoned; see `ubuntu-attempts/`)

1. **`bootstrap.sh`: `sudo: command not found`.** `env.sh` replaces `PATH` with a minimal
   directory of symlinks that does not include `sudo`. The Ubuntu branch also runs
   `apt upgrade` without `-y`, which blocks unattended. Workaround: install the same
   apt package list by hand (plus plain `clang`, since scripts expect `/usr/bin/clang`).
2. **`prebuild.sh`: patch names wrapped in quotes** (`"a-c-...patch"`). Ubuntu's apt
   package `yq` is the Python jq wrapper, which prints JSON-quoted strings; the scripts
   need Go `yq` (mikefarah), which is what Fedora ships. Workaround: install the official
   release binary (checksum verified against GitHub's published digest) and point the
   build at it with `IRONFOX_YQ`.
3. **`build.sh` stops on a missing Safe Browsing key.** If `IRONFOX_SB_GAPI_KEY_FILE` is
   unset it asks `Do you want to continue [y/N]`; with no input that counts as "no".
   Piping a `y` continues without Safe Browsing.
4. **Re-running leaves prompts.** A leftover `external/phoenix/outputs/android` from a
   previous attempt triggers another confirmation prompt. Use a fresh tree.
5. **`mach configure` deadlocked twice** on Ubuntu (single thread in a futex wait, 0% CPU,
   no children, no network; over 2 hours the second time). Not root-caused. It did not
   happen in the Fedora container, so the Docker route is the recommended one.

### Mistake worth not repeating

`pkill -f "<pattern>"` run over SSH matched the SSH command line itself and killed the
session (exit 255). Kill by PID or use `tmux kill-session`.

### Memory

The mozconfig enables full LTO (`ac_add_options --enable-lto='full'`, and
`-flto=full` in the compiler flags). The final `ld.lld` link of `libxul.so` was
single-threaded and very memory hungry: about 13 GB resident and 27.8 GB virtual after
55 minutes, with 13.4 GB of swap in use. The final peak was **not** observed.
Without swap this link would have been OOM-killed on a 16 GiB machine.

For the next build, either:

- use a machine with more RAM (32 GiB or more) so it does not depend on swap, or
- consider thin LTO (a config change that forces a recompile and changes the
  optimization of the shipped app, so decide deliberately).

## Still to do for a real release

- Rebrand: package ID, app name, icons, strings, update URLs (about 26 files reference the
  package ID; most other "ironfox" hits are internal `IRONFOX_*` variable names and do not
  need renaming).
- Add the extension as a new patch applied by `prebuild`.
- Create a release keystore and configure signing (env-var driven in `env_common.sh`).
- Obtain a Safe Browsing API key so release builds include phishing protection.
- Keep the fork current: rebase onto each new upstream tag.

## Files in this folder

| File | What it is |
|---|---|
| `run_docker_build.sh` | The unattended Docker build driver that worked |
| `build-stages.txt` | Start/end timestamps of each stage |
| `build-docker-tail.txt` | Last 300 lines of the successful build log |
| `build-docker.log.gz` | Full successful build log (compressed) |
| `ubuntu-attempts/run_build_ubuntu_native.sh` | The native Ubuntu driver (with the `IRONFOX_YQ` workaround) |
| `ubuntu-attempts/build.log.attempt1` | Native Ubuntu run that hung in `mach configure` (first hang) |
| `ubuntu-attempts/build.log.attempt2` | Re-run stopped by the leftover-directory prompt |
| `ubuntu-attempts/build.log.attempt3` | Native Ubuntu run that hung in `mach configure` (second hang) |

The native-Ubuntu `get_sources` and `prebuild` logs were not saved off the droplet.
