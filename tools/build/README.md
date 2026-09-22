# Building a Straighter release

`docker-build.sh` builds Straighter unattended in upstream's Fedora Docker image, signs it,
and checks the result. Run it on a Linux build machine with Docker, never on a machine you
care about: the build is large (tens of GB of disk, many hours) and needs your keys for a
while.

## Before you start (once)

| What | How |
|---|---|
| Signing key | `tools/signing/generate-keystore.sh`, then back it up (see `tools/signing/README.md`) |
| Safe Browsing key | `tools/build/store-safebrowsing-key.sh`, which asks for it at a hidden prompt |
| Up to date | Rebase onto the newest upstream IronFox tag, run `tools/brand/rebrand_strings.py` and `tools/brand/make_assets.py` if files changed, and commit. A release must be built from a clean commit |

Both keys end up in folders outside the repository (`~/.straighter-signing`,
`~/.straighter-secrets`), readable only by you. The Safe Browsing key is compiled into the
APK, so anyone can extract it: restrict it to the Safe Browsing API in the Google Cloud
console and set a quota alert.

## Build machine

Memory decides how the build goes. The final link of `libxul.so` uses full link-time
optimization and needed about 13 GB of RAM plus 13 GB of swap on the first build, so use a
machine with **32 GB of RAM or more** and **at least 150 GB of disk**, or add swap. Install
Docker, `git` and `tmux`, and add your user to the `docker` group.

1. Clone the repository fresh and check out the commit you are releasing. A tree that has
   already been built cannot be built again from the start.

2. Copy the keys in, into folders only you can read:

   ```bash
   ssh builder@HOST 'mkdir -p -m 700 ~/signing ~/secrets'
   ```

   ```bash
   scp ~/.straighter-signing/{straighter-release.jks,keystore.pass,signing-cert-fingerprints.txt} builder@HOST:signing/
   ```

   ```bash
   scp ~/.straighter-secrets/sb-gapi-key.txt builder@HOST:secrets/
   ```

3. Start the build in `tmux`, so it survives a dropped connection:

   ```bash
   tmux new-session -d -s build 'tools/build/docker-build.sh --release --sign ~/signing --sb-key ~/secrets/sb-gapi-key.txt'
   ```

4. Watch it:

   ```bash
   cat ~/build-docker.status; tail -n 3 ~/build-docker.log
   ```

5. When the status says `DONE`, copy `~/straighter-release/<timestamp>/` back to your Mac.

6. **Delete the keys from the build machine, then destroy the machine.**

   ```bash
   rm -rf ~/signing ~/secrets
   ```

## What the driver checks

| When | Check |
|---|---|
| Before anything | A release must be signed and include Safe Browsing (or pass `--allow-no-safe-browsing`), and must come from a clean commit |
| About 10 minutes in, before the long compile | The signing key opens, matches the fingerprint in `signing-cert-fingerprints.txt`, and `apksigner` runs |
| After the build | Every APK is verified against that fingerprint. A debug-signed APK, or one signed by another certificate, fails the build |

Only file paths are passed into the container, never a password or key. The output folder
holds the APKs renamed `straighter-*`, `SHA256SUMS`, and `BUILD-INFO.txt` with the commit.

If the build stage fails and you want to retry without downloading and preparing everything
again, add `--build-only`. Run `tools/build/docker-build.sh --help` for all options.

## Testing the driver itself

`tools/build/test-docker-build.sh` needs no Docker. It checks the driver against a
stand-in `docker` and covers every refusal above. Run it after changing the driver and
after each rebase.

## After the build

Install the APK on a phone and check that the version, the app ID (`com.s9i.straighter`)
and the signature are right. Before you publish, also inspect the finished APK to see where
Safe Browsing requests are sent (directly to Google or elsewhere), so your privacy policy
states what the app really does.
