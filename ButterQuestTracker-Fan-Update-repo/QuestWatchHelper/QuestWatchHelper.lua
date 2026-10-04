local Compat = LibStub("BQTCompat-1.0");
local QLH = LibStub("QuestLogHelper-1.0");
local helper = LibStub:NewLibrary("QuestWatchHelper-1.0", 2);
if not helper then return end

--[[
    BQT keeps its *own* list of watched quests. Blizzard's watch list has a hard cap, was
    reworked more than once between expansions and isn't something we want to depend on.

    We still mirror our list into Blizzard's, best effort, so the quest log's tracking
    checkmarks stay meaningful, and we listen for the player toggling tracking in the
    quest log so those clicks keep working as manual overrides.
]]

-- questID -> true / false. Quests we haven't decided about yet are absent.
local trackedQuests = {};
-- questID -> the last state we pushed into Blizzard's own watch list.
local mirrored = {};
-- Quests the player had manually tracked last session (SavedVariables), used until we decide otherwise.
local seed = {};
-- True while we are the ones calling Blizzard's watch functions, so our hooks ignore it.
local applying = false;

local timers = {};
local function debounce(name, func)
    if timers[name] then
        timers[name]:Cancel();
    end

    timers[name] = C_Timer.NewTimer(0.1, func);
end

local listeners = {};
local updatedQuestIndexes = {};
local function updateListeners(updatedQuest)
    updatedQuestIndexes[updatedQuest.questID] = updatedQuest;

    debounce("listeners", function()
        local updates = updatedQuestIndexes;
        updatedQuestIndexes = {};

        for _, listener in ipairs(listeners) do
            listener(updates);
        end
    end);
end

local function count(t)
    local _count = 0;
    for _, _ in pairs(t) do _count = _count + 1 end
    return _count;
end

local function findIndex(t, element)
    for index, value in pairs(t) do
        if value == element then
            return index;
        end
    end
end

function helper:GetFrame()
    return Compat:GetBlizzardTrackerFrames()[1];
end

function helper:IsAutomaticQuestWatchEnabled()
    local ok, value = pcall(GetCVar, 'autoQuestWatch');

    return ok and value == '1';
end

function helper:SetAutomaticQuestWatch(autoQuestWatch)
    pcall(SetCVar, 'autoQuestWatch', autoQuestWatch and '1' or '0');
end

-- ---------------------------------------------------------------------------
-- The watched set
-- ---------------------------------------------------------------------------

function helper:IsWatched(questID)
    local watched = trackedQuests[questID];

    if watched == nil then
        return seed[questID] == true;
    end

    return watched;
end

-- Returns true when the watched state actually changed.
function helper:SetWatched(quest, watched)
    local questID = quest.questID;

    if not questID then return false end

    watched = watched and true or false;

    local previous = self:IsWatched(questID);

    trackedQuests[questID] = watched;

    if mirrored[questID] ~= watched then
        mirrored[questID] = watched;

        applying = true;
        pcall(Compat.MirrorWatch, Compat, questID, quest.index, watched);
        applying = false;
    end

    if previous ~= watched then
        updateListeners({
            index = quest.index,
            questID = questID,
            watched = watched,
            byUser = false
        });

        return true;
    end

    return false;
end

local function isShiftAndLogShown()
    return IsShiftKeyDown() and QLH:IsShown();
end

-- Called when the *player* (not us) changes tracking through Blizzard's own UI.
local function onUserWatchChanged(questID, watched)
    if not questID then return end

    trackedQuests[questID] = watched;
    mirrored[questID] = watched;

    updateListeners({
        index = QLH:GetIndexFromQuestID(questID),
        questID = questID,
        watched = watched,
        byUser = true
    });
end

local installed = false;

function helper:BypassWatchLimit(initialTrackedQuests)
    seed = {};
    for questID, tracked in pairs(initialTrackedQuests or {}) do
        if tracked == true then
            seed[questID] = true;
        end
    end

    if installed then return end
    installed = true;

    if Compat:HasModernWatch() then
        local manualType = Compat:GetManualWatchType();

        Compat:SafeHook(C_QuestLog, "AddQuestWatch", function(questID, watchType)
            if applying then return end

            local byUser;
            if manualType ~= nil and watchType ~= nil then
                byUser = watchType == manualType;
            else
                byUser = isShiftAndLogShown() or QLH:IsShown();
            end

            if byUser then
                onUserWatchChanged(questID, true);
            end
        end);

        Compat:SafeHook(C_QuestLog, "RemoveQuestWatch", function(questID)
            if applying then return end

            if QLH:IsShown() then
                onUserWatchChanged(questID, false);
            end
        end);
    elseif Compat:HasLegacyWatch() then
        -- Shift clicking a quest in the (classic style) quest log toggles tracking.
        Compat:SafeHook("AddQuestWatch", function(index)
            if applying or not isShiftAndLogShown() then return end

            onUserWatchChanged(QLH:GetQuestIDFromIndex(index), true);
        end);

        Compat:SafeHook("RemoveQuestWatch", function(index)
            if applying or not isShiftAndLogShown() then return end

            onUserWatchChanged(QLH:GetQuestIDFromIndex(index), false);
        end);
    end

    if not Compat:HasModernQuestLog() then
        -- Classic style clients: Blizzard's quest log UI decides what is "watched" and enforces
        -- a tiny watch limit through these functions, so make them tell it what *we* track.
        if type(_G.IsQuestWatched) == "function" then
            _G.IsQuestWatched = function(index)
                local questID = QLH:GetQuestIDFromIndex(index);

                return questID ~= nil and helper:IsWatched(questID) or false;
            end
        end

        if type(_G.GetNumQuestWatches) == "function" then
            _G.GetNumQuestWatches = function()
                return 0;
            end
        end

        -- This bypasses a limitation that would prevent users from tracking quests without objectives
        if type(_G.GetNumQuestLeaderBoards) == "function" and type(_G.GetQuestLogSelection) == "function" then
            _G.GetNumQuestLeaderBoards = function(index)
                index = index or GetQuestLogSelection();
                local questID = QLH:GetQuestIDFromIndex(index);

                if not questID then return 0 end

                local quest = QLH:GetQuest(questID);

                if not quest then return 0 end

                local objectiveCount = count(quest.objectives);

                if objectiveCount == 0 then return 1 end

                return objectiveCount;
            end
        end

        if _G.MAX_WATCHABLE_QUESTS ~= nil then
            _G.MAX_WATCHABLE_QUESTS = Compat:GetMaxQuests();
        end
    end

    QLH:OnQuestUpdated(function(quests)
        for questID, quest in pairs(quests) do
            if quest.abandoned then
                local wasTracked = trackedQuests[questID];

                trackedQuests[questID] = nil;
                mirrored[questID] = nil;
                seed[questID] = nil;

                if wasTracked then
                    updateListeners({
                        index = quest.index,
                        questID = quest.questID,
                        watched = false,
                        byUser = false
                    });
                end
            end
        end
    end);
end

function helper:OnQuestWatchUpdated(listener)
    tinsert(listeners, listener);
end

function helper:OffQuestWatchUpdated(listener)
    local index = findIndex(listeners, listener);

    if not index then return end

    table.remove(listeners, index);
end

-- ---------------------------------------------------------------------------
-- Blizzard's own tracker
-- ---------------------------------------------------------------------------

local hiddenFrames = {};
local keepHidden = true;

function helper:KeepHidden()
    keepHidden = true;

    for _, frame in ipairs(Compat:GetBlizzardTrackerFrames()) do
        if not hiddenFrames[frame] then
            hiddenFrames[frame] = true;

            if type(frame.HookScript) == "function" then
                pcall(frame.HookScript, frame, "OnShow", function(shown)
                    if keepHidden then
                        shown:Hide();
                    end
                end);
            end
        end

        pcall(frame.Hide, frame);
    end
end

-- Safety net: if BQT can't start we give the player their normal tracker back.
function helper:RestoreBlizzardTracker()
    keepHidden = false;

    for _, frame in ipairs(Compat:GetBlizzardTrackerFrames()) do
        pcall(frame.Show, frame);
    end
end

-- Plug into the quest log helper so it knows what is being watched.
QLH:SetWatchProvider(function(questID)
    return helper:IsWatched(questID);
end);
