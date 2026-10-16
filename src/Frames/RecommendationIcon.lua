local _, addon = ...
if not addon:SupportsModernFeatures() then return end

local Display = addon:NewModule("RecommendationIcon", "AceEvent-3.0")
local Public = addon.IsPriorityValuePublic
local SIZE, BASE_LEVEL = 48, 20
local QUESTION_MARK = 134400
local frame, providerTile
local priorityTiles = {}
local bindingsDirty = true

local function L(text) return addon:Translate(text) end
local function InCombat() return InCombatLockdown and InCombatLockdown() == true end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function IsTexture(value)
    return Public(value) and (type(value) == "number" and value > 0
        or type(value) == "string" and value ~= "")
end

local function Settings()
    local settings = addon:GetSettings()
    if type(settings.recommendationIcon) ~= "table" then settings.recommendationIcon = {} end
    return settings.recommendationIcon
end

function addon:IsRecommendationIconEnabled()
    return Settings().enabled ~= false
end

local function Texture(kind, id)
    local getter = kind == "item" and (C_Item and C_Item.GetItemIconByID or GetItemIcon)
        or kind == "spell" and (C_Spell and C_Spell.GetSpellTexture or GetSpellTexture)
    if type(getter) == "function" then
        local ok, icon = pcall(getter, id)
        if ok and IsTexture(icon) then return icon end
    end
    local _, icon = addon:GetPriorityActionInfo(kind, id)
    if IsTexture(icon) then return icon end
end

local function ShortKey(hotkey)
    if not Public(hotkey) or type(hotkey) ~= "string" then return "" end
    return hotkey:upper():gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-")
        :gsub("NUMPAD", "N"):gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "MW+"):gsub("MOUSEWHEELDOWN", "MW-")
end

local function SetTile(tile, icon, hotkey)
    icon = icon or QUESTION_MARK
    local key = ShortKey(hotkey)
    if tile.lastIcon == icon and tile.lastKey == key then return end
    tile.lastIcon, tile.lastKey = icon, key
    tile.icon:SetTexture(icon)
    tile.key:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    tile.key:SetText(key)
    local width = tile.key:GetStringWidth()
    if width > SIZE - 6 then
        tile.key:SetFont(STANDARD_TEXT_FONT, math.max(8, 13 * (SIZE - 6) / width), "OUTLINE")
    end
    tile.keyBackground:SetShown(key ~= "")
end

local function CreateTile(parent, level)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetAllPoints(frame)
    tile:SetFrameStrata("MEDIUM")
    tile:SetFrameLevel(level)
    tile:EnableMouse(false)
    -- Every tile is opaque, including behind the key. A higher-priority icon
    -- completely covers the provider/lower-priority label beneath it.
    local background = tile:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.03, 0.03, 0.03, 1)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 2, -2)
    tile.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tile.keyBackground = tile:CreateTexture(nil, "OVERLAY", nil, 0)
    tile.keyBackground:SetPoint("TOPLEFT", 2, -2)
    tile.keyBackground:SetPoint("TOPRIGHT", -2, -2)
    tile.keyBackground:SetHeight(16)
    tile.keyBackground:SetColorTexture(0, 0, 0, 0.7)
    tile.key = tile:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    tile.key:SetPoint("TOPRIGHT", -4, -3)
    tile.key:SetWidth(SIZE - 8)
    tile.key:SetWordWrap(false)
    tile.key:SetJustifyH("RIGHT")
    tile.key:SetTextColor(1, 1, 1, 1)
    return tile
end

local function RestorePosition()
    if not frame then return end
    local settings = Settings()
    local x = Number(settings.x) and settings.x or 0
    local y = Number(settings.y) and settings.y or -140
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function StopMoving()
    if not frame or not frame.dragging then return end
    frame:StopMovingOrSizing()
    frame.dragging = nil
    frame:SetScript("OnUpdate", nil)
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if Number(x) and Number(y) and Number(parentX) and Number(parentY) then
        Settings().x, Settings().y = x - parentX, y - parentY
    end
    frame:SetUserPlaced(false)
    RestorePosition()
end

local function UpdateMouse()
    if not frame then return end
    local shift = IsShiftKeyDown and IsShiftKeyDown() == true
    if not shift then StopMoving() end
    frame:EnableMouse(shift)
    -- Shift exposes a placement preview even when there is no recommendation.
    -- This does not depend on reading any priority gate's alpha.
    frame.preview:SetShown(shift)
    if not shift and GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

local function EnsureFrame()
    if frame then return frame end
    if InCombat() then return end
    frame = CreateFrame("Frame", "WoWHACv5RecommendationIcon", UIParent)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(BASE_LEVEL - 2)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame.preview = CreateTile(frame, BASE_LEVEL - 1)
    SetTile(frame.preview, QUESTION_MARK, "")
    providerTile = CreateTile(frame, BASE_LEVEL)
    providerTile:SetAlpha(0)
    frame:SetScript("OnDragStart", function()
        if not IsShiftKeyDown() then return end
        GameTooltip:Hide()
        frame.dragging = true
        frame:StartMoving()
        frame:SetScript("OnUpdate", function() if not IsShiftKeyDown() then UpdateMouse() end end)
    end)
    frame:SetScript("OnDragStop", StopMoving)
    frame:SetScript("OnHide", function()
        StopMoving()
        if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
    end)
    frame:SetScript("OnEnter", function()
        if frame.dragging then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Recommended action"))
        GameTooltip:AddLine(L("Hold Shift to drag."), 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end end)
    RestorePosition()
    UpdateMouse()
    frame:SetShown(addon:IsRecommendationIconEnabled())
    return frame
end

function addon:SetRecommendationIconEnabled(enabled)
    Settings().enabled = enabled == true
    EnsureFrame()
    if frame then frame:SetShown(Settings().enabled) end
    for _, tile in ipairs(priorityTiles) do tile:SetShown(Settings().enabled) end
end

function addon:ClearRecommendationProvider()
    if providerTile then providerTile:SetAlpha(0) end
end

function addon:UpdateRecommendationProvider(id, hotkey)
    if not EnsureFrame() then return end
    if not Public(hotkey) or type(hotkey) ~= "string" or hotkey == ""
        or not self:IsRecommendationIconEnabled() then
        self:ClearRecommendationProvider()
        return
    end
    local icon
    if Number(id) and id ~= 0 and math.abs(id) == math.floor(math.abs(id)) then
        icon = Texture(id < 0 and "item" or "spell", math.abs(id))
    end
    if not icon and self.PriorityBindings.GetActionForHotkey then
        local action = self.PriorityBindings.GetActionForHotkey(hotkey)
        if action then icon = action.icon or Texture(action.kind, action.id) end
    end
    -- Never leave the previous action visible when provider metadata is absent.
    SetTile(providerTile, icon, hotkey)
    providerTile:SetAlpha(1)
end

function addon:AttachPriorityRecommendation(layer, rank)
    if not EnsureFrame() then return end
    local tile = layer.recommendationTile
    if not tile then
        -- Reuse the actual condition chain: native rendering combines secret
        -- alpha values. Lua never reads alpha or chooses a secret winner.
        tile = CreateTile(layer.gates[#layer.gates] or layer.root, BASE_LEVEL + rank)
        layer.recommendationTile = tile
        priorityTiles[#priorityTiles + 1] = tile
    end
    tile:SetFrameLevel(BASE_LEVEL + rank)
    tile.actionKind, tile.actionID = layer.entry.kind, layer.entry.id
    tile.hotkey = layer.binding and layer.binding.hotkey
    SetTile(tile, Texture(tile.actionKind, tile.actionID), tile.hotkey)
    tile:SetShown(self:IsRecommendationIconEnabled())
end

function Display:RefreshBindings()
    if InCombat() then return end
    local bindings = addon.PriorityBindings
    if bindings and bindings.RefreshDisplayBindings then
        local ok, refreshed = pcall(bindings.RefreshDisplayBindings)
        bindingsDirty = not (ok and refreshed)
    end
end

function Display:OnDisplayEvent(event, itemID, success)
    if event == "MODIFIER_STATE_CHANGED" then UpdateMouse(); return end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        StopMoving(); RestorePosition(); return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        EnsureFrame()
        if bindingsDirty then self:RefreshBindings() end
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not Public(itemID) or not Public(success) or success ~= true then return end
        for _, tile in ipairs(priorityTiles) do
            if tile.actionKind == "item" and tile.actionID == itemID then
                SetTile(tile, Texture("item", itemID), tile.hotkey)
            end
        end
        return
    end
    addon:ClearRecommendationProvider()
    bindingsDirty = true
    if addon.PriorityBindings.InvalidateDisplayBindings then addon.PriorityBindings.InvalidateDisplayBindings() end
    self:RefreshBindings()
end

function Display:OnEnable()
    EnsureFrame()
    for _, event in ipairs({
        "MODIFIER_STATE_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS",
        "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "SPELLS_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED",
    }) do pcall(self.RegisterEvent, self, event, "OnDisplayEvent") end
    self:RegisterMessage("WOWHAC_PROVIDER_CHANGED", "OnDisplayEvent")
    self:RefreshBindings()
end
