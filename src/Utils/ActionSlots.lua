local _, WoWHACv5 = ...

local ActionSlots = {}

local ACTION_SLOT_COUNT = 180
local BUTTONS_PER_BAR = 12

local FIXED_BLIZZARD_BARS = {
    { firstSlot = 25, command = "MULTIACTIONBAR3BUTTON" },
    { firstSlot = 37, command = "MULTIACTIONBAR4BUTTON" },
    { firstSlot = 49, command = "MULTIACTIONBAR2BUTTON" },
    { firstSlot = 61, command = "MULTIACTIONBAR1BUTTON" },
    { firstSlot = 145, command = "MULTIACTIONBAR5BUTTON" },
    { firstSlot = 157, command = "MULTIACTIONBAR6BUTTON" },
    { firstSlot = 169, command = "MULTIACTIONBAR7BUTTON" },
}

local INVALIDATION_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "UPDATE_BINDINGS",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM",
    "ACTIONBAR_SLOT_CHANGED",
}

local slotBindings = {}
local sortedBoundSlots = {}
local dirty = true

local function FirstSupported(...)
    for index = 1, select("#", ...) do
        local rawBinding = select(index, ...)
        if WoWHACv5.Binding.IsSupported(rawBinding) then
            return rawBinding
        end
    end
end

local function GetCommandBinding(command)
    if type(command) ~= "string" or command == "" or type(GetBindingKey) ~= "function" then
        return nil
    end
    return FirstSupported(GetBindingKey(command))
end

local function AddBinding(slot, rawBinding)
    if type(slot) == "number"
        and slot > 0
        and slot <= ACTION_SLOT_COUNT
        and not slotBindings[slot]
        and WoWHACv5.Binding.IsSupported(rawBinding) then
        slotBindings[slot] = rawBinding
    end
end

local function AddCommand(slot, command)
    AddBinding(slot, GetCommandBinding(command))
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

local function AddBlizzardBars()
    local mainFirstSlot = (GetMainBarPage() - 1) * BUTTONS_PER_BAR + 1
    for button = 1, BUTTONS_PER_BAR do
        AddCommand(mainFirstSlot + button - 1, "ACTIONBUTTON" .. button)
    end

    for _, bar in ipairs(FIXED_BLIZZARD_BARS) do
        for button = 1, BUTTONS_PER_BAR do
            AddCommand(bar.firstSlot + button - 1, bar.command .. button)
        end
    end
end

function ActionSlots.GetButtonSlot(button)
    if not button then
        return nil
    end
    local slot = button._state_action or button.action
    return type(slot) == "number" and slot > 0 and slot or nil
end

local function AddButton(button)
    local slot = ActionSlots.GetButtonSlot(button)
    if not slot then
        return
    end

    AddCommand(slot, button.keyBoundTarget)
    AddCommand(slot, button.config and button.config.keyBoundTarget)

    local name = button.GetName and button:GetName()
    if name then
        AddCommand(slot, "CLICK " .. name .. ":LeftButton")
        AddCommand(slot, "CLICK " .. name .. ":Keybind")
        AddCommand(slot, "CLICK " .. name .. ":HOTKEY")
    end
end

local function AddAddonBars()
    for index = 1, ACTION_SLOT_COUNT do
        AddButton(_G["BT4Button" .. index])
        AddButton(_G["DominosActionButton" .. index])
    end

    for bar = 1, 15 do
        for button = 1, BUTTONS_PER_BAR do
            AddButton(_G["ElvUI_Bar" .. bar .. "Button" .. button])
        end
    end
end

local function Rebuild()
    slotBindings = {}
    AddBlizzardBars()
    AddAddonBars()

    sortedBoundSlots = {}
    for slot in pairs(slotBindings) do
        sortedBoundSlots[#sortedBoundSlots + 1] = slot
    end
    table.sort(sortedBoundSlots)
    dirty = false
end

local function EnsureReady()
    if dirty then
        Rebuild()
    end
end

function ActionSlots.IsAssistedCombat(slot)
    return C_ActionBar
        and C_ActionBar.IsAssistedCombatAction
        and C_ActionBar.IsAssistedCombatAction(slot) == true
end

function ActionSlots.GetBinding(slot)
    if type(slot) ~= "number" or slot <= 0 then
        return nil
    end
    EnsureReady()
    return not ActionSlots.IsAssistedCombat(slot) and slotBindings[slot] or nil
end

function ActionSlots.GetBoundSlots()
    EnsureReady()
    return sortedBoundSlots
end

function ActionSlots.Invalidate()
    dirty = true
end

if CreateFrame then
    local eventFrame = CreateFrame("Frame")
    for _, event in ipairs(INVALIDATION_EVENTS) do
        eventFrame:RegisterEvent(event)
    end
    eventFrame:SetScript("OnEvent", ActionSlots.Invalidate)
end

WoWHACv5.ActionSlots = ActionSlots
