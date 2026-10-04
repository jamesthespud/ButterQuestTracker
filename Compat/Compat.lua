--[[
    BQTCompat-1.0

    Every call BQT makes into Blizzard's quest / map / UI APIs goes through this file.
    Blizzard has renamed or removed these functions several times (and the new
    "WoW Forever" client uses the modern, Retail-style API on top of Classic content),
    so nothing in here is decided by the client version number. Each function checks
    which API actually exists at call time and falls back to the next best option.

    If a future patch breaks the addon, this is almost always the only file that
    needs touching. Run `/bqt status` in game to see which API paths were detected.
]]

local MAJOR, MINOR = "BQTCompat-1.0", 1;
local Compat = LibStub:NewLibrary(MAJOR, MINOR);
if not Compat then return end

local _G = _G;
local pcall, type, pairs, select, tostring = pcall, type, pairs, select, tostring;
local floor, sqrt = math.floor, math.sqrt;

-- ---------------------------------------------------------------------------
-- Client information (only used for labels / URLs, never for behaviour)
-- ---------------------------------------------------------------------------

local interfaceVersion = select(4, GetBuildInfo()) or 0;
Compat.interfaceVersion = interfaceVersion;

local function detectFlavor(v)
    if v >= 120000 then return "retail";
    elseif v >= 50000 then return "mists";
    elseif v >= 40000 then return "cata";
    elseif v >= 30000 then return "wrath";
    elseif v >= 20000 then return "tbc";
    elseif v >= 16000 then return "forever";
    end

    return "era";
end

Compat.flavor = detectFlavor(interfaceVersion);

local WOWHEAD_PATHS = {
    retail = "",
    era = "classic/",
    tbc = "tbc/",
    wrath = "wotlk/",
    cata = "cata/",
    mists = "mop-classic/",
    forever = "forever/"
};

function Compat:GetWowheadURL(questID)
    return "https://www.wowhead.com/" .. (WOWHEAD_PATHS[self.flavor] or "") .. "quest=" .. tostring(questID);
end

function Compat:GetAddonMetadata(addonName, field)
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata;

    if type(getter) ~= "function" then return nil end

    local ok, value = pcall(getter, addonName, field);

    return ok and value or nil;
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function isFunction(value)
    return type(value) == "function";
end

local function qlog()
    return _G.C_QuestLog;
end

local function qlogHas(name)
    local c = qlog();

    return c ~= nil and isFunction(c[name]);
end

-- Calls fn and returns its results, or nothing if it raised an error.
local function try(fn, ...)
    if not isFunction(fn) then return end

    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...);

    if ok then
        return a, b, c, d, e, f, g, h;
    end
end

Compat.Try = function(_, fn, ...) return try(fn, ...) end

-- Compat:SafeHook("GlobalFunction", handler)  or  Compat:SafeHook(someTable, "Method", handler)
function Compat:SafeHook(target, name, handler)
    if type(target) == "string" then
        -- global function name, the handler is the second argument
        handler = handler or name;

        if not isFunction(_G[target]) or not isFunction(handler) then return false end

        return pcall(hooksecurefunc, target, handler);
    end

    if type(target) == "table" and isFunction(target[name]) then
        return pcall(hooksecurefunc, target, name, handler);
    end

    return false;
end

-- ---------------------------------------------------------------------------
-- Quest log enumeration
-- ---------------------------------------------------------------------------

-- True when the Retail-style C_QuestLog API is available (Retail, WoW Forever, ...).
function Compat:HasModernQuestLog()
    return qlogHas("GetInfo") and qlogHas("GetNumQuestLogEntries");
end

function Compat:HasLegacyQuestLog()
    return isFunction(_G.GetQuestLogTitle) and isFunction(_G.GetNumQuestLogEntries);
end

function Compat:CanReadQuestLog()
    return self:HasModernQuestLog() or self:HasLegacyQuestLog();
end

function Compat:GetMaxQuests()
    local max = try(qlog() and qlog().GetMaxNumQuestsCanAccept)
        or try(qlog() and qlog().GetMaxNumQuests);

    if type(max) == "number" and max > 0 then
        return max;
    end

    return 25;
end

--[[
    Returns a normalised list of quest log rows:
        { index, title, level, isHeader, questID, completed, failed }
    No matter which API the client provides.
]]
function Compat:GetQuestLogEntries()
    local entries = {};

    if self:HasModernQuestLog() then
        local C = qlog();
        local numEntries = try(C.GetNumQuestLogEntries) or 0;

        for index = 1, numEntries do
            local info = try(C.GetInfo, index);

            if info and not info.isHidden and not info.isBounty then
                local questID = info.questID;
                local isHeader = info.isHeader and true or false;
                local completed, failed = false, false;

                if not isHeader and questID and questID ~= 0 then
                    completed = try(C.IsComplete, questID) and true or false;
                    failed = try(C.IsFailed, questID) and true or false;
                end

                entries[#entries + 1] = {
                    index = index,
                    title = info.title or "",
                    level = info.level or 0,
                    isHeader = isHeader,
                    questID = questID,
                    completed = completed,
                    failed = failed
                };
            end
        end
    elseif self:HasLegacyQuestLog() then
        local numEntries = try(_G.GetNumQuestLogEntries) or 0;

        for index = 1, numEntries do
            local title, level, _, isHeader, _, isComplete, _, questID = _G.GetQuestLogTitle(index);

            entries[#entries + 1] = {
                index = index,
                title = title or "",
                level = level or 0,
                isHeader = isHeader and true or false,
                questID = questID,
                completed = isComplete == 1 or isComplete == true,
                failed = isComplete == -1
            };
        end
    end

    return entries;
end

function Compat:GetQuestObjectives(questID)
    if not questID then return {} end

    local objectives = try(qlog() and qlog().GetQuestObjectives, questID);

    if type(objectives) == "table" then
        return objectives;
    end

    return {};
end

-- Is the player currently on this quest? Returns nil when the client can't tell.
function Compat:IsOnQuest(questID)
    if not questID then return false end

    if qlogHas("IsOnQuest") then
        local result = try(qlog().IsOnQuest, questID);

        if result ~= nil then
            return result and true or false;
        end
    end

    return nil;
end

-- ---------------------------------------------------------------------------
-- Index <-> questID helpers (legacy API is index based, and indexes go stale
-- whenever quests are accepted, abandoned or headers are collapsed)
-- ---------------------------------------------------------------------------

function Compat:ResolveLogIndex(questID, hintIndex)
    if not questID then return nil end

    if qlogHas("GetLogIndexForQuestID") then
        local index = try(qlog().GetLogIndexForQuestID, questID);

        if index and index > 0 then
            return index;
        end
    end

    if not isFunction(_G.GetQuestLogTitle) then
        return hintIndex;
    end

    if hintIndex then
        local _, _, _, isHeader, _, _, _, hintID = _G.GetQuestLogTitle(hintIndex);

        if not isHeader and hintID == questID then
            return hintIndex;
        end
    end

    local numEntries = try(_G.GetNumQuestLogEntries) or 0;
    for index = 1, numEntries do
        local _, _, _, isHeader, _, _, _, id = _G.GetQuestLogTitle(index);

        if not isHeader and id == questID then
            return index;
        end
    end

    return nil;
end

-- ---------------------------------------------------------------------------
-- Selection (a lot of the quest APIs act on the "selected" quest)
-- ---------------------------------------------------------------------------

function Compat:CaptureSelection()
    if qlogHas("SetSelectedQuest") and qlogHas("GetSelectedQuest") then
        return { questID = try(qlog().GetSelectedQuest) or 0 };
    end

    if isFunction(_G.GetQuestLogSelection) then
        return { index = try(_G.GetQuestLogSelection) or 0 };
    end

    return nil;
end

function Compat:RestoreSelection(token)
    if not token then return end

    if token.questID ~= nil then
        try(qlog().SetSelectedQuest, token.questID);
    elseif token.index ~= nil then
        try(_G.SelectQuestLogEntry, token.index);
    end
end

-- Selects the quest silently (does not touch any quest log UI).
function Compat:SelectQuest(questID, hintIndex)
    if qlogHas("SetSelectedQuest") then
        try(qlog().SetSelectedQuest, questID);

        return true;
    end

    local index = self:ResolveLogIndex(questID, hintIndex);

    if index and isFunction(_G.SelectQuestLogEntry) then
        try(_G.SelectQuestLogEntry, index);

        return true;
    end

    return false;
end

-- Runs fn while the quest is selected, then puts the previous selection back.
function Compat:WithSelection(questID, hintIndex, fn)
    local token = self:CaptureSelection();
    local selected = self:SelectQuest(questID, hintIndex);

    local ok, a, b = pcall(fn, selected);

    self:RestoreSelection(token);

    if ok then
        return a, b;
    end
end

-- ---------------------------------------------------------------------------
-- Quest details / actions
-- ---------------------------------------------------------------------------

function Compat:IsQuestPushable(questID, hintIndex)
    if qlogHas("IsPushableQuest") then
        return try(qlog().IsPushableQuest, questID) and true or false;
    end

    if isFunction(_G.GetQuestLogPushable) then
        return self:WithSelection(questID, hintIndex, function(selected)
            if not selected then return false end

            return _G.GetQuestLogPushable() and true or false;
        end) or false;
    end

    return false;
end

-- The short "objectives" text of a quest (used for quests without objectives).
function Compat:GetQuestSummary(questID, hintIndex)
    if not isFunction(_G.GetQuestLogQuestText) then return nil end

    return self:WithSelection(questID, hintIndex, function(selected)
        -- Never read the text of whichever quest happened to be selected already.
        if not selected then return nil end

        local _, objectives = try(_G.GetQuestLogQuestText);

        if objectives == nil then
            local index = self:ResolveLogIndex(questID, hintIndex);

            if index then
                _, objectives = try(_G.GetQuestLogQuestText, index);
            end
        end

        return objectives;
    end);
end

function Compat:ShareQuest(questID, hintIndex)
    self:WithSelection(questID, hintIndex, function(selected)
        -- Acting on the wrong quest would be worse than doing nothing.
        if not selected then return end

        if isFunction(_G.QuestLogPushQuest) then
            _G.QuestLogPushQuest();
        elseif qlogHas("ShareQuest") then
            qlog().ShareQuest(questID);
        end
    end);
end

function Compat:AbandonQuest(questID, hintIndex)
    self:WithSelection(questID, hintIndex, function(selected)
        -- Acting on the wrong quest would be worse than doing nothing.
        if not selected then return end

        local setAbandon = (qlogHas("SetAbandonQuest") and qlog().SetAbandonQuest) or _G.SetAbandonQuest;
        local abandon = (qlogHas("AbandonQuest") and qlog().AbandonQuest) or _G.AbandonQuest;

        if isFunction(setAbandon) and isFunction(abandon) then
            setAbandon();
            abandon();
        end
    end);
end

function Compat:GetQuestChatLink(quest)
    -- Classic's GetQuestLink wants a log index while Retail's wants a questID, so
    -- we only trust it on the modern API.
    if self:HasModernQuestLog() and isFunction(_G.GetQuestLink) then
        local link = try(_G.GetQuestLink, quest.questID);

        if type(link) == "string" and link ~= "" then
            return link;
        end
    end

    return "[" .. (quest.title or "?") .. "]";
end

-- ---------------------------------------------------------------------------
-- Blizzard's quest watch list (we mirror our own tracked set into it, best effort)
-- ---------------------------------------------------------------------------

function Compat:HasModernWatch()
    return qlogHas("AddQuestWatch") and qlogHas("RemoveQuestWatch");
end

function Compat:HasLegacyWatch()
    return isFunction(_G.AddQuestWatch) and isFunction(_G.RemoveQuestWatch);
end

function Compat:GetManualWatchType()
    local watchType = _G.Enum and _G.Enum.QuestWatchType;

    return watchType and watchType.Manual or nil;
end

function Compat:MirrorWatch(questID, hintIndex, watched)
    if self:HasModernWatch() then
        if watched then
            try(qlog().AddQuestWatch, questID, self:GetManualWatchType());
        else
            try(qlog().RemoveQuestWatch, questID);
        end

        return true;
    end

    if self:HasLegacyWatch() then
        local index = self:ResolveLogIndex(questID, hintIndex);

        if index then
            try(watched and _G.AddQuestWatch or _G.RemoveQuestWatch, index);
        end

        return true;
    end

    return false;
end

-- Which of Blizzard's built-in trackers exist on this client?
function Compat:GetBlizzardTrackerFrames()
    local frames = {};

    for _, name in pairs({ "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" }) do
        local frame = _G[name];

        if type(frame) == "table" and isFunction(frame.Hide) then
            frames[#frames + 1] = frame;
        end
    end

    return frames;
end

-- ---------------------------------------------------------------------------
-- Maps / distance
-- ---------------------------------------------------------------------------

function Compat:GetPlayerWorldPosition()
    local C_Map = _G.C_Map;

    if not (C_Map and isFunction(C_Map.GetBestMapForUnit) and isFunction(C_Map.GetPlayerMapPosition) and isFunction(C_Map.GetWorldPosFromMapPos)) then
        return nil;
    end

    local uiMapID = try(C_Map.GetBestMapForUnit, "player");

    if not uiMapID then return nil end

    local mapPosition = try(C_Map.GetPlayerMapPosition, uiMapID, "player");

    if not mapPosition then return nil end

    local _, worldPosition = try(C_Map.GetWorldPosFromMapPos, uiMapID, mapPosition);

    if worldPosition and worldPosition.x and worldPosition.y then
        return worldPosition;
    end

    return nil;
end

function Compat:WorldPositionFromMap(uiMapID, x, y)
    local C_Map = _G.C_Map;

    if not (uiMapID and C_Map and isFunction(C_Map.GetWorldPosFromMapPos)) then return nil end

    local _, worldPosition = try(C_Map.GetWorldPosFromMapPos, uiMapID, { x = x, y = y });

    if worldPosition and worldPosition.x and worldPosition.y then
        return worldPosition;
    end

    return nil;
end

function Compat:HasBuiltInQuestDistance()
    return qlogHas("GetDistanceSqToQuest") or isFunction(_G.GetDistanceSqToQuest);
end

function Compat:GetBuiltInQuestDistance(questID, hintIndex)
    local squared;

    if qlogHas("GetDistanceSqToQuest") then
        squared = try(qlog().GetDistanceSqToQuest, questID);
    elseif isFunction(_G.GetDistanceSqToQuest) then
        local index = self:ResolveLogIndex(questID, hintIndex);

        if index then
            squared = try(_G.GetDistanceSqToQuest, index);
        end
    end

    if type(squared) == "number" and squared >= 0 then
        return sqrt(squared);
    end

    return nil;
end

-- ---------------------------------------------------------------------------
-- Diagnostics (/bqt status)
-- ---------------------------------------------------------------------------

function Compat:Describe()
    local function yes(value) return value and "yes" or "no" end

    return {
        "Interface " .. tostring(interfaceVersion) .. " (" .. self.flavor .. ")",
        "Quest log API: " .. (self:HasModernQuestLog() and "modern (C_QuestLog)" or (self:HasLegacyQuestLog() and "legacy (GetQuestLogTitle)" or "NONE FOUND")),
        "Quest watch API: " .. (self:HasModernWatch() and "modern" or (self:HasLegacyWatch() and "legacy" or "none")),
        "Blizzard trackers found: " .. #self:GetBlizzardTrackerFrames(),
        "Settings panel API: " .. yes(_G.Settings and _G.Settings.RegisterCanvasLayoutCategory),
        "Context menu API: " .. ((_G.MenuUtil and _G.MenuUtil.CreateContextMenu) and "MenuUtil" or (isFunction(_G.UIDropDownMenu_Initialize) and "UIDropDownMenu" or "none")),
        "Built-in quest distance: " .. yes(self:HasBuiltInQuestDistance())
    };
end
