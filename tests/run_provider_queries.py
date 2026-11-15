"""Run focused query-provider regressions, comparing their stable source versions."""

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
    parser.add_argument("--baseline-ref", default="270933f")
    parser.add_argument("--provider-ref", help="Candidate provider Git revision, instead of the working tree")
    parser.add_argument("--registry-ref", help="Provider registry Git revision, instead of the working tree")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    files = ("AethysRotationProvider.lua", "AssistedCombat.lua", "BetterAssistantProvider.lua", "RotationHelperProvider.lua")
    with tempfile.TemporaryDirectory(prefix="wowhac-query-tests-") as directory:
        def snapshot(ref: str, label: str, names=files) -> str:
            if ref.startswith("-"):
                raise ValueError("A Git revision cannot start with '-'")
            target = Path(directory) / label
            for name in names:
                relative = f"src/Providers/{name}"
                content = subprocess.check_output(["git", "show", f"{ref}:{relative}"], cwd=root)
                path = target / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            return target.as_posix()

        try:
            baseline = snapshot(options.baseline_ref, "baseline")
            candidate = snapshot(options.provider_ref, "candidate") if options.provider_ref else root.as_posix()
            registry = snapshot(options.registry_ref, "registry", ("ProviderRegistry.lua",)) if options.registry_ref else root.as_posix()
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(error, file=sys.stderr)
            return 2
        interpreter = options.lua or shutil.which("lua") or shutil.which("luajit")
        if interpreter:
            return subprocess.run([interpreter, str(root / "tests/provider_queries.lua"), root.as_posix(), baseline, candidate, registry],
                                  cwd=root, check=False).returncode
        if options.runtime_path:
            sys.path.insert(0, str(Path(options.runtime_path).resolve()))
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            print("Supply --lua or install lupa in an isolated Python environment.", file=sys.stderr)
            return 2
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals()["_TEST_ROOT"] = root.as_posix()
        lua.globals()["_BASELINE_ROOT"] = baseline
        lua.globals()["_CANDIDATE_ROOT"] = candidate
        lua.globals()["_REGISTRY_ROOT"] = registry
        try:
            lua.execute((root / "tests/provider_queries.lua").read_text(encoding="utf-8"))
        except Exception as error:
            print(error, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
