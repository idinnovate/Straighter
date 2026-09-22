#!/usr/bin/env bash
#
# Store your Google Safe Browsing API key where the build can use it, without the key ever
# appearing in a command line, a shell history, a log, this repository, or a chat.
#
# Run it yourself, in your own terminal:
#
#     tools/build/store-safebrowsing-key.sh
#
# It asks for the key at a hidden prompt and writes it to
# ~/.straighter-secrets/sb-gapi-key.txt (override the folder with STRAIGHTER_SECRETS_DIR),
# readable only by you. Then pass that file to the build with --sb-key:
#
#     tools/build/docker-build.sh --release --sign ~/signing --sb-key ~/secrets/sb-gapi-key.txt
#
# (copy it to the build machine for the build and delete it afterwards, as for the signing
# key). Options: --replace overwrites an existing key file.
#
# Keep in mind that the key is compiled into the APK, so anyone can extract it. In the
# Google Cloud console, restrict it to the Safe Browsing API only and set a quota alert.

set -euo pipefail

DIR="${STRAIGHTER_SECRETS_DIR:-$HOME/.straighter-secrets}"
FILE="${DIR}/sb-gapi-key.txt"
REPLACE=0

die() {
  echo "error: $*" >&2
  exit 1
}

case "${1:-}" in
  --replace) REPLACE=1 ;;
  "") ;;
  -h | --help)
    sed -n '3,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) die "unknown option: $1 (try --help)" ;;
esac

if [[ -e "${FILE}" && "${REPLACE}" != 1 ]]; then
  die "${FILE} already exists. Use --replace if you really mean to overwrite it."
fi

umask 077
mkdir -p "${DIR}"
chmod 700 "${DIR}"

read -r -s -p "Paste your Google Safe Browsing API key (it will not be shown): " KEY
echo
[[ -n "${KEY}" ]] || die "nothing entered."
[[ "${KEY}" =~ ^[A-Za-z0-9_.-]+$ ]] || die "the key contains spaces or unexpected characters. Paste it again without quotes or line breaks."

# Google API keys are normally "AIza" plus 35 characters. Anything else is probably a mispaste,
# but do not insist: the format is not guaranteed.
if [[ ! "${KEY}" =~ ^AIza[0-9A-Za-z_-]{35}$ ]]; then
  echo "note: this does not look like the usual Google API key format (AIza + 35 characters)." >&2
  ANSWER=""
  read -r -p "Store it anyway? [y/N] " ANSWER || true
  [[ "${ANSWER}" =~ ^[Yy]$ ]] || die "not stored."
fi

# No trailing newline: the file holds exactly the key.
printf '%s' "${KEY}" > "${FILE}"
chmod 600 "${FILE}"
LEN=${#KEY}
unset KEY

echo
echo "Stored in ${FILE} (${LEN} characters, mode 600). The key itself was not printed."
echo
echo "Next:"
echo "  1. In the Google Cloud console, restrict this key to the Safe Browsing API only,"
echo "     and set a quota/usage alert."
echo "  2. Back it up somewhere safe (a password manager). It can be re-created in the"
echo "     console, but a new key needs a new build."
echo "  3. For a build, copy it to the build machine and pass it with --sb-key (see above)."
