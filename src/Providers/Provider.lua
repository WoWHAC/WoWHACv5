local _, WoWHACv5 = ...

local currentId = 0
local currentHotkey
local suggestionResolver

function WoWHACv5:SetCurrentSuggestion(id, hotkey)
    if hotkey then
        WoWHACv5:Debug("Current hotkey is: " .. hotkey)
    end
    currentId = id
    currentHotkey = hotkey
end

function WoWHACv5:SetSuggestionResolver(resolver)
    suggestionResolver = type(resolver) == "function" and resolver or nil
end

function WoWHACv5:GetCurrentSuggestion()
    if suggestionResolver then
        return suggestionResolver()
    end
    return currentId, currentHotkey
end

function WoWHACv5:RegisterUntypedSuggestionProvider(name, getId)
    self.providers[name] = function()
        self:Log("Supplier found: " .. name .. ".")
        self:SetSuggestionResolver(function()
            return self.ActionBinding.ForUntypedId(getId())
        end)
    end
end

WoWHACv5.Provider = function()
    if not C_AssistedCombat then
        WoWHACv5:Log("No rotation suppliers found. A list of available suppliers can be found at https://wowhac.fun/")
    else
        WoWHACv5.providers["AssistedCombat"]()
    end
end
