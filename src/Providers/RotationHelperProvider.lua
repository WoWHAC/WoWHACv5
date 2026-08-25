local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["RotationHelper"] = function()
    WoWHACv5:Log("Supplier found: Synaptic.")

    local spellSuggestion = RotationHelper
        and RotationHelper.modules
        and RotationHelper.modules.SpellSuggestion
    if not spellSuggestion then
        return
    end

    local function GetSuggestion()
        local data = spellSuggestion.tooltipData
        if not data or type(data.id) ~= "number" then
            return nil
        end
        if data.type == "spell" then
            return data.id, WoWHACv5.ActionBinding.ForSpell(data.id)
        end
        if data.type == "item" then
            return -data.id, WoWHACv5.ActionBinding.ForItem(data.id)
        end
    end

    WoWHACv5:SetSuggestionResolver(GetSuggestion)
end
