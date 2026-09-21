#!/usr/bin/env python3
"""Apply Straighter's user-visible rebrand to the IronFox overlay files.

Idempotent: safe to run again, for example after rebasing onto a new upstream tag.

    python3 tools/brand/rebrand_strings.py [--check]

--check changes nothing and exits 1 if any file would change.

What changes: the product name where users can read it (Android string resources,
Fluent/properties brand files, the display name, the vendor, and the project links).

What deliberately does NOT change:
  * identifiers: class, package, pref and variable names (IronFoxSettings, IRONFOX_*,
    browser.ironfox.*, org.ironfoxoss.*) are internal and renaming them breaks patches;
  * URLs and hostnames that point at the IronFox project;
  * attribution and provenance text: the "fingerprinting overrides from IronFox" strings
    (SKIP_KEYS below), the wallpaper credit, and the translated attribution page, which
    truthfully credit IronFox. The English attribution line is reworded, not removed.
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OV = ROOT / "patches"
NAME = "Straighter"  # the app's name on the device and in the app's own screens
BRAND = "Straighter"  # vendor name, wallpaper collection
STORE_NAME = "Straighter Browser"  # the store listing title only (set in the Play Console); never used inside the app
REPO = "https://github.com/idinnovate/Straighter"
REPO_SSH = "github.com:idinnovate/Straighter.git"

# String resources whose text credits IronFox as the source of a list: keep as written.
SKIP_KEYS = re.compile(r"^preference_fpp_overrides_ironfox_")

# "IronFox" as a brand name, not inside a URL, path, e-mail or identifier. Only ASCII
# characters count as boundaries, so inflected or particle-suffixed forms in Finnish,
# Estonian, Korean, Japanese and so on ("IronFoxin", "IronFoxを") are still renamed, while
# identifiers such as IronFoxSettings (capital letter next) and IronFox.git are left alone.
# The second alternative folds text that an earlier run renamed to the store title
# ("Straighter Browser") back to the app name, so the script gives the same result from
# any starting state.
WORD = re.compile(rf"(?<![A-Za-z0-9_/.@:\-])(?:IronFox(?: OSS)?|{STORE_NAME})(?![A-Z0-9_/])")

STRING_EL = re.compile(r'(<string\b[^>]*\bname="(?P<name>[^"]+)"[^>]*>)(?P<body>.*?)(</string>)', re.S)

# The English Safe Browsing blurb says "IronFox proxies these connections". That is true of
# IronFox's proxy service, not of a Straighter build that has none. Drop the sentence from
# the English text and drop the translations of that one string (Android then falls back
# to English) instead of leaving a privacy claim that is not true. Restore both once
# Straighter runs its own proxy, or once it is confirmed that IronFox's may be used.
PROXY_KEY = "ironfox_onboarding_safe_browsing_enabled_description"
PROXY_SENTENCE = f" Note that {NAME} proxies these connections, to prevent your public IP address from being associated with these requests."
PROXY_ELEMENT = re.compile(rf'\n[ \t]*<string\b[^>]*\bname="{PROXY_KEY}"[^>]*>.*?</string>', re.S)


def rename(text):
    return WORD.sub(NAME, text)


def brand_ftl(text):
    """Product names get the full name; the vendor is the short brand, not the product."""
    text = rename(text)
    return re.sub(r"(?m)^(-vendor-short-name = ).*$", rf"\g<1>{BRAND}", text)


def android_strings(text, base):
    def fix(m):
        if SKIP_KEYS.match(m.group("name")):
            return m.group(0)
        return m.group(1) + rename(m.group("body")) + m.group(4)

    text = STRING_EL.sub(fix, text)
    if base:
        return text.replace(PROXY_SENTENCE, "")
    return PROXY_ELEMENT.sub("", text)


def exact(*pairs):
    def fn(text):
        for old, new in pairs:
            text = text.replace(old, new)
        return text

    return fn


def configure(text):
    text = text.replace('imply_option("MOZ_APP_VENDOR", "IronFox OSS")', f'imply_option("MOZ_APP_VENDOR", "{BRAND}")')
    text = text.replace("# Make it IronFox...", f"# Make it {BRAND} (based on IronFox)...")
    urls = {
        "IRONFOX_BUGS_URL": f"{REPO}/issues",
        "IRONFOX_FAQ_URL": REPO,
        "IRONFOX_RELEASES_URL": f"{REPO}/releases",
        "IRONFOX_REPO_GIT_URL": REPO_SSH,
        "IRONFOX_REPO_URL": REPO,
        "IRONFOX_URL": REPO,
    }
    for key, value in urls.items():
        text = re.sub(
            rf'(imply_option\("{key}",\s+)"[^"]*"(\))',
            lambda m, v=value: f'{m.group(1)}"{v}"{m.group(2)}',
            text,
        )
    return text


ATTRIBUTION_OLD = "about-attribution-subtitle = IronFox wouldn't be what it is without"
ATTRIBUTION_NEW = f"about-attribution-subtitle = {NAME} is based on IronFox, which wouldn't be what it is without"
ATTRIBUTION_STORE = f"about-attribution-subtitle = {STORE_NAME} is based on IronFox, which wouldn't be what it is without"


def plan():
    """(path, transform) for every file this script may touch."""
    jobs = []
    for f in sorted(OV.glob("fenix-overlay/**/values*/*.xml")) + sorted(OV.glob("gecko-overlay/**/values*/*.xml")):
        base = f.parent.name == "values"
        jobs.append((f, lambda t, base=base: android_strings(t, base)))
    gecko = OV / "gecko-overlay/ironfox"
    for ch in ("ironfox", "ironfox-nightly"):
        b = gecko / "branding" / ch
        jobs.append((b / "locales/en-US/brand.ftl", brand_ftl))
        jobs.append((b / "locales/en-US/brand.properties", rename))
        jobs.append((b / "configure.sh", rename))
    jobs.append((gecko / "locales/en-US/ironfox/ironfox.ftl",
                 exact((ATTRIBUTION_OLD, ATTRIBUTION_NEW), (ATTRIBUTION_STORE, ATTRIBUTION_NEW))))
    jobs.append((gecko / "ironfox.configure", configure))
    jobs.append((gecko / "android/core/src/main/res/raw/wallpapers.json",
                 exact(('"heading": "Classic IronFox"', f'"heading": "Classic {BRAND}"'))))
    jobs.append((ROOT / "configs/phoenix/ironfox.cfg",
                 exact(("'Autofill in IronFox'", f"'Autofill in {NAME}'"),
                       (f"'Autofill in {STORE_NAME}'", f"'Autofill in {NAME}'"))))
    return jobs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    changed = []
    for path, fn in plan():
        if not path.exists():
            print(f"missing (skipped): {path.relative_to(ROOT)}", file=sys.stderr)
            continue
        old = path.read_text(encoding="utf-8")
        new = fn(old)
        if new != old:
            changed.append(path)
            if not args.check:
                path.write_text(new, encoding="utf-8")
    verb = "would change" if args.check else "changed"
    print(f"{verb} {len(changed)} file(s)")
    for p in changed[:8]:
        print("  ", p.relative_to(ROOT))
    if len(changed) > 8:
        print(f"   ... and {len(changed) - 8} more")
    return 1 if (args.check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())
