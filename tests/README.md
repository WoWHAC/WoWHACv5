Run the focused Hekili adapter regressions with `python tests/run_hekili.py` when Lua is available. Alternatively, install `lupa` in an isolated Python environment and run the script with that Python. `--lua PATH` selects an interpreter; `--runtime-path PATH` selects an existing isolated Lupa installation. Lupa runs Lua 5.1.

The default run uses a small public API fixture and requires no Hekili download. To repeat the checks against a downloaded Hekili Forever source tree, run:

```powershell
python tests/run_hekili.py --hekili-root temp/Hekili
```

This loads the fork's real `Engine/Output.lua`, including its publish, subscribe, unsubscribe and buffer-swap behavior. Both runs execute the repository's actual provider registry, Hekili adapter and binding encoder. The checks cover empty/paused/disabled/unbound/future recommendations, item IDs, binding updates and abbreviations, provider switching and cleanup, minor cooldown toggle names, plus both older Hekili integration paths. These are mocked client checks; they do not replace testing in the game.
