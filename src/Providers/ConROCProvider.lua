local _, WoWHACv5 = ...

WoWHACv5:RegisterUntypedSuggestionProvider("ConROC", function()
    return ConROC and ConROC.Spell
end)
