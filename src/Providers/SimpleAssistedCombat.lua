local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["SimpleAssistedCombatIcon"] = function()
    WoWHACv5:Log("Supplier found: SimpleAssistedCombatIcon.")

    local provider = AssistedCombatIconFrame
    WoWHACv5:SetSuggestionResolver(function()
        local id = provider and provider.Ability and provider.spellID
        return id, WoWHACv5.ActionBinding.ForSpell(id)
    end)
end
