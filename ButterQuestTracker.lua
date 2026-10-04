local NAME, ns = ...

local Compat = LibStub("BQTCompat-1.0");
local QWH = LibStub("QuestWatchHelper-1.0");
local QLH = LibStub("QuestLogHelper-1.0");
local ZH = LibStub("BQTZoneHelper-1.0");
local QH = LibStub("LibQuestHelpers-1.0");

local BQTL = ButterQuestTrackerLocale;
ButterQuestTracker = LibStub("AceAddon-3.0"):NewAddon("ButterQuestTracker", "AceEvent-3.0");
local BQT = ButterQuestTracker;

-- Plays one of Blizzard's UI sounds, quietly doing nothing if the sound kit isn't there.
local function playSound(name)
    if SOUNDKIT and SOUNDKIT[name] then
        pcall(PlaySound, SOUNDKIT[name]);
    end
end

-- The dialog's frames have been renamed between client versions (editBox / EditBox / GetEditBox()).
local function getPopupEditBox(dialog)
    if dialog.editBox then
        return dialog.editBox;
    elseif dialog.EditBox then
        return dialog.EditBox;
    elseif type(dialog.GetEditBox) == "function" then
        return dialog:GetEditBox();
    elseif dialog.GetName and dialog:GetName() then
        return _G[dialog:GetName() .. "EditBox"];
    end
end

StaticPopupDialogs[NAME .. "_WowheadURL"] = {
    -- The whole text (title + quest name) is passed in as the first argument.
    text = "%s",
    button2 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 300,

    EditBoxOnEnterPressed = function(self)
        self:GetParent():Hide()
    end,

    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,

    OnShow = function(self, data)
        local editBox = getPopupEditBox(self);

        if not editBox or not data then return end

        editBox:SetText(Compat:GetWowheadURL(data));
        editBox:SetFocus();
        editBox:HighlightText();
    end,

    whileDead = true,
    hideOnEscape = true
}

function BQT:OnEnable()
    self.db = LibStub("AceDB-3.0"):New("ButterQuestTrackerConfig", ns.CONSTANTS.DB_DEFAULTS, true);
    self.hiddenContainers = {};

    -- TODO: This is for backwards compatible support of the SavedVariables
    -- Remove this in v2.0.0
    if ButterQuestTrackerCharacterConfig then
        for key, value in pairs(ButterQuestTrackerCharacterConfig) do
            self.db.char[key] = value;
            ButterQuestTrackerCharacterConfig[key] = nil;
        end
    end
    -- END TODO

    QWH:BypassWatchLimit(self.db.char.MANUALLY_TRACKED_QUESTS);
    QWH:KeepHidden();
end

function BQT:OnPlayerEnteringWorld()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD");

    -- If anything below blows up the player would be left with no quest tracker at all,
    -- so in that case hand the Blizzard tracker back.
    local ok, err = xpcall(function() self:Initialize() end, geterrorhandler());

    if not ok then
        QWH:RestoreBlizzardTracker();

        print(ns.CONSTANTS.LOGGER.PREFIX .. ns.CONSTANTS.LOGGER.TYPES.ERROR.COLOR, "failed to start, the default quest tracker was restored. Type /bqt status and report the output.");
    end
end

function BQT:Initialize()
    if self.HookOptionsPanels then
        self:HookOptionsPanels();
    end

    BQTL:SetLocale(BQT.db.global.Locale);
    QWH:OnQuestWatchUpdated(function(questWatchUpdates)
        for _, updateInfo in pairs(questWatchUpdates) do
            if updateInfo.byUser then
                if updateInfo.watched then
                    self.db.char.MANUALLY_TRACKED_QUESTS[updateInfo.questID] = true;
                else
                    self.db.char.MANUALLY_TRACKED_QUESTS[updateInfo.questID] = false;
                end
            end
        end

        self:RefreshView();
    end);

    QLH:OnQuestUpdated(function(quests)
        self:LogTrace("Event(OnQuestUpdated)");

        local currentZone = GetRealZoneText();
        local minimapZone = GetMinimapZoneText();

        for questID, quest in pairs(quests) do
            if quest.abandoned then
                self.db.char.QUESTS_LAST_UPDATED[questID] = nil;
                self.db.char.MANUALLY_TRACKED_QUESTS[questID] = nil;
            elseif quest.accepted or quest.updated then
                self.db.char.QUESTS_LAST_UPDATED[questID] = quest.lastUpdated;

                -- If the quest is updated then remove it from the manually tracked quests list.
                if self.db.global.AutoTrackUpdatedQuests then
                    self.db.char.MANUALLY_TRACKED_QUESTS[questID] = true;
                elseif self.db.char.MANUALLY_TRACKED_QUESTS[questID] == false then
                    self.db.char.MANUALLY_TRACKED_QUESTS[questID] = nil;
                end

                self:UpdateQuestWatch(currentZone, minimapZone, QLH:GetQuest(questID));
            end
        end

        self:RefreshView();
    end);

    ZH:OnZoneChanged(function(info)
        self:LogInfo("Changed Zones: (" .. info.zone .. ", " .. info.subZone .. ")");
        self:RefreshQuestWatch();
    end);

    self.tracker = LibStub("TrackerHelper-1.0"):New({
        position = {
            x = self.db.global.PositionX,
            y = self.db.global.PositionY
        },

        width = self.db.global.Width,
        maxHeight = self.db.global.MaxHeight,

        backgroundColor = self.db.global.BackgroundColor,

        backgroundVisible = self.db.global.BackgroundAlwaysVisible or self.db.global.DeveloperMode,

        locked = self.db.global.LockFrame
    });

    -- TODO: This automatically updates invalid last updated values to the current time
    -- Remove this in v2.0.0
    for questID, lastUpdated in pairs(self.db.char.QUESTS_LAST_UPDATED) do
        if lastUpdated < 1000000 then
            self.db.char.QUESTS_LAST_UPDATED[questID] = time();
        end
    end
    -- END TODO

    self.db.char.QUESTS_LAST_UPDATED = QLH:SetQuestsLastUpdated(self.db.char.QUESTS_LAST_UPDATED);

    self:RefreshQuestWatch();
    self:RefreshView();
    if self.db.global.Sorting == "ByQuestProximity" then
        self:UpdateQuestProximityTimer();
    end

    -- This is a massive hack to prevent questie from ignoring us.
    C_Timer.After(3.0, function()
        QH:SetAutoHideQuestHelperIcons(self.db.global.AutoHideQuestHelperIcons);
    end);

    self:LogInfo("Enabled");
end

BQT:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

function BQT:ShowWowheadPopup(id)
    local quest = QLH:GetQuest(id);
    local title = ns.CONSTANTS.PATHS.LOGO .. ns.CONSTANTS.BRAND_COLOR .. " Butter Quest Tracker Fan Update" .. "|r - Wowhead URL " .. ns.CONSTANTS.PATHS.LOGO;

    if quest and quest.title then
        title = title .. "\n\n|cffff7f00" .. quest.title .. "|r";
    end

    StaticPopup_Show(NAME .. "_WowheadURL", title, nil, id);
end

local function getDistance(x1, y1, x2, y2)
	return math.min( (x2-x1)^2 + (y2-y1)^2 );
end

local function count(t)
    local _count = 0;
    if t then
        for _, _ in pairs(t) do _count = _count + 1 end
    end
    return _count;
end

local function getWorldPlayerPosition()
    return Compat:GetPlayerWorldPosition();
end

-- The quest log index can change at any time, always ask for the current one.
local function currentIndex(quest)
    return QLH:GetIndexFromQuestID(quest.questID) or quest.index;
end

local function sortQuestFallback(quest, otherQuest, field, comparator)
    local value = quest[field];
    local otherValue = otherQuest[field];

    if value == otherValue then
        return quest.index < otherQuest.index;
    end

    if not value and otherValue then
        return false;
    elseif value and not otherValue then
        return true;
    end

    if comparator == ">" then
        return value > otherValue;
    elseif comparator == "<" then
        return value < otherValue;
    else
        BQT:LogError("Unknown Comparator. (" .. comparator .. ")");
    end
end

local function sortQuests(quest, otherQuest)
    local sorting = BQT.db.global.Sorting or "nil";
    if sorting == "Disabled" then
        return sortQuestFallback(quest, otherQuest);
    end

    if sorting == "ByLevel" then
        return sortQuestFallback(quest, otherQuest, "level", "<");
    elseif sorting == "ByLevelReversed" then
        return sortQuestFallback(quest, otherQuest, "level", ">");
    elseif sorting == "ByPercentCompleted" then
        return sortQuestFallback(quest, otherQuest, "completionPercent", ">");
    elseif sorting == "ByRecentlyUpdated" then
        return sortQuestFallback(quest, otherQuest, "lastUpdated", ">");
    elseif sorting == "ByQuestProximity" then
        if QH:IsSupported() then
            quest.distance = QH:GetDistanceToClosestObjective(quest.questID);
            otherQuest.distance = QH:GetDistanceToClosestObjective(otherQuest.questID);
        else
            quest.distance = 0;
            otherQuest.distance = 0;
        end

        return sortQuestFallback(quest, otherQuest, "distance", "<");
    else
        BQT:LogError("Unknown Sorting value. (" .. sorting .. ")")
    end

    return false;
end

function BQT:UpdateQuestProximityTimer()
    if self.db.global.Sorting == "ByQuestProximity" then
        local initialized = false;
        self:Sort();

        self.questProximityTimer = C_Timer.NewTicker(5.0, function()
            self:LogTrace("-- Starting ByQuestProximity Checks --");
            self:LogTrace("Checking if player has moved...");
            local position = getWorldPlayerPosition();

            if position then
                local distance = self.playerPosition and getDistance(position.x, position.y, self.playerPosition.x, self.playerPosition.y);

                if not initialized or not distance or distance > 0.01 then
                    initialized = true;
                    self.playerPosition = position;
                    self:Sort();
                else
                    self:LogTrace("Player movement wasn't greater then 5, ignoring... (" .. distance .. ")");
                end
                self:LogTrace("-- Ending ByQuestProximity Checks --");
            end
        end);
    elseif self.questProximityTimer then
        self.playerPosition = nil;
        self.questProximityTimer:Cancel();
    end
end

function BQT:RefreshQuestWatch()
    self:LogTrace("Refreshing Quest Watch");

    local quests = QLH:GetQuests();

    local currentZone = GetRealZoneText();
    local minimapZone = GetMinimapZoneText();

    for _, quest in pairs(quests) do
        self:UpdateQuestWatch(currentZone, minimapZone, quest);
    end
end

function BQT:UpdateQuestWatch(currentZone, minimapZone, quest)
    QWH:SetWatched(quest, self:ShouldWatchQuest(currentZone, minimapZone, quest));
end

-- Untrack a quest by hand (shift click / context menu) and remember that it was the player's choice.
function BQT:UntrackQuest(quest)
    self.db.char.MANUALLY_TRACKED_QUESTS[quest.questID] = false;
    QWH:SetWatched(quest, false);
    self:RefreshView();
end

function BQT:ShouldWatchQuest(currentZone, minimapZone, quest)
    quest.isCurrentZone = quest.zone == currentZone or quest.zone == minimapZone;

    if self.db.char.MANUALLY_TRACKED_QUESTS[quest.questID] == true then
        return true;
    elseif self.db.char.MANUALLY_TRACKED_QUESTS[quest.questID] == false or self.db.global.DisableFilters then
        return false;
    end

    if self.db.global.HideCompletedQuests and quest.completed then
        return false;
    end

    if self.db.global.CurrentZoneOnly and not quest.isCurrentZone and not quest.isClassQuest and not quest.isProfessionQuest then
        return false;
    end

    return true;
end

function BQT:GetQuestInfo()
    if self.db.global.DisplayDummyData and self:IsOptionsShown() then
        -- TODO: Move this into QuestLogHelper
        local quests = {
            -- Partially Completed
            [6563] = {
                index = 1,
                questID = 6563,
                title = "The Essence of Aku'Mai",
                zone = "Blackfathom Deeps",
                completed = false,
                failed = false,
                isClassQuest = false,
                isProfessionQuest = false,
                sharable = true,
                level = 22,
                difficulty = QLH:GetDifficulty(22),
                completionPercent = 0.25,

                objectives = {
                    [1] = {
                        text = "Sapphire of Aku'Mai: 5/20",
                        fulfilled = 5,
                        required = 20,
                        completed = false
                    }
                }
            },

            -- No objectives, summary only
            [1196] = {
                index = 2,
                questID = 1196,
                title = "The Sacred Flame",
                summary = "Deliver the Filled Etched Phial to Rau Cliffrunner at the Freewind Post.",
                zone = "Thunder Bluff",
                completed = false,
                failed = false,
                isClassQuest = false,
                isProfessionQuest = false,
                sharable = true,
                level = 29,
                difficulty = QLH:GetDifficulty(29),
                completionPercent = 1
            },

            -- Multiple Objectives, partially completed.
            [4841] = {
                index = 3,
                questID = 4841,
                title = "Pacify the Centaur",
                zone = "Thousand Needles",
                completed = false,
                failed = false,
                isClassQuest = false,
                isProfessionQuest = false,
                sharable = true,
                level = 25,
                difficulty = QLH:GetDifficulty(25),
                completionPercent = 0.5714,

                objectives = {
                    [1] = {
                        text = "Galak Scout slain: 0/12",
                        fulfilled = 0,
                        required = 12,
                        completed = false
                    },

                    [2] = {
                        text = "Galak Wrangler slain: 10/10",
                        fulfilled = 10,
                        required = 10,
                        completed = true
                    },

                    [3] = {
                        text = "Galak Windchaser slain: 6/6",
                        fulfilled = 6,
                        required = 6,
                        completed = true
                    }
                }
            },

            -- Completed
            [5147] = {
                index = 4,
                questID = 5147,
                title = "Compendium of the Fallen",
                zone = "Scarlet Monastery",
                completed = true,
                failed = false,
                isClassQuest = false,
                isProfessionQuest = false,
                sharable = true,
                level = 38,
                difficulty = QLH:GetDifficulty(38),
                completionPercent = 1,

                objectives = {
                    [1] = {
                        text = "Compendium of the Fallen: 1/1",
                        fulfilled = 1,
                        required = 1,
                        completed = true
                    }
                }
            },

            -- Failed
            [4904] = {
                index = 5,
                questID = 4904,
                title = "Free at Last",
                zone = "Thousand Needles",
                completed = false,
                failed = true,
                isClassQuest = false,
                isProfessionQuest = false,
                sharable = false,
                level = 29,
                difficulty = QLH:GetDifficulty(29),
                completionPercent = 0,

                objectives = {
                    [1] = {
                        text = "Escort Lakota Windsong from the Darkcloud Pinnacle.",
                        type = "event",
                        fulfilled = 0,
                        required = 1,
                        completed = false
                    }
                }
            }
        };

        local currentZone = "Thunder Bluff";
        local minimapZone = GetMinimapZoneText();

        local watchedQuests = {};
        for questID, quest in pairs(quests) do
            if self:ShouldWatchQuest(currentZone, minimapZone, quest) then
                watchedQuests[questID] = quest;
            end
        end

        return watchedQuests, count(quests), true;
    end

    return QLH:GetWatchedQuests(), QLH:GetQuestCount(), false;
end

function BQT:GetTrackerHeader(visibleQuestCount, questCount)
    if self.db.global.TrackerHeaderFormat == "QuestsNumberVisible" then
        return BQTL:GetString('QT_QUESTS') .. " (" .. visibleQuestCount .. "/" .. questCount .. ")";
    elseif self.db.global.TrackerHeaderFormat == "QuestsNumberVisibleTotal" then
        return BQTL:GetString('QT_QUESTS') .. " (" .. visibleQuestCount .. "/" .. Compat:GetMaxQuests() .. ")";
    end

    return BQTL:GetString('QT_QUESTS');
end

function BQT:GetQuestHeader(quest)
    local format = self.db.global.QuestHeaderFormat;

    for match, key in format:gmatch("({{(%w+)}})" ) do
        local value = quest[key] or "";

        if type(value) == "number" and math.floor(value) ~= value then
            value = string.format("%.1f", value);
        end

        format = format:gsub(match, value, 1);
    end

    return format;
end

function BQT:Sort()
    self:LogInfo("Sort");

    if not self.questContainers then return end

    -- collect the keys
    local quests = self:GetQuestInfo();
    local keys = {};
    for k in pairs(quests) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return sortQuests(quests[a], quests[b]) end);

    local questIDToOrderMap = {};
    local zoneToOrderMap = {};
    for i, questID in pairs(keys) do
        questIDToOrderMap[questID] = i;

        local zone = quests[questID].zone;
        if zone then
            zoneToOrderMap[zone] = zoneToOrderMap[zone] or i;
        end
    end

    if self.db.global.ZoneSorting ~= "ByQuestOrder" then
        -- Stable zone order: the zone you are in first, then the rest alphabetically.
        local zones = {};
        for zone in pairs(zoneToOrderMap) do zones[#zones + 1] = zone end

        local currentZone, minimapZone = GetRealZoneText(), GetMinimapZoneText();
        local function isCurrent(zone) return zone == currentZone or zone == minimapZone end

        table.sort(zones, function(a, b)
            local aCurrent, bCurrent = isCurrent(a), isCurrent(b);

            if aCurrent ~= bCurrent then return aCurrent end

            local aName, bName = tostring(a):lower(), tostring(b):lower();
            if aName ~= bName then return aName < bName end

            return tostring(a) < tostring(b);
        end);

        zoneToOrderMap = {};
        for rank, zone in ipairs(zones) do
            zoneToOrderMap[zone] = rank;
        end
    end

    for _, element in pairs(self.questContainers) do
        element:SetOrder(questIDToOrderMap[element.metadata.quest.questID]);
    end

    if self.db.global.ZoneHeaderEnabled then
        for _, element in ipairs(self.questsContainer.elements) do
            local order = zoneToOrderMap[element.metadata.zone];

            if order then
                if not element.metadata.header then
                    order = order + 0.1;
                end

                element:SetOrder(order, false);
            end
        end

        self.questsContainer:Order();
    end
end

function BQT:RefreshView()
    self:LogInfo("Refresh Quests");
    self.tracker:Clear();

    local watchedQuests, questCount = self:GetQuestInfo();

    self:LogTrace("Quest Count:", questCount);

    local trackerContainer = self.tracker:Container({
        margin = {
            x = 10,
            y = 10
        },

        backgroundColor = self.db.global.DeveloperMode and {
            r = 1.0,
            g = 1.0,
            a = 0.2
        }
    });

    if self.db.global.TrackerHeaderEnabled then
        self.tracker:Font({
            label = self:GetTrackerHeader(count(watchedQuests), questCount),
            color = self.db.global.TrackerHeaderFontColor,
            size = self.db.global.TrackerHeaderFontSize,

            container = self.tracker:Container({
                container = trackerContainer,

                margin = {
                    bottom = 10
                },

                events = {
                    OnMouseDown = function(button)
                        if button ~= "LeftButton" or self.db.global.LockFrame then return end

                        self.tracker:StartMoving();
                    end,

                    OnMouseUp = function(button)
                        if button ~= "LeftButton" or self.db.global.LockFrame then return end

                        self.tracker:StopMovingOrSizing();
                    end,

                    OnButterDragStart = function()
                        self.tracker:SetBackgroundVisibility(true);
                    end,

                    -- This fires only if OnButterDragStart fires as well.
                    OnButterDragStop = function()
                        local x, y = self.tracker:GetPosition();
                        if not self.db.global.DeveloperMode and not self.db.global.BackgroundAlwaysVisible then
                            self.tracker:SetBackgroundVisibility(false);
                        end

                        self.db.global.PositionX = x;
                        self.db.global.PositionY = y;

                        LibStub("AceConfigRegistry-3.0"):NotifyChange("ButterQuestTracker");
                    end,

                    -- This fires only if OnButterDragStart doesn't fire.
                    OnButterMouseUp = function(button)
                        if button == "LeftButton" then
                            self.hiddenContainers["QUESTS"] = self.questsContainer:ToggleHidden() or nil;
                            playSound("IG_MAINMENU_OPTION_CHECKBOX_ON");
                        else
                            self:ToggleOptions();
                        end
                    end
                }
            })
        });
    end

    self.questsContainer = self.tracker:Container({
        container = trackerContainer,
        hidden = self.hiddenContainers["QUESTS"]
    });
    self.questContainers = {};
    local zoneContainers = {};
    local index = 1;
    for _, quest in pairs(watchedQuests) do
        if not zoneContainers[quest.zone] then
            if self.db.global.ZoneHeaderEnabled then
                -- Zone Header
                self.tracker:Font({
                    label = quest.zone,
                    color = self.db.global.ZoneHeaderFontColor,
                    size = self.db.global.ZoneHeaderFontSize,

                    container = self.tracker:Container({
                        container = self.questsContainer,

                        margin = {
                            bottom = 10,
                            left = 2
                        },

                        metadata = {
                            header = true,
                            zone = quest.zone
                        },

                        events = {
                            OnMouseUp = function()
                                self.hiddenContainers["Z-" .. quest.zone] = zoneContainers[quest.zone]:ToggleHidden() or nil;
                                playSound("IG_MAINMENU_OPTION_CHECKBOX_ON");
                            end
                        }
                    })
                });

                zoneContainers[quest.zone] = self.tracker:Container({
                    container = self.questsContainer,
                    hidden = self.hiddenContainers["Z-" .. quest.zone],

                    margin = {
                        left = 8
                    },

                    metadata = {
                        header = false,
                        zone = quest.zone
                    }
                });
            end
        end

        local questContainer = self.tracker:Container({
            container = self.db.global.ZoneHeaderEnabled and zoneContainers[quest.zone] or self.questsContainer,

            backgroundColor = self.db.global.DeveloperMode and {
                g = 1.0,
                a = 0.2
            },

            margin = {
                bottom = self.db.global.QuestPadding,
                left = (self.db.global.ZoneHeaderEnabled or not self.db.global.TrackerHeaderEnabled) and 0 or 5
            },

            metadata = {
                quest = quest
            },

            events = {
                OnMouseUp = function(button)
                    if button == "LeftButton" then
                        if IsShiftKeyDown() then
                            playSound("IG_MAINMENU_OPTION_CHECKBOX_ON");
                            self:UntrackQuest(quest);
                        elseif IsAltKeyDown() then
                            self:ShowWowheadPopup(quest.questID);
                        elseif IsControlKeyDown() then
                            ChatEdit_InsertLink(Compat:GetQuestChatLink(quest));
                        else
                            QLH:ToggleQuest(currentIndex(quest));
                        end
                    else
                        self:ToggleContextMenu(quest);
                    end
                end,

                OnEnter = function(_, target)
                    GameTooltip:SetOwner(target, "ANCHOR_NONE");
                    GameTooltip:SetPoint("RIGHT", target, "LEFT");
                    GameTooltip:AddLine(quest.title .. "\n", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true);
                    GameTooltip:AddLine(quest.summary or "", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true);

                    if self.db.global.DeveloperMode then
                        GameTooltip:AddDoubleLine("\nQuest ID:", quest.questID, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
                        GameTooltip:AddDoubleLine("Quest Index:", quest.index, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);

                        for _, addon in ipairs(QH:GetActiveAddons()) do
                            local distance = QH:GetDistanceToClosestObjective(quest.questID, addon);
                            if distance then
                                GameTooltip:AddDoubleLine(addon .. " (distance):", string.format("%.1fm", distance), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
                            else
                                GameTooltip:AddDoubleLine(addon .. " (distance):", "N/A", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
                            end
                        end
                    end

                    GameTooltip:Show();
                end,

                OnLeave = function()
                    GameTooltip:ClearLines();
                    GameTooltip:Hide();
                end
            }
        });
        tinsert(self.questContainers, questContainer);

        self.tracker:Font({
            label = self:GetQuestHeader(quest),
            size = self.db.global.QuestHeaderFontSize,
            color = self.db.global.ColorHeadersByDifficultyLevel and QLH:GetDifficultyColor(quest.difficulty) or self.db.global.QuestHeaderFontColor,
            container = questContainer
        });

        local objectiveCount = count(quest.objectives);

        if objectiveCount == 0 then
            -- Not every client can tell us the quest's objective text, in which case there is nothing to show.
            if quest.summary and quest.summary ~= "" then
                self.tracker:Font({
                    label = ' - ' .. quest.summary,
                    size = self.db.global.ObjectiveFontSize,
                    color = self.db.global.ObjectiveFontColor,
                    container = questContainer,
                    margin = {
                        bottom = 2.5
                    }
                });
            end
        elseif quest.completed then
            self.tracker:Font({
                label = ' - ' .. BQTL:GetString('QT_READY_TO_TURN_IN'),
                size = self.db.global.ObjectiveFontSize,
                color = "00b205",
                container = questContainer,
                margin = {
                    bottom = 2.5
                }
            });
        elseif quest.failed then
            self.tracker:Font({
                label = ' - ' .. BQTL:GetString('QT_FAILED'),
                size = self.db.global.ObjectiveFontSize,
                color = { r = 1, g = 0.1, b = 0.1 },
                container = questContainer,
                margin = {
                    bottom = 2.5
                }
            });
        else
            for _, objective in ipairs(quest.objectives) do
                self.tracker:Font({
                    label = ' - ' .. objective.text,
                    size = self.db.global.ObjectiveFontSize,
                    color = objective.completed and HIGHLIGHT_FONT_COLOR or self.db.global.ObjectiveFontColor,
                    container = questContainer,
                    margin = {
                        bottom = 2.5
                    }
                });
            end
        end
        index = index + 1;
    end

    self:Sort();
end

-- Right click menu for a quest. Retail style clients use the new Menu API, older ones UIDropDownMenu.
function BQT:ToggleContextMenu(quest)
    if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
        if pcall(self.ShowContextMenu, self, quest) then
            return;
        end
    end

    self:ShowLegacyContextMenu(quest);
end

function BQT:ShowContextMenu(quest)
    MenuUtil.CreateContextMenu(UIParent, function(_, root)
        root:CreateTitle(quest.title);

        root:CreateButton(BQTL:GetString('QT_UNTRACK_QUEST'), function()
            self:UntrackQuest(quest);
        end);

        root:CreateButton(BQTL:GetString('QT_VIEW_QUEST'), function()
            QLH:ToggleQuest(currentIndex(quest));
        end);

        root:CreateButton(BQTL:GetString('QT_WOWHEAD_URL'), function()
            BQT:ShowWowheadPopup(quest.questID);
        end);

        local share = root:CreateButton(BQTL:GetString('QT_SHARE_QUEST'), function()
            Compat:ShareQuest(quest.questID, currentIndex(quest));
        end);

        if share and share.SetEnabled and (not UnitInParty("player") or not quest.sharable) then
            share:SetEnabled(false);
        end

        root:CreateButton(BQTL:GetString('QT_CANCEL_QUEST'), function()
            playSound("IG_MAINMENU_OPTION_CHECKBOX_ON");
        end);

        root:CreateDivider();

        root:CreateButton("|cffff0000" .. BQTL:GetString('QT_ABANDON_QUEST') .. "|r", function()
            Compat:AbandonQuest(quest.questID, currentIndex(quest));
            playSound("IG_QUEST_LOG_ABANDON_QUEST");
        end);
    end);
end

function BQT:ShowLegacyContextMenu(quest)
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return end

    if not self.contextMenu then
        self.contextMenu = CreateFrame("Frame", "BQTContextMenu", UIParent, "UIDropDownMenuTemplate");
    end

    local isActive = UIDROPDOWNMENU_OPEN_MENU == self.contextMenu;
    local hasQuestChanged = not self.contextMenu.quest or self.contextMenu.quest.questID ~= quest.questID;

    self.contextMenu.quest = quest;

    UIDropDownMenu_Initialize(self.contextMenu, function()
        local menuQuest = self.contextMenu.quest;

        UIDropDownMenu_AddButton({
            text = menuQuest.title,
            notCheckable = true,
            isTitle = true
        });

        UIDropDownMenu_AddButton({
            text = BQTL:GetString('QT_UNTRACK_QUEST'),
            notCheckable = true,
            func = function()
                self:UntrackQuest(menuQuest);
            end
        });

        UIDropDownMenu_AddButton({
            text = BQTL:GetString('QT_VIEW_QUEST'),
            notCheckable = true,
            func = function()
                QLH:ToggleQuest(currentIndex(menuQuest));
            end
        });

        UIDropDownMenu_AddButton({
            text = BQTL:GetString('QT_WOWHEAD_URL'),
            notCheckable = true,
            func = function()
                BQT:ShowWowheadPopup(menuQuest.questID);
            end
        });

        UIDropDownMenu_AddButton({
            text = BQTL:GetString('QT_SHARE_QUEST'),
            notCheckable = true,
            disabled = not UnitInParty("player") or not menuQuest.sharable,
            func = function()
                Compat:ShareQuest(menuQuest.questID, currentIndex(menuQuest));
            end
        });

        UIDropDownMenu_AddButton({
            text = BQTL:GetString('QT_CANCEL_QUEST'),
            notCheckable = true,
            func = function()
                playSound("IG_MAINMENU_OPTION_CHECKBOX_ON");
            end
        });

        UIDropDownMenu_AddButton({
            isTitle = true
        });

        UIDropDownMenu_AddButton({
            text = BQTL:GetString('QT_ABANDON_QUEST'),
            notCheckable = true,
            colorCode = "|cffff0000",
            func = function()
                Compat:AbandonQuest(menuQuest.questID, currentIndex(menuQuest));
                playSound("IG_QUEST_LOG_ABANDON_QUEST");
            end
        });
    end, "MENU");

    -- If this Dropdown menu isn't already open then play the sound effect.
    if isActive and not hasQuestChanged then
        CloseDropDownMenus();
    else
        ToggleDropDownMenu(1, nil, self.contextMenu, "cursor", 0, -3);
        playSound("IG_MAINMENU_OPEN");
    end
end

-- /bqt status: everything needed to work out why the addon misbehaves on a given client.
function BQT:PrintStatus()
    local prefix = ns.CONSTANTS.LOGGER.PREFIX .. ns.CONSTANTS.LOGGER.TYPES.INFO.COLOR;

    print(prefix, "Version " .. tostring(ns.CONSTANTS.VERSION));

    for _, line in ipairs(Compat:Describe()) do
        print(prefix, line);
    end

    local watched = 0;
    for questID in pairs(QLH:GetQuests()) do
        if QWH:IsWatched(questID) then
            watched = watched + 1;
        end
    end

    print(prefix, "Quests found: " .. QLH:GetQuestCount() .. ", tracked: " .. watched);
    print(prefix, "Quest helper addons: " .. (#QH:GetActiveAddons() > 0 and table.concat(QH:GetActiveAddons(), ", ") or "none"));
end

function BQT:ResetOverrides()
    self:LogInfo("Clearing Tracking Overrides...");
    self.db.char.MANUALLY_TRACKED_QUESTS = {};
    self:RefreshQuestWatch();
end

function BQT:Debug(type, bypass, ...)
    if bypass or (self.db.global.DeveloperMode and self.db.global.DebugLevel >= type.LEVEL) then
        print(ns.CONSTANTS.LOGGER.PREFIX .. type.COLOR, ...);
    end
end

function BQT:LogError(...)
    self:Debug(ns.CONSTANTS.LOGGER.TYPES.ERROR, true, ...);
end

function BQT:LogWarn(...)
    self:Debug(ns.CONSTANTS.LOGGER.TYPES.WARN, false, ...);
end

function BQT:LogInfo(...)
    self:Debug(ns.CONSTANTS.LOGGER.TYPES.INFO, false, ...);
end

function BQT:LogTrace(...)
    self:Debug(ns.CONSTANTS.LOGGER.TYPES.TRACE, false, ...);
end
