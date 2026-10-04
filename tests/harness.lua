--[[
    A tiny fake of the WoW addon environment, just big enough to load Butter Quest Tracker, run its
    start up and drive its main code paths. It is NOT a WoW emulator: it exists so that API
    changes can be simulated ("what if GetQuestLogTitle disappears?") without logging in.

    Two quest API "shapes" are provided:
        legacy  - Classic Era style (GetQuestLogTitle, global AddQuestWatch, QuestWatchFrame ...)
        modern  - Retail / WoW Forever style (C_QuestLog.GetInfo, ObjectiveTrackerFrame, Menu API ...)
]]

local H = {};

local ADDON_NAME = "ButterQuestTracker";

-- ---------------------------------------------------------------------------
-- plumbing: errors, output, timers, events
-- ---------------------------------------------------------------------------

H.errors = {};
H.printed = {};
H.timers = {};
H.now = 0;
H.frames = {};
H.fontStrings = {};

local function reset()
    H.errors = {};
    H.printed = {};
    H.timers = {};
    H.now = 0;
    H.frames = {};
    H.fontStrings = {};
end

function H.advance(seconds)
    local target = H.now + seconds;

    while true do
        local nextTimer, nextIndex;
        for index, timer in ipairs(H.timers) do
            if not timer.cancelled and timer.due <= target and (not nextTimer or timer.due < nextTimer.due) then
                nextTimer, nextIndex = timer, index;
            end
        end

        if not nextTimer then break end

        H.now = math.max(H.now, nextTimer.due);

        if nextTimer.ticker then
            nextTimer.due = nextTimer.due + nextTimer.interval;
        else
            table.remove(H.timers, nextIndex);
        end

        local ok, err = pcall(nextTimer.fn, nextTimer);
        if not ok then
            table.insert(H.errors, "timer: " .. tostring(err));
        end
    end

    H.now = target;
end

function H.fire(event, ...)
    for _, frame in ipairs(H.frames) do
        if frame.__events[event] then
            local handler = frame.__scripts.OnEvent;

            if handler then
                local ok, err = pcall(handler, frame, event, ...);
                if not ok then
                    table.insert(H.errors, event .. ": " .. tostring(err));
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- frames
-- ---------------------------------------------------------------------------

local Methods = {};
local objectMeta = { __index = Methods };

local function newObject(kind, name, parent)
    local object = setmetatable({
        __kind = kind,
        __name = name,
        __parent = parent,
        __points = {},
        __scripts = {},
        __hooks = {},
        __events = {},
        __shown = true,
        __alpha = 1,
        __w = 0,
        __h = 0,
        __text = ""
    }, objectMeta);

    if kind == "Frame" or kind == "Button" or kind == "EditBox" or kind == "ScrollFrame" or kind == "Slider" or kind == "CheckButton" or kind == "GameTooltip" then
        table.insert(H.frames, object);
    end

    if kind == "FontString" then
        table.insert(H.fontStrings, object);
    end

    if name then
        _G[name] = object;
    end

    return object;
end

local noops = {
    "IsOwned",
    "SetFontString",
    "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetClipsChildren", "EnableMouseWheel", "SetMovable",
    "StartMoving", "StopMovingOrSizing", "SetUserPlaced", "EnableMouse", "SetToplevel", "Raise", "Lower", "SetScale",
    "SetID", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetFocus", "ClearFocus", "HighlightText",
    "SetAutoFocus", "RegisterForDrag", "RegisterForClicks", "SetJustifyH", "SetJustifyV", "SetTextColor", "SetTexture",
    "SetTexCoord", "SetVertexColor", "SetBlendMode", "SetDrawLayer", "SetFontObject", "SetNormalFontObject",
    "SetHighlightFontObject", "SetDisabledFontObject", "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture",
    "SetDisabledTexture", "SetCheckedTexture", "SetDisabledCheckedTexture", "SetMinMaxValues", "SetValueStep",
    "SetObeyStepOnDrag", "SetOrientation", "SetThumbTexture", "SetNumeric", "SetMaxLetters", "SetMultiLine",
    "SetTextInsets", "SetHitRectInsets", "SetPropagateKeyboardInput", "SetHyperlinksEnabled", "SetWordWrap",
    "SetNonSpaceWrap", "SetMaxLines", "SetSpacing", "SetShadowColor", "SetShadowOffset", "SetIgnoreParentScale",
    "SetIgnoreParentAlpha", "SetDontSavePosition", "SetResizable", "SetResizeBounds", "SetMinResize", "SetMaxResize",
    "SetEnabled", "Enable", "Disable", "SetChecked", "SetFixedFrameStrata", "SetFixedFrameLevel", "SetAtlas",
    "SetDesaturated", "SetRotation", "SetColorTexture", "SetFromAlpha", "SetToAlpha", "SetSmoothing", "SetDuration",
    "SetLooping", "SetToFinalAlpha", "SetOrder", "SetTextToFit", "SetTitle", "SetText", "SetNormalAtlas", "SetHighlightAtlas",
    "SetPushedAtlas", "RegisterAllEvents", "SetVerticalScroll", "SetHorizontalScroll", "UpdateScrollChildRect",
    "SetScrollChild", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetFlattensRenderLayers", "SetIgnoreParentScale",
    "SetShown", "SetPassThroughButtons", "SetHighlightLocked", "SetMotionScriptsWhileDisabled", "AddMaskTexture",
    "SetSubTexCoord", "StopAnimating", "SetClipsChildren", "SetNumLines", "SetCursorPosition", "Insert",
    "ClearHighlightTexture", "SetButtonState", "LockHighlight", "UnlockHighlight", "SetAllPointsTo", "SetHeightMargin",
    "SetStatusBarTexture", "SetStatusBarColor", "SetValue", "SetIgnoreParentScale", "SetAutoHeight", "SetMaxLines"
};
for _, name in ipairs(noops) do
    Methods[name] = function() end;
end

function Methods:SetTexture(texture) self.__texture = texture; end

function Methods:SetText(text) self.__text = text or ""; end
function Methods:GetText() return self.__text; end
function Methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Methods:SetEnabled() end
function Methods:GetName() return self.__name; end
function Methods:GetObjectType() return self.__kind; end
function Methods:SetParent(parent) self.__parent = parent; end
function Methods:GetParent() return self.__parent; end
function Methods:SetAlpha(alpha) self.__alpha = alpha; end
function Methods:GetAlpha() return self.__alpha; end
function Methods:SetWidth(w) self.__w = w; end
function Methods:SetHeight(h) self.__h = h; end
function Methods:SetSize(w, h) self.__w = w; self.__h = h or self.__h; end
function Methods:GetWidth() return self.__w; end
function Methods:GetStringWidth() return 100; end
function Methods:GetStringHeight() return 12; end
function Methods:GetEffectiveScale() return 1; end
function Methods:GetScale() return 1; end
function Methods:IsVisible() return self.__shown; end
function Methods:GetFrameLevel() return 1; end
function Methods:GetFrameStrata() return "MEDIUM"; end
function Methods:GetNumPoints() return #self.__points; end
function Methods:IsMouseOver() return false; end
function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", self.__fontSize or 12, ""; end
function Methods:SetFont(path, size) self.__fontSize = size; return true; end
function Methods:GetFontObject() return nil; end
function Methods:GetNumChildren() return 0; end
function Methods:GetTexture() return self.__texture or "Interface\\Buttons\\WHITE8X8"; end
function Methods:GetTexCoord() return 0, 1, 0, 1; end
function Methods:GetVertexColor() return 1, 1, 1, 1; end
function Methods:GetTextColor() return 1, 1, 1, 1; end
function Methods:GetJustifyH() return "LEFT"; end
function Methods:GetCenter() return 960, 540; end
function Methods:GetNumRegions() return 0; end
function Methods:GetChildren() end
function Methods:GetRegions() end
function Methods:GetValue() return self.__value or 0; end
function Methods:GetChecked() return self.__checked or false; end
function Methods:GetNumLines() return 1; end
function Methods:IsEnabled() return true; end
function Methods:GetValueStep() return 1; end

function Methods:GetHeight()
    if self.__kind == "FontString" then
        return 12;
    end

    return self.__h;
end

function Methods:SetValue(value) self.__value = value; end
function Methods:SetChecked(value) self.__checked = value; end

local function layoutNumber(self, value)
    if self.__nolayout then return nil end

    return value;
end

function Methods:GetRight() if self == UIParent then return 1920 end return layoutNumber(self, 1900); end
function Methods:GetTop() if self == UIParent then return 1080 end return layoutNumber(self, 900); end
function Methods:GetLeft() return layoutNumber(self, 1650); end
function Methods:GetBottom() return layoutNumber(self, 500); end

function Methods:SetPoint(point, a, b, c, d)
    local relativeTo, relativePoint, x, y;

    if type(a) == "number" then
        x, y = a, b;
    elseif type(b) == "string" then
        relativeTo, relativePoint, x, y = a, b, c, d;
    else
        relativeTo, x, y = a, b, c;
    end

    for index, existing in ipairs(self.__points) do
        if existing[1] == point then
            table.remove(self.__points, index);
            break;
        end
    end

    table.insert(self.__points, { point, relativeTo, relativePoint or point, x or 0, y or 0 });
end

function Methods:ClearAllPoints() self.__points = {}; end
function Methods:SetAllPoints() self.__points = { { "TOPLEFT" }, { "BOTTOMRIGHT" } }; end

function Methods:GetPoint(index)
    -- Real clients want an index. Being strict here is the whole point.
    if index ~= nil and type(index) ~= "number" then
        error("bad argument #1 to 'GetPoint' (number expected, got " .. type(index) .. ")");
    end

    local point = self.__points[index or 1];

    if not point then return nil end

    return point[1], point[2], point[3], point[4], point[5];
end

function Methods:Show()
    if self.__shown then return end

    self.__shown = true;

    if self.__scripts.OnShow then self.__scripts.OnShow(self) end
    for _, hook in ipairs(self.__hooks.OnShow or {}) do hook(self) end
end

function Methods:Hide()
    if not self.__shown then return end

    self.__shown = false;

    if self.__scripts.OnHide then self.__scripts.OnHide(self) end
    for _, hook in ipairs(self.__hooks.OnHide or {}) do hook(self) end
end

function Methods:IsShown() return self.__shown; end

function Methods:SetScript(name, fn) self.__scripts[name] = fn; end
function Methods:GetScript(name) return self.__scripts[name]; end
function Methods:HookScript(name, fn)
    self.__hooks[name] = self.__hooks[name] or {};
    table.insert(self.__hooks[name], fn);
end

function Methods:RegisterEvent(event) self.__events[event] = true; end
function Methods:UnregisterEvent(event) self.__events[event] = nil; end
function Methods:UnregisterAllEvents() self.__events = {}; end

function Methods:CreateTexture(name) return newObject("Texture", name, self); end

for _, name in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture",
    "GetCheckedTexture", "GetThumbTexture", "GetStatusBarTexture", "GetFontString", "GetScrollChild" }) do
    Methods[name] = function(self)
        self.__cache = self.__cache or {};
        self.__cache[name] = self.__cache[name] or newObject("Texture", nil, self);
        return self.__cache[name];
    end;
end
function Methods:CreateFontString(name) return newObject("FontString", name, self); end
function Methods:CreateAnimationGroup()
    local group = newObject("AnimationGroup", nil, self);
    function group:CreateAnimation() return newObject("Animation", nil, self); end
    function group:Play() self.__playing = true; end
    function group:Stop() self.__playing = false; end
    return group;
end

-- ---------------------------------------------------------------------------
-- the world: a quest log we can poke at
-- ---------------------------------------------------------------------------

H.world = nil;

local function newWorld()
    return {
        zone = "Elwynn Forest",
        minimap = "Goldshire",
        class = "Warrior",
        level = 10,
        log = {
            { header = true, title = "Elwynn Forest" },
            { questID = 33, title = "Wolves Across the Border", level = 5,
              summary = "Kill 8 wolves.", pushable = true,
              objectives = { { text = "Prowler killed: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } } },
            { questID = 54, title = "Report to Goldshire", level = 6,
              summary = "Speak to Marshal Dughan.", pushable = true, objectives = {} },
            { header = true, title = "Westfall" },
            { questID = 65, title = "The Defias Brotherhood", level = 12,
              summary = "Find Gryan Stoutmantle.", pushable = false,
              objectives = { { text = "Find Gryan Stoutmantle", type = "event", finished = true, numFulfilled = 1, numRequired = 1 } }, complete = true },
            { header = true, title = "Warrior" },
            { questID = 1639, title = "Veteran Uzzek", level = 10, summary = "Report to the trainer.", pushable = false,
              objectives = { { text = "Speak to Uzzek", type = "event", finished = false, numFulfilled = 0, numRequired = 1 } } },
        },
        selected = 0,
        blizzardWatch = {},
        shared = {},
        abandoned = {}
    };
end

local function entryAt(index)
    return H.world.log[index];
end

local function findByQuestID(questID)
    for index, entry in ipairs(H.world.log) do
        if entry.questID == questID then
            return entry, index;
        end
    end
end

local function completionOf(entry)
    if entry.failed then return -1 end
    if entry.complete then return 1 end
    return nil;
end

function H.acceptQuest(entry, afterHeader)
    -- Inserts at the end of the header (or the first header) and fires the usual event.
    local insertAt = #H.world.log + 1;

    if afterHeader then
        for index, row in ipairs(H.world.log) do
            if row.header and row.title == afterHeader then
                insertAt = index + 1;
            end
        end
    end

    table.insert(H.world.log, insertAt, entry);
    H.fire("QUEST_LOG_UPDATE");
end

function H.updateObjective(questID, fulfilled)
    local entry = findByQuestID(questID);
    local objective = entry.objectives[1];

    objective.numFulfilled = fulfilled;
    objective.finished = fulfilled >= objective.numRequired;
    objective.text = (objective.text:gsub("%d+/%d+", fulfilled .. "/" .. objective.numRequired));
    entry.complete = objective.finished;

    H.fire("QUEST_LOG_UPDATE");
end

-- ---------------------------------------------------------------------------
-- environment construction
-- ---------------------------------------------------------------------------

local function installLuaExtras()
    _G.tinsert = table.insert;
    _G.tremove = table.remove;
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end;
    table.wipe = _G.wipe;
    _G.strsplit = function(delim, str, pieces)
        local result = {};
        local pattern = "([^" .. delim .. "]*)" .. delim .. "?";
        for part in tostring(str):gmatch(pattern) do result[#result + 1] = part end
        if #result > 0 and result[#result] == "" then table.remove(result) end
        return unpack(result);
    end;
    string.split = function(delim, str, pieces) return _G.strsplit(delim, str, pieces) end;
    _G.strjoin = function(delim, ...) return table.concat({ ... }, delim) end;
    _G.format = string.format;
    _G.strlower = string.lower;
    _G.strupper = string.upper;
    _G.strtrim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end;
    _G.strfind = string.find;
    _G.strsub = string.sub;
    _G.strlen = string.len;
    _G.gsub = string.gsub;
    _G.max, _G.min, _G.floor, _G.ceil, _G.abs = math.max, math.min, math.floor, math.ceil, math.abs;
    _G.sort = table.sort;
    _G.getglobal = function(name) return _G[name] end;
    _G.setglobal = function(name, value) _G[name] = value end;
    _G.GetTime = function() return H.now end;
    _G.date = os.date;
    _G.time = function() return 1790000000 + math.floor(H.now) end;
    _G.CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and _G.CopyTable(v) or v end return c end;
    _G.Mixin = function(object, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do object[k] = v end end return object end;
    _G.CreateFromMixins = function(...) return _G.Mixin({}, ...) end;
    _G.geterrorhandler = function()
        return function(err)
            table.insert(H.errors, tostring(err));
        end;
    end;
    _G.seterrorhandler = function() end;
    _G.issecurevariable = function() return false end;
    _G.securecallfunction = function(fn, ...) return fn(...) end;
    _G.securecall = function(fn, ...)
        if type(fn) == "string" then fn = _G[fn] end
        return fn(...);
    end;
    _G.InCombatLockdown = function() return false end;
    _G.IsLoggedIn = function() return true end;
    _G.print = function(...)
        local parts = {};
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        table.insert(H.printed, table.concat(parts, " "));
    end;
    _G.debugstack = function() return "" end;
    _G.debugprofilestop = function() return H.now * 1000 end;
    _G.xpcall = (function(real)
        -- Lua 5.1's xpcall has no extra arguments, WoW's does.
        return function(fn, handler, ...)
            local args = { ... };
            return real(function() return fn(unpack(args)) end, handler);
        end;
    end)(xpcall);
    _G.hooksecurefunc = function(a, b, c)
        local tbl, name, fn;
        if type(a) == "string" then tbl, name, fn = _G, a, b else tbl, name, fn = a, b, c end

        local original = tbl[name];
        if type(original) ~= "function" then
            error("Attempt to hook a non-existent function: " .. tostring(name));
        end

        tbl[name] = function(...)
            local results = { original(...) };
            fn(...);
            return unpack(results);
        end;
    end;
end

local function installApi(flavor)
    local world = H.world;

    -- General -------------------------------------------------------------
    local interface = ({ era = 11509, forever = 16001, retail = 120100, mists = 50504 })[flavor.client] or 11509;
    _G.GetBuildInfo = function() return "x.y.z", "1", "Oct 1 2026", interface end;
    _G.GetLocale = function() return "enUS" end;
    _G.GetRealZoneText = function() return world.zone end;
    _G.GetMinimapZoneText = function() return world.minimap end;
    _G.UnitClass = function() return world.class, "WARRIOR" end;
    _G.UnitLevel = function() return world.level end;
    _G.UnitName = function() return "Tester", nil end;
    _G.UnitNameUnmodified = function() return "Tester", nil end;
    _G.GetNormalizedRealmName = function() return "TestRealm" end;
    _G.GetCurrentRegionName = function() return "US" end;
    _G.GetCurrentRegion = function() return 1 end;
    _G.GetServerTime = function() return 1790000000 end;
    _G.UnitSex = function() return 2 end;
    _G.GetRealmName = function() return "TestRealm" end;
    _G.UnitRace = function() return "Human", "Human" end;
    _G.UnitFactionGroup = function() return "Alliance", "Alliance" end;
    _G.UnitGUID = function() return "Player-1-00000001" end;
    _G.IsInGroup = function() return flavor.inParty or false end;
    _G.GetNumGroupMembers = function() return flavor.inParty and 2 or 0 end;
    _G.UnitInParty = function() return flavor.inParty or false end;
    _G.GetCVar = function() return "1" end;
    _G.SetCVar = function() end;
    _G.GetCursorPosition = function() return 100, 100 end;
    _G.IsShiftKeyDown = function() return H.keys.shift end;
    _G.IsAltKeyDown = function() return H.keys.alt end;
    _G.IsControlKeyDown = function() return H.keys.ctrl end;
    _G.GetScreenWidth = function() return 1920 end;
    _G.GetScreenHeight = function() return 1080 end;
    _G.GetNumAddOns = function() return 0 end;
    _G.IsAddOnLoaded = function() return false end;
    _G.LoadAddOn = function() end;
    _G.GetAddOnMetadata = nil;
    _G.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "9.9.9-test" end end };
    _G.CLOSE = "Close";
    _G.NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0, a = 1 };
    _G.HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1, a = 1 };
    _G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPEN = 850, IG_QUEST_LOG_ABANDON_QUEST = 843 };
    _G.PlaySound = function(id) table.insert(H.sounds, id) end;
    _G.StaticPopupDialogs = {};
    _G.StaticPopup_Show = function(which, text, text2, data)
        local dialog = _G.StaticPopupDialogs[which];
        if not dialog then error("no such popup " .. tostring(which)) end

        local frame = newObject("Frame", "StaticPopupMock" .. (#H.popups + 1), UIParent);
        frame.text = newObject("FontString", nil, frame);
        frame.text:SetText((dialog.text:gsub("%%s", function() return text end)));
        frame.editBox = newObject("EditBox", nil, frame);
        if flavor.renamedPopupFields then
            frame.EditBox, frame.editBox = frame.editBox, nil;
        end
        table.insert(H.popups, frame);

        if dialog.OnShow then dialog.OnShow(frame, data) end

        return frame;
    end;
    _G.ChatEdit_InsertLink = function(link) table.insert(H.chatLinks, link) end;
    _G.ShowUIPanel = function(frame) frame:Show() end;
    _G.HideUIPanel = function(frame) frame:Hide() end;
    _G.SlashCmdList = {};

    _G.C_Timer = {
        After = function(seconds, fn)
            table.insert(H.timers, { due = H.now + seconds, fn = fn });
        end,
        NewTimer = function(seconds, fn)
            local timer = { due = H.now + seconds, fn = fn };
            function timer:Cancel() self.cancelled = true; end
            table.insert(H.timers, timer);
            return timer;
        end,
        NewTicker = function(seconds, fn)
            local timer = { due = H.now + seconds, interval = seconds, ticker = true, fn = fn };
            function timer:Cancel() self.cancelled = true; end
            table.insert(H.timers, timer);
            return timer;
        end
    };

    _G.C_Map = {
        GetBestMapForUnit = function() return 1429 end,
        GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
        GetWorldPosFromMapPos = function(_, pos)
            return 0, { x = pos.x * 1000, y = pos.y * 1000 };
        end
    };

    _G.UIParent = newObject("Frame", "UIParent", nil);
    _G.GameTooltip = newObject("GameTooltip", "GameTooltip", UIParent);
    function _G.GameTooltip:AddLine(text)
        if type(text) ~= "string" then error("GameTooltip:AddLine needs a string, got " .. type(text)) end
    end
    function _G.GameTooltip:AddDoubleLine() end
    function _G.GameTooltip:SetOwner(owner) self.__owner = owner end
    function _G.GameTooltip:ClearLines() end

    _G.CreateFrame = function(kind, name, parent, template)
        local frame = newObject(kind, name, parent);
        if template == "UIDropDownMenuTemplate" and not _G.UIDropDownMenu_Initialize then
            error("UIDropDownMenuTemplate doesn't exist on this client");
        end
        return frame;
    end;

    -- Quest log (shared) --------------------------------------------------
    local function objectivesOf(questID)
        local entry = findByQuestID(questID);

        return entry and entry.objectives or nil;
    end

    local C_QuestLog = {
        GetQuestObjectives = function(questID)
            return objectivesOf(questID) or {};
        end,
        IsOnQuest = function(questID) return findByQuestID(questID) ~= nil end,
    };
    _G.C_QuestLog = C_QuestLog;

    -- Legacy flavour -----------------------------------------------------
    if flavor.log == "legacy" then
        C_QuestLog.GetMaxNumQuests = function() return 20 end;

        _G.GetNumQuestLogEntries = function()
            local quests = 0;
            for _, entry in ipairs(world.log) do if not entry.header then quests = quests + 1 end end
            return #world.log, quests;
        end;

        _G.GetQuestLogTitle = function(index)
            local entry = entryAt(index);
            if not entry then return nil end
            if entry.header then
                return entry.title, 0, 0, true, false, nil, nil, 0;
            end
            return entry.title, entry.level, 0, false, false, completionOf(entry), nil, entry.questID;
        end;

        _G.GetQuestLogSelection = function() return world.selected end;
        _G.SelectQuestLogEntry = function(index) world.selected = index end;
        _G.QuestLog_SetSelection = function(index) world.selected = index; table.insert(H.uiSelections, index) end;
        _G.GetQuestLogPushable = function()
            local entry = entryAt(world.selected);
            return entry and entry.pushable and true or false;
        end;
        _G.GetQuestLogQuestText = function()
            local entry = entryAt(world.selected);
            if not entry then return nil end
            return "Long description", entry.summary;
        end;
        _G.QuestLogPushQuest = function()
            local entry = entryAt(world.selected);
            table.insert(world.shared, entry and entry.questID);
        end;
        _G.SetAbandonQuest = function() world.pendingAbandon = world.selected end;
        _G.AbandonQuest = function()
            local index = world.pendingAbandon;
            local entry = entryAt(index);
            if entry and not entry.header then
                table.insert(world.abandoned, entry.questID);
                table.remove(world.log, index);
                H.fire("QUEST_LOG_UPDATE");
            end
        end;

        _G.MAX_WATCHABLE_QUESTS = 5;
        _G.AddQuestWatch = function(index)
            local entry = entryAt(index);
            if entry and entry.questID then world.blizzardWatch[entry.questID] = true end
        end;
        _G.RemoveQuestWatch = function(index)
            local entry = entryAt(index);
            if entry and entry.questID then world.blizzardWatch[entry.questID] = nil end
        end;
        _G.AutoQuestWatch_Insert = function() end;
        _G.IsQuestWatched = function(index)
            local entry = entryAt(index);
            return entry and world.blizzardWatch[entry.questID] or false;
        end;
        _G.GetNumQuestWatches = function()
            local n = 0; for _ in pairs(world.blizzardWatch) do n = n + 1 end return n;
        end;
        _G.GetNumQuestLeaderBoards = function(index)
            local entry = entryAt(index);
            return entry and #entry.objectives or 0;
        end;

        _G.QuestWatchFrame = newObject("Frame", "QuestWatchFrame", UIParent);
        _G.QuestLogFrame = newObject("Frame", "QuestLogFrame", UIParent);
        _G.QuestLogFrame.__shown = false;
        _G.QuestLogListScrollFrame = newObject("ScrollFrame", "QuestLogListScrollFrame", UIParent);
        _G.QuestLogListScrollFrame.ScrollBar = newObject("Slider", nil, _G.QuestLogListScrollFrame);
    end

    -- Modern flavour -----------------------------------------------------
    if flavor.log == "modern" then
        local selectedID = 0;

        C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end;
        C_QuestLog.GetNumQuestLogEntries = function()
            local quests = 0;
            for _, entry in ipairs(world.log) do if not entry.header then quests = quests + 1 end end
            return #world.log, quests;
        end;
        C_QuestLog.GetInfo = function(index)
            local entry = entryAt(index);
            if not entry then return nil end
            if entry.header then
                return { title = entry.title, level = 0, isHeader = true, questID = 0, isHidden = false };
            end
            return { title = entry.title, level = entry.level, isHeader = false, questID = entry.questID, isHidden = entry.hidden or false };
        end;
        C_QuestLog.IsComplete = function(questID) local e = findByQuestID(questID) return e and e.complete or false end;
        C_QuestLog.IsFailed = function(questID) local e = findByQuestID(questID) return e and e.failed or false end;
        C_QuestLog.SetSelectedQuest = function(questID) selectedID = questID; table.insert(H.selectionCalls, questID) end;
        C_QuestLog.GetSelectedQuest = function() return selectedID end;
        C_QuestLog.IsPushableQuest = function(questID) local e = findByQuestID(questID) return e and e.pushable or false end;
        C_QuestLog.GetLogIndexForQuestID = function(questID) local _, index = findByQuestID(questID) return index end;
        C_QuestLog.AddQuestWatch = function(questID, watchType)
            if findByQuestID(questID) then world.blizzardWatch[questID] = watchType or "default" end
        end;
        C_QuestLog.RemoveQuestWatch = function(questID) world.blizzardWatch[questID] = nil end;
        C_QuestLog.GetQuestWatchType = function(questID) return world.blizzardWatch[questID] end;
        C_QuestLog.SetAbandonQuest = function() world.pendingAbandon = selectedID end;
        C_QuestLog.AbandonQuest = function()
            local entry, index = findByQuestID(world.pendingAbandon);
            if entry then
                table.insert(world.abandoned, entry.questID);
                table.remove(world.log, index);
                H.fire("QUEST_LOG_UPDATE");
            end
        end;
        C_QuestLog.GetDistanceSqToQuest = function(questID) return questID * 10 end;

        _G.Enum = { QuestWatchType = { Automatic = 0, Manual = 1 } };

        _G.GetQuestLogQuestText = function()
            local entry = findByQuestID(selectedID);
            if not entry then return nil end
            return "Long description", entry.summary;
        end;
        _G.QuestLogPushQuest = function() table.insert(world.shared, selectedID) end;
        _G.GetQuestLink = function(questID) return "|cffffff00|Hquest:" .. questID .. ":10|h[quest " .. questID .. "]|h|r" end;

        _G.ObjectiveTrackerFrame = newObject("Frame", "ObjectiveTrackerFrame", UIParent);
        _G.WorldMapFrame = newObject("Frame", "WorldMapFrame", UIParent);
        _G.WorldMapFrame.__shown = false;
        _G.QuestMapFrame_OpenToQuestDetails = function(questID)
            _G.WorldMapFrame:Show();
            selectedID = questID;
            H.openedQuest = questID;
        end;
    end

    if flavor.selectionFiresEvent then
        local function wrap(tbl, name)
            local original = tbl[name];
            tbl[name] = function(...)
                original(...);
                H.fire("QUEST_LOG_UPDATE");
            end;
        end

        if flavor.log == "legacy" then
            wrap(_G, "SelectQuestLogEntry");
            wrap(_G, "QuestLog_SetSelection");
        else
            wrap(_G.C_QuestLog, "SetSelectedQuest");
        end
    end

    -- Menus ----------------------------------------------------------------
    if flavor.menu == "modern" then
        _G.MenuUtil = {
            CreateContextMenu = function(owner, generator)
                local items = {};
                local root = {};
                function root:CreateTitle(text) table.insert(items, { kind = "title", text = text }) end
                function root:CreateDivider() table.insert(items, { kind = "divider" }) end
                function root:CreateButton(text, callback)
                    local item = { kind = "button", text = text, callback = callback, enabled = true };
                    function item:SetEnabled(enabled) self.enabled = enabled end
                    table.insert(items, item);
                    return item;
                end
                generator(owner, root);
                H.menu = items;
            end
        };
    else
        _G.UIDROPDOWNMENU_OPEN_MENU = nil;
        _G.UIDropDownMenu_Initialize = function(frame, initFn) frame.__init = initFn end;
        _G.UIDropDownMenu_AddButton = function(info) table.insert(H.menu, info) end;
        _G.CloseDropDownMenus = function() _G.UIDROPDOWNMENU_OPEN_MENU = nil end;
        _G.ToggleDropDownMenu = function(_, _, frame)
            H.menu = {};
            _G.UIDROPDOWNMENU_OPEN_MENU = frame;
            frame.__init();
        end;
    end

    -- Options panels -------------------------------------------------------
    if flavor.settings then
        local nextID = 100;
        local categories = {};
        _G.Settings = {
            RegisterCanvasLayoutCategory = function(frame, name)
                nextID = nextID + 1;
                local category = { ID = nextID, name = name, frame = frame };
                categories[category.ID] = category;
                return category;
            end,
            RegisterAddOnCategory = function() end,
            GetCategory = function(id) return categories[id] end,
            OpenToCategory = function(id)
                H.openedCategory = id;
                _G.SettingsPanel:Show();
            end
        };
        _G.SettingsPanel = newObject("Frame", "SettingsPanel", UIParent);
        _G.SettingsPanel.__shown = false;
    end

    if flavor.interfaceOptions then
        _G.InterfaceOptionsFrame = newObject("Frame", "InterfaceOptionsFrame", UIParent);
        _G.InterfaceOptionsFrame.__shown = false;
        _G.InterfaceOptionsFrame_OpenToCategory = function(name) H.openedCategory = name; _G.InterfaceOptionsFrame:Show() end;
    end
end

-- ---------------------------------------------------------------------------
-- loading files / XML manifests
-- ---------------------------------------------------------------------------

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "cannot open " .. path);
    local content = handle:read("*a");
    handle:close();
    return content;
end

local function dirname(path)
    return (path:match("^(.*)/[^/]*$")) or ".";
end

local ns = {};

local loadXml;

local function loadLua(path)
    local chunk, err = loadfile(path);
    if not chunk then
        error("syntax error: " .. tostring(err), 0);
    end

    return chunk(ADDON_NAME, ns);
end

loadXml = function(path)
    local content = readFile(path):gsub("<!%-%-.-%-%->", "");
    local base = dirname(path);

    for tag, file in content:gmatch('<(%a+)%s+file="([^"]+)"') do
        local resolved = base .. "/" .. file:gsub("\\", "/");

        if tag == "Script" then
            loadLua(resolved);
        elseif tag == "Include" then
            loadXml(resolved);
        end
    end
end

local function loadToc(root)
    local toc = readFile(root .. "/ButterQuestTracker.toc");

    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") then
            local file = line:match("^%s*(%S.-)%s*$");

            if file and file ~= "" then
                local resolved = root .. "/" .. file:gsub("\\", "/");

                if file:lower():match("%.xml$") then
                    loadXml(resolved);
                elseif file:lower():match("%.lua$") then
                    loadLua(resolved);
                end
            end
        end
    end
end

-- Flavours -----------------------------------------------------------------
H.flavors = {
    era = { client = "era", log = "legacy", menu = "legacy", settings = true, interfaceOptions = true },
    era_oldui = { client = "era", log = "legacy", menu = "legacy", settings = false, interfaceOptions = true },
    forever = { client = "forever", log = "modern", menu = "modern", settings = true, interfaceOptions = false },
    era_reentrant = { client = "era", log = "legacy", menu = "legacy", settings = true, interfaceOptions = true, selectionFiresEvent = true },
    forever_reentrant = { client = "forever", log = "modern", menu = "modern", settings = true, interfaceOptions = false, selectionFiresEvent = true },
    nolog = { client = "forever", log = "none", menu = "modern", settings = true, interfaceOptions = false },
    forever_oldmenu = { client = "forever", log = "modern", menu = "legacy", settings = true, interfaceOptions = false, renamedPopupFields = true },
    retail = { client = "retail", log = "modern", menu = "modern", settings = true, interfaceOptions = false },
};

function H.boot(flavorName)
    reset();

    H.keys = { shift = false, alt = false, ctrl = false };
    H.sounds, H.popups, H.chatLinks, H.uiSelections, H.selectionCalls, H.menu = {}, {}, {}, {}, {}, {};
    H.openedCategory, H.openedQuest = nil, nil;
    H.world = newWorld();
    H.flavor = H.flavors[flavorName];
    assert(H.flavor, "unknown flavor " .. tostring(flavorName));

    installLuaExtras();
    installApi(H.flavor);

    loadToc(ROOT_DIR);

    -- Normal start up sequence
    H.fire("ADDON_LOADED", ADDON_NAME);
    H.fire("PLAYER_LOGIN");
    H.fire("PLAYER_ENTERING_WORLD");
    H.advance(5);

    return ButterQuestTracker;
end

local function isVisible(object, ancestor)
    local current = object;

    while current do
        if current.__shown == false then return false end
        if current == ancestor then return true end

        current = current.__parent;
    end

    return false;
end

-- All text currently visible inside the tracker frame.
function H.trackerTexts(tracker)
    local texts = {};

    for _, fontString in ipairs(H.fontStrings) do
        if fontString.__text and fontString.__text ~= "" and isVisible(fontString, tracker) then
            table.insert(texts, fontString.__text);
        end
    end

    return texts;
end

H.ns = ns;
H.findByQuestID = findByQuestID;

return H;
