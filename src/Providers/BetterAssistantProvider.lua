local _, WoWHACv5 = ...

local ADDON_NAME = "BetterAssistant"
local SUGGESTION_CACHE_TTL = 0.05

local providerInitialized = false
local betterAssistantCore

local alphaFormatter
local formatAlpha
local alphaFlag
local alphaProbeArg

local cachedAt
local cachedId
local cachedHotkey

local function IsBetterAssistantCore(frame)
    return frame
        and frame.dbgPctBg
        and frame.overlay
        and frame.interruptFrame
        and type(frame.defensivesFrames) == "table"
        and type(frame.defensivesSlotData) == "table"
        and type(frame.GetMainIconReadiness) == "function"
end

local function GetBetterAssistantCore()
    if betterAssistantCore then
        return betterAssistantCore
    end
    if not UIParent or type(UIParent.GetChildren) ~= "function" then
        return nil
    end

    for _, child in ipairs({ UIParent:GetChildren() }) do
        if IsBetterAssistantCore(child) then
            betterAssistantCore = child
            return child
        end
    end
end

local function ProbeAlpha()
    return tonumber(formatAlpha(alphaFormatter, alphaProbeArg)) == 1
end

local function EnsureAlphaProbe()
    if alphaFlag then
        return true
    end
    if not (C_StringUtil
            and C_StringUtil.CreateNumericRuleFormatter
            and C_StringUtil.TruncateWhenZero
            and Enum
            and Enum.NumericRuleFormatRounding) then
        return false
    end

    local formatterOk, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
    if not formatterOk or not formatter then
        return false
    end

    local addBreakpoint = formatter.AddBreakpoint
    formatAlpha = formatter.FormatNumber or formatter.Format
    if type(addBreakpoint) ~= "function" or type(formatAlpha) ~= "function" then
        return false
    end
    if not pcall(addBreakpoint, formatter, {
        threshold = 0,
        step = 1,
        min = 0,
        rounding = Enum.NumericRuleFormatRounding.Down,
        format = "%d",
    }) then
        return false
    end

    local holderOk, holder = pcall(CreateFrame, "Frame")
    if not holderOk or not holder then
        return false
    end
    holder:Hide()

    local flagOk, flag = pcall(
        holder.CreateFontString,
        holder,
        nil,
        "BACKGROUND",
        "GameFontNormal"
    )
    if not flagOk or not flag then
        return false
    end
    if not flag:GetFontObject() and not flag:GetFont() then
        pcall(flag.SetFontObject, flag, GameFontNormal)
    end

    alphaFormatter = formatter
    alphaFlag = flag
    return true
end

local function IsAlphaReady(alpha)
    if not EnsureAlphaProbe() then
        return false
    end

    alphaProbeArg = alpha
    local ok, ready = pcall(ProbeAlpha)
    alphaProbeArg = nil
    return ok and ready == true
end

local function IsFrameReady(frame)
    if not frame or type(frame.GetAlpha) ~= "function" then
        return false
    end
    local ok, alpha = pcall(frame.GetAlpha, frame)
    return ok and IsAlphaReady(alpha)
end

local function GetBoundSuggestion(spellId)
    local hotkey = WoWHACv5.ActionBinding.ForSpell(spellId)
    if hotkey then
        return spellId, hotkey
    end
end

local function GetInterruptSuggestion(core)
    if not IsFrameReady(core.interruptFrame) then
        return false
    end
    local id, hotkey = GetBoundSuggestion(core.interruptSpellID)
    return true, id, hotkey
end

local function GetDefensiveSuggestion(core)
    for index, frame in ipairs(core.defensivesFrames) do
        local data = core.defensivesSlotData[index]
        if data
            and data.active
            and IsFrameReady(frame)
            and IsAlphaReady(frame.iconColorAlpha) then
            local id, hotkey = GetBoundSuggestion(data.spellID)
            return true, id, hotkey
        end
    end
    return false
end

local function IsRotationReady(core)
    local ready, _, resourceAlpha = core:GetMainIconReadiness()
    return ready
        and IsFrameReady(core)
        and IsAlphaReady(resourceAlpha)
end

local function GetRotationSuggestion(core)
    local ok, isReady = pcall(IsRotationReady, core)
    if ok and isReady then
        return GetBoundSuggestion(core.currentSpellID)
    end
end

local function CalculateSuggestion()
    local core = GetBetterAssistantCore()
    if not core then
        return nil
    end

    local matched, id, hotkey = GetInterruptSuggestion(core)
    if matched then
        return id, hotkey
    end
    matched, id, hotkey = GetDefensiveSuggestion(core)
    if matched then
        return id, hotkey
    end
    return GetRotationSuggestion(core)
end

local function GetCurrentSuggestion()
    local now = GetTime()
    if cachedAt and now - cachedAt < SUGGESTION_CACHE_TTL then
        return cachedId, cachedHotkey
    end

    cachedAt = now
    local ok, id, hotkey = pcall(CalculateSuggestion)
    if ok and type(id) == "number" and WoWHACv5.Binding.IsSupported(hotkey) then
        cachedId = id
        cachedHotkey = hotkey
    else
        cachedId = nil
        cachedHotkey = nil
    end
    return cachedId, cachedHotkey
end

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers[ADDON_NAME] = function()
    if providerInitialized then
        return
    end
    providerInitialized = true

    WoWHACv5:Log("Supplier found: BetterAssistant.")

    WoWHACv5:SetSuggestionResolver(GetCurrentSuggestion)
end
