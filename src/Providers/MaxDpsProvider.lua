local _, WoWHACv5 = ...
WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["MaxDps"] = function()
    WoWHACv5:Log("Supplier found: MaxDps.")
    if not WeakAuras then
        MaxDps.db.global.onCombatEnter = false
        MaxDps.db.global.spellFrame.enabled = true
        MaxDps.db.global.enabled = true
        MaxDpsSpellFrame:Show()

        local currentSpellId
        WoWHACv5:SecureHook(MaxDps, "UpdateSpellFrame", function(_, spellID)
            currentSpellId = spellID
        end)

        WoWHACv5:SetSuggestionResolver(function()
            return currentSpellId, WoWHACv5.ActionBinding.ForSpell(currentSpellId)
        end)
    else
        -- Это нужно сохранить: здесь поддерживаются legacy-версии игры.
        WoWHACv5:RegisterMessage("WOWHACV4_WA_PRESENTS", function(_, _, isLoaded)
            if isLoaded then
                local currentButton
                WoWHACv5.ToggleBurstFrame:Show()
                WoWHACv5:SecureHook(WeakAuras, "ScanEvents", function(event, _)
                    if event == "MAXDPS_COOLDOWN_UPDATE" then
                        currentButton = nil
                        for _, frame in pairs(MaxDps.Frames) do
                            if frame and frame:IsVisible() then
                                if WoWHACv5.burst or frame.ovType ~= "cooldown" then
                                    local button = frame:GetParent()
                                    if WoWHACv5.ActionBinding.ForButton(button) then
                                        currentButton = button
                                        return
                                    end
                                end
                            end
                        end
                        return
                    end
                end)

                WoWHACv5:SetSuggestionResolver(function()
                    return nil, WoWHACv5.ActionBinding.ForButton(currentButton)
                end)
            else
                WoWHACv5:Log("To use the MaxDps as rotation provider, you need to install WeakAuras.")
            end
        end)
    end
end
