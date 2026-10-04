local AceEvent = LibStub:GetLibrary("AceEvent-3.0");
local Compat = LibStub("BQTCompat-1.0");
local helper = LibStub:NewLibrary("QuestLogHelper-1.0", 2);
if not helper then return end
-- /dump LibStub("QuestLogHelper-1.0"):GetQuests();
-- /dump LibStub("QuestLogHelper-1.0"):GetWatchedQuests();

local class = UnitClass("player");
local professions = {
    'Herbalism',
    'Mining',
    'Skinning',
    'Alchemy',
    'Blacksmithing',
    'Enchanting',
    'Engineering',
    'Leatherworking',
    'Tailoring',
    'Cooking',
    'Fishing',

    -- Classic Only Professions
    'First Aid',

    -- Retail Only Professions
    'Inscription',
    'Jewelcrafting',
    'Archaeology'
};

local cache = {
    indexToQuestID = {},
    lastUpdated = {}
};

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"));
end

local function count(t)
    local _count = 0;
    if t then
        for _, _ in pairs(t) do _count = _count + 1 end
    end
    return _count;
end

local function has_value (tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

local function getQuestGrayLevel(level)
    if (level <= 5) then
        return 0;
    elseif (level <= 39) then
        return (level - math.floor(level / 10) - 5);
    else
        return (level - math.floor(level / 5) - 1);
    end
end

local function getCompletionPercent(objectives)
    local total = #objectives;

    -- Quests without objectives (deliveries and the like) have nothing to measure.
    if total == 0 then
        return 0;
    end

    local completionPercent = 0;

    for _, objective in ipairs(objectives) do
        if objective.completed then
            completionPercent = completionPercent + 1;
        elseif objective.fulfilled and objective.required and objective.required > 0 then
            completionPercent = completionPercent + math.min(objective.fulfilled / objective.required, 1);
        end
    end

    return completionPercent / total;
end

local listeners = {};
local updateListenersTimer;
local updatedQuests = {};
local function updateListeners(questID, info)
    if updateListenersTimer then
        updateListenersTimer:Cancel();
    end

    updatedQuests[questID] = info;

    updateListenersTimer = C_Timer.NewTimer(0.1, function()
        local updates = updatedQuests;
        updatedQuests = {};

        for _, listener in ipairs(listeners) do
            listener(updates);
        end
    end)
end

function helper:OnQuestUpdated(listener)
    tinsert(listeners, listener);
end

function helper:SetQuestsLastUpdated(questsLastUpdated)
    if not questsLastUpdated then return end

    local quests = self:GetQuests();

    for questID, lastUpdated in pairs(questsLastUpdated) do
        if quests[questID] then
            quests[questID].lastUpdated = lastUpdated;
        else
            questsLastUpdated[questID] = nil;
        end
    end

    return questsLastUpdated;
end

function helper:GetQuestIDFromIndex(index)
    if not index then return nil end

    if cache.indexToQuestID and cache.quests then
        return cache.indexToQuestID[index];
    end

    return nil;
end

function helper:GetIndexFromQuestID(questID)
    local quest = self:GetQuest(questID);

    return quest and quest.index;
end

-- Which quest log window should we open? Quest log addons win over Blizzard's own.
function helper:GetQuestFrame()
    local frame, addon;

    if QuestGuru then -- https://www.curseforge.com/wow/addons/questguru_classic
        frame, addon = QuestGuru, 'QuestGuru';
    elseif ClassicQuestLog then -- https://www.curseforge.com/wow/addons/classic-quest-log
        frame, addon = ClassicQuestLog, 'ClassicQuestLog';
    elseif QuestLogEx then -- https://www.wowinterface.com/downloads/info24980-QuestLogEx.html
        frame, addon = QuestLogExFrame, 'QuestLogEx';
    elseif QuestLogFrame then -- This is the built-in frame for classic.
        frame, addon = QuestLogFrame, 'Classic';
    elseif WorldMapFrame then -- Retail style clients keep the quest log inside the world map.
        frame, addon = WorldMapFrame, 'Retail';
    end

    if frame then
        frame.addon = addon;
    end

    return frame;
end

function helper:IsShown()
    local frame = self:GetQuestFrame();

    return frame ~= nil and frame:IsShown();
end

function helper:IsQuestSelected(index)
    local selection = Compat:CaptureSelection();

    if not selection then return false end

    if selection.questID ~= nil then
        return selection.questID == self:GetQuestIDFromIndex(index);
    end

    return selection.index == index;
end

function helper:GetWowheadURL(questID)
    return Compat:GetWowheadURL(questID);
end

-- Opens the quest log on the given quest (or closes it if that quest is already showing).
function helper:ToggleQuest(index)
    local questFrame = self:GetQuestFrame();

    if not questFrame then
        return false;
    end

    local questID = self:GetQuestIDFromIndex(index);
    local isQuestAlreadyOpen = self:IsShown() and self:IsQuestSelected(index);

    if isQuestAlreadyOpen then
        HideUIPanel(questFrame);

        return true;
    end

    if questFrame.addon == 'Retail' then
        if not questID then return false end

        if type(QuestMapFrame_OpenToQuestDetails) == "function" then
            pcall(QuestMapFrame_OpenToQuestDetails, questID);
        else
            ShowUIPanel(questFrame);
            Compat:SelectQuest(questID, index);

            if type(QuestMapFrame_ShowQuestDetails) == "function" then
                pcall(QuestMapFrame_ShowQuestDetails, questID);
            end
        end

        return true;
    end

    ShowUIPanel(questFrame);
    self:Select(index);

    if questFrame.addon == 'QuestLogEx' then
        if QuestLogEx and QuestLogEx.Maximize then
            QuestLogEx:Maximize();
        end
    elseif questFrame.addon == 'Classic' then
        pcall(function()
            local valueStep = QuestLogListScrollFrame.ScrollBar:GetValueStep();
            QuestLogListScrollFrame.ScrollBar:SetValue(index * valueStep - valueStep * 3);
        end);
    end

    return true;
end

function helper:GetDifficulty(level)
    local playerLevel = UnitLevel("player");

    if (level > (playerLevel + 4)) then
        return 4; -- Extremely Hard (Red)
    elseif (level > (playerLevel + 2)) then
        return 3; -- Hard (Orange)
    elseif (level <= (playerLevel + 2)) and (level >= (playerLevel - 2)) then
        return 2; -- Normal (Yellow)
    elseif (level > getQuestGrayLevel(playerLevel)) then
        return 1; -- Easy
    end

    return 0; -- Too Easy
end

function helper:GetDifficultyColor(difficulty)
    if (difficulty == 4) then
         -- Red
        return { r = 1, g = 0.1, b = 0.1 };
    elseif (difficulty == 3) then
        return { r = 1, g = 0.5, b = 0.25 }; -- Orange
    elseif (difficulty == 2) then
        return { r = 1, g = 1, b = 0 }; -- Yellow
    elseif (difficulty == 1) then
        return { r = 0.25, g = 0.75, b = 0.25 }; -- Green
    end

    return { r = 0.75, g = 0.75, b = 0.75 }; -- Grey
end

local refreshing = false;
local refreshQueued = false;

local function doRefresh(self)
    local initialized = cache.quests and true;
    cache.quests = cache.quests or {};

    if not Compat:CanReadQuestLog() then
        return;
    end

    local entries = Compat:GetQuestLogEntries();

    local present = {};
    for _, entry in ipairs(entries) do
        if not entry.isHeader and entry.questID then
            present[entry.questID] = true;
        end
    end

    -- Anything we knew about that is no longer in the log has been turned in or abandoned.
    for questID, quest in pairs(cache.quests) do
        if not present[questID] then
            local onQuest = Compat:IsOnQuest(questID);
            local gone;

            if onQuest ~= nil then
                gone = not onQuest;
            else
                -- The client can't tell us, so only trust an empty log when it actually has rows.
                gone = #entries > 0;
            end

            if gone then
                cache.quests[questID] = nil;
                cache.lastUpdated[questID] = nil;
                cache.indexToQuestID[quest.index] = nil;

                updateListeners(questID, {
                    index = quest.index,
                    questID = quest.questID,
                    lastUpdated = quest.lastUpdated,
                    previousCompletionPercent = quest.completionPercent,
                    completionPercent = quest.completionPercent,
                    abandoned = true
                });
            end
        end
    end

    local zone;
    for _, entry in ipairs(entries) do
        local index = entry.index;
        local questID = entry.questID;

        if entry.isHeader then
            zone = entry.title;
        elseif questID and questID ~= 0 then
            local isClassQuest = zone == class;
            local isProfessionQuest = has_value(professions, zone);

            local wasCached = cache.quests[questID] ~= nil;
            local accepted = initialized and not wasCached and true;

            if not wasCached then
                -- Store the quest before asking the client for extras: those calls move the
                -- quest log selection around and may fire events that bring us back in here.
                cache.quests[questID] = {
                    questID = questID,
                    index = index,
                    summaryTries = 0
                };
            end

            local quest = cache.quests[questID];

            quest.title = entry.title;
            quest.level = entry.level;
            quest.zone = zone;
            quest.isClassQuest = isClassQuest;
            quest.isProfessionQuest = isProfessionQuest;

            if quest.sharable == nil then
                quest.sharable = Compat:IsQuestPushable(questID, index);
            end

            if quest.summary == nil and quest.summaryTries < 3 then
                quest.summaryTries = quest.summaryTries + 1;
                quest.summary = Compat:GetQuestSummary(questID, index);
            end

            if quest.index and cache.indexToQuestID[quest.index] == questID then
                cache.indexToQuestID[quest.index] = nil;
            end
            cache.indexToQuestID[index] = questID;

            quest.index = index;
            quest.completed = entry.completed;
            quest.failed = entry.failed;
            quest.difficulty = self:GetDifficulty(entry.level);
            quest.objectives = self:GetObjectives(questID);

            local completionPercent = getCompletionPercent(quest.objectives);

            local updated = quest.completionPercent and quest.completionPercent ~= completionPercent;
            if updated then
                quest.lastUpdated = time();

                updateListeners(questID, {
                    index = quest.index,
                    questID = quest.questID,
                    lastUpdated = quest.lastUpdated,
                    previousCompletionPercent = quest.completionPercent,
                    completionPercent = completionPercent,
                    accepted = accepted,
                    updated = updated
                });
            elseif accepted then
                quest.lastUpdated = time();

                updateListeners(questID, {
                    index = quest.index,
                    questID = quest.questID,
                    lastUpdated = quest.lastUpdated,
                    previousCompletionPercent = quest.completionPercent,
                    completionPercent = completionPercent,
                    accepted = accepted,
                    updated = updated
                });
            else
                quest.lastUpdated = quest.lastUpdated or cache.lastUpdated[questID];
            end

            quest.completionPercent = completionPercent;
        end
    end
end

function helper:Refresh()
    -- Selecting quests (to read their details) can fire QUEST_LOG_UPDATE again, don't recurse.
    if refreshing then
        refreshQueued = true;

        return cache.quests;
    end

    refreshing = true;
    local ok, err = pcall(doRefresh, self);
    refreshing = false;

    if not ok then
        -- Report it like any other addon error but keep the event handler alive.
        geterrorhandler()(err);
    end

    if refreshQueued then
        refreshQueued = false;

        C_Timer.After(0, function()
            helper:Refresh();
        end);
    end

    return cache.quests;
end

function helper:AreQuestsLoaded()
    return cache.quests ~= nil;
end

function helper:GetQuests()
    if not self:AreQuestsLoaded() then
        self:Refresh();
    end

    return cache.quests or {};
end

function helper:GetQuest(questID)
    if not cache.quests then
        self:Refresh();
    end

    return cache.quests and cache.quests[questID];
end

function helper:GetQuestCount()
    return count(helper:GetQuests());
end

-- The set of quests being watched is owned by QuestWatchHelper, which plugs itself in here.
local watchProvider;
function helper:SetWatchProvider(provider)
    watchProvider = provider;
end

function helper:GetWatchedQuests()
    local quests = self:GetQuests();
    local watchedQuests = {};

    for questID, quest in pairs(quests) do
        if watchProvider and watchProvider(questID, quest) then
            watchedQuests[questID] = quest;
        end
    end

    return watchedQuests;
end

function helper:GetObjectives(questID)
    local objectives = Compat:GetQuestObjectives(questID);
    local formattedObjectives = {};

    for _, objective in ipairs(objectives) do
        -- Some quests will return blank objectives.
        --
        -- Examples
        -- - https://classic.wowhead.com/quest=1149
        if objective.text and trim(objective.text) ~= "" then
            formattedObjectives[#formattedObjectives + 1] = {
                text = objective.text,
                type = objective.type,
                completed = objective.finished,
                fulfilled = objective.numFulfilled,
                required = objective.numRequired
            };
        end
    end

    return formattedObjectives;
end

function helper:IsQuestSharable(index)
    local questID = self:GetQuestIDFromIndex(index);

    return questID ~= nil and Compat:IsQuestPushable(questID, index);
end

function helper:AbandonQuest(index)
    local questID = self:GetQuestIDFromIndex(index);

    if questID then
        Compat:AbandonQuest(questID, index);
    end
end

function helper:ShareQuest(index)
    local questID = self:GetQuestIDFromIndex(index);

    if questID then
        Compat:ShareQuest(questID, index);
    end
end

function helper:GetQuestSummary(index)
    local questID = self:GetQuestIDFromIndex(index);

    return questID and Compat:GetQuestSummary(questID, index) or nil;
end

-- Selects a quest in the log (including any visible quest log UI).
function helper:Select(index)
    if type(QuestLog_SetSelection) == "function" then
        pcall(QuestLog_SetSelection, index);

        return;
    end

    local questID = self:GetQuestIDFromIndex(index);

    if questID then
        Compat:SelectQuest(questID, index);
    end
end

local previousSelection;
function helper:SetFocusByQuestIndex(index)
    local questID = self:GetQuestIDFromIndex(index);

    previousSelection = Compat:CaptureSelection();

    if questID then
        Compat:SelectQuest(questID, index);
    end
end

function helper:SetFocus(options)
    if options and options.questLog then
        self:SetFocusByQuestIndex(options.questLog);
    end
end

function helper:RevertFocus()
    if not previousSelection then return end

    Compat:RestoreSelection(previousSelection);
    previousSelection = nil;
end

AceEvent.RegisterEvent(helper, "QUEST_LOG_UPDATE", "Refresh");
