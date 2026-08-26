local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["SimpleAssistedCombatIcon"] = function()
    WoWHACv5:Log("Supplier found: SimpleAssistedCombatIcon.")

    local provider = AssistedCombatIconFrame;
    local Keybind = provider.Keybind

    WoWHACv5:SecureHook(Keybind, "SetText", function(_, txt)
        if provider.Ability ~= nil then
            WoWHACv5:SetCurrentId(provider.spellID)
        end
        WoWHACv5:SetCurrentHotKey(txt)
    end)
end
