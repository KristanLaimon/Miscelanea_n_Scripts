if G_reader_settings:isTrue("kindle_preferences_20261025") then return end

local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/bookends.lua")
local rules = settings:readSetting("format_preset_rules", {})
rules.CBZ, rules.CBR, rules.PDF = "HIDDEN", "HIDDEN", "HIDDEN"
settings:saveSetting("format_preset_rules", rules)
settings:flush()

G_reader_settings:saveSetting("default_highlight_action", "highlight")
G_reader_settings:saveSetting("highlight_action_on_single_word", true)
G_reader_settings:saveSetting("kindle_preferences_20261025", true)
G_reader_settings:flush()
