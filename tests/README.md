# Tests

A mock of the WoW addon environment (`harness.lua`) plus scenarios (`scenarios.lua`) that run the whole
addon, start to finish, against several fake clients:

| flavour | what it simulates |
| --- | --- |
| `era`, `era_oldui`, `era_reentrant` | Classic Era style API (`GetQuestLogTitle`, global `AddQuestWatch`, `QuestWatchFrame`). `era_oldui` has no Settings API, `era_reentrant` fires `QUEST_LOG_UPDATE` whenever the selection changes. |
| `forever`, `forever_oldmenu`, `forever_reentrant`, `retail` | Modern API (`C_QuestLog.GetInfo`, `ObjectiveTrackerFrame`, `MenuUtil`, Settings panel). |
| `nolog` | A client where no usable quest log API exists. The addon must load quietly and show nothing. |

```
pip install lupa
python3 tests/run_tests.py            # everything
python3 tests/run_tests.py forever    # one flavour
python3 tests/global_audit.py         # lists reads of undefined globals made by the addon's own files
```

This is not a WoW emulator. It catches logic errors, missing guards and wrong API usage on the paths the
mock implements, it can't tell you how the real client lays things out or what a brand new API returns.
