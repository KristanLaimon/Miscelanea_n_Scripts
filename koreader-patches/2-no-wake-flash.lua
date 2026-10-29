local Device = require("device")
if not Device:isKindle() then return end

local UIManager = require("ui/uimanager")
local time = require("ui/time")
local wake_until = 0
local outofScreenSaver = Device.outofScreenSaver
function Device:outofScreenSaver(...)
    if self.screen_saver_mode then
        wake_until = time.now() + time.s(4)
    end
    return outofScreenSaver(self, ...)
end

-- shortcut: firmware refreshes are outside KOReader; investigate firmware if flashing persists.
local refresh = UIManager._refresh
function UIManager:_refresh(mode, ...)
    if time.now() < wake_until
        and (mode == "full" or mode == "flashui" or mode == "flashpartial") then
        mode = "ui"
    end
    return refresh(self, mode, ...)
end
