"""Run provider-session and saved-selection regressions on the actual core Lua."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", help="Lua interpreter path")
    parser.add_argument("--runtime-path", help="Directory containing an isolated Lupa installation")
    parser.add_argument("--source-ref", help="Git revision for Provider and ProviderRegistry; defaults to working tree")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="wowhac-registry-tests-") as directory:
        source_root = root
        if options.source_ref:
            if options.source_ref.startswith("-"):
                parser.error("A Git revision cannot start with '-'")
            source_root = Path(directory)
            for path in ("src/Providers/Provider.lua", "src/Providers/ProviderRegistry.lua"):
                target = source_root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(subprocess.check_output(["git", "show", f"{options.source_ref}:{path}"], cwd=root))
        print(f"Provider core: {options.source_ref or 'working tree'}", flush=True)
        interpreter = options.lua or shutil.which("lua") or shutil.which("luajit")
        if interpreter:
            return subprocess.run(
                [interpreter, str(root / "tests" / "provider_registry.lua"), source_root.as_posix()],
                cwd=root, check=False,
            ).returncode
        if options.runtime_path:
            sys.path.insert(0, str(Path(options.runtime_path).resolve()))
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            print("Supply --lua or install lupa in an isolated Python environment.", file=sys.stderr)
            return 2
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals()["_SOURCE_ROOT"] = source_root.as_posix()
        try:
            lua.execute((root / "tests" / "provider_registry.lua").read_text(encoding="utf-8"))
        except Exception as error:
            print(error, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
