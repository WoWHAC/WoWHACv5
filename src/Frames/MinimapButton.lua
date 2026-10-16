local _, addon = ...

if not addon:SupportsModernFeatures() then return end

local Controls = addon:NewModule("MinimapControls", "AceEvent-3.0")
local DEFAULT_ANGLE = 225
local MENU_WIDTH = 280
local ROW_HEIGHT = 26
local LANGUAGE_CHOICES = { "auto", "ruRU", "enUS" }

local function L(key, ...)
    if addon.Translate then return addon:Translate(key, ...) end
    return select("#", ...) > 0 and string.format(key, ...) or key
end

local function LanguageLabel(language)
    if language == "ruRU" then return "Русский" end
    if language == "enUS" then return "English" end
    return L("Automatic")
end

local shapes = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function GetSettings()
    local settings = addon:GetSettings()
    if type(settings.minimap) ~= "table" then settings.minimap = {} end
    return settings.minimap
end

local function GetProviderLabel()
    local active = addon:GetActiveProvider()
    for _, provider in ipairs(addon:GetAvailableProviders()) do
        if provider.id == active then return provider.label end
    end
    return active or L("None available")
end

local function StopDragging(button)
    button.dragging = nil
    button:SetScript("OnUpdate", nil)
    button:UnlockHighlight()
end

function Controls:UpdatePosition()
    local button = self.button
    -- Minimap collection addons own the layout after reparenting the button.
    if not button or button:GetParent() ~= Minimap then return end
    local angle = tonumber(GetSettings().angle) or DEFAULT_ANGLE
    if angle ~= angle or angle == math.huge or angle == -math.huge then angle = DEFAULT_ANGLE end
    angle = math.rad(angle % 360)
    local x, y = math.cos(angle), math.sin(angle)
    local quadrant = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
    local corners = shapes[GetMinimapShape and GetMinimapShape() or "ROUND"] or shapes.ROUND
    local width, height = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    if corners[quadrant] then
        x, y = x * width, y * height
    else
        x = math.max(-width, math.min(x * (math.sqrt(2) * width - 10), width))
        y = math.max(-height, math.min(y * (math.sqrt(2) * height - 10), height))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function Controls:UpdatePositionFromCursor()
    if self.button:GetParent() ~= Minimap then return end
    local x, y = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    if not x or not y or not scale or scale <= 0 then return end
    local cursorX, cursorY = GetCursorPosition()
    local dx, dy = cursorX / scale - x, cursorY / scale - y
    -- atan2 is supplied by WoW's Lua runtime, including older clients.
    local angle = math.deg(math.atan2(dy, dx))
    GetSettings().angle = angle % 360
    self:UpdatePosition()
end

function Controls:ShowTooltip(button)
    if button.dragging then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("WoWHACv5")
    GameTooltip:AddLine(L("Provider: %s", GetProviderLabel()), 1, 1, 1, true)
    GameTooltip:AddLine(L("Click for providers and settings."), 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(L("Drag to move around the minimap."), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function CreateMenuRow(menu)
    local row = CreateFrame("Button", nil, menu)
    row:SetSize(MENU_WIDTH - 24, ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(20, 20)
    row.check:SetPoint("LEFT", 1, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", 26, 0)
    row.label:SetPoint("RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
        if self.providerID then
            local ok, reason = addon:SelectProvider(self.providerID)
            if ok then
                menu:Hide()
            else
                local errors = {
                    combat = "Providers cannot be changed in combat. Try again after combat.",
                    unavailable = "This provider is no longer available. Choose another provider or reload the UI.",
                    initialization_failed = "This provider could not start. Choose another provider or reload the UI.",
                }
                Controls:RefreshMenu(errors[reason] or "The provider could not be selected. Try again.")
            end
        elseif self.action == "settings" then
            menu:Hide()
            addon:ShowSettings()
        else
            menu:Hide()
            addon:ShowPriorityActionsEditor()
        end
    end)
    return row
end

function Controls:CreateMenu()
    -- A stable UIParent owner keeps the popup alive when a minimap manager
    -- hides its flyout (and therefore our icon) after the click.
    local menu = CreateFrame("Frame", "WoWHACv5ProviderMenu", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetWidth(MENU_WIDTH)
    menu:SetFrameStrata("DIALOG")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0.08, 0.08, 0.08, 1)
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    menu.title:SetPoint("TOPLEFT", 16, -16)
    menu.title:SetPoint("RIGHT", -30, 0)
    menu.title:SetJustifyH("LEFT")
    menu.title:SetText("WoWHACv5")
    local close = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() menu:Hide() end)
    menu.current = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    menu.current:SetPoint("TOPLEFT", 16, -39)
    menu.current:SetWidth(MENU_WIDTH - 32)
    menu.current:SetJustifyH("LEFT")
    menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.empty:SetPoint("TOPLEFT", 16, -66)
    menu.empty:SetWidth(MENU_WIDTH - 32)
    menu.empty:SetJustifyH("LEFT")
    menu.status = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    menu.status:SetWidth(MENU_WIDTH - 32)
    menu.status:SetJustifyH("LEFT")
    menu.status:SetTextColor(1, 0.35, 0.35)
    menu.rows = {}
    menu:Hide()
    UISpecialFrames[#UISpecialFrames + 1] = "WoWHACv5ProviderMenu"
    self.menu = menu
end

function Controls:RefreshMenu(errorMessage)
    local menu = self.menu
    if not menu then return end
    local providers = addon:GetAvailableProviders()
    local active = addon:GetActiveProvider()
    menu.errorKey = errorMessage
    menu.current:SetText(L("Providers"))
    menu.priorityRow, menu.settingsRow = nil, nil
    for _, row in ipairs(menu.rows) do row:Hide() end
    local top = 62
    if #providers == 0 then
        menu.empty:SetText(L("No providers available.") .. "\n" .. L("Enable a supported addon or use Assisted Combat."))
        menu.empty:Show()
        top = top + 78
    else
        menu.empty:Hide()
    end
    for index, provider in ipairs(providers) do
        local row = menu.rows[index] or CreateMenuRow(menu)
        menu.rows[index] = row
        row.providerID = provider.id
        row.action = nil
        row.label:SetText(provider.label)
        if provider.id == active then row.check:Show() else row.check:Hide() end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 12, -top)
        row:Show()
        top = top + ROW_HEIGHT
    end
    if active then
        local index = #providers + 1
        local row = menu.rows[index] or CreateMenuRow(menu)
        menu.rows[index] = row
        row.providerID = nil
        row.action = "priorities"
        row.check:Hide()
        row.label:SetText(L("Priority actions..."))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 12, -(top + 8))
        row:Show()
        menu.priorityRow = row
        top = top + ROW_HEIGHT + 8
    end
    local index = #providers + (active and 2 or 1)
    local row = menu.rows[index] or CreateMenuRow(menu)
    menu.rows[index] = row
    row.providerID, row.action = nil, "settings"
    row.check:Hide()
    row.label:SetText(L("Settings..."))
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 12, -(top + (active and 0 or 8)))
    row:Show()
    menu.settingsRow = row
    top = top + ROW_HEIGHT + (active and 0 or 8)
    menu.status:ClearAllPoints()
    menu.status:SetPoint("TOPLEFT", 16, -(top + 8))
    menu.status:SetText(errorMessage and L(errorMessage) or "")
    menu:SetHeight(top + (errorMessage and 60 or 14))
end

function Controls:ToggleMenu()
    if self.menu and self.menu:IsShown() then
        self.menu:Hide()
        return
    end
    addon:RefreshProviders()
    if not self.menu then self:CreateMenu() end
    self:RefreshMenu()
    GameTooltip:Hide()
    local menu = self.menu
    menu:ClearAllPoints()
    local button = self.button
    local x, y
    if button then x, y = button:GetCenter() end
    if x and y and button:IsVisible() then
        -- Snapshot screen coordinates instead of anchoring to a flyout child.
        local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
        x, y = x * scale, y * scale
        if x > UIParent:GetWidth() / 2 then
            menu:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x - 20, y + 16)
        else
            menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 20, y + 16)
        end
    else
        menu:SetPoint("CENTER", UIParent, "CENTER")
    end
    menu:Show()
end

function Controls:OnProvidersChanged()
    if self.menu and self.menu:IsShown() then self:RefreshMenu() end
end

function Controls:OnGlobalMouseDown()
    if not self.menu or not self.menu:IsShown() or not MouseIsOver then return end
    if not MouseIsOver(self.menu) and
        (not self.button or not self.button:IsVisible() or not MouseIsOver(self.button)) then
        self.menu:Hide()
    end
end

function Controls:IsInCombat()
    return self.inCombat or (InCombatLockdown and InCombatLockdown()) or false
end

function Controls:CloseSettings()
    self.pendingSettingsOpen = nil
    if self.settingsFrame then self.settingsFrame:Hide() end
end

function Controls:RefreshSettings()
    local frame = self.settingsFrame
    if not frame then return end
    frame.title:SetText(L("Settings"))
    frame.languageLabel:SetText(L("Language"))
    local choice = frame.language
    for _, value in ipairs(LANGUAGE_CHOICES) do choice.values[value] = LanguageLabel(value) end
    choice:SelectValue(addon:GetLanguage(), true)
    local recommendation = frame.recommendation
    recommendation.label:SetText(L("Show recommendation icon"))
    recommendation:SetChecked(addon:IsRecommendationIconEnabled())
    recommendation:SetHitRectInsets(0, -math.min(296, recommendation.label:GetStringWidth() + 4), 0, 0)
end

function Controls:SelectLanguage(value)
    if self:IsInCombat() then return false end
    if not addon:SetLanguage(value) then return false end
    self:RefreshSettings()
    return true
end

function Controls:CreateSettings()
    if self:IsInCombat() then return false end
    local frame = CreateFrame("Frame", "WoWHACv5Settings", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.settingsFrame = frame
    frame:SetSize(380, 172)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 24, -22)
    local brand = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    brand:SetPoint("TOPRIGHT", -50, -26)
    brand:SetText("WoWHACv5")
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 12, -8)
    drag:SetPoint("TOPRIGHT", -40, -8)
    drag:SetHeight(38)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -4, -4)
    frame.close:SetScript("OnClick", function() self:CloseSettings() end)
    frame.languageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.languageLabel:SetPoint("TOPLEFT", 24, -72)
    frame.languageLabel:SetWidth(80)
    frame.languageLabel:SetJustifyH("LEFT")
    local choice = CreateFrame("Frame", "WoWHACv5LanguageChoice", frame, "UIDropDownMenuTemplate")
    frame.language = choice
    choice:SetPoint("TOPLEFT", 106, -62)
    choice:SetSize(250, 32)
    choice.values = {}
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(choice, 200) end
    if UIDropDownMenu_SetFrameStrata then UIDropDownMenu_SetFrameStrata(choice, "TOOLTIP") end
    function choice:SelectValue(value, silent)
        if not silent then return Controls:SelectLanguage(value) end
        self.value = value
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, value) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, LanguageLabel(value)) end
        return true
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(choice, function()
            for _, key in ipairs(LANGUAGE_CHOICES) do
                local value = key
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value, info.checked = LanguageLabel(value), value, choice.value == value
                info.func = function() choice:SelectValue(value) end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    local recommendation = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.recommendation = recommendation
    recommendation:SetSize(28, 28)
    recommendation:SetPoint("TOPLEFT", 20, -112)
    recommendation.label = recommendation:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    recommendation.label:SetPoint("LEFT", recommendation, "RIGHT", 4, 0)
    recommendation.label:SetWidth(296)
    recommendation.label:SetJustifyH("LEFT")
    recommendation.label:SetWordWrap(false)
    recommendation:SetScript("OnClick", function(button)
        if not self:IsInCombat() then
            addon:SetRecommendationIconEnabled(not not button:GetChecked())
        end
        self:RefreshSettings()
    end)
    local function HandleEscape()
        if not frame:IsShown() then return false end
        self:CloseSettings()
        return true
    end
    if type(RegisterGameMenuEscHandler) == "function" and GameMenuEscPriority and GameMenuEscPriority.AddOn then
        RegisterGameMenuEscHandler(GameMenuEscPriority.AddOn, HandleEscape)
    elseif frame.SetPropagateKeyboardInput then
        frame:SetPropagateKeyboardInput(true)
        frame:EnableKeyboard(true)
        frame:SetScript("OnKeyDown", function(_, key)
            if self:IsInCombat() then return end
            frame:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then HandleEscape() end
        end)
    end
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        if CloseDropDownMenus then CloseDropDownMenus() end
        if not self.combatHiding then self.pendingSettingsOpen = nil end
    end)
    frame:Hide()
    return true
end

function Controls:ShowSettings()
    if self:IsInCombat() then
        self.pendingSettingsOpen = true
        return false
    end
    if not self.settingsFrame then self:CreateSettings() end
    self.pendingSettingsOpen = nil
    self:RefreshSettings()
    self.settingsFrame:Show()
    self.settingsFrame:Raise()
    return true
end

function Controls:OnCombatStarted()
    self.inCombat = true
    if self.settingsFrame and self.settingsFrame:IsShown() then
        self.pendingSettingsOpen = true
        self.combatHiding = true
        self.settingsFrame:Hide()
        self.combatHiding = nil
    end
end

function Controls:OnCombatEnded()
    self.inCombat = nil
    if self.pendingSettingsOpen and not self:IsInCombat() then self:ShowSettings() end
end

function Controls:OnLanguageChanged()
    if self.menu and self.menu:IsShown() then self:RefreshMenu(self.menu.errorKey) end
    self:RefreshSettings()
end

function Controls:CreateButton()
    if not Minimap then return end
    local button = CreateFrame("Button", "WoWHACv5MinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local retail = WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(retail and 24 or 20, retail and 24 or 20)
    background:SetPoint("CENTER", retail and 0 or 1, retail and 0 or 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", retail and 0 or 1, retail and 0 or 1)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(retail and 50 or 53, retail and 50 or 53)
    border:SetPoint("TOPLEFT")
    button:SetScript("OnEnter", function(owner) self:ShowTooltip(owner) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnMouseDown", function(owner)
        owner.suppressClick = nil
        icon:SetTexCoord(0, 1, 0, 1)
    end)
    button:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
    button:SetScript("OnClick", function(owner)
        if owner.suppressClick then
            owner.suppressClick = nil
            return
        end
        self:ToggleMenu()
    end)
    button:SetScript("OnDragStart", function(owner)
        if owner:GetParent() ~= Minimap then return end
        owner.suppressClick = true
        owner.dragging = true
        owner:LockHighlight()
        if self.menu then self.menu:Hide() end
        GameTooltip:Hide()
        owner:SetScript("OnUpdate", function() self:UpdatePositionFromCursor() end)
    end)
    button:SetScript("OnDragStop", function(owner)
        if owner.dragging then self:UpdatePositionFromCursor() end
        StopDragging(owner)
    end)
    button:SetScript("OnHide", function(owner)
        StopDragging(owner)
        icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        GameTooltip:Hide()
    end)
    self.button = button
    self:UpdatePosition()
end

function addon:InitializeControls()
    if not Controls.button then Controls:CreateButton() end
    if Controls.initialized then return end
    Controls.initialized = true
    Controls:RegisterMessage("WOWHAC_PROVIDER_CHANGED", "OnProvidersChanged")
    Controls:RegisterMessage("WOWHAC_PROVIDERS_CHANGED", "OnProvidersChanged")
    Controls:RegisterMessage("WOWHAC_LANGUAGE_CHANGED", "OnLanguageChanged")
    Controls:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStarted")
    Controls:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
    Controls:RegisterEvent("UI_SCALE_CHANGED", "UpdatePosition")
    Controls:RegisterEvent("DISPLAY_SIZE_CHANGED", "UpdatePosition")
    Controls:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdatePosition")
    -- Older clients have no global mouse event; close, Escape and icon toggle
    -- still work there without placing a mouse-blocking frame over the world.
    pcall(Controls.RegisterEvent, Controls, "GLOBAL_MOUSE_DOWN", "OnGlobalMouseDown")
    self:RegisterChatCommand("wowhac", function() Controls:ToggleMenu() end)
end

function addon:ShowSettings()
    self:InitializeControls()
    return Controls:ShowSettings()
end

function addon:ToggleControlsMenu()
    self:InitializeControls()
    Controls:ToggleMenu()
end
