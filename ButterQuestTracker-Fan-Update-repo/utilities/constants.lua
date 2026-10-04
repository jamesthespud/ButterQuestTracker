local NAME, ns = ...

local FALLBACK_VERSION = "1.0.0-forever";
local function getVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata;
    local ok, version = false, nil;

    if type(getter) == "function" then
        ok, version = pcall(getter, NAME, "Version");
    end

    -- "@project-version@" is what the CurseForge packager would have replaced.
    if ok and type(version) == "string" and version ~= "" and not version:find("@", 1, true) then
        return version;
    end

    return FALLBACK_VERSION;
end

local CONSTANTS = {
    VERSION = getVersion(),
    NAME = "Butter Quest Tracker Fan Update",
    NAME_SQUASHED = "ButterQuestTracker",
    CURSEFORGE_SLUG = "butter-quest-tracker",
    BRAND_COLOR = "|c00FF9696",
    PATHS = {}
};

CONSTANTS.PATHS.MEDIA = "Interface\\AddOns\\" .. NAME .. "\\Media\\";
CONSTANTS.PATHS.LOGO = "|T" .. CONSTANTS.PATHS.MEDIA .. "BQT_logo:24:24:0:-8" .. "|t";

CONSTANTS.DB_DEFAULTS = {
    global = {
        DisplayDummyData = false,

        -- Filters & Sorting

        DisableFilters = false,
        Sorting = "Disabled",
        CurrentZoneOnly = false,
        HideCompletedQuests = false,
        QuestLimit = 20,
        AutoTrackUpdatedQuests = false,
        AutoHideQuestHelperIcons = false,

        -- Visuals

        BackgroundAlwaysVisible = false,
        BackgroundColor = "7F000000",

        QuestPadding = 10,

        -- Visuals > Tracker Header Font Settings

        TrackerHeaderEnabled = true,
        TrackerHeaderFormat = "QuestsNumberVisible",
        TrackerHeaderFontSize = 12,
        TrackerHeaderFontColor = "FFD100",

        -- Visuals > Zone Header Font Settings

        ZoneHeaderEnabled = true,
        ZoneSorting = "CurrentThenAlphabetical",
        ZoneHeaderFontSize = 12,
        ZoneHeaderFontColor = "FFD100",

        -- Visuals > Quest Header Font Settings

        ColorHeadersByDifficultyLevel = false,
        QuestHeaderFormat = "{{title}}",
        QuestHeaderFontSize = 12,
        QuestHeaderFontColor = "FFD100",

        -- Visuals > Objective Font Settings

        ObjectiveFontSize = 12,
        ObjectiveFontColor = "CCCCCC",

        -- Frame Settings

        LockFrame = false,
        PositionX = 0,
        PositionY = -240,
        Width = 250,
        MaxHeight = 450,

        -- Advanced

        DeveloperMode = false,
        DebugLevel = 3
    },

    char = {
        -- Backend

        MANUALLY_TRACKED_QUESTS = {},
        QUESTS_LAST_UPDATED = {}
    }
};

CONSTANTS.LOGGER = {
    PREFIX = "|r[" .. CONSTANTS.BRAND_COLOR .. CONSTANTS.NAME_SQUASHED .. "|r]: |r",
    TYPES = {
        ERROR = {
            COLOR = "|c00FF0000",
            LEVEL = 1
        },
        WARN = {
            COLOR = "|c00FF7F00",
            LEVEL = 2
        },
        INFO = {
            COLOR = "|r",
            LEVEL = 3
        },
        TRACE = {
            COLOR = "|c00ADD8E6",
            LEVEL = 4
        }
    }
};

ns.CONSTANTS = CONSTANTS
