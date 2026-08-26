local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["Hekili"] = function()
    WoWHACv5:Log("Supplier found: Hekili.")
    pcall(WoWHACv5.ToggleHekiliFrame.Init, WoWHACv5.ToggleHekiliFrame)

    local provider = Hekili_Primary_B1;
    if provider == nil then
        function WoWHACv5:GetCurrentHotKey()
            return Hekili_D1_B1_KB:GetText()
        end

        function WoWHACv5:GetCurrentId()
            return Hekili_GetRecommendedAbility(1, 1) or 0
        end
    else
        local Keybind = provider.Keybinding

        WoWHACv5:SecureHook(Keybind, "SetText", function(_, txt)
            if provider.Ability ~= nil then
                WoWHACv5:SetCurrentId(provider.Ability.id)
            end
            WoWHACv5:SetCurrentHotKey(txt)
        end)
    end
end
