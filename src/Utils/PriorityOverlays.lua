local _, addon = ...
if not addon:SupportsModernFeatures() then return end
local Runtime = addon:NewModule("PriorityOverlays", "AceEvent-3.0")
local active, cached = {}, {}
local currentProfile, dirty = nil, true
local bindingsDirty = false

local function InCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

local function HideAll()
    for _, layer in ipairs(active) do layer.root:SetAlpha(0) end
end

local function PlayerIdle(channelGraceMS)
    local public = addon.IsPriorityValuePublic
    if type(UnitCastingInfo) ~= "function" or type(UnitChannelInfo) ~= "function" then return false end
    for index, getter in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
        local ok, info = pcall(function() return { getter("player") } end)
        if not ok then return false end
        local name, castBarID = info[1], info[index == 1 and 10 or 11]
        local channelEnding = false
        if index == 2 and channelGraceMS then
            local endTimeMS = info[5]
            local clockOK, now = pcall(GetTime)
            if public(endTimeMS) and type(endTimeMS) == "number"
                and endTimeMS == endTimeMS and math.abs(endTimeMS) < math.huge
                and clockOK and public(now) and type(now) == "number"
                and now == now and math.abs(now) < math.huge then
                channelEnding = endTimeMS - now * 1000 < channelGraceMS
            end
        end
        -- castBarID is documented NeverSecret. On clients without that field,
        -- only an explicitly public name may establish the absence of a cast.
        if not channelEnding then
            if public(castBarID) and castBarID ~= nil then return false end
            if not public(name) or name ~= nil then return false end
        end
    end
    return true
end

function addon:IsPriorityPlayerIdle() return PlayerIdle() end

-- Keep the provider's original channel queue window separate from the strict
-- idle requirement for configured priority actions and the Forever pipeline.
function addon:IsProviderPlayerIdle() return PlayerIdle(300) end

local function IsBindingCurrent(entry, binding)
    local checker = addon.PriorityBindings and addon.PriorityBindings.IsCurrent
    if not binding or type(checker) ~= "function" then return false end
    local ok, current = pcall(checker, entry, binding)
    return ok and current == true
end

local function CreateLayer(binding, gateCount)
    local pixel = addon.pixel
    local root = CreateFrame("Frame", nil, pixel.frame)
    root:SetAllPoints(pixel.frame)
    root:SetFrameStrata("TOOLTIP")
    root:SetAlpha(0)
    local layer = { root = root, gates = {}, textures = {} }
    local parent = root
    for index = 1, gateCount do
        local gate = CreateFrame("Frame", nil, parent)
        gate:SetAllPoints(root)
        gate:SetAlpha(0)
        layer.gates[index], parent = gate, gate
    end
    local rgb = binding or addon.Protocol.NO_OP
    for _, pixelIndex in ipairs({ 1, #pixel.pixels }) do
        local texture = parent:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints(pixel.pixels[pixelIndex])
        if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
        if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
        if texture.SetColorTexture then texture:SetColorTexture(rgb.red, rgb.green, rgb.blue, 1)
        else texture:SetTexture(rgb.red, rgb.green, rgb.blue) end
        layer.textures[#layer.textures + 1] = texture
    end
    -- These textures are never recolored. A different public binding selects
    -- a separately allocated layer, while this one stays transparent.
    return layer
end

function addon:RefreshPriorityActions()
    HideAll()
    if InCombat() then dirty = true; return false end
    if not self.pixel or not self.PriorityBindings or not self.PriorityConditions then return false end
    local profile = self:GetPriorityActionProfile()
    local ok, bindings = pcall(self.PriorityBindings.Build, profile.actions)
    if not ok or type(bindings) ~= "table" then dirty = true; return false end
    local nextActive = {}
    for index, entry in ipairs(profile.actions) do
        if type(entry) == "table" and (entry.kind == "spell" or entry.kind == "item") and self.PriorityActionID(entry.id) then
            local binding = bindings[entry.kind .. ":" .. entry.id]
            local built, descriptors = pcall(self.PriorityConditions.Build, entry, binding)
            local valid = built and type(descriptors) == "table" and #descriptors > 0 and #descriptors <= 64
            descriptors = valid and descriptors or { { type = "unavailable" } }
            local key = (binding and binding.hotkey or "unbound") .. ":" .. #descriptors
            cached[entry] = cached[entry] or {}
            local layer = cached[entry][key]
            if not layer then
                layer = CreateLayer(binding, #descriptors)
                cached[entry][key] = layer
            end
            layer.entry, layer.binding, layer.descriptors, layer.valid = entry, binding, descriptors, valid
            layer.interrupt = false
            for _, descriptor in ipairs(descriptors) do
                if descriptor.type == "interrupt" then layer.interrupt = true; break end
            end
            -- A secure override can already redirect this key before any
            -- binding-change event occurs. Validate the initial capture too.
            layer.bindingCurrent = IsBindingCurrent(entry, binding)
            local baseLevel = self.pixel.frame:GetFrameLevel()
            local level = baseLevel + #profile.actions - index + 1
            layer.root:SetFrameLevel(level)
            -- Give all descendants the same level as their own sibling root;
            -- a long condition chain cannot overtake a higher-priority action.
            for _, gate in ipairs(layer.gates) do gate:SetFrameLevel(level) end
            layer.root:SetAlpha(0)
            if self.AttachPriorityRecommendation then
                self:AttachPriorityRecommendation(layer, #profile.actions - index + 1)
            end
            nextActive[#nextActive + 1] = layer
        end
    end
    active, currentProfile, dirty, bindingsDirty = nextActive, profile, false, false
    return true
end

local function RecheckBindings(onlyInvalid)
    for _, layer in ipairs(active) do
        if not onlyInvalid or not layer.bindingCurrent then
            layer.bindingCurrent = IsBindingCurrent(layer.entry, layer.binding)
            if not layer.bindingCurrent then layer.root:SetAlpha(0) end
        end
    end
end

local function BindingsChanged()
    if not InCombat() then addon:RefreshPriorityActions(); return end
    -- A slot/spell notification does not mean every binding changed. Keep each
    -- preallocated layer whose public action/key mapping is still valid. Never
    -- recolor or allocate layers in combat; changed/unknown mappings stay hidden.
    bindingsDirty = true
    RecheckBindings(false)
end

function addon:InvalidatePriorityActions(resetUsage)
    HideAll()
    dirty = true
    if resetUsage ~= false and self.PriorityConditions and self.PriorityConditions.ResetUsage then
        self.PriorityConditions.ResetUsage()
    end
    if not InCombat() then self:RefreshPriorityActions() end
end

function addon:UpdatePriorityActions()
    local profile = self:GetPriorityActionProfile()
    if profile ~= currentProfile then
        currentProfile = profile
        self:InvalidatePriorityActions()
    end
    if dirty and not self:RefreshPriorityActions() then return end
    if bindingsDirty then
        if InCombat() then RecheckBindings(true)
        else self:RefreshPriorityActions() end
    else
        -- An initially overridden/unreadable mapping may become valid without
        -- changing the saved base binding or rebuilding layers in combat.
        RecheckBindings(true)
    end
    local evaluator = self.PriorityConditions
    local idle = PlayerIdle()
    for _, layer in ipairs(active) do
        layer.root:SetAlpha(0)
        -- Interrupt is an explicit request to react to the enemy cast even
        -- while the player is casting/channeling. Its other gates still apply.
        if (idle or layer.interrupt) and profile.enabled == true
            and layer.entry.enabled == true and layer.binding and layer.bindingCurrent and layer.valid then
            for index, descriptor in ipairs(layer.descriptors) do
                local gate = layer.gates[index]
                gate:SetAlpha(0)
                -- Success only means the call ran. Eligibility stays entirely
                -- in the native alpha sink, including when its value is secret.
                local ok = pcall(evaluator.Apply, gate, descriptor, layer.entry)
                if not ok then gate:SetAlpha(0) end
            end
            layer.root:SetAlpha(1)
        end
    end
end

function Runtime:OnEnable()
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
        "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "UPDATE_MACROS",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_EMPOWER_START", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED", "ENCOUNTER_START", "ENCOUNTER_END",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    }) do
        -- Some older clients do not expose every modern event.
        pcall(self.RegisterEvent, self, event, "OnRuntimeEvent")
    end
    self:RegisterMessage("WOWHAC_PROVIDER_CHANGED", "OnProviderChanged")
end

function Runtime:OnProviderChanged()
    if not InCombat() then addon:InvalidatePriorityActions(); return end
    -- The provider is the fallback beneath these actions. Its failure must not
    -- invalidate their already allocated bindings and condition layers.
    local conditions = addon.PriorityConditions
    if conditions and conditions.ResetUsage then conditions.ResetUsage() end
end

local tracked = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true,
    PLAYER_TARGET_CHANGED = true, PLAYER_REGEN_ENABLED = true,
    PLAYER_REGEN_DISABLED = true, ENCOUNTER_START = true, ENCOUNTER_END = true,
    NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true,
}

function Runtime:OnRuntimeEvent(event, ...)
    local unit = ...
    if event == "PLAYER_SPECIALIZATION_CHANGED"
        and (not addon.IsPriorityValuePublic(unit) or unit ~= "player") then return end
    if event:sub(1, 15) == "UNIT_SPELLCAST_" and addon.IsPriorityValuePublic(unit) and unit == "player" then
        -- Repeated player actions must not flicker an interrupt between ticks.
        -- Its existing gates stay active until the next normal condition update.
        for _, layer in ipairs(active) do
            if not layer.interrupt then layer.root:SetAlpha(0) end
        end
    end
    local conditions = addon.PriorityConditions
    if conditions and conditions.TrackEvent then conditions.TrackEvent(event, ...) end
    if not tracked[event] then
        local resetUsage = event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "ACTIVE_TALENT_GROUP_CHANGED"
        if resetUsage then addon:InvalidatePriorityActions(true)
        else BindingsChanged() end
    elseif event == "PLAYER_REGEN_ENABLED" and (dirty or bindingsDirty) then
        addon:RefreshPriorityActions()
    end
end

-- Introspection exposes only public allocation metadata, never gate alpha.
function addon:GetPriorityOverlayCount() return #active end
