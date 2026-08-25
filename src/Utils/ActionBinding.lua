local _, WoWHACv5 = ...

local ActionBinding = {}
local ActionSlots = WoWHACv5.ActionSlots

local function GetLastPositiveNumber(...)
    local result
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "number" and value > 0 then
            result = value
        end
    end
    return result
end

local function GetMacroSpellId(macroId)
    if type(GetMacroSpell) ~= "function" then
        return nil
    end
    return GetLastPositiveNumber(GetMacroSpell(macroId))
end

local function GetItemId(value)
    if type(value) == "number" and value > 0 then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end

    local linkId = tonumber(value:match("item:(%d+)"))
    if linkId then
        return linkId
    end
    if GetItemInfoInstant then
        local itemId = GetItemInfoInstant(value)
        return type(itemId) == "number" and itemId > 0 and itemId or nil
    end
end

local function GetMacroItemId(macroId)
    if type(GetMacroItem) ~= "function" then
        return nil
    end
    local name, link = GetMacroItem(macroId)
    return GetItemId(link) or GetItemId(name)
end

local function MacroUsesModifierCondition(macroId)
    if type(GetMacroInfo) ~= "function" then
        return true
    end

    local _, _, body = GetMacroInfo(macroId)
    if type(body) ~= "string" then
        return true
    end

    for conditionBlock in body:lower():gmatch("%b[]") do
        local conditions = conditionBlock:sub(2, -2)
        for token in conditions:gmatch("[^,%s]+") do
            local name = token:match("^([^:]+)")
            if name == "mod"
                or name == "nomod"
                or name == "modifier"
                or name == "nomodifier" then
                return true
            end
        end
    end
    return false
end

local function IsSafeSlot(slot)
    if type(slot) ~= "number" or slot <= 0 or type(GetActionInfo) ~= "function" then
        return false
    end

    local actionType, id = GetActionInfo(slot)
    return actionType ~= "macro" or not MacroUsesModifierCondition(id)
end

local function GetActionDescriptor(slot)
    if type(GetActionInfo) ~= "function" then
        return nil
    end
    if HasAction and not HasAction(slot) then
        return nil
    end

    local actionType, id, subType = GetActionInfo(slot)
    if ActionSlots.IsAssistedCombat(slot)
        or (actionType == "spell" and subType == "assistedcombat") then
        return nil
    end
    if actionType == "spell" and type(id) == "number" then
        return "spell", id
    end
    if actionType == "item" then
        return "item", GetItemId(id)
    end
    if actionType == "macro" then
        if MacroUsesModifierCondition(id) then
            return nil
        end
        local spellId = GetMacroSpellId(id)
        if spellId then
            return "spell", spellId
        end
        local itemId = GetMacroItemId(id)
        if itemId then
            return "item", itemId
        end
    end
end

local function AddSpellEquivalent(equivalents, spellId)
    if type(spellId) == "number" and spellId > 0 then
        equivalents[spellId] = true
    end
end

local function GetSpellEquivalents(spellId)
    local equivalents = {}
    AddSpellEquivalent(equivalents, spellId)
    if FindBaseSpellByID then
        AddSpellEquivalent(equivalents, FindBaseSpellByID(spellId))
    end
    if C_Spell and C_Spell.GetOverrideSpell then
        AddSpellEquivalent(equivalents, C_Spell.GetOverrideSpell(spellId))
    end

    local initial = {}
    for id in pairs(equivalents) do
        initial[#initial + 1] = id
    end
    for _, id in ipairs(initial) do
        if FindBaseSpellByID then
            AddSpellEquivalent(equivalents, FindBaseSpellByID(id))
        end
        if C_Spell and C_Spell.GetOverrideSpell then
            AddSpellEquivalent(equivalents, C_Spell.GetOverrideSpell(id))
        end
    end
    return equivalents
end

local function GetBindingFromCandidateSlots(slots, expectedKind, expectedIds, visited)
    for _, slot in ipairs(slots or {}) do
        if not visited or not visited[slot] then
            if visited then
                visited[slot] = true
            end
            local rawBinding = ActionSlots.GetBinding(slot)
            if rawBinding then
                local kind, id = GetActionDescriptor(slot)
                if kind == expectedKind and expectedIds[id] then
                    return rawBinding
                end
            end
        end
    end
end

local function CallBooleanApi(api, id)
    if type(api) ~= "function" then
        return nil
    end

    local ok, result = pcall(api, id)
    if ok and type(result) == "boolean" then
        return result
    end
end

function ActionBinding.ForSlot(slot)
    return IsSafeSlot(slot) and ActionSlots.GetBinding(slot) or nil
end

function ActionBinding.ForButton(button)
    return ActionBinding.ForSlot(ActionSlots.GetButtonSlot(button))
end

function ActionBinding.ForSpell(spellId)
    if type(spellId) ~= "number" or spellId <= 0 then
        return nil
    end
    local equivalents = GetSpellEquivalents(spellId)
    local visited = {}
    if C_ActionBar and C_ActionBar.FindSpellActionButtons then
        for equivalentId in pairs(equivalents) do
            local rawBinding = GetBindingFromCandidateSlots(
                C_ActionBar.FindSpellActionButtons(equivalentId),
                "spell",
                equivalents,
                visited
            )
            if rawBinding then
                return rawBinding
            end
        end
    end

    return GetBindingFromCandidateSlots(
        ActionSlots.GetBoundSlots(),
        "spell",
        equivalents,
        visited
    )
end

function ActionBinding.ForItem(itemId, itemCastSpellId)
    itemId = GetItemId(itemId)
    if not itemId then
        return itemCastSpellId and ActionBinding.ForSpell(itemCastSpellId) or nil
    end
    local rawBinding = GetBindingFromCandidateSlots(
        ActionSlots.GetBoundSlots(),
        "item",
        { [itemId] = true }
    )
    if rawBinding then
        return rawBinding
    end
    return itemCastSpellId and ActionBinding.ForSpell(itemCastSpellId) or nil
end

function ActionBinding.ForUntypedId(id)
    if type(id) ~= "number" or id <= 0 then
        return nil
    end

    local spellExists = CallBooleanApi(C_Spell and C_Spell.DoesSpellExist, id)
    local itemExists = CallBooleanApi(C_Item and C_Item.DoesItemExistByID, id)

    if spellExists == nil
        or itemExists == nil
        or spellExists == itemExists then
        return nil
    end

    if spellExists then
        local hotkey = ActionBinding.ForSpell(id)
        return hotkey and id or nil, hotkey
    end

    local hotkey = ActionBinding.ForItem(id)
    return hotkey and -id or nil, hotkey
end

WoWHACv5.ActionBinding = ActionBinding
