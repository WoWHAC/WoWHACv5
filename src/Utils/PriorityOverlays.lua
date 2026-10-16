local _, addon = ...
if not addon:SupportsModernFeatures() then return end
local Runtime = addon:NewModule("PriorityOverlays", "AceEvent-3.0")
local active, cached = {}, {}
local currentProfile, dirty = nil, true

local function InCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

local function HideAll()
    for _, layer in ipairs(active) do layer.root:SetAlpha(0) end
end

local function PlayerIdle()
    local public = addon.IsPriorityValuePublic
    if type(UnitCastingInfo) ~= "function" or type(UnitChannelInfo) ~= "function" then return false end
    for index, getter in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
        local ok, info = pcall(function() return { getter("player") } end)
        if not ok then return false end
        local name, castBarID = info[1], info[index == 1 and 10 or 11]
        -- castBarID is documented NeverSecret. On clients without that field,
        -- only an explicitly public name may establish the absence of a cast.
        if public(castBarID) and castBarID ~= nil then return false end
        if not public(name) or name ~= nil then return false end
    end
    return true
end

function addon:IsPriorityPlayerIdle() return PlayerIdle() end

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
            local baseLevel = self.pixel.frame:GetFrameLevel()
            local level = baseLevel + #profile.actions - index + 1
            layer.root:SetFrameLevel(level)
            -- Give all descendants the same level as their own sibling root;
            -- a long condition chain cannot overtake a higher-priority action.
            for _, gate in ipairs(layer.gates) do gate:SetFrameLevel(level) end
            layer.root:SetAlpha(0)
            nextActive[#nextActive + 1] = layer
        end
    end
    active, currentProfile, dirty = nextActive, profile, false
    return true
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
    local evaluator = self.PriorityConditions
    local idle = PlayerIdle()
    local providerAvailable = type(self.GetActiveProvider) ~= "function" or self:GetActiveProvider() ~= nil
    for _, layer in ipairs(active) do
        layer.root:SetAlpha(0)
        if providerAvailable and idle and profile.enabled == true and layer.entry.enabled == true and layer.binding and layer.valid then
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
    addon:InvalidatePriorityActions()
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
    if event:sub(1, 14) == "UNIT_SPELLCAST_" and addon.IsPriorityValuePublic(unit) and unit == "player" then
        HideAll()
    end
    local conditions = addon.PriorityConditions
    if conditions and conditions.TrackEvent then conditions.TrackEvent(event, ...) end
    if not tracked[event] then
        local resetUsage = event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "ACTIVE_TALENT_GROUP_CHANGED"
        addon:InvalidatePriorityActions(resetUsage)
    elseif event == "PLAYER_REGEN_ENABLED" and dirty then
        addon:RefreshPriorityActions()
    end
end

-- Introspection exposes only public allocation metadata, never gate alpha.
function addon:GetPriorityOverlayCount() return #active end
