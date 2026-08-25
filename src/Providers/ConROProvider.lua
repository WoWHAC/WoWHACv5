local _, WoWHACv5 = ...

WoWHACv5:RegisterUntypedSuggestionProvider("ConRO", function()
    return ConRO and ConRO.Spell
end)
