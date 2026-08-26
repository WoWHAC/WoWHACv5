local _, WoWHACv5 = ...

local PlayerLoginHandler = WoWHACv5:NewModule("PlayerLoginHandler", "AceEvent-3.0")

function PlayerLoginHandler:OnEnable()
    WoWHACv5:Debug("Register WeakAuras handlers")
    PlayerLoginHandler:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function PlayerLoginHandler:PLAYER_ENTERING_WORLD()
    local initialized = false
    for key, value in pairs(WoWHACv5.providers) do
        if C_AddOns.IsAddOnLoaded(key) then
            value()
            initialized = true;
            break
        end
    end
    if initialized == false then
        pcall(WoWHACv5.Provider)
    end
    WoWHACv5:SendMessage("WOWHACV4_WA_PRESENTS", C_AddOns.IsAddOnLoaded("WeakAuras"))
end
