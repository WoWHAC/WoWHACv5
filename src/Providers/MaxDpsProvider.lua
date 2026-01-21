local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["MaxDps"] = function()
    WoWHACv5:Log("Supplier found: MaxDps.")
    if not WeakAuras then
        function WoWHACv5:GetCurrentHotKey()
            for _, frame in pairs(MaxDps.Frames) do
                if frame and frame:IsVisible() then
                    if WoWHACv5.burst or frame.ovType ~= "cooldown" then
                        local button = frame:GetParent()
                        return button.HotKey:GetText()
                    end
                end
            end
        end

        function WoWHACv5:GetCurrentId()
            return MaxDps.Spell
        end
    else
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
