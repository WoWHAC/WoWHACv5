local _, WoWHACv5 = ...
WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["MaxDps"] = function()
    WoWHACv5:Log("Supplier found: MaxDps.")
    if not WeakAuras then
        MaxDps.db.global.onCombatEnter = false
        MaxDps.db.global.spellFrame.enabled = true
        MaxDps.db.global.enabled = true
        MaxDpsSpellFrame:Show()

        local provider = MaxDpsSpellFrame
        local Keybind = provider.bindText

        WoWHACv5:SecureHook(MaxDps, "UpdateSpellFrame", function(_, spellID)
            WoWHACv5:SetCurrentId(spellID)
            WoWHACv5:SetCurrentHotKey(spellID and spellID > 0 and Keybind:GetText() or nil)
        end)
    else
--         Это нужно сохранить, это поддержка legacy версий игры
        WoWHACv5:RegisterMessage("WOWHACV4_WA_PRESENTS", function(_, _, isLoaded)
            if isLoaded then
                WoWHACv5.ToggleBurstFrame:Show()
                WoWHACv5:SecureHook(WeakAuras, "ScanEvents", function(event, _)
                    if event == "MAXDPS_COOLDOWN_UPDATE" then
                        for _, frame in pairs(MaxDps.Frames) do
                            if frame and frame:IsVisible() then
                                if WoWHACv5.burst or frame.ovType ~= "cooldown" then
                                    local button = frame:GetParent()
                                    WoWHACv5:SetCurrentHotKey(button.HotKey:GetText())
                                    return
                                end
                            end
                        end
                        return
                    end
                end)
            else
                WoWHACv5:Log("To use the MaxDps as rotation provider, you need to install WeakAuras.")
            end
        end)
    end
end
