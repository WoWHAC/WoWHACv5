local _, addon = ...
if not addon:SupportsModernFeatures() then return end

local function Public(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

local function ActionID(value)
    if not Public(value) or (type(value) ~= "string" and type(value) ~= "number") then return nil end
    local id = tonumber(value)
    if id and id > 0 and id < math.huge and id == math.floor(id) then return id end
end

local function Kind(value) return Public(value) and (value == "spell" or value == "item") end

local function CharacterKey()
    local guid = UnitGUID and UnitGUID("player")
    if Public(guid) and guid and guid ~= "" then return guid end
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    name = name or (UnitName and UnitName("player")) or "player"
    realm = realm or (GetRealmName and GetRealmName()) or "realm"
    return name .. "-" .. realm
end

local function SpecializationKey()
    local index = GetSpecialization and GetSpecialization()
    local id = index and GetSpecializationInfo and GetSpecializationInfo(index)
    return id or (GetActiveTalentGroup and GetActiveTalentGroup()) or index or 0
end

local function DefaultConditions() return { { type = "combat", unit = "player" }, { type = "range" } } end

function addon:GetPriorityActionProfile()
    -- Upgrade the existing character/spec store in place, preserving order,
    -- IDs and enabled flags, including profiles not currently selected.
    local settings = self:GetSettings()
    if type(settings.offensiveCooldowns) ~= "table" then settings.offensiveCooldowns = {} end
    local characterKey, specKey = CharacterKey(), SpecializationKey()
    local characters = settings.offensiveCooldowns
    if type(characters[characterKey]) ~= "table" then characters[characterKey] = {} end
    local profiles = characters[characterKey]
    if type(profiles[specKey]) ~= "table" then profiles[specKey] = { enabled = false, actions = {} } end
    local profile = profiles[specKey]
    if type(profile.enabled) ~= "boolean" then profile.enabled = false end
    if type(profile.actions) ~= "table" then
        profile.actions = type(profile.spells) == "table" and profile.spells or {}
    end
    profile.spells = profile.actions -- Compatibility alias, not a second copy.
    if profile.version ~= 2 then
        for _, entry in ipairs(profile.actions) do
            if type(entry) == "table" then
                if entry.kind == nil then entry.kind = "spell" end
                if entry.conditions == nil then entry.conditions = DefaultConditions() end
            end
        end
        profile.version = 2
    end
    return profile
end

function addon:GetPriorityActionInfo(kind, value)
    local id = ActionID(value)
    if not Kind(kind) or not id then return nil end
    if kind == "item" then
        local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
        if not getter then return nil end
        local ok, name, _, _, _, _, _, _, _, _, icon = pcall(getter, id)
        if ok and Public(name) and type(name) == "string" and name ~= "" then return name, icon end
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil
    end
    local getter = C_Spell and C_Spell.GetSpellInfo or GetSpellInfo
    if not getter then return nil end
    local ok, info, _, icon = pcall(getter, id)
    if not ok or not Public(info) then return nil end
    if type(info) == "table" then
        if Public(info.name) and type(info.name) == "string" and info.name ~= "" then
            local iconID = Public(info.iconID) and info.iconID or nil
            if not iconID and Public(info.icon) then iconID = info.icon end
            return info.name, iconID
        end
    elseif type(info) == "string" and info ~= "" then return info, icon end
end

local function Changed(profile)
    if addon.InvalidatePriorityActions then addon:InvalidatePriorityActions() end
    if addon.SendMessage then
        addon:SendMessage("WOWHAC_PRIORITY_ACTIONS_CHANGED", profile)
        addon:SendMessage("WOWHAC_OFFENSIVE_COOLDOWNS_CHANGED", profile)
    end
end

local function Find(profile, kind, id)
    if not id or not Kind(kind) then return nil end
    for index, entry in ipairs(profile.actions) do
        if type(entry) == "table" and entry.kind == kind and entry.id == id then return index, entry end
    end
end

local function NewEntry(kind, id)
    return { kind = kind, id = id, enabled = true, conditions = DefaultConditions() }
end

function addon:AddPriorityAction(kind, value)
    local id = ActionID(value)
    if not Kind(kind) or not id then return false, "Choose a spell or item and enter a positive whole-number ID." end
    local profile = self:GetPriorityActionProfile()
    if Find(profile, kind, id) then return false, "That action is already in this profile." end
    if not self:GetPriorityActionInfo(kind, id) then return false, "No data found for that ID. Try again after the client loads it." end
    profile.actions[#profile.actions + 1] = NewEntry(kind, id)
    Changed(profile)
    return true
end

function addon:PlacePriorityAction(kind, value, destination)
    local id = ActionID(value)
    if not Kind(kind) or not id then return false, "Choose a spell or item and enter a positive whole-number ID." end
    if type(destination) ~= "number" or destination ~= destination
        or math.abs(destination) == math.huge or destination ~= math.floor(destination) then
        return false, "Choose a whole-number priority position."
    end
    local profile = self:GetPriorityActionProfile()
    local index, entry = Find(profile, kind, id)
    if not entry and not self:GetPriorityActionInfo(kind, id) then return false, "No data found for that ID." end
    destination = math.max(1, math.min(#profile.actions + (entry and 0 or 1), destination))
    if index == destination then return true end
    if entry then table.remove(profile.actions, index) end
    table.insert(profile.actions, destination, entry or NewEntry(kind, id))
    Changed(profile)
    return true
end

function addon:RemovePriorityAction(kind, value)
    local profile = self:GetPriorityActionProfile()
    local index = Find(profile, kind, ActionID(value))
    if not index then return false, "That action is not in this profile." end
    table.remove(profile.actions, index)
    Changed(profile)
    return true
end

function addon:MovePriorityAction(kind, value, delta)
    local profile = self:GetPriorityActionProfile()
    local index = Find(profile, kind, ActionID(value))
    if not index then return false, "That action is not in this profile." end
    if type(delta) ~= "number" or delta ~= delta or math.abs(delta) == math.huge
        or delta == 0 or delta ~= math.floor(delta) then return false, "Choose a whole-number move distance." end
    local destination = math.max(1, math.min(#profile.actions, index + delta))
    if destination == index then return false, "That action is already at the edge of the list." end
    table.insert(profile.actions, destination, table.remove(profile.actions, index))
    Changed(profile)
    return true
end

function addon:SetPriorityActionEnabled(kind, value, enabled)
    local profile = self:GetPriorityActionProfile()
    local _, entry = Find(profile, kind, ActionID(value))
    if not entry then return false, "That action is not in this profile." end
    enabled = enabled == true
    if entry.enabled ~= enabled then entry.enabled = enabled; Changed(profile) end
    return true
end

function addon:SetPriorityActionsEnabled(enabled)
    local profile = self:GetPriorityActionProfile()
    enabled = enabled == true
    if profile.enabled ~= enabled then profile.enabled = enabled; Changed(profile) end
    return true
end

function addon:SetPriorityActionConditions(kind, value, conditions)
    local profile = self:GetPriorityActionProfile()
    local _, entry = Find(profile, kind, ActionID(value))
    if not entry then return false, "That action is not in this profile." end
    if not self.PriorityConditions or not self.PriorityConditions.Validate then return false, "Condition support is unavailable." end
    local validated, reason = self.PriorityConditions.Validate(conditions)
    if not validated then return false, reason end
    entry.conditions = validated
    Changed(profile)
    return true
end

addon.PriorityActionID = ActionID
addon.IsPriorityValuePublic = Public

-- Legacy editor API names. Eligibility is presentation-only now, so the old
-- GetOffensiveCooldownSuggestion function is intentionally removed.
addon.GetOffensiveCooldownProfile = addon.GetPriorityActionProfile
function addon:GetOffensiveCooldownSpellInfo(id) return self:GetPriorityActionInfo("spell", id) end
function addon:AddOffensiveCooldown(id) return self:AddPriorityAction("spell", id) end
function addon:PlaceOffensiveCooldown(id, position) return self:PlacePriorityAction("spell", id, position) end
function addon:RemoveOffensiveCooldown(id) return self:RemovePriorityAction("spell", id) end
function addon:MoveOffensiveCooldown(id, delta) return self:MovePriorityAction("spell", id, delta) end
function addon:SetOffensiveCooldownEnabled(id, enabled) return self:SetPriorityActionEnabled("spell", id, enabled) end
addon.SetOffensiveCooldownsEnabled = addon.SetPriorityActionsEnabled
