"""Run addon regressions with Lua or the optional Lupa Lua 5.1 runtime."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", help="Path to a Lua interpreter")
    parser.add_argument("--runtime-path", help="Directory containing an isolated Lupa installation")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    interpreter = options.lua or shutil.which("lua") or shutil.which("luajit")
    if interpreter:
        return subprocess.run(
            [interpreter, str(root / "tests" / "regression.lua"), root.as_posix()],
            cwd=root,
            check=False,
        ).returncode
    if options.runtime_path:
        sys.path.insert(0, str(Path(options.runtime_path).resolve()))
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        print(
            "Lua is unavailable. Supply --lua, or install lupa in a virtual environment "
            "and run this script with that environment's Python.",
            file=sys.stderr,
        )
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()["_TEST_ROOT"] = root.as_posix()
    try:
        lua.execute((root / "tests" / "regression.lua").read_text(encoding="utf-8"))
    except Exception as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
