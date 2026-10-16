local _, addon = ...
if not addon:SupportsModernFeatures() then return end

-- Only readable observations enter this cache. Restricted identities, threat,
-- and range never become Lua decisions; they make the count a lower bound.
local Enemies = {}
addon.CombatEnemies = Enemies
local snapshot, states, encounter = nil, {}, false

local function Public(value)
    if addon.IsPriorityValuePublic then return addon.IsPriorityValuePublic(value) end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return not issecretvalue or not issecretvalue(value)
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and Public(value) then return value end
end

local function Identity(unit)
    local guid = Read(UnitGUID, unit)
    if type(guid) == "string" and guid ~= "" then return guid end
end

local function GroupUnits()
    local units = { "player" }
    if Read(UnitExists, "pet") == true then units[#units + 1] = "pet" end
    local raid = Read(IsInRaid) == true
    local size = Read(GetNumGroupMembers)
    if not Number(size) then size = 0 end
    size = math.min(40, math.max(0, math.floor(size)))
    if not raid then size = math.min(4, math.max(0, size - 1)) end
    for i = 1, size do
        local unit = (raid and "raid" or "party") .. i
        if Read(UnitExists, unit) == true then units[#units + 1] = unit end
        local pet = (raid and "raidpet" or "partypet") .. i
        if Read(UnitExists, pet) == true then units[#units + 1] = pet end
    end
    return units
end

local function LivingEnemy(unit)
    local exists = Read(UnitExists, unit)
    if exists == false then return false, false end
    if exists ~= true then return false, true end
    local hostile = Read(UnitCanAttack, "player", unit)
    if hostile == false then return false, false end
    local dead = Read(UnitIsDeadOrGhost, unit)
    if dead == true then return false, false end
    if hostile ~= true or dead ~= false then return false, true end
    return true, false
end

local function Engaged(unit, isBoss, group)
    local combat = Read(UnitAffectingCombat, unit)
    -- A visible boss or a non-target nameplate that is explicitly idle is not
    -- engaged, even during an encounter.
    if combat == false then return false, false end
    if isBoss and encounter then return true, false end
    local unknown = false
    for _, member in ipairs(group) do
        if UnitThreatSituation then
            local ok, threat = pcall(UnitThreatSituation, member, unit)
            if not ok or not Public(threat) then
                unknown = true
            elseif Number(threat) and threat >= 0 then
                return true, false
            end
        else
            unknown = true
        end
    end
    if combat == true then
        local target = unit .. "target"
        local exists = Read(UnitExists, target)
        if exists == true then
            for _, member in ipairs(group) do
                local same = Read(UnitIsUnit, target, member)
                if same == true then return true, false end
                if same == nil then unknown = true end
            end
        elseif exists == nil then
            unknown = true
        end
    elseif combat == nil then
        unknown = true
    end
    return false, unknown
end

local function Scan(now)
    if snapshot and now - snapshot.time < 0.2 then return snapshot end
    local result = { time = now, units = {}, uncertain = false }
    local activeEncounter = Read(IsEncounterInProgress)
    if type(activeEncounter) == "boolean" then encounter = activeEncounter end
    local group, seen, anchors = GroupUnits(), {}, {}
    local function Add(unit, kind)
        local alive, unknown = LivingEnemy(unit)
        if unknown then result.uncertain = true end
        if not alive then return end
        local guid = Identity(unit)
        if guid and seen[guid] then return end
        if kind ~= "target" then
            local engaged, engagementUnknown = Engaged(unit, kind == "boss", group)
            if engagementUnknown then result.uncertain = true end
            if not engaged then return end
            -- Nameplate unit tokens are distinct from one another. Boss and
            -- target tokens can alias them, so compare only those anchors.
            -- UnitIsUnit may remain public even while GUIDs are restricted.
            for _, anchor in ipairs(anchors) do
                local same = Read(UnitIsUnit, unit, anchor.unit)
                if same == true then return end
                if same ~= false then
                    if guid and anchor.guid then
                        if guid == anchor.guid then return end
                    else
                        result.uncertain = true
                        return
                    end
                end
            end
        end
        if guid then seen[guid] = true
        end
        result.units[#result.units + 1] = unit
        if kind == "target" or kind == "boss" then anchors[#anchors + 1] = { unit = unit, guid = guid } end
    end
    Add("target", "target")
    for i = 1, 8 do Add("boss" .. i, "boss") end
    local tokens, havePlates = {}, false
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and Public(plates) and type(plates) == "table" then
            havePlates = true
            for _, plate in ipairs(plates) do
                if Public(plate) and type(plate) == "table" then
                    local token = plate.namePlateUnitToken
                    if Public(token) and type(token) == "string" and token ~= "" then
                        tokens[token] = true
                    else result.uncertain = true end
                else result.uncertain = true end
            end
        end
    end
    if not havePlates then
        for i = 1, 40 do tokens["nameplate" .. i] = true end
    end
    for token in pairs(tokens) do Add(token, "nameplate") end
    snapshot = result
    return result
end

local function InActionRange(entry, unit)
    local isItem = entry.kind == "item"
    local hasRange, getter
    if isItem then
        hasRange = (C_Item and C_Item.ItemHasRange) or ItemHasRange
        getter = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    else
        hasRange = (C_Spell and C_Spell.SpellHasRange) or SpellHasRange
        getter = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    end
    local ranged = Read(hasRange, entry.id)
    -- Actions with no target range (self buffs, for example) cover every
    -- otherwise confirmed unit. Missing range information is not a pass.
    if ranged == false then return true, false end
    local value = Read(getter, entry.id, unit)
    if value == true or value == 1 then return true, false end
    if value == false or value == 0 then return false, false end
    return false, true
end

function Enemies.GetCount(entry)
    if not Public(entry) or type(entry) ~= "table" or not Public(entry.id) or not Number(entry.id)
        or not Public(entry.kind)
        or (entry.kind ~= "spell" and entry.kind ~= "item") then return 0, true end
    local now = Read(GetTime)
    if not Number(now) then return 0, true end
    local scan = Scan(now)
    local key = entry.kind .. ":" .. entry.id
    local state = states[key]
    if state and state.sample == scan.time then return state.count, state.uncertain end
    local count, uncertain = 0, scan.uncertain
    for _, unit in ipairs(scan.units) do
        local inRange, rangeUnknown = InActionRange(entry, unit)
        if inRange then count = count + 1 end
        if rangeUnknown then uncertain = true end
    end
    if not state then state = { count = 0 }; states[key] = state end
    if state.sample and now - state.sample > 2 then
        state.pending, state.since = nil, nil
    end
    if count < state.count then
        state.count, state.pending, state.since = count, nil, nil
    elseif count == state.count then
        state.pending, state.since = nil, nil
    else
        if state.count == 0 then state.count = 1 end
        if count > state.count then
            if state.pending ~= count then
                state.pending, state.since = count, now
            elseif now - state.since >= 0.4 then
                state.count, state.pending, state.since = count, nil, nil
            end
        end
    end
    state.sample = scan.time
    state.uncertain = uncertain or state.count < count
    return state.count, state.uncertain
end

function Enemies.Reset()
    snapshot, states = nil, {}
end

function Enemies.TrackEvent(event)
    if event == "ENCOUNTER_START" then encounter = true
    elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then encounter = false end
    if event == "PLAYER_TARGET_CHANGED" then
        snapshot = nil
        for _, state in pairs(states) do state.sample, state.pending, state.since = nil, nil, nil end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        snapshot = nil
    elseif event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTERING_WORLD"
        or event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then Enemies.Reset() end
end
