local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["Hekili"] = function(session)
    local modern = WoWHACv5:SupportsModernFeatures()
    local hooks = session or WoWHACv5
    WoWHACv5:Log("Supplier found: Hekili.")
    pcall(WoWHACv5.ToggleHekiliFrame.Init, WoWHACv5.ToggleHekiliFrame)
    if modern then WoWHACv5.ToggleHekiliFrame:Show() end
    if session then
        session:AddCleanup(function() WoWHACv5.ToggleHekiliFrame:Hide() end)
    end

    local provider = Hekili_Primary_B1;
    if provider == nil then
        if not Hekili_D1_B1_KB or type(Hekili_GetRecommendedAbility) ~= "function" then return false end
        function WoWHACv5:GetCurrentHotKey()
            return Hekili_D1_B1_KB:GetText()
        end

        function WoWHACv5:GetCurrentId()
            return Hekili_GetRecommendedAbility(1, 1) or 0
        end
    else
        local Keybind = provider.Keybinding

        if not Keybind then return false end
        if modern then
            WoWHACv5:SetCurrentId(provider.Ability and provider.Ability.id or 0)
            WoWHACv5:SetCurrentHotKey(Keybind:GetText())
        end
        hooks:SecureHook(Keybind, "SetText", function(_, txt)
            if provider.Ability ~= nil then
                WoWHACv5:SetCurrentId(provider.Ability.id)
            end
            WoWHACv5:SetCurrentHotKey(txt)
        end)
    end
end
