"""Build standalone PriorityAssistant archives without bundling rotation addons.

Current authored files come from src. Each target borrows only its existing
WoWHACv5/Libs directory from a prebuild, leaving dependency code and attribution
unchanged. Branding is applied to the archive contents, never to src/prebuilds.
"""

import argparse
from pathlib import Path, PurePosixPath
import posixpath
import re
import stat
import subprocess
import sys
import json
from zipfile import BadZipFile, ZipFile, ZipInfo, ZIP_DEFLATED


ROOT = Path(__file__).resolve().parent.parent
ADDON = "PriorityAssistant"
SOURCE_ADDON = "WoWHACv5"
TEXT_SUFFIXES = {".lua", ".xml", ".toc", ".txt", ".md", ".json"}
OLD_PROVIDER_MESSAGE = (
    "No rotation suppliers found. A list of available suppliers can be found at "
    "https://wowhac.fun/"
)
NEW_PROVIDER_MESSAGE = "No rotation provider found. Install and enable a supported rotation addon."
XML_FILES = re.compile(r'<(?:Script|Include)\b[^>]*\bfile\s*=\s*[\"\']([^\"\']+)[\"\']', re.I)


def safe_path(name):
    """Accept only portable relative ZIP paths, without extracting anything."""
    normalized = name.replace("\\", "/")
    parts = normalized.rstrip("/").split("/")
    if not parts or any(part in {"", ".", ".."} or ":" in part for part in parts):
        raise ValueError(f"Unsafe archive path: {name!r}")
    if any(any(ord(char) < 32 for char in part) for part in parts):
        raise ValueError(f"Invalid archive path: {name!r}")
    return "/".join(parts)


def version():
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "sync_version.py"), "--check"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Version validation failed")
    return (ROOT / "VERSION").read_text(encoding="utf-8-sig").strip()


def targets():
    interfaces = json.loads((ROOT / "scripts" / "priority_assistant_targets.json").read_text(encoding="utf-8"))
    donors = {}
    for archive in sorted((ROOT / "prebuilds").glob("*.zip")):
        match = re.fullmatch(r"([0-9]+[a-z]?)[A-Z].*\.zip", archive.name)
        if not match:
            raise ValueError(f"Cannot determine game version from {archive.name}")
        donors.setdefault(match[1], archive)
    if not donors or set(donors) != set(interfaces):
        missing = sorted(set(donors) - set(interfaces))
        stale = sorted(set(interfaces) - set(donors))
        raise ValueError(f"Target interfaces must match prebuild versions; missing={missing}, stale={stale}")
    for game_version, donor in sorted(donors.items()):
        declared = interfaces[game_version]
        compatible = declared if isinstance(declared, list) else [declared]
        if not compatible or any(type(value) is not int or value <= 0 for value in compatible):
            raise ValueError(f"Invalid Interface for {game_version}: {declared!r}")
        if len(set(compatible)) != len(compatible):
            raise ValueError(f"Duplicate Interface values for {game_version}")
        yield game_version, ", ".join(str(value) for value in compatible), donor


def rebrand(text):
    text = text.replace(OLD_PROVIDER_MESSAGE, NEW_PROVIDER_MESSAGE)
    text = re.sub(r'(?m)^[ \t]*self:Log\("Join our discord: https://discord\.gg/P7FaqjcATp"\)\r?\n', "", text)
    for old, new in (
        ("WoWHACv5", ADDON), ("WOWHACV4", "PRIORITYASSISTANT"),
        ("WOWHAC", "PRIORITYASSISTANT"), ("wowhac", "priorityassistant"),
    ):
        text = text.replace(old, new)
    if re.search("wowhac", text, re.I):
        raise ValueError("Unrecognized old branding remains in authored content")
    if "P7FaqjcATp" in text or re.search(r"https?://priorityassistant\.", text, re.I):
        raise ValueError("Unexpected legacy invitation or generated product URL")
    return text


def field(text, name, value):
    text, count = re.subn(rf"(?m)^## {re.escape(name)}:[^\r\n]*", f"## {name}: {value}", text)
    if count != 1:
        raise ValueError(f"The addon TOC must contain exactly one {name} field")
    return text


def standalone_embeds(text):
    # Bundled providers used to supply this library before AceEvent loaded.
    # A standalone addon must explicitly load its own copy after LibStub.
    if "CallbackHandler-1.0" not in text:
        text, count = re.subn(
            r'(<Script\s+file="Libs\\LibStub\\LibStub\.lua"\s*/>)',
            lambda match: match[1] + '\n    <Include file="Libs\\CallbackHandler-1.0\\CallbackHandler-1.0.xml"/>',
            text,
        )
        if count != 1:
            raise ValueError("Cannot locate the LibStub entry in embeds.xml")
    return text


def authored_files(interface):
    result = {}
    for source in sorted((ROOT / "src").rglob("*")):
        if source.is_symlink():
            raise ValueError(f"Source symlinks are not supported: {source}")
        if not source.is_file():
            continue
        relative = source.relative_to(ROOT / "src").as_posix()
        if relative.split("/")[0].casefold() == "libs":
            raise ValueError("src/Libs is not supported; target dependencies come from prebuilds")
        destination = safe_path(rebrand(relative))
        data = source.read_bytes()
        if source.suffix.lower() in TEXT_SUFFIXES:
            text = rebrand(data.decode("utf-8-sig"))
            if relative == f"{SOURCE_ADDON}.toc":
                text = field(text, "Interface", interface)
                text = field(text, "Title", ADDON)
                text = field(text, "Notes", "Custom priority actions with optional rotation-provider integration.")
                text = field(text, "SavedVariables", f"{ADDON}DB")
            elif relative == "embeds.xml":
                text = standalone_embeds(text)
            elif relative == "Frames/PixelFrame.lua":
                text = text.replace('CreateFrame("Frame", "PixelFrame",', 'CreateFrame("Frame", "PriorityAssistantPixelFrame",')
            data = text.encode("utf-8")
        result[destination] = data
    return result


def library_files(donor):
    result = {}
    seen = set()
    prefix = f"{SOURCE_ADDON}/Libs/"
    with ZipFile(donor) as archive:
        for entry in archive.infolist():
            name = safe_path(entry.filename)
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"Archive symlinks are not supported: {donor.name}/{name}")
            if entry.is_dir():
                continue
            if name.casefold() in seen:
                raise ValueError(f"Duplicate archive path: {donor.name}/{name}")
            seen.add(name.casefold())
            if name.startswith(prefix):
                # Do not inspect or copy any other addon or old authored files.
                if "tests" in PurePosixPath(name).parts:
                    continue
                result[name[len(SOURCE_ADDON) + 1:]] = archive.read(entry)
    if not result:
        raise ValueError(f"No embedded libraries in {donor.name}")
    return result


def references(name, data):
    text = data.decode("utf-8-sig")
    if name.lower().endswith(".toc"):
        return [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    return XML_FILES.findall(text)


def validate(files, authored, interface, release_version):
    names = {name.casefold(): name for name in files}
    if len(names) != len(files):
        raise ValueError("Case-insensitive duplicate package paths")
    for name in files:
        safe_path(name)
        if re.search("wowhac", name, re.I):
            raise ValueError(f"Old branding in package path: {name}")
        if name in authored and PurePosixPath(name).suffix.lower() in TEXT_SUFFIXES:
            if re.search(rb"wowhac", files[name], re.I):
                raise ValueError(f"Old branding in authored file: {name}")
        if name.lower().endswith((".toc", ".xml")):
            for reference in references(name, files[name]):
                reference = reference.replace("\\", "/")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), reference))
                safe_path(resolved)
                if resolved.casefold() not in names:
                    raise ValueError(f"Missing file referenced by {name}: {reference}")
    toc = files[f"{ADDON}.toc"].decode("utf-8")
    for key, value in {"Interface": interface, "Title": ADDON, "Version": release_version, "SavedVariables": f"{ADDON}DB"}.items():
        if not re.search(rf"(?m)^## {key}: {re.escape(str(value))}\r?$", toc):
            raise ValueError(f"Incorrect {key} in generated TOC")
    embeds = [ref.replace("\\", "/") for ref in references("embeds.xml", files["embeds.xml"])]
    required = ["Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.xml", "Libs/AceEvent-3.0/AceEvent-3.0.xml"]
    if any(name not in embeds for name in required) or [embeds.index(name) for name in required] != sorted(embeds.index(name) for name in required):
        raise ValueError("LibStub and CallbackHandler must load before AceEvent")


def write_archive(destination, files):
    # Fixed timestamps/permissions and ordering make repeated builds identical.
    temporary = destination.with_suffix(".zip.tmp")
    try:
        with ZipFile(temporary, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for name, data in sorted(files.items()):
                entry = ZipInfo(f"{ADDON}/{name}", date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (stat.S_IFREG | 0o644) << 16
                entry.compress_type = ZIP_DEFLATED
                archive.writestr(entry, data, compress_type=ZIP_DEFLATED, compresslevel=9)
        with ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError(f"Archive checksum validation failed: {destination.name}")
            if {name.split("/")[0] for name in archive.namelist()} != {ADDON}:
                raise ValueError("The archive must contain only the PriorityAssistant folder")
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="Directory for standalone ZIP archives")
    args = parser.parse_args()
    release_version = version()
    output = args.output.resolve()
    for protected in (ROOT / "src", ROOT / "prebuilds"):
        if output == protected or protected in output.parents:
            raise ValueError("Output must be outside src and prebuilds")
    output.mkdir(parents=True, exist_ok=True)
    count = 0
    for game_version, interface, donor in targets():
        authored = authored_files(interface)
        files = {**authored, **library_files(donor)}
        validate(files, authored, interface, release_version)
        destination = output / f"{ADDON}-{release_version}-{game_version}.zip"
        write_archive(destination, files)
        count += 1
        print(f"{destination.name}: Interface {interface}, {len(files)} files")
    print(f"Built {count} standalone archives in {output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, BadZipFile) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
