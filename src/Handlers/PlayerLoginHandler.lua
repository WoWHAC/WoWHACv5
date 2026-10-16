local _, WoWHACv5 = ...

local PlayerLoginHandler = WoWHACv5:NewModule("PlayerLoginHandler", "AceEvent-3.0")
local modern = WoWHACv5:SupportsModernFeatures()

function PlayerLoginHandler:OnEnable()
    WoWHACv5:Debug("Register provider handlers")
    PlayerLoginHandler:RegisterEvent("PLAYER_ENTERING_WORLD")
    if modern then
        PlayerLoginHandler:RegisterEvent("PLAYER_REGEN_ENABLED")
        PlayerLoginHandler:RegisterEvent("ADDON_LOADED")
    end
end

function PlayerLoginHandler:PLAYER_ENTERING_WORLD()
    if modern then
        self.enteredWorld = true
        WoWHACv5:RefreshProviders()
        if WoWHACv5.InitializeControls then WoWHACv5:InitializeControls() end
    else
        -- Keep the original loaded-addon scan and native fallback. A saved
        -- modern provider selection has no effect on older clients.
        local initialized = false
        for id, initialize in pairs(WoWHACv5.providers) do
            if C_AddOns.IsAddOnLoaded(id) then
                initialize()
                initialized = true
                break
            end
        end
        if not initialized then pcall(WoWHACv5.Provider) end
    end
    WoWHACv5:SendMessage("WOWHACV4_WA_PRESENTS", C_AddOns.IsAddOnLoaded("WeakAuras"))
end

function PlayerLoginHandler:PLAYER_REGEN_ENABLED()
    if self.enteredWorld then WoWHACv5:RefreshProviders() end
end

function PlayerLoginHandler:ADDON_LOADED(_, id)
    if self.enteredWorld and WoWHACv5.providers[id] then WoWHACv5:RefreshProviders() end
end
