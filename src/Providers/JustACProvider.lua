local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providerOrder = WoWHACv5.providerOrder or {}

table.insert(WoWHACv5.providerOrder, 1, "JustAC")

WoWHACv5.providers["JustAC"] = function()
    WoWHACv5:Log("Supplier found: JustAC.")

    local JustACAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)

    if not JustACAddon or not JustACAddon.spellIcons then return end
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)

    local intIcon = JustACAddon.interruptIcon

    function WoWHACv5:GetCurrentHotKey()
        local spellId = WoWHACv5:GetCurrentId()
        return spellId and ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(spellId) or ""
    end

    function WoWHACv5:GetCurrentId()
        if intIcon and intIcon:IsShown() and intIcon.spellID and math.random() < 0.41 then
            return intIcon.spellID
        end
        return SpellQueue.GetCurrentSpellQueue()[1]
    end
end
