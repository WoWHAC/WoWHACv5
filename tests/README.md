Run the focused Hekili adapter regressions with `python tests/run_hekili.py` when Lua is available. Alternatively, install `lupa` in an isolated Python environment and run the script with that Python. `--lua PATH` selects an interpreter; `--runtime-path PATH` selects an existing isolated Lupa installation. Lupa runs Lua 5.1.

The default run uses a small public API fixture and requires no Hekili download. To repeat the checks against a downloaded Hekili Forever source tree, run:

```powershell
python tests/run_hekili.py --hekili-root temp/Hekili
```

This loads the fork's real `Engine/Output.lua`, including its publish, subscribe, unsubscribe and buffer-swap behavior. Both runs execute the repository's actual provider registry, Hekili adapter and binding encoder. The checks cover empty/paused/disabled/unbound/future recommendations, item IDs, binding updates and abbreviations, provider switching and cleanup, minor cooldown toggle names, plus both older Hekili integration paths. These are mocked client checks; they do not replace testing in the game.

For the JustAC regression against stable revision `270933f`, run `python tests/run_justac.py`. The runner snapshots the actual stable provider into a temporary directory and compares its priority and binding behavior with the working provider. The remaining client and registry source comes from the working tree. It also checks paired queue reads, switching, item IDs, waiting entries and disabled custom-priority pixel output.

Use `--provider-ref 152d035` to reproduce the automatic-heal/maintenance regressions in the unfixed revision. `--baseline-ref REF` selects another stable provider. The Lua and isolated Lupa options match the Hekili runner. The runner neither edits the checkout nor changes Git history.

`--pipeline-ref 152d035` additionally loads that revision's `PriorityOverlays.lua` and `Rotation.lua`, reproducing the channel-tail and initial secure-binding-override regressions. The working pipeline checks the 300 ms provider boundary, strict priority/Forever channel blocking, unreadable data, and provider fallback beneath an overridden custom action.

The broader provider checks use the same Lua/Lupa runtime options:

```powershell
python tests/run_provider_registry.py
python tests/run_provider_queries.py
python tests/run_provider_hooks.py
```

The registry suite covers transient-error recovery, atomic ID/key output, saved selection, initialization rollback, stale callbacks and combat restrictions. `--source-ref 152d035` reproduces the old registry failures. The query suite compares AethysRotation, Assisted Combat, BetterAssistant and RotationHelper against `270933f`; `--registry-ref 152d035` reproduces their shared recovery failure. The hook suite covers ConRO, ConROC, HeroRotation, Hekili's older APIs, SimpleAssistedCombat, MaxDps and Ovale; `--provider-ref 152d035` reproduces the MaxDps activation and Ovale API/cache failures. Git history must include the requested reference commits. All suites use mocked client APIs and do not replace in-game testing.
