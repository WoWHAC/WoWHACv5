local _, WoWHACv5 = ...

local currentId = 0
local currentHotkey
local nextId
local nextHotkey
local hasChanges = false

function WoWHACv5:GetCurrentHotKey()
    return currentHotkey
end

function WoWHACv5:GetCurrentId()
    return currentId
end

function WoWHACv5:SetCurrentHotKey(hotkey)
    if hotkey then
        WoWHACv5:Debug("Current hotkey is: " .. hotkey)
    end
    if currentHotkey ~= hotkey then
        hasChanges = true
    end
    currentHotkey = hotkey
end

function WoWHACv5:SetCurrentId(spellId)
    currentId = spellId
end

function WoWHACv5:GetNextHotKey()
    return nextHotkey
end

function WoWHACv5:GetNextId()
    return nextId
end

function WoWHACv5:SetNextHotKey(hotkey)
    if hotkey then
        WoWHACv5:Debug("Next hotkey is: " .. hotkey)
    end
    if nextHotkey ~= hotkey then
        hasChanges = true
    end
    nextHotkey = hotkey
end

function WoWHACv5:SetNextId(spellId)
    nextId = spellId
end

function WoWHACv5:HasChanges()
    return hasChanges
end

function WoWHACv5:NoChanges()
    hasChanges = false
end

WoWHACv5.Provider = function()
    if not C_AssistedCombat then
        WoWHACv5:Log("No rotation suppliers found. A list of available suppliers can be found at https://wowhac.fun/")
    else
        WoWHACv5.providers["AssistedCombat"]()
    end
end
