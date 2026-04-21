local addonName, WoWHACv5 = ...
WoWHACv5 = LibStub("AceAddon-3.0"):NewAddon(WoWHACv5, addonName, "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")
WoWHACv5.providers = {}

--[[===== LOGGER START =====]]
WoWHACv5.debug = false

function WoWHACv5:Debug(message)
    if WoWHACv5.debug then
        self:Log(message)
    end
end

function WoWHACv5:Log(message)
    self:Print("[WoWHACv5] " .. message)
end
--[[===== LOGGER END =====]]

--[[===== LIFECYCLE START =====]]
function WoWHACv5:OnInitialize()
    --  nothing to do, but can be used by external lua via AceHook so we should keep it
end

function WoWHACv5:OnEnable()
    self:Log("Join our discord: https://discord.gg/P7FaqjcATp")
    self:Log("Initializing...")
end

function WoWHACv5:OnDisable()
    --  nothing to do, but can be used by external lua via AceHook so we should keep it
end
--[[===== LIFECYCLE END =====]]