#!/usr/bin/env bash
#
# Regression test for tools/build/docker-build.sh. It needs no Docker: it puts a stand-in
# `docker` on the PATH that records every call and answers the way the build container
# would (keytool fingerprint, apksigner output, the APKs it "built"), then checks what the
# driver mounted and passed, that no secret leaks, and that every unsafe situation stops
# the build where it should.
#
#     tools/build/test-docker-build.sh
#
# Exits non-zero if any check fails. Run it after changing the driver or after a rebase.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="${HERE}/docker-build.sh"
T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin"

# The certificate fingerprint used throughout is a made-up one; the password and API key
# are sentinels that must never appear in any docker call or log.
FP="AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
FP_PLAIN="$(printf '%s' "${FP}" | tr -d ':' | tr 'A-F' 'a-f')"
SECRET="SENTINEL-PASSWORD-must-not-leak"
SBSECRET="SENTINEL-API-KEY-must-not-leak"

cat > "${T}/bin/docker" << 'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
case "$1" in
  info | build | rm | run) exit 0 ;;
  exec)
    cmd="${!#}"
    echo "   EXEC: ${cmd}" >> "$STUB_LOG"
    case "${cmd}" in
      *keytool*) printf 'Alias name: straighter\n\t SHA256: %s\n' "${STUB_KEYTOOL_FP}" ;;
      *"apksigner --version"*) [[ -n "${STUB_APKSIGNER_FAIL:-}" ]] && exit 1; echo "0.9" ;;
      *"find /app/outputs/apk"*)
        mkdir -p "${STUB_ROOT}/outputs/apk"
        echo fakeapk > "${STUB_ROOT}/outputs/apk/ironfox-156.0-arm64-v8a.apk"
        echo /app/outputs/apk/ironfox-156.0-arm64-v8a.apk ;;
      *apksigner*)
        printf 'Verifies\nSigner #1 certificate DN: %s\nSigner #1 certificate SHA-256 digest: %s\n' "${STUB_SIGNER_DN}" "${STUB_APK_FP}" ;;
    esac ;;
esac
exit 0
STUB
chmod +x "${T}/bin/docker"
export PATH="${T}/bin:${PATH}"
export STUB_LOG="${T}/calls.log"

reset_stub() {
  export STUB_KEYTOOL_FP="${FP}" STUB_APK_FP="${FP_PLAIN}" STUB_SIGNER_DN="CN=Straighter, O=Test, C=GB"
  unset STUB_APKSIGNER_FAIL
}

PASS=0
FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then PASS=$((PASS + 1)); echo "  ok    $1"; else FAIL=$((FAIL + 1)); echo "  FAIL  $1 (got '$2', want '$3')"; fi
}
has() { grep -q -- "$1" "${STUB_LOG}" && echo yes || echo no; }
before() { # is the first line matching $1 before the first matching $2 in the docker log?
  local a b
  a="$(grep -n -- "$1" "${STUB_LOG}" | head -1 | cut -d: -f1)"
  b="$(grep -n -- "$2" "${STUB_LOG}" | head -1 | cut -d: -f1)"
  [[ -n "${a}" && -n "${b}" && "${a}" -lt "${b}" ]] && echo yes || echo no
}

newrepo() { # a throwaway git repo with a copy of the driver
  R="${T}/$1"
  rm -rf "${R}"
  mkdir -p "${R}/scripts" "${R}/tools/build" "${T}/home_$1"
  echo "#!/bin/sh" > "${R}/scripts/build.sh"
  echo "FROM fedora:44" > "${R}/Dockerfile"
  cp "${DRIVER}" "${R}/tools/build/"
  (cd "${R}" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init)
  export STUB_ROOT="${R}"
  : > "${STUB_LOG}"
  reset_stub
}
newsign() {
  S="${T}/sign_$1"
  rm -rf "${S}"
  mkdir -p "${S}"
  echo fakejks > "${S}/straighter-release.jks"
  printf '%s' "${SECRET}" > "${S}/keystore.pass"
  printf 'Owner: CN=Straighter\n\t SHA256: %s\n' "${FP}" > "${S}/signing-cert-fingerprints.txt"
  chmod 600 "${S}"/*
}
drv() { # drv NAME ARGS...  -> prints the driver's exit code
  local n="$1"
  shift
  HOME="${T}/home_${n}" bash "${R}/tools/build/docker-build.sh" "$@" > "${T}/out_${n}.txt" 2>&1
  echo $?
}
outmatches() { grep -c -- "$2" "${T}/out_$1.txt"; }

echo "T1 nightly, unsigned, no Safe Browsing key"
newrepo t1; rc=$(drv t1)
ok "succeeds" "${rc}" 0
ok "mounts only the repo" "$(has ' /signing')" no
ok "release flag is 0" "$(has 'IRONFOX_RELEASE=0')" yes
ok "skips the interactive ADB prompt" "$(has 'IRONFOX_SIGN_SKIP_ADB=1')" yes
ok "passes no keystore variables" "$(has 'IRONFOX_ANDROID_KEYSTORE')" no
ok "answers the missing-Safe-Browsing prompt" "$(has "printf 'y")" yes
ok "APK renamed straighter-*" "$(ls "${T}"/home_t1/straighter-release/*/ | grep -c '^straighter-156.0-arm64-v8a.apk$')" 1
ok "BUILD-INFO flags a test build" "$(grep -c 'NO (test build)' "${T}"/home_t1/straighter-release/*/BUILD-INFO.txt)" 1
ok "status is DONE" "$(cat "${T}/home_t1/build-docker.status")" DONE

echo "T2 release without --sign is refused"
newrepo t2; rc=$(drv t2 --release)
ok "refused" "${rc}" 1
ok "nothing was built" "$(has 'docker build')" no

echo "T3 signed release, full path"
newrepo t3; newsign t3; rc=$(drv t3 --release --sign "${S}")
ok "succeeds" "${rc}" 0
ok "signing folder mounted read-only" "$(has "-v ${S}:/signing:ro")" yes
ok "release flag is 1" "$(has 'IRONFOX_RELEASE=1')" yes
ok "keystore path is the container path" "$(has 'IRONFOX_ANDROID_KEYSTORE=/signing/straighter-release.jks')" yes
ok "both password FILE paths passed" "$(grep -o 'PASS_FILE=/signing/keystore.pass' "${STUB_LOG}" | sort -u | wc -l | tr -d ' ')" 1
ok "alias passed" "$(has 'KEY_ALIAS=straighter')" yes
ok "password never in a docker call" "$(grep -c "${SECRET}" "${STUB_LOG}")" 0
ok "password never in driver log or output" "$(cat "${T}"/home_t3/build-docker.log "${T}/out_t3.txt" | grep -c "${SECRET}")" 0
ok "key checked before the build" "$(before 'keytool' 'build.sh arm64')" yes
ok "apksigner checked before the build" "$(before 'apksigner --version' 'build.sh arm64')" yes
ok "BUILD-INFO records the certificate" "$(grep -c "yes, certificate SHA-256 ${FP_PLAIN}" "${T}"/home_t3/straighter-release/*/BUILD-INFO.txt)" 1
ok "SHA256SUMS written" "$(wc -l < "${T}"/home_t3/straighter-release/*/SHA256SUMS | tr -d ' ')" 1

echo "T4 wrong key: stops before compiling"
newrepo t4; newsign t4; export STUB_KEYTOOL_FP="00:11:22"; rc=$(drv t4 --release --sign "${S}")
ok "refused" "${rc}" 1
ok "build.sh never ran" "$(has 'build.sh arm64')" no
ok "says nothing was built" "$(outmatches t4 'Nothing was built')" 1

echo "T5 debug-signed APK is rejected"
newrepo t5; newsign t5; export STUB_SIGNER_DN="C=US, O=Android, CN=Android Debug"; rc=$(drv t5 --release --sign "${S}")
ok "refused" "${rc}" 1
ok "nothing published" "$(ls "${T}/home_t5/straighter-release" 2> /dev/null | wc -l | tr -d ' ')" 0
ok "names the debug key" "$(outmatches t5 'DEBUG key')" 1

echo "T6 APK signed by a different certificate is rejected"
newrepo t6; newsign t6; export STUB_APK_FP="$(printf '0%.0s' $(seq 1 64))"; rc=$(drv t6 --release --sign "${S}")
ok "refused" "${rc}" 1
ok "says different certificate" "$(outmatches t6 'different certificate')" 1

echo "T7 release from a dirty tree"
newrepo t7; newsign t7; echo change >> "${R}/Dockerfile"
rc=$(drv t7 --release --sign "${S}"); ok "refused" "${rc}" 1
rc=$(drv t7 --release --sign "${S}" --allow-dirty); ok "--allow-dirty proceeds" "${rc}" 0

echo "T8 tree that was built before"
newrepo t8; mkdir "${R}/external"; rc=$(drv t8); ok "refused without --build-only" "${rc}" 1
newrepo t8b; mkdir "${R}/external"; rc=$(drv t8b --build-only)
ok "--build-only accepted" "${rc}" 0
ok "get_sources skipped" "$(has 'get_sources.sh')" no
ok "prebuild skipped" "$(has 'prebuild.sh')" no

echo "T9 missing password file"
newrepo t9; newsign t9; rm "${S}/keystore.pass"; rc=$(drv t9 --release --sign "${S}")
ok "refused" "${rc}" 1
ok "nothing was built" "$(has 'docker build')" no

echo "T10 with a Safe Browsing key file"
newrepo t10; echo "${SBSECRET}" > "${T}/sbkey.txt"; rc=$(drv t10 --sb-key "${T}/sbkey.txt")
ok "succeeds" "${rc}" 0
ok "key file mounted read-only" "$(has 'sbkey.txt:/secrets/sb-gapi-key.txt:ro')" yes
ok "path passed as an env var" "$(has 'IRONFOX_SB_GAPI_KEY_FILE=/secrets/sb-gapi-key.txt')" yes
ok "no prompt answer needed" "$(has "printf 'y")" no
ok "key content never in a docker call" "$(grep -c "${SBSECRET}" "${STUB_LOG}")" 0

echo "T11 bad input"
newrepo t11
ok "bad ABI refused" "$(drv t11 --abi mips)" 1
ok "unknown option refused" "$(drv t11 --bogus)" 1
ok "missing value refused" "$(drv t11 --sign)" 1

echo "T12 apksigner cannot run: stops before compiling"
newrepo t12; newsign t12; export STUB_APKSIGNER_FAIL=1; rc=$(drv t12 --release --sign "${S}")
ok "refused" "${rc}" 1
ok "build.sh never ran" "$(has 'build.sh arm64')" no
ok "says nothing was built" "$(outmatches t12 'Nothing was built')" 1

echo
echo "${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]
