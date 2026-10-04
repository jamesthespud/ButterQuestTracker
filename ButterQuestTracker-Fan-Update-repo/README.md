**Butter Quest Tracker Fan Update** is an unofficial, community-maintained update of [Butter Quest Tracker](https://github.com/butter-cookie-kitkat/ButterQuestTracker) by Butter Cookie Kitkat, used under its MIT license. It is not made, endorsed or supported by the original author.

It has been played on the new **World of Warcraft: Forever** client. Classic Era, Cataclysm / Mists Classic and Retail support is checked against simulated clients only (see `tests/`), so please report anything odd.

## Installing

1. Delete any old `Interface/AddOns/ButterQuestTracker` folder (your settings are kept, they live in `WTF`).
2. Copy the `ButterQuestTracker` folder from this download into your game's `Interface/AddOns` folder for the right client (`_classic_era_`, `_classic_`, `_retail_`, or the WoW Forever folder).
3. The folder must be named exactly `ButterQuestTracker` (GitHub downloads call it `ButterQuestTracker-master`, rename it).
4. Start the game. If the addon is shown as "out of date", tick **Load out of date AddOns** on the character select AddOns screen, or add the new interface number to the first line of `ButterQuestTracker.toc` (see below).

All libraries (Ace3) are bundled, nothing else needs installing.

## What changed in this version

- Works on clients that no longer have the old Classic quest APIs (WoW Forever uses the modern Retail style API). Everything that talks to the game's quest, map or UI APIs now goes through `Compat/Compat.lua`, which checks what actually exists instead of guessing from the version number.
- BQT keeps its own list of tracked quests, so it no longer depends on Blizzard's tracking limit. It still mirrors the list into Blizzard's, and still reacts when you track/untrack from the quest log.
- Uses the modern Settings panel and Menu API when they exist (with fallbacks for older clients).
- Bundled libraries, and the old `Poncho` frame library (which needed a Blizzard internal that no longer exists) was replaced by a tiny built in one.
- Fixed several latent bugs: quests without objectives constantly re-triggering "updated", broken locale fallback, popup text fields that moved between clients, nil layout values, and stale quest log indexes.
- If BQT ever fails while starting, it gives you the default Blizzard tracker back instead of leaving you with none.

## If something looks wrong

Type `/bqt status` and read the lines it prints (client, which quest API was found, ...). Include that output when reporting an issue. Use BugSack/BugGrabber to capture Lua errors.

Slash commands: `/bqt` (options), `/bqt reset` (clear manual track/untrack choices), `/bqt status` (diagnostics).

## Keeping it working

Blizzard changes the addon API every patch, so "forever" really means "cheap to fix":

1. **New patch says the addon is out of date**: open `ButterQuestTracker.toc` and add the new interface number to the `## Interface:` line (find it with `/dump (select(4, GetBuildInfo()))` in game).
2. **A quest/map/UI function got renamed or removed**: fix it in `Compat/Compat.lua`. Each function there tries the modern API first and falls back to older ones, and every call is guarded so one missing function can't take the whole addon down.
3. **Check your change** without logging in: `pip install lupa` then `python3 tests/run_tests.py`. The tests load the whole addon against fake "Classic Era" and "Forever / Retail" clients (including ones with missing APIs) and drive tracking, clicks, menus and options.

# Butter Quest Tracker Fan Update

> A butter smooth quest tracker for World of Warcraft: Classic Era, Cataclysm / MoP Classic, Retail and **WoW Forever**

## Features

- Change tracker position
- Collapsible zone headers
- Format the quest headers to your liking
- Manually track / untrack quests (see caveats below)
- Quickly grab the Wowhead URL of a quest by alt clicking the quests
- Filter quests by your current zone / subzone
- Sort your quests by level, completion percentage, recently updated, or by quest proximity (only if you have a quest helper installed).
- Change the quest watch limit or remove it entirely
- Context menus to enable you to quickly share or abandon quests
- Colored quest names based on their difficulty
- Link quests in chat by ctrl clicking their name
- Adjust the font-size or padding of the tracker to your liking
- Type **/bqt** to quickly open the settings menu

## Supported Addons

### Quest Helpers

- [Questie](https://www.curseforge.com/wow/addons/questie) **(Removes pins and allows sorting "By Quest Proximity")**
- [ClassicCodex](https://www.curseforge.com/wow/addons/ClassicCodex) **(Removes pins and allows sorting "By Quest Proximity")**

### Quest Logs

- [Classic Quest Log](https://www.curseforge.com/wow/addons/classic-quest-log)
- [QuestLogEx](https://www.wowinterface.com/downloads/info24980-QuestLogEx.html)
- [QuestGuru](https://www.curseforge.com/wow/addons/questguru_classic)

## Manually Tracking / Untracking Quests

If you manually track / untrack a quest and which to reset it so that filtering will impact it again you need to do the following.

Open the BQT Settings menu (`/bqt`) > Filters & Sorting (Tab) > Reset Tracking Overrides

## Bugs or Feature requests

If you find a bug in this Fan Update, report it on this addon's CurseForge page and include the `/bqt status` output. Please don't report problems with this version to the original author.


## Credits and license

- Original addon: **Butter Quest Tracker** by Butter Cookie Kitkat, (c) 2019, MIT license. See `LICENSE`, which is unchanged.
- Fan Update changes (WoW Forever / modern API support, own tracked-quest list, stable zone grouping, bug fixes) are released under the same MIT license.
- Bundled libraries keep their own licenses: Ace3 (see `Libs/Ace3-LICENSE.txt`), LibStub and CallbackHandler.
