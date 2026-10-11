These regressions execute the actual addon Lua in isolated WoW/Ace fixtures. They cover Forever client detection, the existing Retail and Classic pixel behavior, native and legacy spell APIs, JustAC suggestion priority, item suggestions, waiting queues, low-health warnings, and keyboard encoding.

Forever is identified by the client's matching `WOW_PROJECT_CAMELOT` and `WOW_PROJECT_ID` values. It blocks output while a cast or channel is present, without reading current IDs, comparing timestamps, or querying legacy castability. Tests verify that interface `16001` alone does not activate this behavior and that other clients retain their original gate.

With Lua installed, run `python tests/run_regressions.py` (or `lua tests/regression.lua .`). Without Lua, use an isolated Python environment:

```powershell
python -m venv .venv-tests
.venv-tests\Scripts\python -m pip install lupa
.venv-tests\Scripts\python tests\run_regressions.py
```

An existing isolated Lupa installation can be supplied with `--runtime-path PATH`; an interpreter can be supplied with `--lua PATH`. Lupa runs these checks on Lua 5.1, matching the addon's language baseline. The tests mock the client APIs; an in-game check is still needed for beta-client secret values and actual action-bar bindings.
