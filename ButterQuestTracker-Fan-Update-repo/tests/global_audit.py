#!/usr/bin/env python3
"""Lists every read of an undefined global made by the addon's own files while the scenarios run.

Reads of globals that are *meant* to be optional (other addons, newer client APIs) are expected;
anything else is a typo or a missing API worth looking at.
"""
import os
import sys
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FLAVORS = sys.argv[1:] or ["era", "era_oldui", "forever", "forever_oldmenu", "retail"]

AUDIT = r'''
local reads = {}
local function install()
    setmetatable(_G, { __index = function(_, key)
        local info = debug.getinfo(2, "Sl")
        local source = info and info.source or "?"
        if source:find("ButterQuestTracker%-master/") and not source:find("/Libs/") and not source:find("/tests/") then
            local where = source:gsub("^.*ButterQuestTracker%-master/", "") .. ":" .. tostring(info.currentline)
            reads[key] = reads[key] or {}
            reads[key][where] = true
        end
        return nil
    end })
end
return { install = install, reads = reads }
'''

seen = {}
for flavor in FLAVORS:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ROOT_DIR = ROOT
    audit = lua.execute(AUDIT)
    H = lua.eval("loadfile")(os.path.join(HERE, "harness.lua"))()
    lua.globals().H = H
    # the audit hook goes in once the harness has defined its own globals, just before the addon loads
    original_boot = H.boot
    lua.globals().audit = audit
    lua.execute("""
        local boot = H.boot
        H.boot = function(name)
            local realLoadfile = loadfile
            local installed = false
            _G.loadfile = function(path)
                if not installed and path:find("ButterQuestTracker.lua", 1, true) then
                    installed = true
                    audit.install()
                end
                return realLoadfile(path)
            end
            return boot(name)
        end
    """)
    try:
        lua.eval("loadfile")(os.path.join(HERE, "scenarios.lua"))(flavor)
    except Exception as exc:
        print("scenario crashed for", flavor, exc)
    for key, wheres in audit.reads.items():
        for where in wheres.keys():
            seen.setdefault(str(key), {}).setdefault(where, set()).add(flavor)

for key in sorted(seen):
    print(key)
    for where, flavors in sorted(seen[key].items()):
        print("    %-55s %s" % (where, ",".join(sorted(flavors))))
