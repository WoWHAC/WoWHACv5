local _, WoWHACv5 = ...

local ADDON_NAME = "AethysRotation"
local REQUIRED_ROTATION_METHODS = {
    "GetTexture",
    "ResetIcons",
    "Cast",
    "CastQueue",
    "CastSuggested",
}

local function NormalizeHotkey(hotkey)
    if not hotkey or hotkey == "" then
        return nil
    end
    return hotkey
end

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers[ADDON_NAME] = function(session)
    local hooks = session or WoWHACv5
    local rotation = AethysRotation
    local core = AethysCore
    if not rotation or not core or type(core.FindKeyBinding) ~= "function"
            or not C_Timer or type(C_Timer.After) ~= "function" then
        return false
    end

    for _, method in ipairs(REQUIRED_ROTATION_METHODS) do
        if type(rotation[method]) ~= "function" then
            return false
        end
    end

    if not WoWHACv5:SupportsModernFeatures() and WoWHACv5:IsHooked(rotation, "ResetIcons") then return end

    WoWHACv5:Log("Supplier found: AethysRotation.")

    local generation = 0
    local state = { offGCD = {} }

    local function ResolveAction(action)
        if not action then
            return nil
        end

        local texture = rotation.GetTexture(action)
        local hotkey = texture and core.FindKeyBinding(texture)

        return {
            -- Item recommendations still use their hotkey; zero skips spell-only validation.
            id = action.SpellID or 0,
            hotkey = NormalizeHotkey(hotkey),
        }
    end

    local function SelectRecommendation()
        local suggested = state.suggested
        if suggested and suggested.hotkey then
            return suggested
        end

        for index = 1, 2 do
            local offGCD = state.offGCD[index]
            if offGCD and offGCD.hotkey then
                return offGCD
            end
        end

        return state.main
    end

    local function PublishRecommendations()
        local current = SelectRecommendation()
        WoWHACv5:SetCurrentId(current and current.id or 0)
        WoWHACv5:SetCurrentHotKey(current and current.hotkey or nil)

        local nextAction = current == state.main and state.next or nil
        WoWHACv5:SetNextId(nextAction and nextAction.id or nil)
        WoWHACv5:SetNextHotKey(nextAction and nextAction.hotkey or nil)
    end

    hooks:SecureHook(rotation, "ResetIcons", function()
        generation = generation + 1
        local currentGeneration = generation
        state = { offGCD = {} }

        local publish = function()
            if generation == currentGeneration then
                PublishRecommendations()
            end
        end
        if session then session:After(0, publish) else C_Timer.After(0, publish) end
    end)

    hooks:SecureHook(rotation, "Cast", function(action, offGCD)
        if offGCD then
            if #state.offGCD < 2 then
                state.offGCD[#state.offGCD + 1] = ResolveAction(action)
            end
        else
            state.main = ResolveAction(action)
            state.next = nil
        end
    end)

    hooks:SecureHook(rotation, "CastQueue", function(current, nextAction)
        state.main = ResolveAction(current)
        state.next = ResolveAction(nextAction)
    end)

    hooks:SecureHook(rotation, "CastSuggested", function(action)
        state.suggested = state.suggested or ResolveAction(action)
    end)
end
