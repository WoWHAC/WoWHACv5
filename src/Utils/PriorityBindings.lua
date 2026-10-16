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
    if type(fn) ~= "function" then return nil end
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

local function MainPage()
    local vehicle = Call(ActionBarAPI("HasVehicleActionBar", HasVehicleActionBar))
    if vehicle == true then return ActionID(Call(ActionBarAPI("GetVehicleBarIndex", GetVehicleBarIndex))) end
    local override = Call(ActionBarAPI("HasOverrideActionBar", HasOverrideActionBar))
    if override == true then return ActionID(Call(ActionBarAPI("GetOverrideBarIndex", GetOverrideBarIndex))) end
    local temporary = Call(ActionBarAPI("HasTempShapeshiftActionBar", HasTempShapeshiftActionBar))
    if temporary == true then return ActionID(Call(ActionBarAPI("GetTempShapeshiftBarIndex", GetTempShapeshiftBarIndex))) end
    local page = ActionID(Call(ActionBarAPI("GetActionBarPage", GetActionBarPage))) or 1
    local bonus = Call(ActionBarAPI("GetBonusBarOffset", GetBonusBarOffset))
    if page == 1 and type(bonus) == "number" and bonus > 0 then return bonus + 6 end
    return page
end

function Bindings.Build(entries)
    -- Public configuration is read only outside combat. A binding/bar change
    -- invalidates every old layer before this snapshot can be used again.
    if InCombatLockdown and InCombatLockdown() then return nil end
    local result, configured = {}, {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and (entry.kind == "spell" or entry.kind == "item") and ActionID(entry.id) then
            local key = entry.kind .. ":" .. entry.id
            configured[key] = entry
        end
    end
    local function Remember(kind, id, hotkey, slot)
        if not kind or not id or not ValidBinding(hotkey) then return end
        for key, entry in pairs(configured) do
            local matches = entry.kind == kind and (entry.id == id
                or kind == "spell" and BaseSpell(entry.id) == BaseSpell(id))
            if matches and not result[key] then
                local rgb = addon.Protocol.EncodeBinding(hotkey)
                result[key] = { hotkey = hotkey, red = rgb.red, green = rgb.green, blue = rgb.blue, slot = slot }
            end
        end
    end
    local function Scan(slot, command, frameName)
        local key = CommandKey(command) or CommandKey("CLICK " .. frameName .. ":LeftButton")
        if not key then return end
        local kind, id = SlotAction(slot)
        Remember(kind, id, key, slot)
    end
    local mainPage = MainPage()
    if mainPage then
        for button = 1, 12 do
            local frame = _G["ActionButton" .. button]
            local slot = frame and ActionID(Call(frame.CalculateAction, frame)) or (mainPage - 1) * 12 + button
            Scan(slot, "ACTIONBUTTON" .. button, "ActionButton" .. button)
        end
    end
    for _, bar in ipairs(BARS) do
        for button = 1, 12 do Scan(bar.first + button - 1, bar.command .. button, bar.frame .. button) end
    end
    for key, entry in pairs(configured) do
        if not result[key] then
            local name = addon:GetPriorityActionInfo(entry.kind, entry.id)
            if name then Remember(entry.kind, entry.id, CommandKey(entry.kind:upper() .. " " .. name)) end
        end
    end
    return result
end
