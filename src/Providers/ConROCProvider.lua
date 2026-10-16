local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["ConROC"] = function(session)
    local modern = WoWHACv5:SupportsModernFeatures()
    local hooks = session or WoWHACv5
    if not ConROC or not ConROCWindow or not ConROCWindow.fontkey then return false end
    WoWHACv5:Log("Supplier found: ConROC.")
    if ConROCWindow and ConROCWindow.fontkey then
        local Keybind = ConROCWindow.fontkey
        local last = Keybind:GetText()
        if modern then
            WoWHACv5:SetCurrentId(ConROC.Spell)
            WoWHACv5:SetCurrentHotKey(last)
        end
        hooks:SecureHook(Keybind, "SetText", function(_, txt)
            WoWHACv5:SetCurrentId(ConROC.Spell)
            WoWHACv5:SetCurrentHotKey(txt)
        end)
    end

    -- Следующий хоткей/ид (вторая иконка)
    if ConROCWindow2 and ConROCWindow2.fontkey then
        local Keybind = ConROCWindow2.fontkey
        local last = Keybind:GetText()
        if modern then
            WoWHACv5:SetNextId(ConROC.SuggestedSpells and ConROC.SuggestedSpells[2] or nil)
            WoWHACv5:SetNextHotKey(last)
        end
        hooks:SecureHook(Keybind, "SetText", function(_, txt)
            WoWHACv5:SetNextId(ConROC.SuggestedSpells and ConROC.SuggestedSpells[2] or nil)
            WoWHACv5:SetNextHotKey(txt)
        end)
    end
end
