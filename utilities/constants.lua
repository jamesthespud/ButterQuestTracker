local NAME, ns = ...

local CONSTANTS = {
    VERSION = "1.7.0",
    NAME = "Butter Quest Tracker",
    NAME_SQUASHED = "ButterQuestTracker",
    CURSEFORGE_SLUG = "butter-quest-tracker",
    BRAND_COLOR = "|c00FF9696",
    PATHS = {}
};

CONSTANTS.PATHS.MEDIA = "Interface\\AddOns\\" .. NAME .. "\\Media\\";
CONSTANTS.PATHS.LOGO = "|T" .. CONSTANTS.PATHS.MEDIA .. "BQT_logo:24:24:0:-8" .. "|t";

CONSTANTS.DEFAULT_CONFIG = {
    -- Filters & Sorting

    Sorting = "Disabled",
    CurrentZoneOnly = false,
    HideCompletedQuests = false,
    QuestLimit = 10,
    AutoTrackUpdatedQuests = false,

    -- Frame Settings

    PositionX = 0,
    PositionY = -240,
    Width = 250,
    MaxHeight = 600,

    -- Visuals

    TrackerHeaderFormat = "QuestsNumberVisible",
    ColorHeadersByDifficultyLevel = false,
    TrackerHeaderFontSize = 12,
    QuestHeaderFontSize = 12,
    ObjectiveFontSize = 12,
    QuestPadding = 10,

    -- Advanced

    DeveloperMode = false,
    DebugLevel = 3
};

CONSTANTS.DEFAULT_CHARACTER_CONFIG = {
    -- Backend

    MANUALLY_TRACKED_QUESTS = {},
    QUESTS_LAST_UPDATED = {}
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
