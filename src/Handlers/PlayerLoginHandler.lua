local _, WoWHACv5 = ...

local PlayerLoginHandler = WoWHACv5:NewModule("PlayerLoginHandler", "AceEvent-3.0")
local providerInitialized = false

local function TryInitialize(initializer, name)
    local ok, errorMessage = pcall(initializer)
    if not ok then
        WoWHACv5:Log("Could not initialize supplier " .. name .. ": " .. tostring(errorMessage))
    end
    return ok
end

local function InitializeProvider()
    for name, initializer in pairs(WoWHACv5.providers) do
        if C_AddOns.IsAddOnLoaded(name) then
            return TryInitialize(initializer, name)
        end
    end
    return TryInitialize(WoWHACv5.Provider, "AssistedCombat")
end

function PlayerLoginHandler:OnEnable()
    WoWHACv5:Debug("Register provider initialization handler")
    PlayerLoginHandler:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function PlayerLoginHandler:PLAYER_ENTERING_WORLD()
    if providerInitialized or not InitializeProvider() then
        return
    end

    providerInitialized = true
    PlayerLoginHandler:UnregisterEvent("PLAYER_ENTERING_WORLD")
    WoWHACv5:SendMessage("WOWHACV4_WA_PRESENTS", C_AddOns.IsAddOnLoaded("WeakAuras"))
end
