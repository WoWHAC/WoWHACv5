local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["AssistedCombat"] = function()
    WoWHACv5:Log("Supplier found: AssistedCombat.")

    WoWHACv5:SetSuggestionResolver(function()
        local id = C_AssistedCombat.IsAvailable() and C_AssistedCombat.GetNextCastSpell() or 0
        return id, WoWHACv5.ActionBinding.ForSpell(id)
    end)
end
