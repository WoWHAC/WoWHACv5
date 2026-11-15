"""Compare the JustAC adapter with its stable source and run focused regressions."""

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
    parser.add_argument("--baseline-ref", default="270933f", help="Stable provider Git revision")
    parser.add_argument("--provider-ref", help="Candidate provider Git revision; defaults to the working tree")
    parser.add_argument("--pipeline-ref", help="Git revision for PriorityOverlays and Rotation; defaults to the working tree")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    provider = "src/Providers/JustACProvider.lua"

    def from_git(ref: str, path: str = provider) -> bytes:
        if ref.startswith("-"):
            raise ValueError("A Git revision cannot start with '-'")
        return subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=root)

    try:
        baseline = from_git(options.baseline_ref)
        candidate = from_git(options.provider_ref) if options.provider_ref else (root / provider).read_bytes()
        pipeline = {
            path: from_git(options.pipeline_ref, path)
            for path in ("src/Utils/PriorityOverlays.lua", "src/Rotation.lua")
        } if options.pipeline_ref else {}
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="wowhac-justac-tests-") as directory:
        baseline_path, candidate_path = Path(directory) / "baseline.lua", Path(directory) / "candidate.lua"
        baseline_path.write_bytes(baseline)
        candidate_path.write_bytes(candidate)
        for path, content in pipeline.items():
            target = Path(directory) / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        pipeline_dir = Path(directory).as_posix() if pipeline else ""
        print(
            f"Stable {options.baseline_ref}; candidate {options.provider_ref or 'working tree'}; "
            f"pipeline {options.pipeline_ref or 'working tree'}", flush=True,
        )
        interpreter = options.lua or shutil.which("lua") or shutil.which("luajit")
        if interpreter:
            return subprocess.run(
                [interpreter, str(root / "tests" / "justac.lua"), root.as_posix(),
                 baseline_path.as_posix(), candidate_path.as_posix(), pipeline_dir], cwd=root, check=False,
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
        lua.globals()["_BASELINE_PATH"] = baseline_path.as_posix()
        lua.globals()["_CANDIDATE_PATH"] = candidate_path.as_posix()
        lua.globals()["_PIPELINE_DIR"] = pipeline_dir
        try:
            lua.execute((root / "tests" / "justac.lua").read_text(encoding="utf-8"))
        except Exception as error:
            print(error, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
