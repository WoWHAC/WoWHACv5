local _, addon = ...
if not addon:SupportsModernFeatures() then return end
local Bindings = {}
addon.PriorityBindings = Bindings

local Public = addon.IsPriorityValuePublic
local ActionID = addon.PriorityActionID
local BARS = {
    { first = 25, command = "MULTIACTIONBAR3BUTTON", frame = "MultiBarRightButton" },
    { first = 37, command = "MULTIACTIONBAR4BUTTON", frame = "MultiBarLeftButton" },
    { first = 49, command = "MULTIACTIONBAR2BUTTON", frame = "MultiBarBottomRightButton" },
    { first = 61, command = "MULTIACTIONBAR1BUTTON", frame = "MultiBarBottomLeftButton" },
    { first = 145, command = "MULTIACTIONBAR5BUTTON", frame = "MultiBar5Button" },
    { first = 157, command = "MULTIACTIONBAR6BUTTON", frame = "MultiBar6Button" },
    { first = 169, command = "MULTIACTIONBAR7BUTTON", frame = "MultiBar7Button" },
}

local function Call(fn, ...)
    if not Public(fn) or type(fn) ~= "function" then return nil end
    local ok, first, second = pcall(fn, ...)
    if ok and Public(first) and Public(second) then return first, second end
end

local function ValidBinding(key)
    return Public(key) and type(key) == "string" and key ~= ""
        and addon.Binding.Parse(key) ~= 0
end

local function CommandKey(command)
    local first, second = Call(GetBindingKey, command)
    if ValidBinding(first) then return first end
    if ValidBinding(second) then return second end
end

local function BaseSpell(id)
    local base = C_Spell and Call(C_Spell.GetBaseSpell, id)
    return ActionID(base) or id
end

local function MacroAction(id)
    local spell = ActionID(Call(GetMacroSpell, id))
    if spell then return "spell", spell end
    local name, link = Call(GetMacroItem, id)
    if type(link) == "string" then
        local item = ActionID(link:match("item:(%d+)"))
        if item then return "item", item end
    end
    if type(name) == "string" then
        local getter = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        local item = ActionID(Call(getter, name))
        if item then return "item", item end
    end
end

local function SlotAction(slot)
    local kind, id = Call(GetActionInfo, slot)
    id = ActionID(id)
    if not id then return nil end
    if kind == "macro" then return MacroAction(id) end
    if kind == "spell" or kind == "item" then return kind, id end
end

local function ActionBarAPI(name, legacy)
    return C_ActionBar and C_ActionBar[name] or legacy
end

local function MainPage(strict)
    local vehicleAPI = ActionBarAPI("HasVehicleActionBar", HasVehicleActionBar)
    local vehicle = Call(vehicleAPI)
    if strict and (not Public(vehicleAPI) or vehicleAPI ~= nil and type(vehicle) ~= "boolean") then return nil end
    if vehicle == true then return ActionID(Call(ActionBarAPI("GetVehicleBarIndex", GetVehicleBarIndex))) end
    local overrideAPI = ActionBarAPI("HasOverrideActionBar", HasOverrideActionBar)
    local override = Call(overrideAPI)
    if strict and (not Public(overrideAPI) or overrideAPI ~= nil and type(override) ~= "boolean") then return nil end
    if override == true then return ActionID(Call(ActionBarAPI("GetOverrideBarIndex", GetOverrideBarIndex))) end
    local temporaryAPI = ActionBarAPI("HasTempShapeshiftActionBar", HasTempShapeshiftActionBar)
    local temporary = Call(temporaryAPI)
    if strict and (not Public(temporaryAPI) or temporaryAPI ~= nil and type(temporary) ~= "boolean") then return nil end
    if temporary == true then return ActionID(Call(ActionBarAPI("GetTempShapeshiftBarIndex", GetTempShapeshiftBarIndex))) end
    local page = ActionID(Call(ActionBarAPI("GetActionBarPage", GetActionBarPage)))
    if strict and not page then return nil end
    page = page or 1
    local bonusAPI = ActionBarAPI("GetBonusBarOffset", GetBonusBarOffset)
    local bonus = Call(bonusAPI)
    if strict and (not Public(bonusAPI) or bonusAPI ~= nil and (type(bonus) ~= "number" or bonus < 0
        or bonus == math.huge or bonus ~= math.floor(bonus))) then return nil end
    if page == 1 and type(bonus) == "number" and bonus > 0 then return bonus + 6 end
    return page
end

local function VisitSlots(visit)
    local mainPage = MainPage()
    if mainPage then
        for button = 1, 12 do
            local frame = _G["ActionButton" .. button]
            local slot = frame and ActionID(Call(frame.CalculateAction, frame)) or (mainPage - 1) * 12 + button
            visit(slot, "ACTIONBUTTON" .. button, "ActionButton" .. button, button, mainPage)
        end
    end
    for _, bar in ipairs(BARS) do
        for button = 1, 12 do visit(bar.first + button - 1, bar.command .. button, bar.frame .. button) end
    end
end

local displayBindings

local function DisplayKey(hotkey)
    if not ValidBinding(hotkey) then return nil end
    local action, modifiers = addon.Binding.Parse(hotkey)
    return action .. ":" .. modifiers
end

local function DisplayIcon(kind, id, slot)
    local icon = Call(ActionBarAPI("GetActionTexture", GetActionTexture), slot)
    if not icon then
        local _, actionIcon = Call(addon.GetPriorityActionInfo, addon, kind, id)
        icon = actionIcon
    end
    if Public(icon) and (type(icon) == "number" and icon > 0 or type(icon) == "string" and icon ~= "") then
        return icon
    end
end

function Bindings.InvalidateDisplayBindings()
    displayBindings = nil
end

function Bindings.RefreshDisplayBindings()
    -- Only public action-bar configuration is cached, never a recommendation or
    -- a protected result. Changes in combat leave the snapshot unavailable.
    displayBindings = nil
    if InCombatLockdown and InCombatLockdown() then return false end
    local result = {}
    VisitSlots(function(slot, command, frameName)
        local kind, id = SlotAction(slot)
        if not kind or not id then return end
        local entry = { kind = kind, id = id, icon = DisplayIcon(kind, id, slot) }
        local function Remember(hotkey)
            local key = DisplayKey(hotkey)
            if key and not result[key] then result[key] = entry end
        end
        local first, second = Call(GetBindingKey, command)
        Remember(first)
        Remember(second)
        first, second = Call(GetBindingKey, "CLICK " .. frameName .. ":LeftButton")
        Remember(first)
        Remember(second)
    end)
    displayBindings = result
    return true
end

function Bindings.GetActionForHotkey(hotkey)
    if not displayBindings then return nil end
    local key = DisplayKey(hotkey)
    return key and displayBindings[key] or nil
end

function Bindings.IsCurrent(entry, binding)
    -- Revalidate only this public mapping. An unrelated slot/spell event must
    -- not suspend every preallocated priority action until combat ends.
    if not Public(entry) or type(entry) ~= "table" or not Public(binding) or type(binding) ~= "table" then return false end
    local kind, id = entry.kind, ActionID(entry.id)
    if not Public(kind) or (kind ~= "spell" and kind ~= "item") or not id then return false end
    local command, hotkey = binding.command, binding.hotkey
    if not Public(command) or type(command) ~= "string" or command == "" or not ValidBinding(hotkey) then return false end
    local first, second = Call(GetBindingKey, command)
    if first ~= hotkey and second ~= hotkey then return false end
    -- Base bindings remain registered while a secure override redirects a key.
    -- Only the exact captured command may keep this layer eligible.
    if Call(GetBindingAction, hotkey, true) ~= command then return false end

    local rawSlot = binding.slot
    if not Public(rawSlot) then return false end
    if rawSlot == nil then
        local name = Call(addon.GetPriorityActionInfo, addon, kind, id)
        return type(name) == "string" and name ~= "" and command == kind:upper() .. " " .. name
    end
    local slot = ActionID(rawSlot)
    if not slot then return false end
    local mainButton = binding.mainButton
    if not Public(mainButton) then return false end
    if mainButton ~= nil then
        mainButton = ActionID(mainButton)
        local savedPage = ActionID(binding.mainPage)
        local frameName = binding.frameName
        if not mainButton or mainButton > 12 or not savedPage or not Public(frameName)
            or type(frameName) ~= "string" or frameName == "" then return false end
        local page = MainPage(true)
        if not page or page ~= savedPage then return false end
        local frame = _G[frameName]
        if not Public(frame) then return false end
        local currentSlot = (page - 1) * 12 + mainButton
        if frame ~= nil then
            if type(frame) ~= "table" and type(frame) ~= "userdata" then return false end
            local calculate = frame.CalculateAction
            if not Public(calculate) then return false end
            if calculate ~= nil then
                currentSlot = ActionID(Call(calculate, frame))
                if not currentSlot then return false end
            end
        end
        if currentSlot ~= slot then return false end
    end
    local currentKind, currentID = SlotAction(slot)
    return currentKind == kind and currentID ~= nil and (currentID == id
        or kind == "spell" and BaseSpell(currentID) == BaseSpell(id))
end

function Bindings.Build(entries)
    -- Full scans and layer allocation remain outside combat. IsCurrent may
    -- revalidate a captured public mapping without rebuilding any UI.
    if InCombatLockdown and InCombatLockdown() then return nil end
    local result, configured = {}, {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and (entry.kind == "spell" or entry.kind == "item") and ActionID(entry.id) then
            local key = entry.kind .. ":" .. entry.id
            configured[key] = entry
        end
    end
    local function Remember(kind, id, hotkey, slot, command, frameName, mainButton, mainPage)
        if not kind or not id or not ValidBinding(hotkey) then return end
        for key, entry in pairs(configured) do
            local matches = entry.kind == kind and (entry.id == id
                or kind == "spell" and BaseSpell(entry.id) == BaseSpell(id))
            if matches and not result[key] then
                local rgb = addon.Protocol.EncodeBinding(hotkey)
                result[key] = {
                    hotkey = hotkey, red = rgb.red, green = rgb.green, blue = rgb.blue, slot = slot,
                    command = command, frameName = frameName, mainButton = mainButton, mainPage = mainPage,
                }
            end
        end
    end
    local function Scan(slot, command, frameName, mainButton, mainPage)
        local key = CommandKey(command)
        if not key then
            command = "CLICK " .. frameName .. ":LeftButton"
            key = CommandKey(command)
        end
        if not key then return end
        local kind, id = SlotAction(slot)
        Remember(kind, id, key, slot, command, frameName, mainButton, mainPage)
    end
    VisitSlots(Scan)
    for key, entry in pairs(configured) do
        if not result[key] then
            local name = Call(addon.GetPriorityActionInfo, addon, entry.kind, entry.id)
            if type(name) == "string" and name ~= "" then
                local command = entry.kind:upper() .. " " .. name
                Remember(entry.kind, entry.id, CommandKey(command), nil, command)
            end
        end
    end
    return result
end
