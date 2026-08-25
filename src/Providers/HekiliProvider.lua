local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["Hekili"] = function()
    WoWHACv5:Log("Supplier found: Hekili.")
    pcall(WoWHACv5.ToggleHekiliFrame.Init, WoWHACv5.ToggleHekiliFrame)

    local provider = Hekili_Primary_B1
    local function GetSuggestion()
        local id
        if provider then
            id = provider.Ability and provider.Ability.id
        else
            id = Hekili_GetRecommendedAbility(1, 1)
        end
        return WoWHACv5.ActionBinding.ForUntypedId(id)
    end

    WoWHACv5:SetSuggestionResolver(GetSuggestion)
end
