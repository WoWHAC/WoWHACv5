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

if not WoWHACv5:SupportsModernFeatures() then
    WoWHACv5.Provider = function()
        if not C_AssistedCombat then
            WoWHACv5:Log("No rotation suppliers found. A list of available suppliers can be found at https://wowhac.fun/")
        else
            WoWHACv5.providers["AssistedCombat"]()
        end
    end
    return
end

local baseGetters = {
    GetCurrentHotKey = WoWHACv5.GetCurrentHotKey,
    GetCurrentId = WoWHACv5.GetCurrentId,
    GetNextHotKey = WoWHACv5.GetNextHotKey,
    GetNextId = WoWHACv5.GetNextId,
}

function WoWHACv5:ClearProviderOutput()
    currentId, currentHotkey, nextId, nextHotkey = 0, nil, nil, nil
    hasChanges = false
    if self.pixel then
        self.pixel:SetColor(0, 0, 0)
    end
end

function WoWHACv5:ResetProviderState()
    for name, getter in pairs(baseGetters) do
        self[name] = getter
    end
    self.GetCurrentSuggestion = nil
    self:ClearProviderOutput()
end

WoWHACv5.Provider = function()
    return WoWHACv5:RefreshProviders()
end
