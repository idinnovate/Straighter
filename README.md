# Straighter

<div align="center">

<img src="tools/brand/straighter-logo.png"
  alt="Straighter"
  height="200">

</div>

---

Straighter is a free and open source, privacy and security-oriented web browser for Android, built on [Mozilla Firefox](https://www.firefox.com/)'s engine (GeckoView).

> [!NOTE]
> The app is called **Straighter** on your device. In app stores it is listed as **Straighter Browser**.

> [!NOTE]
> Straighter is under development and has no public release yet. Installation instructions will be published here with the first release.

> [!IMPORTANT]
> Straighter uses a privacy-hardened Firefox configuration, so some sites may behave differently than in a stock browser.

Found a bug or have a suggestion? Please open an issue at [github.com/idinnovate/Straighter/issues](https://github.com/idinnovate/Straighter/issues).

## App Verification

**Package ID**: `com.s9i.straighter`

**Package ID** *(Nightly)*: `com.s9i.straighter.nightly`

**SHA-256 Hash of Signing Certificate**:

```text
F8:25:70:91:28:8F:86:98:73:05:31:D4:E3:8A:DA:B2:FD:FF:9B:B1:D5:65:09:5F:4E:CA:09:86:A6:C5:C7:C0
```

Releases downloaded directly (for example from GitHub Releases) are signed with this key. Compare it with the output of `apksigner verify --print-certs` (see [`tools/signing/README.md`](tools/signing/README.md)). If Straighter is also offered through Google Play with Play App Signing, installs from Play are signed by Google's app-signing key instead, and its fingerprint will be listed here too.

## Building

Straighter uses IronFox's build system, which makes it easier (and faster) to build the project locally.
For example, prebuilt versions of wasi-sdk sysroot and llvm-project are used instead of building them locally. ~~F-Droid builds still build those from source.~~

**It is recommended to use the Docker image for building Straighter.** (The image is published by the IronFox project; Straighter uses it unchanged.)

### Build with Docker

Pull the docker image with :

```sh
docker pull registry.gitlab.com/ironfox-oss/ironfox:latest
```

You can also use the `main` tag to pull the image which was used to
build the latest IronFox release. Or you can use exact version names
to pull images for those versions.

For example:

```
docker pull registry.gitlab.com/ironfox-oss/ironfox:v135-0
```

Then, you need to [set up the source files](#get--patch-sources).

### Build without Docker

**NOTE**: Currently, builds on the latest versions of **`Fedora`**, **`macOS`**, **`secureblue`**, and **`Ubuntu`** systems are supported. YMMV for other operating systems/environments.

**NOTE**: **`macOS`** users must install [Homebrew](https://brew.sh/) *(if is not already installed)* before following the steps below.

First, if you haven't already installed it, you'll want to install `git` for your platform of choice:

**`Fedora`**:

```sh
sudo dnf install git
```

**`macOS`**:

```sh
brew install git
```

**`secureblue`**:

`git` is already installed on secureblue by default, so nothing to do here.

**`Ubuntu`**:

```sh
sudo apt install git
```

After you've successfully installed `git`, the first thing you'll need to do is clone Straighter's source repository:

*(`--depth=1` is specified below to reduce the size of the cloned repository, it can be removed if preferred)*

```sh
git clone --depth=1 https://github.com/idinnovate/Straighter.git Straighter
```

You should now navigate to the root of Straighter's source directory, and run the `bootstrap` script:

*(The `bootstrap` script will set-up and install dependencies required to build Straighter on your system)*

```sh
cd Straighter
./scripts/bootstrap.sh
```

#### Get sources

Still from the root of Straighter's source directory, you should now run the `get_sources` script to download the external sources required for building Straighter:

**NOTE**: If you need to fetch sources for a different version of a dependency than the version Straighter is currently using, you'll need to modify `scripts/versions.sh` **BEFORE** running the `get_sources` script.

_This may take some time depending on your network speed..._

```sh
./scripts/get_sources.sh
```

#### Preparing sources

You now need to patch/prepare your newly downloaded sources with the `prebuild` script:

_This must be run once after getting your sources._

```sh
./scripts/prebuild.sh
```

#### Build

Finally, you can start the build process with:

```sh
./scripts/build.sh <build-variant>
```

Where `<build-variant>` specifies the variant to build, and is **one** of the following:

- `arm` - 32-bit ARM (`armeabi-v7a`)
- `arm64` - 64-bit ARM (`arm64-v8a`)
- `x86_64` - 64-bit x86
- `bundle` - Android App Bundle (AAB) with all supported ABIs

In addition to the `AAB`, the `bundle` target also produces APKs for each architecture *(`arm`, `arm64`, and `x86_64`)*, as well as a universal APK containing all architectures.

### Linting

Straighter is largely driven by shell scripts, which are checked with [`shellcheck`](https://www.shellcheck.net/) *(static analysis)* and [`shfmt`](https://github.com/mvdan/sh) *(formatting)*. These run automatically in CI *(the `lint-scripts` job)* and are enforced there — a lint failure stops the pipeline before any build starts.

`./scripts/get_sources.sh` installs both tools and enables a git pre-commit hook *(via `core.hooksPath`)* that lints your staged scripts before each commit. The hook is a convenience and can be bypassed with `git commit --no-verify`; CI remains the source of truth.

If you are providing your own copies of `shellcheck` and `shfmt` *(instead of getting them from `./scripts/get_sources.sh`)*, after setting `IRONFOX_SHELLCHECK_DIR` and `IRONFOX_SHFMT_DIR` to the appropriate directories, you can set-up the pre-commit hook directly by running:

```sh
./scripts/lint-hook.sh
```

To run the linting checks manually:

```sh
./scripts/lint.sh
```

To auto-fix formatting:

```sh
git ls-files 'scripts/*.sh' | xargs shfmt -w
```

Linter configuration lives in `.shellcheckrc` *(checks)* and `.editorconfig` *(formatting)*.

## Translation

Straighter's translations come from IronFox, which is translated using Weblate. To help with translations, visit [IronFox's Weblate project](https://hosted.weblate.org/engage/ironfox/).

## Acknowledgements

**Thank you to the IronFox team.** Straighter is built on [IronFox](https://gitlab.com/ironfox-oss/IronFox). Its build system, hardening patches and default configuration are the foundation of this project, and Straighter would not exist without the time and work of IronFox's maintainers and contributors. IronFox documents the trade-offs that come with this hardening on its [Limitations](https://ironfoxoss.org/docs/limitations/) and [FAQ](https://ironfoxoss.org/docs/faq/) pages, and they apply to Straighter too.

IronFox is itself a fork of [Mull](https://web.archive.org/web/20250113132510/https://divestos.org/pages/our_apps#mull) by [Divested Computing Group](https://divested.dev/), and both build on [Mozilla Firefox](https://www.firefox.com/). Thank you to those projects, and to everyone whose work they include. The Licensing section below lists the projects whose patches IronFox adapts.

## Licensing

The scripts are licensed under the [GNU Affero General Public License, version 3 or later](COPYING).

Changes to patches are licensed according to the header in the files this patch adds or modifies ([Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) or [MPL 2.0](https://www.mozilla.org/MPL/)).

[Phoenix](https://phoenix.celenity.dev/) is licensed under the [GNU General Public License v3.0 or later](https://spdx.org/licenses/GPL-3.0-or-later.html) _(`GPL-3.0-or-later`)_ where applicable. See [`COPYING`](https://phoenix.celenity.dev/COPYING.txt).

`a-c-liberate.patch`, `a-s-localize-maven.patch`, and `fenix-liberate.patch` are adapted from [Fennec F-Droid](https://gitlab.com/relan/fennecbuild). See [`COPYING`](https://gitlab.com/relan/fennecbuild/-/blob/master/COPYING).

`gecko-configure-ublock-origin.patch`, `gecko-devtools-bypass.patch`, `gecko-fix-rfphelper-import.patch`, `gecko-ironfox-branding.patch`, `gecko-prevent-exposing-name-and-vendor-to-extensions.patch`, and `gecko-rs-blocker.patch` are adapted from [LibreWolf](https://librewolf.net/). See [LibreWolf License and Disclaimers](https://librewolf.net/license-disclaimers/).

`fenix-disable-network-connectivity-monitoring.patch`, `gecko-disable-network-id.patch`, `gecko-prevent-fingerprinting-via-chrome-resources.patch`, `geckoview-ironfox-settings-support-spoof-english.patch`, and `glean-noop.patch` are adapted from the [Tor Project](https://www.torproject.org/). See [`LICENSE`](https://gitlab.torproject.org/tpo/core/tor/-/raw/HEAD/LICENSE).

Our current set of default wallpapers are taken from [Fennec F-Droid](https://gitlab.com/relan/fennecmedia), and are available under the [Unsplash license](https://gitlab.com/relan/fennecmedia#licenses).

## Notices

Mozilla Firefox is a trademark of The Mozilla Foundation.

This is not an officially supported Mozilla product. Straighter is in no way affiliated with Mozilla.

Straighter is not sponsored or endorsed by Mozilla.

Straighter is a fork of IronFox. It is not affiliated with, sponsored by, or endorsed by IronFox OSS.

Straighter is not associated with DivestOS, Divested Computing Group, or Mull in any manner.

Firefox source code is available at [https://github.com/mozilla-firefox/firefox](https://github.com/mozilla-firefox/firefox).
