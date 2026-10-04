#!/usr/bin/env python3
"""Runs the mock-WoW test scenarios under Lua 5.1 (via the `lupa` package).

    pip install lupa
    python3 tests/run_tests.py [flavor ...]
"""
import os
import sys

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

FLAVORS = ["era", "era_oldui", "era_reentrant", "forever", "forever_oldmenu", "forever_reentrant", "retail", "nolog"]


def run(flavor):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("ROOT_DIR = ...", ROOT) if False else None
    lua.globals().ROOT_DIR = ROOT

    # `require`-less loading: harness and scenarios are plain chunks that return a table.
    harness = lua.eval("loadfile")(os.path.join(HERE, "harness.lua"))()
    lua.globals().H = harness
    scenarios = lua.eval("loadfile")(os.path.join(HERE, "scenarios.lua"))
    results = scenarios(flavor)

    return results


def main():
    flavors = sys.argv[1:] or FLAVORS
    failed = 0

    for flavor in flavors:
        print("=" * 70)
        print("FLAVOR:", flavor)
        print("=" * 70)

        try:
            results = run(flavor)
        except Exception as exc:  # a Lua error escaping the scenarios
            print("  CRASH:", exc)
            failed += 1
            continue

        for row in results.values():
            ok, name, detail = row["ok"], row["name"], row["detail"]
            print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, ("  -> " + str(detail)) if (detail and not ok) else ""))
            if not ok:
                failed += 1

    print()
    print("FAILURES:", failed)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
