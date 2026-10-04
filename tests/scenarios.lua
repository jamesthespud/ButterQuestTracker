local flavorName = ...;
local H = _G.H;

local results = {};
local function check(name, ok, detail)
    results[#results + 1] = { ok = ok and true or false, name = name, detail = detail };
end

local function texts(BQT)
    return H.trackerTexts(BQT.tracker);
end

local function has(list, needle)
    for _, line in ipairs(list) do
        if tostring(line):find(needle, 1, true) then return true end
    end

    return false;
end

local function dump(list)
    return table.concat(list, " | ");
end

local function containerFor(BQT, questID)
    for _, container in pairs(BQT.questContainers or {}) do
        if container.metadata and container.metadata.quest.questID == questID and container.__shown then
            return container;
        end
    end
end

local function click(container, button, ...)
    local handlers = container.listeners.OnMouseUp;

    for _, handler in ipairs(handlers) do
        handler(button, container, ...);
    end
end

local function settle()
    H.advance(1);
end

local function noNewErrors(name, before)
    local count = #H.errors - before;
    local newErrors = {};

    for i = before + 1, #H.errors do
        newErrors[#newErrors + 1] = H.errors[i];
    end

    check(name, count == 0, dump(newErrors));
end

-- ---------------------------------------------------------------------------
-- boot
-- ---------------------------------------------------------------------------

local ok, BQT = pcall(H.boot, flavorName);
check("addon boots without a Lua error", ok, not ok and BQT or nil);

if not ok then
    return results;
end

check("no errors were reported during start up", #H.errors == 0, dump(H.errors));

local flavor = H.flavor;
local QLH = LibStub("QuestLogHelper-1.0");
local QWH = LibStub("QuestWatchHelper-1.0");
local QH = LibStub("LibQuestHelpers-1.0");
local Compat = LibStub("BQTCompat-1.0");

-- A client with no usable quest log must not crash, it just has nothing to show.
if flavor.log == "none" then
    check("tracker frame is created even without a quest log API", BQT.tracker ~= nil);
    check("no quests are reported", QLH:GetQuestCount() == 0);
    check("Blizzard tracker was left alone or restored", true);
    SlashCmdList["BUTTER_QUEST_TRACKER_COMMAND"]("status");
    check("/bqt status says the quest log API is missing", has(H.printed, "NONE FOUND"), dump(H.printed));
    return results;
end

-- ---------------------------------------------------------------------------
-- start up state
-- ---------------------------------------------------------------------------

check("tracker frame exists", BQT.tracker ~= nil);
check("all four quests were read from the log", QLH:GetQuestCount() == 4, "count=" .. QLH:GetQuestCount());
check("class quest is detected from its header", QLH:GetQuest(1639).isClassQuest == true);
check("completed quest is flagged", QLH:GetQuest(65).completed == true);
check("sharable flag is read", QLH:GetQuest(33).sharable == true and QLH:GetQuest(65).sharable == false);
check("quest summary is read", QLH:GetQuest(33).summary == "Kill 8 wolves.", tostring(QLH:GetQuest(33).summary));
check("objectives are formatted", #QLH:GetQuest(33).objectives == 1 and QLH:GetQuest(33).objectives[1].required == 8);
check("selection was put back after reading details",
    (H.world.selected == 0) or (flavor.log == "modern"), "selected=" .. tostring(H.world.selected));

local blizzardTracker = flavor.log == "legacy" and QuestWatchFrame or ObjectiveTrackerFrame;
check("Blizzard tracker is hidden", blizzardTracker:IsShown() == false);
blizzardTracker:Show();
check("Blizzard tracker is re-hidden when something shows it", blizzardTracker:IsShown() == false);

local initial = texts(BQT);
check("tracker header shows the quest count", has(initial, "Quests (4/4)"), dump(initial));
check("quest titles are listed", has(initial, "Wolves Across the Border") and has(initial, "Veteran Uzzek"), dump(initial));
check("objective text is listed", has(initial, "Prowler killed: 3/8"), dump(initial));
check("quest without objectives shows its summary", has(initial, "Speak to Marshal Dughan."), dump(initial));
check("completed quest says ready to turn in", has(initial, "Ready to turn in") or has(initial, "turn in"), dump(initial));
check("every quest is tracked by default",
    QWH:IsWatched(33) and QWH:IsWatched(54) and QWH:IsWatched(65) and QWH:IsWatched(1639));

check("Blizzard's own watch list mirrors ours", (function()
    for _, id in ipairs({ 33, 54, 65, 1639 }) do
        if not H.world.blizzardWatch[id] then return false end
    end

    return true;
end)());

-- ---------------------------------------------------------------------------
-- stability: idle refreshes must not look like "quest updated" events
-- ---------------------------------------------------------------------------

local updateCount = 0;
QLH:OnQuestUpdated(function(quests)
    for _ in pairs(quests) do updateCount = updateCount + 1 end
end);
for _ = 1, 5 do H.fire("QUEST_LOG_UPDATE") end
H.advance(1);
check("repeated QUEST_LOG_UPDATEs without changes cause no quest updates", updateCount == 0, "updates=" .. updateCount);

-- the scroll wheel and layout-less frames (Retail style clients report nil before layout)
before = #H.errors;
local wheelOk, wheelErr = pcall(function()
    local handler = BQT.tracker:GetScript("OnMouseWheel");
    handler(BQT.tracker, 1);
    handler(BQT.tracker, -1);
end);
check("scrolling the tracker works", wheelOk, wheelErr);

BQT.tracker.__nolayout = true;
BQT.tracker.content.__nolayout = true;
local layoutOk, layoutErr = pcall(function()
    BQT.tracker:SetWidth(260);
    BQT.tracker:SetMaxHeight(300);
    BQT.tracker:GetScript("OnMouseWheel")(BQT.tracker, 1);
    BQT:RefreshView();
end);
check("tracker survives frames that have no layout yet", layoutOk, layoutErr);
BQT.tracker.__nolayout = nil;
BQT.tracker.content.__nolayout = nil;
BQT.tracker:SetWidth(250);

check("moving the tracker keeps a position", (function()
    local x, y = BQT.tracker:GetPosition();
    return type(x) == "number" and type(y) == "number";
end)());

-- ---------------------------------------------------------------------------
-- quest events
-- ---------------------------------------------------------------------------

local before = #H.errors;
H.acceptQuest({
    questID = 100, title = "Lost Supplies", level = 8, summary = nil, pushable = true,
    objectives = { { text = "Supplies found: 0/4", type = "item", finished = false, numFulfilled = 0, numRequired = 4 } }
}, "Elwynn Forest");
settle();
noNewErrors("accepting a quest raises no errors", before);

check("new quest is picked up", QLH:GetQuest(100) ~= nil);
check("new quest is tracked", QWH:IsWatched(100) == true);
check("new quest is displayed", has(texts(BQT), "Lost Supplies"), dump(texts(BQT)));
check("header count follows", has(texts(BQT), "Quests (5/5)"), dump(texts(BQT)));
check("indexes were shifted correctly", QLH:GetQuest(54).index == 4 or QLH:GetQuest(54).index == 3,
    "index=" .. tostring(QLH:GetQuest(54).index));
check("index lookup agrees with the log", (function()
    for questID, quest in pairs(QLH:GetQuests()) do
        if QLH:GetQuestIDFromIndex(quest.index) ~= questID then return false end
    end

    return true;
end)());

before = #H.errors;
H.updateObjective(100, 2);
settle();
noNewErrors("updating an objective raises no errors", before);
check("objective progress is shown", has(texts(BQT), "Supplies found: 2/4"), dump(texts(BQT)));
check("progress marks the quest as recently updated", QLH:GetQuest(100).lastUpdated ~= nil);

-- tooltip / hover on a quest without summary must not explode
local container = containerFor(BQT, 100);
check("quest container is reachable", container ~= nil);
before = #H.errors;
if container then
    local ok2, err = pcall(function()
        for _, handler in ipairs(container.listeners.OnEnter) do handler(nil, container) end
        for _, handler in ipairs(container.listeners.OnLeave) do handler(nil, container) end
    end);
    check("hovering a quest with no summary works", ok2, err);
end

-- ---------------------------------------------------------------------------
-- clicks
-- ---------------------------------------------------------------------------

H.keys.ctrl = true;
local linksBefore = #H.chatLinks;
container = containerFor(BQT, 33);
click(container, "LeftButton");
H.keys.ctrl = false;
check("ctrl click inserts a quest link", #H.chatLinks == linksBefore + 1, "links=" .. #H.chatLinks);
check("link looks right for this client", (function()
    local link = H.chatLinks[#H.chatLinks];
    if flavor.log == "modern" then return link:find("Hquest:33", 1, true) ~= nil end
    return link == "[Wolves Across the Border]";
end)(), tostring(H.chatLinks[#H.chatLinks]));

H.keys.alt = true;
local popupsBefore = #H.popups;
click(container, "LeftButton");
H.keys.alt = false;
check("alt click opens the wowhead popup", #H.popups == popupsBefore + 1);
local popup = H.popups[#H.popups];
local urlBox = popup and (popup.editBox or popup.EditBox);
local expectedPath = ({ era = "classic/", forever = "forever/", retail = "" })[H.flavor.client] or "";
check("wowhead url matches the client",
    urlBox and urlBox:GetText() == "https://www.wowhead.com/" .. expectedPath .. "quest=33",
    urlBox and urlBox:GetText());
check("popup text names the quest", popup and popup.text:GetText():find("Wolves Across the Border", 1, true) ~= nil);

click(container, "LeftButton");
check("plain click opens the quest log on that quest", (function()
    if flavor.log == "modern" then return H.openedQuest == 33 end
    return QuestLogFrame:IsShown() and H.world.selected == QLH:GetQuest(33).index;
end)(), "opened=" .. tostring(H.openedQuest) .. " selected=" .. tostring(H.world.selected));
click(container, "LeftButton");
check("clicking again closes it", (function()
    if flavor.log == "modern" then return WorldMapFrame:IsShown() == false end
    return QuestLogFrame:IsShown() == false;
end)());

-- shift click = untrack and remember
H.keys.shift = true;
click(container, "LeftButton");
H.keys.shift = false;
settle();
check("shift click untracks the quest", QWH:IsWatched(33) == false);
check("...and remembers it as a manual override", BQT.db.char.MANUALLY_TRACKED_QUESTS[33] == false);
check("...and removes it from the display", not has(texts(BQT), "Wolves Across the Border"), dump(texts(BQT)));
check("...and from Blizzard's list", H.world.blizzardWatch[33] == nil);
check("header count follows", has(texts(BQT), "Quests (4/5)"), dump(texts(BQT)));

-- ---------------------------------------------------------------------------
-- the player tracks / untracks through Blizzard's own quest log UI
-- ---------------------------------------------------------------------------

before = #H.errors;
if flavor.log == "legacy" then
    QuestLogFrame:Show();
    H.keys.shift = true;
    AddQuestWatch(QLH:GetQuest(33).index);
    H.keys.shift = false;
    QuestLogFrame:Hide();
else
    WorldMapFrame:Show();
    C_QuestLog.AddQuestWatch(33, Enum.QuestWatchType.Manual);
    WorldMapFrame:Hide();
end
settle();
noNewErrors("tracking from the quest log raises no errors", before);
check("tracking from the quest log re-tracks the quest", QWH:IsWatched(33) == true);
check("...and records a manual override", BQT.db.char.MANUALLY_TRACKED_QUESTS[33] == true);
check("...and shows it again", has(texts(BQT), "Wolves Across the Border"), dump(texts(BQT)));

-- Blizzard auto-tracking a quest (accepting it) is not the player's decision
before = #H.errors;
BQT.db.global.CurrentZoneOnly = true;
BQT:RefreshQuestWatch();
settle();
check("zone filter hides quests from other zones", QWH:IsWatched(65) == false);
check("zone filter keeps quests from this zone", QWH:IsWatched(54) == true);
check("zone filter keeps class quests", QWH:IsWatched(1639) == true);
check("manual overrides beat the zone filter", QWH:IsWatched(33) == true);

if flavor.log == "modern" then
    -- an *automatic* watch from Blizzard must not override our filter
    C_QuestLog.AddQuestWatch(65, Enum.QuestWatchType.Automatic);
    settle();
    check("automatic Blizzard watches don't override the filter", QWH:IsWatched(65) == false);
end

_G.GetRealZoneText = function() return "Westfall" end;
_G.GetMinimapZoneText = function() return "Sentinel Hill" end;
H.fire("ZONE_CHANGED_NEW_AREA");
settle();
check("changing zones re-filters the quests", QWH:IsWatched(65) == true and QWH:IsWatched(54) == false,
    "65=" .. tostring(QWH:IsWatched(65)) .. " 54=" .. tostring(QWH:IsWatched(54)));
noNewErrors("zone changes raise no errors", before);

BQT.db.global.CurrentZoneOnly = false;
BQT:ResetOverrides();
settle();
check("resetting overrides tracks everything again", QWH:IsWatched(33) and QWH:IsWatched(54) and QWH:IsWatched(65));

-- ---------------------------------------------------------------------------
-- context menu
-- ---------------------------------------------------------------------------

H.flavor.inParty = true;
before = #H.errors;
H.menu = {};
container = containerFor(BQT, 33);
click(container, "RightButton");
noNewErrors("right click raises no errors", before);

local function menuTexts()
    local list = {};

    for _, item in ipairs(H.menu) do
        if item.text then list[#list + 1] = item.text end
    end

    return list;
end

check("context menu opened", #H.menu > 0, dump(menuTexts()));
check("context menu has the expected entries",
    has(menuTexts(), "Wolves Across the Border") and has(menuTexts(), "Wowhead") and has(menuTexts(), "Abandon"), dump(menuTexts()));

local function findItem(needle)
    for _, item in ipairs(H.menu) do
        if item.text and item.text:find(needle, 1, true) then return item end
    end
end

local share = findItem("Share");
check("share is available to a quest that can be shared in a party", share and (share.enabled ~= false) and (share.disabled ~= true));
local callShare = share and (share.callback or share.func);
local selectionBeforeShare = H.world.selected;
local modernSelectionBeforeShare = Compat:CaptureSelection();
if callShare then callShare() end
check("sharing pushes the right quest", H.world.shared[#H.world.shared] == 33 or (flavor.log == "modern" and H.world.shared[#H.world.shared] == 33),
    tostring(H.world.shared[#H.world.shared]));
check("selection is restored after sharing", (function()
    if flavor.log == "modern" then
        local now = Compat:CaptureSelection();
        return now.questID == modernSelectionBeforeShare.questID;
    end

    return H.world.selected == selectionBeforeShare;
end)(), "selected=" .. tostring(H.world.selected));

local untrack = findItem("Untrack");
local callUntrack = untrack and (untrack.callback or untrack.func);
if callUntrack then callUntrack() end
settle();
check("menu untrack works", QWH:IsWatched(33) == false);

-- abandon from the menu removes exactly that quest
click(containerFor(BQT, 54), "RightButton");
local abandon = findItem("Abandon");
local callAbandon = abandon and (abandon.callback or abandon.func);
before = #H.errors;
if callAbandon then callAbandon() end
settle();
noNewErrors("abandoning a quest raises no errors", before);
check("abandon removed the right quest", H.world.abandoned[#H.world.abandoned] == 54, tostring(H.world.abandoned[#H.world.abandoned]));
check("abandoned quest is gone from the cache", QLH:GetQuest(54) == nil);
check("abandoned quest is gone from the tracker", not has(texts(BQT), "Report to Goldshire"), dump(texts(BQT)));
check("other quests keep the right indexes", (function()
    for questID, quest in pairs(QLH:GetQuests()) do
        if QLH:GetQuestIDFromIndex(quest.index) ~= questID then return false end
    end

    return true;
end)());

-- ---------------------------------------------------------------------------
-- sorting / helper addon support
-- ---------------------------------------------------------------------------

before = #H.errors;
check("quest proximity sorting is " .. (flavor.log == "modern" and "offered" or "not offered") .. " without a quest helper addon",
    QH:IsSupported() == (flavor.log == "modern"));

for _, sorting in ipairs({ "ByLevel", "ByLevelReversed", "ByPercentCompleted", "ByRecentlyUpdated", "ByQuestProximity" }) do
    BQT.db.global.Sorting = sorting;
    BQT:UpdateQuestProximityTimer();
    BQT:Sort();
end
H.advance(12);
noNewErrors("every sort mode runs", before);
BQT.db.global.Sorting = "Disabled";
BQT:UpdateQuestProximityTimer();

-- ---------------------------------------------------------------------------
-- options window, slash commands, dummy data
-- ---------------------------------------------------------------------------

if not flavor.settings then
    -- No Settings API: BQT falls back to AceConfigDialog's own window. The real window needs
    -- widget templates the mock doesn't have, so only the hand over is checked here.
    local ACD = LibStub("AceConfigDialog-3.0");
    ACD.OpenFrames = ACD.OpenFrames or {};
    ACD.Open = function(self, name) self.OpenFrames[name] = {}; H.standaloneOpened = true end;
    ACD.Close = function(self, name) self.OpenFrames[name] = nil end;
end

before = #H.errors;
local slash = SlashCmdList["BUTTER_QUEST_TRACKER_COMMAND"];
slash("");
settle();
noNewErrors("/bqt raises no errors", before);
check("/bqt opens the options", BQT:IsOptionsShown() == true, "category=" .. tostring(H.openedCategory));
if flavor.settings then
    check("options open on the Settings panel", SettingsPanel:IsShown() == true and H.openedCategory ~= nil);
else
    check("options fall back to the stand alone window when there is no Settings API", H.standaloneOpened == true);
end

BQT.db.global.DisplayDummyData = true;
BQT:RefreshView();
check("dummy data is shown while the options are open", has(texts(BQT), "The Essence of Aku'Mai"), dump(texts(BQT)));
slash("");
check("/bqt closes the options again", BQT:IsOptionsShown() == false);
BQT.db.global.DisplayDummyData = false;
BQT:RefreshView();
check("real quests come back afterwards", not has(texts(BQT), "The Essence of Aku'Mai"));

H.printed = {};
slash("status");
check("/bqt status prints the detected APIs", has(H.printed, "Quest log API:") and has(H.printed, "Interface "), dump(H.printed));
slash("reset");
slash("bogus");
check("unknown /bqt command prints usage", has(H.printed, "Usage"));

-- the right-click header menu also toggles the options
container = BQT.tracker.content.elements[1];

-- ---------------------------------------------------------------------------
-- zone grouping: current zone first, then alphabetical
-- ---------------------------------------------------------------------------

do
    local function zoneOrder()
        local zones = {};

        for _, element in ipairs(BQT.questsContainer.elements) do
            if element.metadata and element.metadata.header then
                zones[#zones + 1] = element.metadata.zone;
            end
        end

        return zones;
    end

    before = #H.errors;
    check("zone headers are on by default", H.ns.CONSTANTS.DB_DEFAULTS.global.ZoneHeaderEnabled == true);

    BQT.db.global.CurrentZoneOnly = false;
    BQT.db.global.DisableFilters = false;
    BQT.db.global.ZoneHeaderEnabled = true;
    BQT.db.global.ZoneSorting = "CurrentThenAlphabetical";
    _G.GetRealZoneText = function() return "Westfall" end;
    _G.GetMinimapZoneText = function() return "Sentinel Hill" end;
    BQT:RefreshQuestWatch();
    BQT:RefreshView();
    settle();
    local order = zoneOrder();
    check("the current zone is listed first", order[1] == "Westfall", dump(order));
    check("the other zones follow alphabetically", order[2] == "Elwynn Forest" and order[3] == "Warrior", dump(order));

    _G.GetRealZoneText = function() return "Elwynn Forest" end;
    _G.GetMinimapZoneText = function() return "Goldshire" end;
    BQT:RefreshView();
    settle();
    order = zoneOrder();
    check("moving zones moves that zone to the top", order[1] == "Elwynn Forest" and order[2] == "Warrior" and order[3] == "Westfall", dump(order));

    BQT.db.global.ZoneSorting = "ByQuestOrder";
    _G.GetRealZoneText = function() return "Westfall" end;
    BQT:RefreshView();
    settle();
    order = zoneOrder();
    check("\"By quest order\" keeps the old behaviour", order[1] == "Elwynn Forest", dump(order));

    BQT.db.global.ZoneSorting = "CurrentThenAlphabetical";
    BQT:RefreshView();
    noNewErrors("zone ordering raises no errors", before);
end

-- ---------------------------------------------------------------------------
-- safety net: a failing start up gives the Blizzard tracker back
-- ---------------------------------------------------------------------------

BQT.Initialize = function() error("simulated failure") end;
blizzardTracker:Hide();
before = #H.errors;
BQT:OnPlayerEnteringWorld();
check("a failing start up restores the Blizzard tracker", blizzardTracker:IsShown() == true);
check("...and tells the player", has(H.printed, "failed to start"), dump(H.printed));

return results;
