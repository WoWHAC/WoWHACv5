local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["RotationHelper"] = function()
    WoWHACv5:Log("Supplier found: Synaptic.")

    local RH = RotationHelper
    local SpellSuggestion = RH and RH.modules and RH.modules.SpellSuggestion
    if not SpellSuggestion then
        return
    end

    local function GetSynapticHotKey()
        local keybindLabel = SpellSuggestion.keybindLabel
        local key = keybindLabel and keybindLabel:GetText()
        return key or ""
    end

    local function GetSynapticId()
        local tooltipData = SpellSuggestion.tooltipData
        if tooltipData then
            return tooltipData.type == "spell" and tooltipData.id or nil
        end
    end

    function WoWHACv5:GetCurrentHotKey()
        return GetSynapticHotKey()
    end

    function WoWHACv5:GetCurrentId()
        return GetSynapticId()
    end
end
