local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["ConRO"] = function()
    WoWHACv5:Log("Supplier found: ConRO.")
    if ConROWindow and ConROWindow.fontkey then
        local Keybind = ConROWindow.fontkey
        local last = Keybind:GetText()
        WoWHACv5:SecureHook(Keybind, "SetText", function(_, txt)
            if txt ~= last then
                last = txt
                WoWHACv5:SetCurrentId(ConRO.Spell)
                WoWHACv5:SetCurrentHotKey(txt)
            end
        end)
    end

    -- Следующий хоткей/ид (вторая иконка)
    if ConROWindow2 and ConROWindow2.fontkey then
        local Keybind = ConROWindow2.fontkey
        local last = Keybind:GetText()
        WoWHACv5:SecureHook(Keybind, "SetText", function(_, txt)
            if txt ~= last then
                last = txt
                WoWHACv5:SetNextId(ConRO.SuggestedSpells and ConRO.SuggestedSpells[2] or nil)
                WoWHACv5:SetNextHotKey(txt)
            end
        end)
    end
end
