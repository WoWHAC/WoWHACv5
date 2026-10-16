local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["ConRO"] = function(session)
    local modern = WoWHACv5:SupportsModernFeatures()
    local hooks = session or WoWHACv5
    if not ConRO or not ConROWindow or not ConROWindow.fontkey then return false end
    WoWHACv5:Log("Supplier found: ConRO.")
    if ConROWindow and ConROWindow.fontkey then
        local Keybind = ConROWindow.fontkey
        local last = Keybind:GetText()
        if modern then
            WoWHACv5:SetCurrentId(ConRO.Spell)
            WoWHACv5:SetCurrentHotKey(last)
        end
        hooks:SecureHook(Keybind, "SetText", function(_, txt)
            WoWHACv5:SetCurrentId(ConRO.Spell)
            WoWHACv5:SetCurrentHotKey(txt)
        end)
    end

    -- Следующий хоткей/ид (вторая иконка)
    if ConROWindow2 and ConROWindow2.fontkey then
        local Keybind = ConROWindow2.fontkey
        local last = Keybind:GetText()
        if modern then
            WoWHACv5:SetNextId(ConRO.SuggestedSpells and ConRO.SuggestedSpells[2] or nil)
            WoWHACv5:SetNextHotKey(last)
        end
        hooks:SecureHook(Keybind, "SetText", function(_, txt)
            WoWHACv5:SetNextId(ConRO.SuggestedSpells and ConRO.SuggestedSpells[2] or nil)
            WoWHACv5:SetNextHotKey(txt)
        end)
    end
end
