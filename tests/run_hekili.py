"""Run focused Hekili adapter regressions using Lua 5.1 or optional Lupa."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", help="Lua interpreter path")
    parser.add_argument("--runtime-path", help="Directory containing an isolated Lupa installation")
    parser.add_argument("--hekili-root", type=Path, help="Optional Hekili Forever source root for real Engine/Output.lua checks")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    hekili = options.hekili_root.resolve().as_posix() if options.hekili_root else ""
    interpreter = options.lua or shutil.which("lua") or shutil.which("luajit")
    if interpreter:
        return subprocess.run(
            [interpreter, str(root / "tests" / "hekili.lua"), root.as_posix(), hekili],
            cwd=root,
            check=False,
        ).returncode
    if options.runtime_path:
        sys.path.insert(0, str(Path(options.runtime_path).resolve()))
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        print("Supply --lua or install lupa in an isolated Python environment.", file=sys.stderr)
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()["_TEST_ROOT"] = root.as_posix()
    lua.globals()["_HEKILI_ROOT"] = hekili
    try:
        lua.execute((root / "tests" / "hekili.lua").read_text(encoding="utf-8"))
    except Exception as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
