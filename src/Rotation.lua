local _, WoWHACv5 = ...

local function GetItemCooldownDuration(itemId)
    local start, duration, enable = GetItemCooldown(itemId)
    if enable == 0 or start == 0 then
        return 0
    end
    return ((start + duration) - GetTime()) * 1000
end

local function GetCooldownDuration(spellId)
    local itemName = GetItemInfo(spellId)
    if itemName ~= null then
        return GetItemCooldownDuration(spellId)
    end
    local cd = C_Spell.GetSpellCooldown(spellId)
    if cd then
        return ((cd.startTime + cd.duration) - GetTime()) * 1000
    end
    return 0
end
local function IsCooldownActive(spellId, threshold)
    return GetCooldownDuration(spellId) > threshold
end

local function IsGCDActive(threshold)
    return IsCooldownActive(61304, threshold)
end

local function IsChanneling(threshold)
    local _, _, _, _, endTimeMS = UnitChannelInfo("player")
    if not endTimeMS then
        _, _, _, _, endTimeMS = UnitCastingInfo("player")
    end

    if endTimeMS then
        return (endTimeMS - GetTime() * 1000) >= threshold
    end
    return false
end

local function CanCast(spellID, unit, threshold)
    local empower = GetUnitEmpowerStageDuration("player", 3)
    if empower > 0 then
        return true
    end
    local usable = C_Spell.IsSpellUsable(spellID)
    if not usable then
        return false
    end
    --if IsGCDActive(threshold*2) then
    --    return false
    --end
    if IsCooldownActive(spellID, threshold) then
        return false, "On cooldown"
    end
    local inCombat = UnitAffectingCombat("player")
    if inCombat then
        return true
    end
    if unit and C_Spell.IsSpellHarmful(spellID) then
        local inRange = C_Spell.IsSpellInRange(spellID, unit)
        if inRange == 0 or inRange == false then
            return false
        end
        if not C_Spell.CanSpellBeCastOnUnit(spellID, unit) then
            return false
        end
    end
    return true
end

local SpellCastEventHandler = WoWHACv5:NewModule("SpellCastEventHandler", "AceEvent-3.0")

function SpellCastEventHandler:OnEnable()
    WoWHACv5:Debug("Register SpellCast handlers")
    WoWHACv5:RegisterEvent("UNIT_SPELLCAST_SENT", "OnSpellcast")
    WoWHACv5:RegisterEvent("UNIT_SPELLCAST_START", "OnSpellcast")
    WoWHACv5:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnSpellcast")
end
function WoWHACv5:OnSpellcast(event, unit, _, _, spellId)
    if unit == "player" then
        WoWHACv5.pixel:SetColor(0, 0, 0)
    end
    local next = WoWHACv5:GetNextHotKey();
    if next then
        WoWHACv5:SetCurrentHotKey(next)
        WoWHACv5:SetCurrentId(WoWHACv5:GetNextId())
    end
    --if event == "UNIT_SPELLCAST_CHANNEL_START" then
    --    local next = WoWHACv5:GetNextHotKey();
    --    if next then
    --        WoWHACv5:SetCurrentHotKey(next)
    --        WoWHACv5:SetCurrentId(WoWHACv5:GetNextId())
    --    end
    --end
end
local _, _, _, tocVersion = GetBuildInfo()
if tocVersion >= 120000 then
    function WoWHACv5:UpdatePixel()
        local curr = WoWHACv5:GetCurrentHotKey()
        if curr == nil then
            return
        end
        local rgb = WoWHACv5.Steganography(curr)
        WoWHACv5.pixel:SetColor(rgb.red, rgb.green, rgb.blue)
    end
else
    function WoWHACv5:UpdatePixel()
        local casting = UnitCastingInfo("player") ~= nil
        local currentId = WoWHACv5:GetCurrentId()
        if casting or IsChanneling(300) or (currentId ~= nil and currentId > 0 and not CanCast(currentId, "target", 300)) then
            WoWHACv5.pixel:SetColor(0, 0, 0)
        else
            local curr = WoWHACv5:GetCurrentHotKey()
            if curr == nil then
                return
            end
            local rgb = WoWHACv5.Steganography(curr)
            WoWHACv5.pixel:SetColor(rgb.red, rgb.green, rgb.blue)
        end
    end
end

WoWHACv5:ScheduleRepeatingTimer("UpdatePixel", 0.1)