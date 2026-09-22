#!/usr/bin/env bash
#
# Create Straighter's release signing key.
#
# Run this yourself, in your own terminal:
#
#     tools/signing/generate-keystore.sh
#
# The password is typed at a prompt. It never appears on a command line, in the shell
# history, in a log, or in this repository. Everything is written OUTSIDE the repo, to
# ~/.straighter-signing by default (override with STRAIGHTER_SIGNING_DIR).
#
# Files created (all readable only by you):
#   straighter-release.jks          the keystore holding the private key  <- BACK THIS UP
#   keystore.pass                   its password                          <- BACK THIS UP
#   signing.env                     the four IRONFOX_* variables the build scripts read
#   signing-cert-fingerprints.txt   the certificate's public fingerprints (safe to publish)
#
# If you lose the keystore or its password you can never publish an update that installs
# over existing copies of the app. See tools/signing/README.md.

set -euo pipefail

DIR="${STRAIGHTER_SIGNING_DIR:-$HOME/.straighter-signing}"
ALIAS="${STRAIGHTER_KEY_ALIAS:-straighter}"
KEYSTORE="$DIR/straighter-release.jks"
PASSFILE="$DIR/keystore.pass"
ENVFILE="$DIR/signing.env"
FPFILE="$DIR/signing-cert-fingerprints.txt"
KEY_BITS=4096
VALIDITY_DAYS=10000 # about 27 years; Google Play needs the key valid beyond 22 Oct 2033

die() {
  echo "error: $*" >&2
  exit 1
}

# macOS ships a `keytool` stub that only prints "Unable to locate a Java Runtime", so a
# plain `command -v` is not enough: run it. Fall back to Homebrew's openjdk.
find_keytool() {
  if keytool -help > /dev/null 2>&1; then
    command -v keytool
    return 0
  fi
  local jdk
  jdk="$(brew --prefix openjdk 2> /dev/null || true)"
  if [[ -n "${jdk}" && -x "${jdk}/bin/keytool" ]]; then
    echo "${jdk}/bin/keytool"
    return 0
  fi
  return 1
}

KEYTOOL="$(find_keytool)" || die "no Java found. Install one with:  brew install openjdk   and run this again."

# Never overwrite a signing key.
if [[ -e "${KEYSTORE}" ]]; then
  die "${KEYSTORE} already exists. Refusing to overwrite a signing key: replacing it would mean you can no longer update installed copies of the app. Move it away yourself if you truly intend to start over."
fi

umask 077
mkdir -p "${DIR}"
chmod 700 "${DIR}"

echo "Creating Straighter's release signing key in ${DIR}"
echo

read -r -s -p "Choose a keystore password (at least 16 characters): " PW
echo
read -r -s -p "Type it again: " PW2
echo
[[ "${PW}" == "${PW2}" ]] || die "the passwords do not match."
((${#PW} >= 16)) || die "use at least 16 characters."
unset PW2

read -r -p "Name of the organization or person on the certificate [Straighter]: " ORG
ORG="${ORG:-Straighter}"
read -r -p "Two-letter country code (optional, e.g. GB): " CC

# The certificate name is assembled from what was typed, so refuse characters that have a
# special meaning in a distinguished name.
[[ "${ORG}" =~ ^[A-Za-z0-9\ ._\'-]+$ ]] || die "the name may only contain letters, digits, spaces and . _ ' -"
if [[ -n "${CC}" && ! "${CC}" =~ ^[A-Za-z]{2}$ ]]; then
  die "the country code must be exactly two letters."
fi
DNAME="CN=Straighter, O=${ORG}"
[[ -n "${CC}" ]] && DNAME="${DNAME}, C=$(printf '%s' "${CC}" | tr '[:lower:]' '[:upper:]')"

# The password goes into a file (mode 600), and keytool/apksigner read it from there, so
# it never shows up in the process list. A trailing newline is required: apksigner's
# `file:` password source throws "end of file reached" without one (it needs a line
# terminator to know the read is complete), even though keytool accepts either form.
printf '%s\n' "${PW}" > "${PASSFILE}"
unset PW
chmod 600 "${PASSFILE}"

# PKCS12 keystores use one password for the store and the key.
"${KEYTOOL}" -genkeypair \
  -alias "${ALIAS}" \
  -keyalg RSA -keysize "${KEY_BITS}" -sigalg SHA256withRSA \
  -validity "${VALIDITY_DAYS}" \
  -dname "${DNAME}" \
  -storetype PKCS12 \
  -keystore "${KEYSTORE}" \
  -storepass:file "${PASSFILE}"
chmod 600 "${KEYSTORE}"

# The public fingerprints of the certificate: safe to publish, and what users compare to
# confirm an APK really came from you.
"${KEYTOOL}" -list -v \
  -alias "${ALIAS}" \
  -keystore "${KEYSTORE}" \
  -storepass:file "${PASSFILE}" | grep -E '^(Owner|Valid from|.*SHA1|.*SHA256):' > "${FPFILE}" || true
chmod 600 "${FPFILE}"

cat > "${ENVFILE}" << EOF
# Source this before building:   source "${ENVFILE}"
# When all four are set, the IronFox build scripts sign the output APKs automatically.
# On the build machine the paths differ: edit them after copying (see tools/signing/README.md).
export IRONFOX_ANDROID_KEYSTORE='${KEYSTORE}'
export IRONFOX_ANDROID_KEYSTORE_PASS_FILE='${PASSFILE}'
export IRONFOX_ANDROID_KEYSTORE_KEY_ALIAS='${ALIAS}'
export IRONFOX_ANDROID_KEYSTORE_KEY_PASS_FILE='${PASSFILE}'
EOF
chmod 600 "${ENVFILE}"

echo
echo "Done. Created in ${DIR}:"
ls -l "${DIR}" | tail -n +2
echo
echo "Certificate fingerprints (public):"
sed 's/^/  /' "${FPFILE}"
echo
echo "NEXT, before you do anything else:"
echo "  1. Back up ${KEYSTORE} and ${PASSFILE} to two separate, safe places"
echo "     (a password manager's secure notes plus an encrypted drive, for example)."
echo "  2. Never commit them, paste them into chat, or leave them on a build server."
echo "  3. Publish the SHA-256 fingerprint above in the README with your first release."
