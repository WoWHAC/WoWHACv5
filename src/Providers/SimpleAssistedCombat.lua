local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["SimpleAssistedCombatIcon"] = function(session)
    local modern = WoWHACv5:SupportsModernFeatures()
    local hooks = session or WoWHACv5
    WoWHACv5:Log("Supplier found: SimpleAssistedCombatIcon.")

    local provider = AssistedCombatIconFrame;
    if not provider or not provider.Keybind then return false end
    local Keybind = provider.Keybind
    if modern then
        WoWHACv5:SetCurrentId(provider.spellID or 0)
        WoWHACv5:SetCurrentHotKey(Keybind:GetText())
    end

    hooks:SecureHook(Keybind, "SetText", function(_, txt)
        WoWHACv5:SetCurrentId(provider.spellID or 0)
        WoWHACv5:SetCurrentHotKey(txt)
    end)
end
