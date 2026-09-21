# Signing Straighter releases

Every Android app is signed with a private key, and only updates signed with **the same
key** can install over an existing copy of the app. The key is therefore the most
valuable secret in this project: if you lose it you can never update your users again,
and if someone else gets it they can publish a fake "update" that Android will accept.

The IronFox build scripts sign the output automatically once four environment variables
are set. This folder creates the key and those variables safely. The key and its password
live **outside the repository** (`~/.straighter-signing`) and `.gitignore` refuses to add
the usual key file types.

## One-time setup (on your own Mac)

1. Install Java (the Mac has none, and `keytool` needs it):

   ```bash
   brew install openjdk
   ```

2. Create the key. You type the password at a prompt; it is never shown, logged, or put on
   a command line:

   ```bash
   tools/signing/generate-keystore.sh
   ```

The script refuses to overwrite an existing key. It creates, in `~/.straighter-signing`
(directory mode 700, files mode 600):

| File | What it is | Secret? |
|---|---|---|
| `straighter-release.jks` | PKCS12 keystore holding the RSA-4096 private key, valid about 27 years | **Yes** |
| `keystore.pass` | its password | **Yes** |
| `signing.env` | the four `IRONFOX_ANDROID_KEYSTORE*` variables | paths only, but keep private |
| `signing-cert-fingerprints.txt` | the certificate's SHA-1 / SHA-256 | No: publish it |

## Back it up now

Before anything else, copy `straighter-release.jks` and `keystore.pass` to **two separate,
safe places** (for example a password manager's secure notes, plus an encrypted drive).
Test that a copy opens. There is no recovery if every copy is lost.

## Using the key for a build

The build scripts sign automatically when `IRONFOX_ANDROID_KEYSTORE`,
`IRONFOX_ANDROID_KEYSTORE_PASS_FILE`, `IRONFOX_ANDROID_KEYSTORE_KEY_ALIAS` and
`IRONFOX_ANDROID_KEYSTORE_KEY_PASS_FILE` are all set. Without them the APK is debug-signed,
as in the first test build. See `signing.env.example`.

**On your Mac:** `source ~/.straighter-signing/signing.env` before running the build.

**On a build machine (a cloud droplet):** the key should not live there. Copy it in only
for the build, and delete it afterwards:

1. Copy the keystore and password file to a private folder on the build machine, for
   example `~/signing` (mode 700), and point the four variables at those paths.
2. Run the build.
3. Delete the copies when the signed APK has been downloaded, and destroy the machine.

Never put the key or its password in the repository, in CI logs, or in a chat.

## Verify what you built

Use `apksigner` from the Android SDK that `get_sources.sh` downloads (under `external/`),
then compare the SHA-256 with `signing-cert-fingerprints.txt`:

```bash
apksigner verify --print-certs -v <the-apk>
```

If it says the certificate is the Android Debug key, the four variables were not set.

## Google Play

Play offers *Play App Signing*: Google keeps the key that signs what users install, and
your key becomes an **upload key**. If you ever lose an upload key, Google can reset it;
they cannot restore a lost app-signing key you kept yourself. The trade-off is that the
same app installed from Play and from GitHub/Obtainium carries different signatures, so a
user cannot update from one to the other without reinstalling. Decide which channel is
primary before your first upload, because the choice is hard to undo.

## If the key is compromised

Stop distributing builds signed with it and say so publicly. Android 9 and later support
key rotation (APK Signature Scheme v3), which lets an app move to a new key while keeping
existing installs updating, but it needs the old key to sign the rotation proof, so keep
the old key safe even after you stop using it.
