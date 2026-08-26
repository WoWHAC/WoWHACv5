local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["AssistedCombat"] = function()
    WoWHACv5:Log("Supplier found: AssistedCombat.")

    local BarAddonLoaded = false
    local AddonLookupActionBySlot = {}
    local AddonLookupButtonByAction = {}
    local LookupActionBySlot = {}
    local LookupButtonByAction = {}

    local DefaultActionSlotMap = {
        --Default UI Slot mapping https://warcraft.wiki.gg/wiki/Action_slot
        { actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 1, last = 12 }, --Action Bar 1 (Main Bar)
        { actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 13, last = 24 }, --Action Bar 1 (Page 2)
        { actionPrefix = "MULTIACTIONBAR3BUTTON", buttonPrefix = "MultiBarRightButton", start = 25, last = 36 }, --Action Bar 4 (Right)
        { actionPrefix = "MULTIACTIONBAR4BUTTON", buttonPrefix = "MultiBarLeftButton", start = 37, last = 48 }, --Action Bar 5 (Left)
        { actionPrefix = "MULTIACTIONBAR2BUTTON", buttonPrefix = "MultiBarBottomRightButton", start = 49, last = 60 }, --Action Bar 3 (Bottom Right)
        { actionPrefix = "MULTIACTIONBAR1BUTTON", buttonPrefix = "MultiBarBottomLeftButton", start = 61, last = 72 }, --Action Bar 2 (Bottom Left)
        { actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 73, last = 84 }, --Class Bar 1
        { actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 85, last = 96 }, --Class Bar 2
        { actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 97, last = 108 }, --Class Bar 3
        { actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 109, last = 120 }, --Class Bar 4
        { actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 121, last = 132 }, --Action Bar 1 (Skyriding)
        --{ actionPrefix = "UNKNOWN",               buttonPrefix ="",                         start = 133,last = 144},--Unknown
        { actionPrefix = "MULTIACTIONBAR5BUTTON", buttonPrefix = "MultiBar5Button", start = 145, last = 156 }, --Action Bar 6
        { actionPrefix = "MULTIACTIONBAR6BUTTON", buttonPrefix = "MultiBar6Button", start = 157, last = 168 }, --Action Bar 7
        { actionPrefix = "MULTIACTIONBAR7BUTTON", buttonPrefix = "MultiBar7Button", start = 169, last = 180 }, --Action Bar 8
    }

    local bindingOverrides = {
        ["Mouse Button "] = "MB",
        ["Num Pad "] = "NP",
        ["Middle Mouse"] = "MMB",
        ["Mouse Wheel Up"] = "MWU",
        ["Mouse Wheel Down"] = "MWD",
        ["Capslock"] = "Caps",
        ["Backspace"] = "BkSp",
        ["Spacebar"] = "Spbar",
        ["Delete"] = "Del",
        ["Page Up"] = "PgUp",
        ["Page Down"] = "PgDn",
        ["Insert"] = "Ins",
        ["Num Lock"] = "NmLk",
        ["Left Arrow"] = "Left",
        ["Right Arrow"] = "Right",
        ["Up Arrow"] = "Up",
        ["Down Arrow"] = "Down",
    }

    local function IsRelevantAction(actionType, subType)
        return (actionType == "macro" and subType == "spell")
                or (actionType == "spell" and subType ~= "assistedcombat")
    end

    local function GetBindingForAction(action)
        if not action then
            return nil
        end

        local key = GetBindingKey(action)
        if not key then
            return nil
        end

        local text = GetBindingText(key, "KEY_")
        if not text or text == "" then
            return nil
        end

        local count = 0
        for binding, abbrv in pairs(bindingOverrides) do
            text, count = text:gsub(binding, abbrv, 1)
            if count > 0 then
                return text
            end
        end

        return text
    end

    local function GetButtonFrameByAction(addonAction, defaultAction)
        local buttonName

        if BarAddonLoaded and addonAction then
            buttonName = AddonLookupButtonByAction[addonAction]
            if buttonName and _G[buttonName] then
                return _G[buttonName]
            end
        end

        buttonName = LookupButtonByAction[defaultAction]
        return _G[buttonName]
    end

    local function GetKeyBindForSpellID(spellID)
        local baseSpellID = FindBaseSpellByID(spellID)

        if not baseSpellID then
            return
        end

        local slots = C_ActionBar.FindSpellActionButtons(baseSpellID)
        if not slots then
            return
        end

        for _, slot in ipairs(slots) do
            local actionType, _, subType = GetActionInfo(slot)
            if IsRelevantAction(actionType, subType) then

                local defaultAction = LookupActionBySlot[slot]
                local addonAction = BarAddonLoaded and AddonLookupActionBySlot[slot]

                local text = GetBindingForAction(defaultAction)
                if not text and addonAction then
                    text = GetBindingForAction(addonAction)
                end

                local buttonFrame = GetButtonFrameByAction(addonAction, defaultAction)

                if buttonFrame and buttonFrame.action == slot and text then
                    return text
                end
            end
        end
    end

    if C_AddOns.IsAddOnLoaded("Dominos") then
        for slot = 1, 180 do
            AddonLookupActionBySlot[slot] = "CLICK DominosActionButton" .. slot .. ":HOTKEY"
            AddonLookupButtonByAction[AddonLookupActionBySlot[slot]] = "DominosActionButton" .. slot
        end
        BarAddonLoaded = true
    elseif C_AddOns.IsAddOnLoaded("Bartender4") then
        for slot = 1, 180 do
            AddonLookupActionBySlot[slot] = "CLICK BT4Button" .. slot .. ":Keybind"
            AddonLookupButtonByAction[AddonLookupActionBySlot[slot]] = "BT4Button" .. slot
        end
        BarAddonLoaded = true
    end

    for _, info in ipairs(DefaultActionSlotMap) do
        for id = info.start, info.last do
            local index = id - info.start + 1
            LookupActionBySlot[id] = info.actionPrefix .. index
            LookupButtonByAction[LookupActionBySlot[id]] = info.buttonPrefix .. index
        end
    end

    function WoWHACv5:GetCurrentHotKey()
        return GetKeyBindForSpellID(WoWHACv5:GetCurrentId())
    end

    function WoWHACv5:GetCurrentId()
        return C_AssistedCombat.IsAvailable() and C_AssistedCombat.GetNextCastSpell() or 0
    end
end
