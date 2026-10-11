if type(C_Spell) ~= "table" then
    C_Spell = {}
end
if type(C_Spell.GetSpellInfo) ~= "function" then
    C_Spell.GetSpellInfo = function(spellId)
        return GetSpellInfo(spellId)
    end
end
if type(C_Spell.GetSpellCooldown) ~= "function" then
    C_Spell.GetSpellCooldown = function(spellId)
        local start, duration, enabled = GetSpellCooldown(spellId)
        return {
            startTime = start or 0,
            duration = duration or 0,
            isEnabled = (enabled == 1 or enabled == true)
        }
    end
end
if type(C_Spell.IsSpellUsable) ~= "function" then
    C_Spell.IsSpellUsable = function(spellId)
        return IsUsableSpell(spellId)
    end
end
if type(C_Spell.IsSpellInRange) ~= "function" then
    C_Spell.IsSpellInRange = function(spellId, unit)
        return IsSpellInRange(spellId, unit)
    end
end
if type(C_Spell.IsSpellHarmful) ~= "function" then
    C_Spell.IsSpellHarmful = function(spellId)
        return IsHarmfulSpell(spellId)
    end
end
if type(C_Spell.CanSpellBeCastOnUnit) ~= "function" then
    C_Spell.CanSpellBeCastOnUnit = function(spellId, unit)
        return UnitIsVisible(unit)
    end
end

if type(GetUnitEmpowerStageDuration) ~= "function" then
    GetUnitEmpowerStageDuration = function()
        return 0
    end
end
