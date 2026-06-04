local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["Hekili"] = function()
    WoWHACv5:Log("Supplier found: Hekili.")
    pcall(WoWHACv5.ToggleHekiliFrame.Init, WoWHACv5.ToggleHekiliFrame)

    local provider = Hekili_Primary_B1;
    local Keybind = provider.Keybinding

    WoWHACv5:SecureHook(Keybind, "SetText", function(_, txt)
        if provider.Ability ~= nil then
            WoWHACv5:SetCurrentId(provider.Ability.id)
        end
        WoWHACv5:SetCurrentHotKey(txt)
    end)
end
