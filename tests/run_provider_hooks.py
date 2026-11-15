"""Run focused hook-provider compatibility and lifecycle regressions."""

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
    parser.add_argument("--provider-ref", help="Git revision for adapter sources; defaults to the working tree")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    names = ("ConROProvider", "ConROCProvider", "HekiliProvider", "HeroRotationProvider",
             "MaxDpsProvider", "OvaleProvider", "SimpleAssistedCombat")
    if options.provider_ref and options.provider_ref.startswith("-"):
        parser.error("A Git revision cannot start with '-'")
    with tempfile.TemporaryDirectory(prefix="wowhac-hook-tests-") as directory:
        adapter_root = root / "src"
        if options.provider_ref:
            adapter_root = Path(directory)
            (adapter_root / "Providers").mkdir()
            for name in names:
                path = f"src/Providers/{name}.lua"
                try:
                    content = subprocess.check_output(
                        ["git", "show", f"{options.provider_ref}:{path}"], cwd=root,
                    )
                except subprocess.CalledProcessError as error:
                    print(error, file=sys.stderr)
                    return 2
                (adapter_root / "Providers" / f"{name}.lua").write_bytes(content)
        print(f"Provider source: {options.provider_ref or 'working tree'}", flush=True)
        interpreter = options.lua or shutil.which("lua") or shutil.which("luajit")
        if interpreter:
            return subprocess.run(
                [interpreter, str(root / "tests" / "provider_hooks.lua"),
                 root.as_posix(), adapter_root.as_posix()], cwd=root, check=False,
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
        lua.globals()["_ADAPTER_ROOT"] = adapter_root.as_posix()
        try:
            lua.execute((root / "tests" / "provider_hooks.lua").read_text(encoding="utf-8"))
        except Exception as error:
            print(error, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
