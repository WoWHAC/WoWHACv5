local _, addon = ...
if not addon:SupportsModernFeatures() then return end

local Conditions = {}
addon.PriorityConditions = Conditions
local history, uncertainEvents = {}, {}
local retainedSeconds = 60
local MAX_INTEGER = 2147483647

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

local function ID(value)
    if Number(value) and value > 0 and value == math.floor(value) then return value end
end

local function Clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Clone(item) end
    return copy
end

local function AuraAPIAvailable()
    return C_UnitAuras
        and (type(C_UnitAuras.GetUnitAuraBySpellID) == "function" or type(C_UnitAuras.GetPlayerAuraBySpellID) == "function")
        and type(UnitExists) == "function" and type(UnitIsVisible) == "function"
        and ((C_Secrets and (type(C_Secrets.ShouldSpellAuraBeSecret) == "function" or type(C_Secrets.HasSecretRestrictions) == "function"))
            or (not C_Secrets and not issecretvalue and not canaccessvalue))
end

local operators = { lt = "<", lte = "<=", eq = "=", gte = ">=", gt = ">" }
local comparison = { key = "op", label = "Comparison", kind = "select", values = operators }
local percent = { key = "value", label = "Percent", kind = "number", min = 1, max = 100, step = 1 }
local catalog = {
    { type = "combat", label = "In combat", description = "Only suggest this action while you are in combat.",
        defaults = { unit = "player" }, fields = {} },
    { type = "target", label = "Enemy target", description = "Only suggest this action when your current target exists, is alive, and can be attacked.", defaults = {}, fields = {} },
    { type = "health", label = "Health", description = "Choose whose health to check and a percentage. For example, Player < 50 requires your health to be below 50%. The selected character or pet must be alive and present.",
        defaults = { unit = "player", op = "lt", value = 50 }, fields = {
            { key = "unit", label = "Unit", kind = "select", values = { player = "Player", pet = "Pet", mouseover = "Mouseover", target = "Target" } },
            comparison, percent,
        } },
    { type = "resource", label = "Player resource", description = "Check how full your main resource bar is, such as mana or energy. For example, >= 50 requires at least half of your maximum resource. The number is a percentage, not resource points.",
        defaults = { op = "gte", value = 50 }, fields = { comparison, percent } },
    { type = "aura", label = "Aura (unstabile)", description = "Choose who to check and enter the spell ID of a buff or debuff. Present requires that aura; Absent requires it to be missing. The aura ID can differ from the spell you cast. Auras from any caster count. Experimental: if WoW hides the aura data or the selected character or pet is unavailable, neither mode passes. Some clients only support checking Player.",
        defaults = { unit = "player", state = "present", spellID = 0 }, fields = {
            { key = "unit", label = "Unit", kind = "select", values = { player = "Player", pet = "Pet", mouseover = "Mouseover", target = "Target" } },
            { key = "state", label = "Aura state", kind = "select", values = { present = "Present", absent = "Absent" } },
            { key = "spellID", label = "Aura spell ID", kind = "number", min = 1, max = MAX_INTEGER, step = 1 },
        } },
    { type = "range", label = "In range", description = "Only suggest this spell or item when your current target is within its range. Actions with no range requirement pass this condition.", defaults = {}, fields = {} },
    { type = "glow", label = "Proc", description = "Only suggest this action while WoW shows the proc glow for its spell. For an item, this checks the spell used by that item.", defaults = {}, fields = {} },
    { type = "interrupt", label = "Interrupt", description = "Only suggest this action while your living enemy target is casting or channeling a spell that can be interrupted. The target must also be within this action's range. Choose an action that can interrupt if you want to stop the cast.", defaults = {}, fields = {} },
    { type = "repeatDelay", label = "Delay after success", description = "Wait the chosen number of seconds after you successfully use this action before suggesting it again. A cancelled or interrupted cast does not start the wait. Set 0 for no delay.",
        defaults = { seconds = 0 }, fields = {
            { key = "seconds", label = "Seconds", kind = "number", min = 0, max = 60, step = 0.1 },
        } },
    { type = "limit", label = "Usage limit", description = "Stop suggesting this action after the chosen number of uses within the time window (1000 ms = 1 second). For example, 2 uses / 5000 ms blocks suggestions after two uses in the last 5 seconds. A cast counts as soon as it starts, even if interrupted. Enable per target for a separate count on each target. Set allowed uses to 0 to block this action.",
        defaults = { allowance = 1, windowMs = 1000, perTarget = false }, fields = {
            { key = "allowance", label = "Allowed uses", kind = "number", min = 0, max = MAX_INTEGER, step = 1 },
            { key = "windowMs", label = "Window (ms)", kind = "number", min = 1, max = MAX_INTEGER, step = 1 },
            { key = "perTarget", label = "Count per target", kind = "boolean" },
        } },
    { type = "enemies", label = "Enemies count", description = "Check the number of enemies within this action's range. For example, >= 3 requires three or more enemies. Counts your living enemy target and other enemies detected in combat. If the full count is unknown, only checks using > or >= can pass.",
        defaults = { op = "gte", value = 2 }, fields = {
            comparison, { key = "value", label = "Enemies", kind = "number", min = 0, max = 80, step = 1 },
        } },
    { type = "unmounted", label = "Not mounted", description = "Only suggest this action when you are not riding a mount.", defaults = {}, fields = {} },
}
local byType = {}
for _, definition in ipairs(catalog) do byType[definition.type] = definition end

function addon:GetPriorityConditionCatalog()
    local result = Clone(catalog)
    for _, definition in ipairs(result) do
        definition.label = self:Translate(definition.label)
        definition.description = self:Translate(definition.description)
        for _, field in ipairs(definition.fields) do
            field.label = self:Translate(field.label)
            if field.values then
                for key, value in pairs(field.values) do field.values[key] = self:Translate(value) end
            end
        end
        local available = true
        if definition.type == "glow" then available = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed
        elseif definition.type == "interrupt" then available = UnitCastingInfo and UnitChannelInfo
        elseif definition.type == "aura" then available = AuraAPIAvailable()
        elseif definition.type == "unmounted" then available = IsMounted
        elseif definition.type == "enemies" then available = addon.CombatEnemies end
        definition.available = available ~= nil and available ~= false
        if not definition.available then definition.unavailableReason = self:Translate("This version of WoW cannot check this condition. While it is checked, this action will not be suggested.") end
    end
    return result
end

function Conditions.Validate(conditions)
    if not Public(conditions) or type(conditions) ~= "table" then return nil, addon:Translate("Conditions must be a list.") end
    local length = #conditions
    if length > 24 then return nil, addon:Translate("Use at most 24 conditions per action.") end
    for key in pairs(conditions) do
        if not Number(key) or key < 1 or key > length or key ~= math.floor(key) then return nil, addon:Translate("Conditions must be a consecutive list.") end
    end
    local normalized = {}
    for index, condition in ipairs(conditions) do
        if not Public(condition) or type(condition) ~= "table" or not Public(condition.type)
            or type(condition.type) ~= "string" then return nil, addon:Translate("Invalid condition.") end
        local definition = byType[condition.type]
        if not definition then return nil, addon:Translate("Unknown condition type.") end
        local copy = Clone(definition.defaults)
        copy.type = condition.type
        for _, field in ipairs(definition.fields) do
            local value = condition[field.key]
            if not Public(value) then return nil, addon:Translate("Condition settings must be readable.") end
            if value == nil then value = copy[field.key] end
            if field.kind == "number" then
                if not Number(value) or value < field.min or value > field.max
                    or (field.step == 1 and value ~= math.floor(value)) then
                    return nil, addon:Translate("%s must be %s-%s%s.", addon:Translate(field.label), field.min, field.max,
                        field.step == 1 and addon:Translate(" (whole numbers)") or "")
                end
            elseif field.kind == "select" then
                if type(value) ~= "string" or not field.values[value] then return nil, addon:Translate("Choose a valid %s.", addon:Translate(field.label)) end
            elseif field.kind == "boolean" and type(value) ~= "boolean" then
                return nil, addon:Translate("%s must be on or off.", addon:Translate(field.label))
            end
            copy[field.key] = value
        end
        normalized[#normalized + 1] = copy
    end
    return normalized
end

function addon:ValidatePriorityConditions(conditions)
    local normalized, reason = Conditions.Validate(conditions)
    return normalized ~= nil, reason
end

local function Compare(value, op, threshold)
    if op == "lt" then return value < threshold end
    if op == "lte" then return value <= threshold end
    if op == "eq" then return value == threshold end
    if op == "gte" then return value >= threshold end
    if op == "gt" then return value > threshold end
    return false
end

local function ThresholdCurve(condition)
    if not C_CurveUtil or not C_CurveUtil.CreateCurve or not Enum or not Enum.LuaCurveType then return nil end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    local threshold = condition.value / 100
    -- The next representable double distinguishes strict/inclusive boundaries
    -- without rounding health or resource values in Lua.
    local _, exponent = math.frexp(threshold)
    local after = threshold + math.ldexp(1, exponent - 53)
    local beforeValue = Compare(0, condition.op, threshold) and 1 or 0
    local atValue = Compare(threshold, condition.op, threshold) and 1 or 0
    local afterValue = Compare(after, condition.op, threshold) and 1 or 0
    curve:AddPoint(0, beforeValue)
    curve:AddPoint(threshold, atValue)
    curve:AddPoint(after, afterValue)
    curve:AddPoint(2, afterValue)
    -- These probes contain only our own public configuration values. Clients
    -- that round adjacent points or use different step boundaries must not
    -- silently turn an inclusive/equality comparison into another predicate.
    for _, point in ipairs({ { 0, beforeValue }, { threshold, atValue }, { after, afterValue },
        { 1, Compare(1, condition.op, threshold) and 1 or 0 } }) do
        local evaluated = curve:Evaluate(point[1])
        if not Number(evaluated) or evaluated ~= point[2] then return nil end
    end
    return curve
end

function Conditions.Build(entry)
    if not Public(entry) or type(entry) ~= "table" then return { { type = "blocked" } } end
    local source = entry.conditions
    if not Public(source) then return { { type = "blocked" } } end
    if source == nil then source = {} end
    local configured = Conditions.Validate(source)
    if not configured then return { { type = "blocked" } } end
    local descriptors = { { type = "ready" }, { type = "usable" } }
    local haveRange, haveTarget, needRange, needTarget = false, false, false, false
    for _, condition in ipairs(configured) do
        if condition.type == "range" then haveRange = true end
        if condition.type == "target" then haveTarget = true end
        if condition.type == "interrupt" then needRange, needTarget = true, true end
        if condition.type == "limit" then retainedSeconds = math.max(retainedSeconds, condition.windowMs / 1000) end
        if condition.type == "health" or condition.type == "resource" then
            local ok, curve = pcall(ThresholdCurve, condition)
            if ok then condition.curve = curve end
        end
        descriptors[#descriptors + 1] = condition
    end
    if needRange and not haveRange then descriptors[#descriptors + 1] = { type = "range" } end
    if needTarget and not haveTarget then descriptors[#descriptors + 1] = { type = "target" } end
    return descriptors
end

local function BoolAlpha(frame, value, invert)
    -- No boolean arithmetic or comparison occurs before the secret check. The
    -- native setter consumes restricted booleans without revealing them to Lua.
    if not Public(value) then
        if frame.SetAlphaFromBoolean then frame:SetAlphaFromBoolean(value, invert and 0 or 1, invert and 1 or 0) end
    elseif type(value) == "boolean" then
        if frame.SetAlphaFromBoolean then frame:SetAlphaFromBoolean(value, invert and 0 or 1, invert and 1 or 0)
        else frame:SetAlpha((value ~= (invert == true)) and 1 or 0) end
    end
end

local function ActionSpell(entry)
    if entry.kind == "spell" then return ID(entry.id) end
    if entry.kind ~= "item" then return nil end
    local getter = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not getter then return nil end
    local ok, _, spellID = pcall(getter, entry.id)
    if ok then return ID(spellID) end
end

local function BaseSpell(spellID)
    if not ID(spellID) then return nil end
    if C_Spell and C_Spell.GetBaseSpell then
        local base = Read(C_Spell.GetBaseSpell, spellID)
        if ID(base) then return base end
    end
    return spellID
end

local function TargetIdentity()
    local guid = Read(UnitGUID, "target")
    if type(guid) == "string" and guid ~= "" then return guid end
end

local function Prune(now)
    local cutoff = now - retainedSeconds
    for index = #uncertainEvents, 1, -1 do
        if uncertainEvents[index] < cutoff then table.remove(uncertainEvents, index) end
    end
    for spellID, bucket in pairs(history) do
        for index = #bucket.uses, 1, -1 do
            local use = bucket.uses[index]
            if use.time < cutoff then bucket.attempts[use.cast] = nil; table.remove(bucket.uses, index) end
        end
        for index = #bucket.unknown, 1, -1 do
            if bucket.unknown[index] < cutoff then table.remove(bucket.unknown, index) end
        end
        if #bucket.uses == 0 and #bucket.unknown == 0 and (not bucket.success or bucket.success < cutoff) then history[spellID] = nil end
    end
end

function Conditions.ResetUsage()
    history, uncertainEvents = {}, {}
    if addon.CombatEnemies then addon.CombatEnemies.Reset() end
end

function Conditions.TrackEvent(event, unit, castGUID, spellID)
    if addon.CombatEnemies then addon.CombatEnemies.TrackEvent(event) end
    if event ~= "UNIT_SPELLCAST_START" and event ~= "UNIT_SPELLCAST_CHANNEL_START"
        and event ~= "UNIT_SPELLCAST_EMPOWER_START" and event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
    local now = Read(GetTime)
    if not Number(now) then return end
    Prune(now)
    if not Public(unit) then uncertainEvents[#uncertainEvents + 1] = now; return end
    if unit ~= "player" then return end
    spellID = BaseSpell(spellID)
    if not spellID then uncertainEvents[#uncertainEvents + 1] = now; return end
    local bucket = history[spellID]
    if not bucket then bucket = { uses = {}, attempts = {}, unknown = {} }; history[spellID] = bucket end
    if not Public(castGUID) or type(castGUID) ~= "string" or castGUID == "" then
        if event == "UNIT_SPELLCAST_SUCCEEDED" then bucket.success = now end
        bucket.unknown[#bucket.unknown + 1] = now
        return
    end
    local use = bucket.attempts[castGUID]
    if not use then
        use = { time = now, cast = castGUID, target = TargetIdentity() }
        bucket.attempts[castGUID] = use
        bucket.uses[#bucket.uses + 1] = use
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and not use.succeeded then
        use.succeeded, bucket.success = true, now
    end
end

local function UsageAlpha(frame, descriptor, entry)
    if descriptor.type == "repeatDelay" and descriptor.seconds == 0 then frame:SetAlpha(1); return end
    if descriptor.type == "limit" and descriptor.allowance == 0 then return end
    local spellID, now = BaseSpell(ActionSpell(entry)), Read(GetTime)
    if not spellID or not Number(now) then return end
    Prune(now)
    local window = descriptor.type == "repeatDelay" and descriptor.seconds or descriptor.windowMs / 1000
    local cutoff = now - window
    for _, time in ipairs(uncertainEvents) do if time >= cutoff then return end end
    local bucket = history[spellID]
    if descriptor.type == "repeatDelay" then
        if not bucket or not bucket.success or now - bucket.success >= descriptor.seconds then frame:SetAlpha(1) end
        return
    end
    local target
    if descriptor.perTarget then target = TargetIdentity(); if not target then return end end
    local count = 0
    if bucket then
        for _, time in ipairs(bucket.unknown) do if time >= cutoff then return end end
        for _, use in ipairs(bucket.uses) do
            if use.time >= cutoff then
                if descriptor.perTarget and not use.target then return end
                if not descriptor.perTarget or use.target == target then count = count + 1 end
            end
        end
    end
    frame:SetAlpha(count < descriptor.allowance and 1 or 0)
end

local function ReadyAlpha(frame, entry)
    if entry.kind == "item" then
        local getter = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
        if not getter then return end
        local start, duration, enabled = getter(entry.id)
        if not Number(start) or not Number(duration) or not Public(enabled) then return end
        if enabled ~= true and enabled ~= 1 then return end
        local now = Read(GetTime)
        if Number(now) then frame:SetAlpha((duration == 0 or start + duration <= now) and 1 or 0) end
        return
    end
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local duration = C_Spell.GetSpellCooldownDuration(entry.id, true)
        if Public(duration) and duration and duration.IsZero then BoolAlpha(frame, duration:IsZero()) end
        return
    end
    local charges = (C_Spell and C_Spell.GetSpellCharges) or GetSpellCharges
    if charges then
        local count = charges(entry.id)
        if Public(count) and type(count) == "table" then count = count.currentCharges end
        if Number(count) and count > 0 then frame:SetAlpha(1); return end
    end
    local getter = (C_Spell and C_Spell.GetSpellCooldown) or GetSpellCooldown
    if not getter then return end
    local info, duration, enabled = getter(entry.id)
    local start = info
    if Public(info) and type(info) == "table" then
        start, duration, enabled = info.startTime, info.duration, info.isEnabled
        if Public(info.isOnGCD) and info.isOnGCD == true then BoolAlpha(frame, enabled); return end
    end
    if not Number(start) or not Number(duration) or not Public(enabled) then return end
    if enabled ~= true and enabled ~= 1 then return end
    local now = Read(GetTime)
    if Number(now) then frame:SetAlpha((duration == 0 or start + duration <= now) and 1 or 0) end
end

local function RangeAlpha(frame, entry)
    local hasRange, getter
    if entry.kind == "item" then
        hasRange = (C_Item and C_Item.ItemHasRange) or ItemHasRange
        getter = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    else
        hasRange = (C_Spell and C_Spell.SpellHasRange) or SpellHasRange
        getter = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    end
    if Read(hasRange, entry.id) == false then frame:SetAlpha(1); return end
    if not getter then return end
    local value = getter(entry.id, "target")
    if Public(value) and type(value) == "number" then frame:SetAlpha(value == 1 and 1 or 0)
    else BoolAlpha(frame, value) end
end

local function CastPresence(name, castBarID)
    if Public(castBarID) and castBarID ~= nil then return true end
    -- Older clients have no castBarID; a readable name is the only fallback.
    return Public(name) and type(name) == "string" and name ~= ""
end

local function InterruptAlpha(frame)
    if UnitCastingInfo then
        local name, _, _, _, _, _, _, notInterruptible, _, castBarID = UnitCastingInfo("target")
        if CastPresence(name, castBarID) then BoolAlpha(frame, notInterruptible, true); return end
    end
    if UnitChannelInfo then
        local name, _, _, _, _, _, notInterruptible, _, _, _, castBarID = UnitChannelInfo("target")
        if CastPresence(name, castBarID) then BoolAlpha(frame, notInterruptible, true) end
    end
end

local function PercentAlpha(frame, descriptor)
    local isHealth = descriptor.type == "health"
    local unit = isHealth and descriptor.unit or "player"
    if Read(UnitExists, unit) ~= true or Read(UnitIsDeadOrGhost, unit) ~= false then return end
    if descriptor.curve then
        if isHealth and UnitHealthPercent then frame:SetAlpha(UnitHealthPercent(unit, false, descriptor.curve)); return end
        if not isHealth and UnitPowerPercent then frame:SetAlpha(UnitPowerPercent(unit, nil, false, descriptor.curve)); return end
    end
    local current, maximum
    if isHealth then current, maximum = Read(UnitHealth, unit), Read(UnitHealthMax, unit)
    else current, maximum = Read(UnitPower, unit), Read(UnitPowerMax, unit) end
    if Number(current) and Number(maximum) and maximum > 0 then
        frame:SetAlpha(Compare(current / maximum * 100, descriptor.op, descriptor.value) and 1 or 0)
    end
end

local function AuraAlpha(frame, descriptor)
    if not AuraAPIAvailable() then return end
    local unit, spellID = descriptor.unit, descriptor.spellID
    if Read(UnitExists, unit) ~= true or Read(UnitIsVisible, unit) ~= true then return end

    -- RequiresNonSecretAura can return nil for an aura that is present but
    -- restricted. Check the spell's current secrecy before treating nil as
    -- absence, and repeat this check on every update (including during combat).
    if C_Secrets and type(C_Secrets.ShouldSpellAuraBeSecret) == "function" then
        if Read(C_Secrets.ShouldSpellAuraBeSecret, spellID) ~= false then return end
    elseif C_Secrets and type(C_Secrets.HasSecretRestrictions) == "function" then
        if Read(C_Secrets.HasSecretRestrictions) ~= false then return end
    elseif C_Secrets or issecretvalue or canaccessvalue then
        return
    end
    if type(C_UnitAuras.AuraIsPrivate) == "function" and Read(C_UnitAuras.AuraIsPrivate, spellID) ~= false then return end

    local aura
    -- Keep errors distinct from an absent aura: the outer Apply guard leaves
    -- the gate transparent on an API error. Never fall back after a failed read.
    if type(C_UnitAuras.GetUnitAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)
    elseif unit == "player" and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    else
        return
    end
    if not Public(aura) then return end
    if aura ~= nil and type(aura) ~= "table" then return end
    -- The lookup already matches the configured ID. No aura fields, stacks,
    -- timers, or rendered widget values need to be inspected.
    BoolAlpha(frame, aura ~= nil, descriptor.state == "absent")
end

local function Apply(frame, descriptor, entry)
    if not ID(entry.id) or not Public(entry.kind) or (entry.kind ~= "spell" and entry.kind ~= "item") then return end
    if not Public(descriptor.type) then return end
    local kind = descriptor.type
    if kind == "ready" then ReadyAlpha(frame, entry)
    elseif kind == "usable" then
        local getter
        if entry.kind == "item" then
            local count = Read((C_Item and C_Item.GetItemCount) or GetItemCount, entry.id, false, false)
            if not Number(count) or count < 1 then return end
            getter = (C_Item and C_Item.IsUsableItem) or IsUsableItem
        else getter = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell end
        if getter then BoolAlpha(frame, (getter(entry.id))) end
    elseif kind == "combat" then
        if UnitAffectingCombat then BoolAlpha(frame, UnitAffectingCombat("player")) end
    elseif kind == "target" then
        if Read(UnitExists, "target") ~= true or Read(UnitIsDeadOrGhost, "target") ~= false then return end
        if UnitCanAttack then BoolAlpha(frame, UnitCanAttack("player", "target")) end
    elseif kind == "range" then RangeAlpha(frame, entry)
    elseif kind == "health" or kind == "resource" then PercentAlpha(frame, descriptor)
    elseif kind == "aura" then AuraAlpha(frame, descriptor)
    elseif kind == "glow" then
        local spellID = ActionSpell(entry)
        local getter = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed
        if spellID and getter then BoolAlpha(frame, getter(spellID)) end
    elseif kind == "interrupt" then InterruptAlpha(frame)
    elseif kind == "repeatDelay" or kind == "limit" then UsageAlpha(frame, descriptor, entry)
    elseif kind == "unmounted" then
        if IsMounted then BoolAlpha(frame, IsMounted(), true) end
    elseif kind == "enemies" and addon.CombatEnemies then
        local count, uncertain = addon.CombatEnemies.GetCount(entry)
        if uncertain and (count == 0 or (descriptor.op ~= "gt" and descriptor.op ~= "gte")) then return end
        frame:SetAlpha(Compare(count, descriptor.op, descriptor.value) and 1 or 0)
    end
end

function Conditions.Apply(frame, descriptor, entry)
    frame:SetAlpha(0)
    -- This catches API availability/runtime failures, never tests whether a
    -- secret comparison throws. Every Lua comparison above checks readability.
    local ok = pcall(Apply, frame, descriptor, entry)
    if not ok then frame:SetAlpha(0) end
end
