local AceEvent = LibStub:GetLibrary("AceEvent-3.0");
local Compat = LibStub("BQTCompat-1.0");
local ZH = LibStub("BQTZoneHelper-1.0");
local QLH = LibStub("QuestLogHelper-1.0");
local QWH = LibStub("QuestWatchHelper-1.0");
local helper = LibStub:NewLibrary("LibQuestHelpers-1.0", 2);
if not helper then return end

local timers = {};
local function debounce(name, func)
    if timers[name] then
        timers[name]:Cancel();
    end

    timers[name] = C_Timer.NewTimer(0.1, func);
end

local function refresh()
    debounce("refresh", function()
        local questie = helper:GetQuestie();

        if questie then
            -- Questie changes its internals a lot, never let that break us.
            pcall(questie.RefreshIcons);
        end
    end);
end

local function getWorldPlayerPosition()
    return Compat:GetPlayerWorldPosition();
end

local function getDistance(x1, y1, x2, y2)
	return math.sqrt( (x2-x1)^2 + (y2-y1)^2 );
end

function helper:GetAddons()
    return {
        ["Built-In"] = Compat:HasBuiltInQuestDistance(),
        ClassicCodex = CodexQuest,
        Questie = self:GetQuestie()
    };
end

local questie;
-- luacheck: push globals QuestieLoader QuestieDB QuestieQuest
local function buildQuestie()
    -- TODO: Remove in v2.0.0
    if QuestieLoader then
        return {
            DB = QuestieLoader:ImportModule("QuestieDB"),
            Quest = QuestieLoader:ImportModule("QuestieQuest"),
            RefreshIcons = function()
                local module = questie.Quest;

                if module.UpdateHiddenNotes then
                    module:UpdateHiddenNotes();
                else
                    -- TODO: Figure out how this should be implemented with v6+ of Questie.

                end
            end,
            IsQuestComplete = function(_, quest)
                if quest.IsComplete then
                    return quest:IsComplete()
                end

                return questie.Quest:IsComplete(quest)
            end
        };
    elseif QuestieDB and QuestieQuest then
        return {
            DB = QuestieDB,
            Quest = QuestieQuest,
            RefreshIcons = function()
                QuestieQuest:UpdateHiddenNotes();
            end,
            IsQuestComplete = QuestieQuest.IsComplete
        };
    end
end

function helper:GetQuestie()
    -- Verify the Questie Addon is installed and that questie isn't already cached.
    if not questie and Questie then
        local ok, result = pcall(buildQuestie);

        if ok then
            questie = result;
        end
    end

    return questie;
end
-- luacheck: pop

function helper:GetAddonNames()
    local names = {};

    for name in pairs(self:GetAddons()) do
        tinsert(names, name);
    end

    return names;
end

function helper:GetActiveAddons()
    local activeAddons = {};

    for name, active in pairs(self:GetAddons()) do
        if active then
            tinsert(activeAddons, name);
        end
    end

    return activeAddons;
end

function helper:IsSupported()
    return #self:GetActiveAddons() > 0;
end

local function OnQuestWatchUpdated(quests)
    for _, quest in pairs(quests) do
        helper:SetIconsVisibility({
            index = quest.index,
            questID = quest.questID,
            visible = quest.watched
        });
    end
end

function helper:SetAutoHideQuestHelperIcons(autoHideIcons)
    self.autoHideIcons = autoHideIcons;

    if self.autoHideIcons then
        QWH:OnQuestWatchUpdated(OnQuestWatchUpdated);
    else
        QWH:OffQuestWatchUpdated(OnQuestWatchUpdated);
    end

    self:RefreshIconsVisibilityForQuests(QLH:GetQuests());
end

function helper:RefreshIconsVisibilityForQuests(quests)
    if self.autoHideIcons then
        for questID, quest in pairs(QLH:GetQuests()) do
            self:SetIconsVisibility({
                index = quest.index,
                questID = questID,
                visible = QWH:IsWatched(questID)
            });
        end
    else
        for questID, quest in pairs(QLH:GetQuests()) do
            self:SetIconsVisibility({
                index = quest.index,
                questID = questID,
                visible = true
            });
        end
    end
end

function helper:SetIconsVisibility(updatedQuest)
    local addons = self:GetAddons();

    if addons.ClassicCodex then
        pcall(function()
            if updatedQuest.visible then
                CodexQuest.updateQuestLog = true
                CodexQuest.updateQuestGivers = true
            else
                QLH:SetFocusByQuestIndex(updatedQuest.index);
                CodexQuest:HideCurrentQuest();
                QLH:RevertFocus();
            end
        end);
    end


    if addons.Questie then
        pcall(function()
            local quest = addons.Questie.DB:GetQuest(updatedQuest.questID);

            if quest then
                quest.HideIcons = not updatedQuest.visible;
            end
        end);
    end

    if addons["Built-In"] then
        -- TODO: Not sure if this is even supported
        -- Resources
        -- - https://github.com/tomrus88/BlizzardInterfaceCode/blob/master/Interface/FrameXML/QuestPOI.lua
    end

    refresh();
end

local function getDistanceToClosestObjective(self, questID, overrideAddon)
    local player = getWorldPlayerPosition();

    if not player then
        return nil;
    end

    local addons = self:GetAddons();

    local coordinates = {};
    if addons.ClassicCodex and (not overrideAddon or overrideAddon == "ClassicCodex") then
        local quest = QLH:GetQuest(questID);

        -- TODO: Find a way to avoid needing the quest object from the log...
        if not quest then return end

        local maps = CodexDatabase:SearchQuestById(questID, {
            questLogId = quest.index
        });

        for zone in pairs(maps) do
            for _, quests in pairs(CodexMap.nodes["CODEX"][zone]) do
                local node = quests[quest.title];
                if node then
                    -- TODO: Is there a better way to check if this is a completed node.. ?
                    local completionNode = node.texture and (string.find(node.texture, "available") or string.find(node.texture, "complete"));
                    if quest.completed and completionNode or not quest.completed and not completionNode then
                        local worldPosition = Compat:WorldPositionFromMap(ZH:GetUIMapID(zone), node.x / 100, node.y / 100);

                        if worldPosition then
                            tinsert(coordinates, {
                                x = worldPosition.x,
                                y = worldPosition.y
                            });
                        end
                    end
                end
            end
        end
    elseif addons.Questie and (not overrideAddon or overrideAddon == "Questie") then
        local quest = addons.Questie.DB:GetQuest(questID);

        if not quest then return end;

        if addons.Questie:IsQuestComplete(quest) then
            local finisher;
            if quest.Finisher.Type == "monster" then
                finisher = addons.Questie.DB:GetNPC(quest.Finisher.Id)
            elseif quest.Finisher.Type == "object" then
                finisher = addons.Questie.DB:GetObject(quest.Finisher.Id)
            end

            if not finisher then return end;

            for zoneID, spawns in pairs(finisher.spawns) do
                for _, coords in pairs(spawns) do
                    local uiMapID = ZH:GetUIMapID(zoneID);

                    if uiMapID then
                        local worldPosition = Compat:WorldPositionFromMap(uiMapID, coords[1] / 100, coords[2] / 100);

                        if worldPosition then
                            tinsert(coordinates, {
                                x = worldPosition.x,
                                y = worldPosition.y
                            });
                        end
                    end
                end
            end
        elseif quest.Objectives then
            for _, objective in pairs(quest.Objectives) do
                for _, v in pairs(objective.AlreadySpawned) do
                    for _, mapRef in pairs(v.mapRefs) do
                        local worldPosition = Compat:WorldPositionFromMap(mapRef.data and mapRef.data.UiMapID, mapRef.x / 100, mapRef.y / 100);

                        if worldPosition then
                            tinsert(coordinates, {
                                x = worldPosition.x,
                                y = worldPosition.y
                            });
                        end
                    end
                end
            end
        end
    elseif addons["Built-In"] and (not overrideAddon or overrideAddon == "Built-In") then
        local quest = QLH:GetQuest(questID);

        return quest and Compat:GetBuiltInQuestDistance(questID, quest.index) or nil;
    end

    -- TODO: Find a way to avoid needing the quest object from the log...
    if not coordinates then return end

    local closestDistance;
    for _, coords in pairs(coordinates) do
        local distance = getDistance(player.x, player.y, coords.x, coords.y);
        if closestDistance == nil or distance < closestDistance then
            closestDistance = distance;
        end
    end

    return closestDistance;
end

function helper:GetDistanceToClosestObjective(questID, overrideAddon)
    -- Questie / ClassicCodex internals are not ours, a failure there just means "unknown distance".
    local ok, distance = pcall(getDistanceToClosestObjective, self, questID, overrideAddon);

    if ok then
        return distance;
    end

    return nil;
end

AceEvent.RegisterEvent(helper, "ADDON_LOADED", function(_, addon)
    if addon == "Questie" and QLH:AreQuestsLoaded() then
        helper:RefreshIconsVisibilityForQuests(QLH:GetQuests());
    end
end);
