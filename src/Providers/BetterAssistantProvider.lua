local _, WoWHACv5 = ...

local ADDON_NAME = "BetterAssistant"
local NUM_ACTION_BUTTONS = 12
local SUGGESTION_CACHE_TTL = 0.05

local BLIZZARD_BARS = {
    { page = 3,  command = "MULTIACTIONBAR3BUTTON" },
    { page = 4,  command = "MULTIACTIONBAR4BUTTON" },
    { page = 5,  command = "MULTIACTIONBAR2BUTTON" },
    { page = 6,  command = "MULTIACTIONBAR1BUTTON" },
    { page = 13, command = "MULTIACTIONBAR5BUTTON" },
    { page = 14, command = "MULTIACTIONBAR6BUTTON" },
    { page = 15, command = "MULTIACTIONBAR7BUTTON" },
}

local KEYBIND_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "UPDATE_BINDINGS",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM",
    "ACTIONBAR_SLOT_CHANGED",
    "SPELLS_CHANGED",
    "UPDATE_MACROS",
    "PLAYER_SPECIALIZATION_CHANGED",
}

local providerInitialized = false
local betterAssistantCore
local keybindEventFrame
local slotKeys = {}
local slotKeysDirty = true

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

    local breakpointOk = pcall(addBreakpoint, formatter, {
        threshold = 0,
        step = 1,
        min = 0,
        rounding = Enum.NumericRuleFormatRounding.Down,
        format = "%d",
    })
    if not breakpointOk then
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
    local ok, text = pcall(ProbeAlpha)
    alphaProbeArg = nil

    return ok and text == true
end

local function IsFrameReady(frame)
    if not frame or type(frame.GetAlpha) ~= "function" then
        return false
    end

    local ok, alpha = pcall(frame.GetAlpha, frame)
    return ok and IsAlphaReady(alpha)
end

local function GetUnmodifiedKey(hotkey)
    if type(hotkey) ~= "string" or hotkey == "" then
        return nil
    end

    local key = hotkey:upper()
    local patterns = {
        "^ALT%-?", "^A%-?",
        "^CTRL%-?", "^C%-?",
        "^SHIFT%-?", "^S%-?",
    }

    while #key > 1 do
        local matched = false
        for _, pattern in ipairs(patterns) do
            local count
            key, count = key:gsub(pattern, "", 1)
            if count > 0 then
                if key == "" then
                    key = "-"
                end
                matched = true
                break
            end
        end
        if not matched then
            break
        end
    end

    return key
end

local function IsHotkeyEncodable(hotkey)
    local key = GetUnmodifiedKey(hotkey)
    if not key then
        return false
    end
    if #key == 1 then
        return true
    end

    local functionKey = tonumber(key:match("^F(%d+)$"))
    return functionKey ~= nil and functionKey >= 1 and functionKey <= 12
end

local function AddSlotKeys(slot, ...)
    for index = 1, select("#", ...) do
        local hotkey = select(index, ...)
        if IsHotkeyEncodable(hotkey) then
            local keys = slotKeys[slot]
            if not keys then
                keys = {}
                slotKeys[slot] = keys
            end

            local duplicate = false
            for keyIndex = 1, #keys do
                if keys[keyIndex] == hotkey then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                keys[#keys + 1] = hotkey
            end
        end
    end
end

local function AddCommandKeys(slot, command)
    if command and command ~= "" then
        AddSlotKeys(slot, GetBindingKey(command))
    end
end

local function GetMainBarPage()
    if HasVehicleActionBar and HasVehicleActionBar() and GetVehicleBarIndex then
        return GetVehicleBarIndex()
    end
    if HasOverrideActionBar and HasOverrideActionBar() and GetOverrideBarIndex then
        return GetOverrideBarIndex()
    end
    if HasTempShapeshiftActionBar and HasTempShapeshiftActionBar()
        and GetTempShapeshiftBarIndex then
        return GetTempShapeshiftBarIndex()
    end

    local bonusOffset = GetBonusBarOffset and GetBonusBarOffset() or 0
    if bonusOffset > 0 then
        return 6 + bonusOffset
    end
    return GetActionBarPage and GetActionBarPage() or 1
end

local function AddActionBarButton(button)
    if not button then
        return
    end

    local action = button._state_action or button.action
    if type(action) ~= "number" or action <= 0 then
        return
    end

    AddCommandKeys(action, button.keyBoundTarget)
    AddCommandKeys(action, button.config and button.config.keyBoundTarget)

    local name = button.GetName and button:GetName()
    if name then
        AddCommandKeys(action, "CLICK " .. name .. ":LeftButton")
        AddCommandKeys(action, "CLICK " .. name .. ":Keybind")
        AddCommandKeys(action, "CLICK " .. name .. ":HOTKEY")
    end
end

local function ScanAddonBars()
    for bar = 1, 15 do
        for button = 1, NUM_ACTION_BUTTONS do
            AddActionBarButton(_G["ElvUI_Bar" .. bar .. "Button" .. button])
        end
    end

    for index = 1, 180 do
        AddActionBarButton(_G["BT4Button" .. index])
        AddActionBarButton(_G["DominosActionButton" .. index])
    end
end

local function RebuildSlotKeys()
    slotKeys = {}

    for _, bar in ipairs(BLIZZARD_BARS) do
        local firstSlot = (bar.page - 1) * NUM_ACTION_BUTTONS
        for button = 1, NUM_ACTION_BUTTONS do
            AddCommandKeys(firstSlot + button, bar.command .. button)
        end
    end

    local firstMainSlot = (GetMainBarPage() - 1) * NUM_ACTION_BUTTONS
    for button = 1, NUM_ACTION_BUTTONS do
        local command = "ACTIONBUTTON" .. button
        AddCommandKeys(firstMainSlot + button, command)
    end

    ScanAddonBars()
    slotKeysDirty = false
end

local function IsAssistedCombatSlot(slot)
    return C_ActionBar
        and C_ActionBar.IsAssistedCombatAction
        and C_ActionBar.IsAssistedCombatAction(slot)
end

local function GetActionSpell(slot)
    if not HasAction(slot) then
        return nil
    end

    local actionType, id, subType = GetActionInfo(slot)
    if actionType == "spell" and type(id) == "number" then
        return id
    end
    if actionType == "macro" then
        if subType == "spell" and type(id) == "number" then
            return id
        end
        return GetMacroSpell and GetMacroSpell(id) or nil
    end
    if actionType == "item" and GetItemSpell then
        local _, castSpellID = GetItemSpell(id)
        return castSpellID
    end
end

local function SpellIdsMatch(left, right)
    if left == right then
        return true
    end

    if C_Spell and C_Spell.GetOverrideSpell then
        if C_Spell.GetOverrideSpell(left) == right
            or C_Spell.GetOverrideSpell(right) == left then
            return true
        end
    end

    if FindBaseSpellByID then
        return FindBaseSpellByID(left) == right
            or FindBaseSpellByID(right) == left
    end
    return false
end

local function SlotMatchesSpell(slot, spellID)
    if IsAssistedCombatSlot(slot) then
        return false
    end

    local actionSpellID = GetActionSpell(slot)
    return actionSpellID and SpellIdsMatch(actionSpellID, spellID) or false
end

local function GetSlotHotkey(slot)
    local keys = slotKeys[slot]
    return keys and keys[1] or nil
end

local function FindRawHotkey(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then
        return nil
    end
    if slotKeysDirty then
        RebuildSlotKeys()
    end

    local visited = {}
    if C_ActionBar and C_ActionBar.FindSpellActionButtons then
        local baseSpellID = FindBaseSpellByID and FindBaseSpellByID(spellID) or spellID
        local slots = C_ActionBar.FindSpellActionButtons(baseSpellID or spellID)
        for _, slot in ipairs(slots or {}) do
            visited[slot] = true
            if not IsAssistedCombatSlot(slot) then
                local hotkey = GetSlotHotkey(slot)
                if hotkey then
                    return hotkey
                end
            end
        end
    end

    local remainingSlots = {}
    for slot in pairs(slotKeys) do
        if not visited[slot] then
            remainingSlots[#remainingSlots + 1] = slot
        end
    end
    table.sort(remainingSlots)

    for _, slot in ipairs(remainingSlots) do
        if SlotMatchesSpell(slot, spellID) then
            local hotkey = GetSlotHotkey(slot)
            if hotkey then
                return hotkey
            end
        end
    end
end

local function GetBoundSuggestion(spellID)
    local hotkey = FindRawHotkey(spellID)
    if not hotkey then
        return nil
    end
    return spellID, hotkey
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
    local ready, cooldownAlpha, resourceAlpha = core:GetMainIconReadiness()
    return ready
        and IsFrameReady(core)
        --and IsAlphaReady(cooldownAlpha)
        and IsAlphaReady(resourceAlpha)
end

local function GetRotationSuggestion(core)
    local ok, isReady = pcall(IsRotationReady, core)
    if not ok or not isReady then
        return nil
    end
    return GetBoundSuggestion(core.currentSpellID)
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
    local d,h = GetRotationSuggestion(core)
    return d,h
end

local function GetCurrentSuggestion()
    local now = GetTime()
    if cachedAt and now - cachedAt < SUGGESTION_CACHE_TTL then
        return cachedId, cachedHotkey
    end

    cachedAt = now
    local ok, id, hotkey = pcall(CalculateSuggestion)
    if ok and type(id) == "number" and IsHotkeyEncodable(hotkey) then
        cachedId = id
        cachedHotkey = hotkey
    else
        cachedId = nil
        cachedHotkey = nil
    end

    return cachedId, cachedHotkey
end

local function StartKeybindTracking()
    keybindEventFrame = CreateFrame("Frame")
    for _, event in ipairs(KEYBIND_EVENTS) do
        keybindEventFrame:RegisterEvent(event)
    end
    keybindEventFrame:SetScript("OnEvent", function()
        slotKeysDirty = true
        cachedAt = nil
    end)
end

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers[ADDON_NAME] = function()
    if providerInitialized then
        return
    end
    providerInitialized = true

    WoWHACv5:Log("Supplier found: BetterAssistant.")
    StartKeybindTracking()

    function WoWHACv5:GetCurrentHotKey()
        local _, hotkey = GetCurrentSuggestion()
        return hotkey or ""
    end

    function WoWHACv5:GetCurrentId()
        local id = GetCurrentSuggestion()
        return id
    end
end
