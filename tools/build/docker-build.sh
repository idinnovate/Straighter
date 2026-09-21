#!/usr/bin/env bash
#
# Build Straighter unattended in upstream's Fedora Docker image, and sign it.
#
# Run it on a Linux build machine that has Docker, from a FRESH clone of the repository
# (a tree that has already been built needs --build-only). Long builds should run inside
# tmux so they survive a dropped connection:
#
#     tmux new-session -d -s build 'tools/build/docker-build.sh --release --sign ~/signing'
#
# Options:
#   --release            build the release variant (default: Nightly). Must be signed.
#   --abi ABI            arm64 (default), arm, x86_64, or bundle (all ABIs + an AAB)
#   --sign DIR           sign with the key in DIR: the folder that
#                        tools/signing/generate-keystore.sh created, containing
#                        straighter-release.jks, keystore.pass and
#                        signing-cert-fingerprints.txt. It is mounted READ-ONLY into the
#                        container for the build only; the key is never copied anywhere.
#   --sb-key FILE        a Google Safe Browsing API key file (see store-safebrowsing-key.sh).
#                        Without one the build has no Safe Browsing (phishing/malware
#                        warnings), so a release requires it.
#   --allow-no-safe-browsing
#                        build a release without Safe Browsing (not advised)
#   --expect-sha256 FP   fail unless the APK's signing certificate has this SHA-256
#                        (default: read from DIR/signing-cert-fingerprints.txt)
#   --alias NAME         key alias (default: straighter, or $STRAIGHTER_KEY_ALIAS)
#   --build-only         skip get_sources and prebuild (retry after a failed build stage)
#   --allow-dirty        build a release from a tree with uncommitted changes (not advised)
#   --keep-container     leave the build container in place afterwards
#   -h, --help           show this help
#
# Before the multi-hour compile it checks everything that could make the result wrong: the
# key exists, opens with its password and matches the expected fingerprint; a release is
# signed; the tree is clean. After the build it verifies each APK's signature against the
# expected fingerprint and refuses to call a debug-signed APK a release.
#
# Progress: $HOME/build-docker.status (RUNNING/FAILED/DONE) and $HOME/build-docker.log.
# Result:   $HOME/straighter-release/<timestamp>/ with the APK(s) renamed straighter-*,
#           SHA256SUMS and BUILD-INFO.txt. Copy them off, then delete the signing folder
#           from this machine and destroy it.
#
# Secrets: only file paths are passed to the container, never a password. Nothing here
# prints one.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="ironfox-builder"
CONTAINER="ironfox-builder"
LOG="${STRAIGHTER_BUILD_LOG:-$HOME/build-docker.log}"
STATUS="${STRAIGHTER_BUILD_STATUS:-$HOME/build-docker.status}"
OUT_ROOT="${STRAIGHTER_RELEASE_DIR:-$HOME/straighter-release}"
ALIAS="${STRAIGHTER_KEY_ALIAS:-straighter}"
KEYSTORE_NAME="straighter-release.jks"
PASS_NAME="keystore.pass"
FP_NAME="signing-cert-fingerprints.txt"

RELEASE=0
ABI="arm64"
SIGN_DIR=""
SB_KEY=""
EXPECT=""
BUILD_ONLY=0
ALLOW_DIRTY=0
ALLOW_NO_SB=0
KEEP=0

usage() { sed -n '3,/^set -uo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

die() {
  echo "error: $*" >&2
  echo "FAILED: $*" > "${STATUS}" 2> /dev/null || true
  exit 1
}

need() { [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) RELEASE=1; shift ;;
    --nightly) RELEASE=0; shift ;;
    --abi) need "$@"; ABI="$2"; shift 2 ;;
    --sign) need "$@"; SIGN_DIR="$2"; shift 2 ;;
    --sb-key) need "$@"; SB_KEY="$2"; shift 2 ;;
    --expect-sha256) need "$@"; EXPECT="$2"; shift 2 ;;
    --alias) need "$@"; ALIAS="$2"; shift 2 ;;
    --build-only) BUILD_ONLY=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --allow-no-safe-browsing) ALLOW_NO_SB=1; shift ;;
    --keep-container) KEEP=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

log() { echo "=== [$(date -u +%FT%TZ)] $*" | tee -a "${LOG}"; }
mode_of() { stat -c %a "$1" 2> /dev/null || stat -f %Lp "$1"; }
hex_only() { printf '%s' "$1" | tr -d ': \r\n' | tr 'A-F' 'a-f'; }

# ---------------------------------------------------------------- checks before any work

[[ -f "${ROOT}/scripts/build.sh" && -f "${ROOT}/Dockerfile" ]] || die "${ROOT} does not look like the Straighter repository."
case "${ABI}" in arm64 | arm | x86_64 | bundle) ;; *) die "--abi must be arm64, arm, x86_64 or bundle (got '${ABI}')" ;; esac
[[ "${ALIAS}" =~ ^[A-Za-z0-9._-]+$ ]] || die "the key alias may only contain letters, digits and . _ -"

DOCKER=(docker)
"${DOCKER[@]}" info > /dev/null 2>&1 || DOCKER=(sudo docker)
"${DOCKER[@]}" info > /dev/null 2>&1 || die "Docker is not usable here (tried 'docker' and 'sudo docker')."

if [[ "${RELEASE}" == 1 && -z "${SIGN_DIR}" ]]; then
  die "a release must be signed: add --sign DIR. Without a key the APK is only debug-signed."
fi

if [[ "${RELEASE}" == 1 && -z "${SB_KEY}" && "${ALLOW_NO_SB}" != 1 ]]; then
  die "a release should include Safe Browsing (phishing and malware protection): add --sb-key FILE, or --allow-no-safe-browsing to build without it."
fi

if [[ "${RELEASE}" == 1 && "${ALLOW_DIRTY}" != 1 ]]; then
  if [[ -n "$(git -C "${ROOT}" status --porcelain 2> /dev/null)" ]]; then
    die "the working tree has uncommitted changes. A release must be built from a commit, so that the published source matches the binary. Commit first, or pass --allow-dirty."
  fi
fi

if [[ -d "${ROOT}/external" && "${BUILD_ONLY}" != 1 ]]; then
  die "${ROOT}/external already exists, so this tree has been built before and re-running get_sources/prebuild on it stops at leftover-file prompts. Use a fresh clone, or --build-only to retry just the build stage."
fi

if [[ -n "${SIGN_DIR}" ]]; then
  SIGN_DIR="$(cd "${SIGN_DIR}" 2> /dev/null && pwd)" || die "the --sign folder does not exist."
  for f in "${KEYSTORE_NAME}" "${PASS_NAME}" "${FP_NAME}"; do
    [[ -s "${SIGN_DIR}/${f}" ]] || die "missing or empty: ${SIGN_DIR}/${f}"
  done
  for f in "${KEYSTORE_NAME}" "${PASS_NAME}"; do
    case "$(mode_of "${SIGN_DIR}/${f}")" in 600 | 400) ;; *) echo "warning: ${SIGN_DIR}/${f} should be mode 600 (chmod 600 it)" >&2 ;; esac
  done
  if [[ -z "${EXPECT}" ]]; then
    EXPECT="$(grep -o 'SHA256: .*' "${SIGN_DIR}/${FP_NAME}" | head -1 | sed 's/SHA256: //')"
  fi
  EXPECT="$(hex_only "${EXPECT}")"
  [[ "${EXPECT}" =~ ^[0-9a-f]{64}$ ]] || die "no valid SHA-256 fingerprint: pass --expect-sha256 or provide ${FP_NAME}."
fi

if [[ -n "${SB_KEY}" ]]; then
  [[ -s "${SB_KEY}" ]] || die "the Safe Browsing key file is missing or empty: ${SB_KEY}"
  SB_KEY="$(cd "$(dirname "${SB_KEY}")" && pwd)/$(basename "${SB_KEY}")"
fi

# ---------------------------------------------------------------- what the container sees

MOUNTS=(-v "${ROOT}:/app")
ENVS=(-e "IRONFOX_RELEASE=${RELEASE}" -e "IRONFOX_SIGN_SKIP_ADB=1")
if [[ -n "${SIGN_DIR}" ]]; then
  MOUNTS+=(-v "${SIGN_DIR}:/signing:ro")
  ENVS+=(
    -e "IRONFOX_ANDROID_KEYSTORE=/signing/${KEYSTORE_NAME}"
    -e "IRONFOX_ANDROID_KEYSTORE_PASS_FILE=/signing/${PASS_NAME}"
    -e "IRONFOX_ANDROID_KEYSTORE_KEY_ALIAS=${ALIAS}"
    -e "IRONFOX_ANDROID_KEYSTORE_KEY_PASS_FILE=/signing/${PASS_NAME}"
  )
fi
if [[ -n "${SB_KEY}" ]]; then
  MOUNTS+=(-v "${SB_KEY}:/secrets/sb-gapi-key.txt:ro")
  ENVS+=(-e "IRONFOX_SB_GAPI_KEY_FILE=/secrets/sb-gapi-key.txt")
fi

dexec() { "${DOCKER[@]}" exec "${ENVS[@]}" "${CONTAINER}" bash -c "$1"; }

# Newest bundled JDK: the build downloads jdk-17/21/25 into external/ (get_sources).
FIND_JDK='JH=$(ls -d /app/external/jdk-* 2>/dev/null | sort -V | tail -1); export JAVA_HOME="$JH"'

run_stage() {
  local name="$1"
  shift
  log "START ${name}"
  echo "RUNNING ${name}" > "${STATUS}"
  "$@" < /dev/null >> "${LOG}" 2>&1
  local rc=$?
  log "END ${name} (exit ${rc})"
  if [[ "${rc}" -ne 0 ]]; then
    echo "FAILED ${name} (exit ${rc}); see ${LOG}" > "${STATUS}"
    echo "error: stage '${name}' failed (exit ${rc}). See ${LOG}" >&2
    exit "${rc}"
  fi
}

: > "${LOG}"
log "Straighter build: release=${RELEASE} abi=${ABI} sign=$([[ -n "${SIGN_DIR}" ]] && echo yes || echo NO) safe-browsing=$([[ -n "${SB_KEY}" ]] && echo yes || echo NO) commit=$(git -C "${ROOT}" rev-parse --short HEAD 2> /dev/null || echo unknown)"
[[ -z "${SIGN_DIR}" ]] && log "NOTE: no --sign, so this is a TEST build (debug-signed). Do not publish it."
[[ -z "${SB_KEY}" ]] && log "NOTE: no --sb-key, so this build has NO Safe Browsing."

# ---------------------------------------------------------------- build

start_container() {
  "${DOCKER[@]}" rm -f "${CONTAINER}" > /dev/null 2>&1
  "${DOCKER[@]}" run -d -it --name "${CONTAINER}" "${MOUNTS[@]}" "${IMAGE}"
}

run_stage image "${DOCKER[@]}" build -t "${IMAGE}" -f "${ROOT}/Dockerfile" "${ROOT}"
run_stage container start_container
run_stage git_trust dexec 'git config --global --add safe.directory "*"'

if [[ "${BUILD_ONLY}" != 1 ]]; then
  run_stage get_sources dexec 'cd /app && ./scripts/get_sources.sh'
  run_stage prebuild dexec 'cd /app && ./scripts/prebuild.sh'
fi

# Prove the key opens and is the one we expect BEFORE spending hours compiling.
if [[ -n "${SIGN_DIR}" ]]; then
  log "START check_signing_key"
  echo "RUNNING check_signing_key" > "${STATUS}"
  got="$(dexec "${FIND_JDK}; \"\${JH}/bin/keytool\" -list -v -alias '${ALIAS}' -keystore '/signing/${KEYSTORE_NAME}' -storepass:file '/signing/${PASS_NAME}'" 2>> "${LOG}" | grep -m1 'SHA256:' | sed 's/.*SHA256: //')"
  got="$(hex_only "${got}")"
  if [[ "${got}" != "${EXPECT}" ]]; then
    die "the key in ${SIGN_DIR} does not open, or its fingerprint is not the expected one (got '${got:-nothing}'). Nothing was built."
  fi
  # apksigner both signs and verifies; learn now, not after hours of compiling, if it cannot run.
  dexec "${FIND_JDK}; /app/external/android-sdk-build-tools/apksigner --version" >> "${LOG}" 2>&1 \
    || die "apksigner does not run in the container, so the result could not be signed or verified. Nothing was built."
  log "END check_signing_key: the key opens, matches ${EXPECT:0:16}..., and apksigner runs"
fi

run_stage marker dexec 'touch /tmp/straighter-build-start'
if [[ -n "${SB_KEY}" ]]; then
  run_stage "build_${ABI}" dexec "cd /app && ./scripts/build.sh ${ABI}"
else
  # Without a Safe Browsing key the build asks "Do you want to continue [y/N]".
  run_stage "build_${ABI}" dexec "cd /app && printf 'y\n' | ./scripts/build.sh ${ABI}"
fi

# ---------------------------------------------------------------- verify

log "START verify"
echo "RUNNING verify" > "${STATUS}"
APKS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && APKS+=("${line}")
done < <(dexec "find /app/outputs/apk -maxdepth 1 -name '*.apk' -newer /tmp/straighter-build-start | sort" 2>> "${LOG}")
[[ "${#APKS[@]}" -gt 0 ]] || die "the build finished but produced no APK under outputs/apk."

for apk in "${APKS[@]}"; do
  out="$(dexec "${FIND_JDK}; /app/external/android-sdk-build-tools/apksigner verify --print-certs -v '${apk}'" 2>> "${LOG}")"
  rc=$?
  sha="$(hex_only "$(grep -m1 'certificate SHA-256 digest' <<< "${out}" | awk '{print $NF}')")"
  dn="$(grep -m1 'certificate DN' <<< "${out}" | sed 's/.*DN: //')"
  log "$(basename "${apk}"): verify exit ${rc}, signer '${dn:-unknown}', SHA-256 ${sha:0:16}..."
  if [[ -n "${SIGN_DIR}" ]]; then
    [[ "${rc}" -eq 0 ]] || die "apksigner rejected $(basename "${apk}")."
    [[ "${dn}" != *"Android Debug"* ]] || die "$(basename "${apk}") is signed with the Android DEBUG key, not yours. The signing variables did not reach the build."
    [[ "${sha}" == "${EXPECT}" ]] || die "$(basename "${apk}") is signed by a different certificate than expected (${sha:0:16}... vs ${EXPECT:0:16}...)."
  fi
done
log "END verify"

# ---------------------------------------------------------------- collect

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${OUT_ROOT}/${STAMP}"
mkdir -p "${DEST}"
for apk in "${APKS[@]}"; do
  name="$(basename "${apk}")"
  cp "${ROOT}/outputs/apk/${name}" "${DEST}/${name/#ironfox-/straighter-}"
done
(
  cd "${DEST}" || exit 1
  if command -v sha256sum > /dev/null 2>&1; then sha256sum ./*.apk; else shasum -a 256 ./*.apk; fi
) > "${DEST}/SHA256SUMS"
{
  echo "Straighter build"
  echo "date:        ${STAMP}"
  echo "commit:      $(git -C "${ROOT}" rev-parse HEAD 2> /dev/null || echo unknown)"
  echo "variant:     $([[ "${RELEASE}" == 1 ]] && echo release || echo nightly)"
  echo "abi:         ${ABI}"
  echo "signed:      $([[ -n "${SIGN_DIR}" ]] && echo "yes, certificate SHA-256 ${EXPECT}" || echo "NO (test build)")"
  echo "safe browsing: $([[ -n "${SB_KEY}" ]] && echo yes || echo no)"
} > "${DEST}/BUILD-INFO.txt"

[[ "${KEEP}" == 1 ]] || "${DOCKER[@]}" rm -f "${CONTAINER}" > /dev/null 2>&1 || true

echo "DONE" > "${STATUS}"
log "DONE. Output: ${DEST}"
ls -l "${DEST}" | tail -n +2 | tee -a "${LOG}"
if [[ -n "${SIGN_DIR}" ]]; then
  echo
  echo "Now copy ${DEST} off this machine, then delete ${SIGN_DIR} from it and destroy the machine."
fi
