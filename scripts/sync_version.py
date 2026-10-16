"""Generate the addon TOC version from the repository's VERSION file."""

import argparse
from pathlib import Path
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the TOC needs updating")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    version = (root / "VERSION").read_text(encoding="utf-8-sig").strip()
    number = r"(?:0|[1-9][0-9]*)"
    identifier = rf"(?:{number}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    semver = rf"{number}\.{number}\.{number}(?:-{identifier}(?:\.{identifier})*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    if not re.fullmatch(semver, version):
        raise ValueError("VERSION must contain one valid SemVer version")
    toc = root / "src" / "WoWHACv5.toc"
    source = toc.read_bytes().decode("utf-8")
    generated, count = re.subn(r"(?m)^## Version:[^\r\n]*", f"## Version: {version}", source)
    if count != 1:
        raise ValueError("The TOC must contain exactly one Version field")
    if generated != source:
        if args.check:
            raise ValueError("TOC version is stale; run python scripts/sync_version.py")
        toc.write_bytes(generated.encode("utf-8"))
    print(version)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
