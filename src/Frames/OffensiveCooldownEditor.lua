local _, addon = ...

if not addon:SupportsModernFeatures() then return end

local Editor = addon:NewModule("OffensiveCooldownEditor", "AceEvent-3.0")
local PANEL_WIDTH, PANEL_HEIGHT = 520, 484
local CONDITIONS_WIDTH, CONDITION_ROW_HEIGHT, DOCK_GAP = 600, 28, 0
local COLUMNS, SLOT_SIZE, CELL_WIDTH, CELL_HEIGHT = 6, 48, 74, 76
local GRID_WIDTH, GRID_HEIGHT = COLUMNS * CELL_WIDTH, 276
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local BUILDER_HINT = "If you want more conditions, try our new product"
local BUILDER_URLS = { ruRU = "https://discord.gg/YERDhtDqqt", enUS = "https://discord.gg/nEMJrgSZUV" }
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

local function L(key, ...)
    if addon.Translate then return addon:Translate(key, ...) end
    if select("#", ...) > 0 then return string.format(key, ...) end
    return key
end

local function Locale()
    return addon.GetEffectiveLocale and addon:GetEffectiveLocale() or "enUS"
end

local function KindLabel(kind)
    return kind == "item" and L("Item") or L("Spell")
end

local function SetEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function MakeButton(parent, text, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(L(text))
    button:SetScript("OnClick", callback)
    return button
end

local function Label(parent, text, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetText(L(text))
    label:SetJustifyH("LEFT")
    return label
end

local function SetTooltip(frame, text)
    frame:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(L(text), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ValidID(value)
    return type(value) == "number" and value > 0 and value <= 2147483647
        and value == math.floor(value) and value or nil
end

local FindAction

function Editor:IsInCombat()
    return self.inCombat or (InCombatLockdown and InCombatLockdown()) or false
end

function Editor:Close()
    self.pendingRestore = nil
    if self.frame then self.frame:Hide() end
end

function Editor:CloseConditions()
    if self.pendingRestore then self.pendingRestore.conditions = nil end
    self:CloseRotationBuilderLink()
    if self.frame and self.frame.conditionsDialog then self.frame.conditionsDialog:Hide() end
end

function Editor:CloseRotationBuilderLink()
    if self.pendingRestore and not self.combatHiding then self.pendingRestore.builderLink = nil end
    local conditions = self.frame and self.frame.conditionsDialog
    if conditions and conditions.linkDialog then conditions.linkDialog:Hide(); conditions.linkDialog.input:ClearFocus() end
end

function Editor:CloseAddDialog()
    if self.pendingRestore then self.pendingRestore.add = nil end
    if self.frame and self.frame.addDialog then self.frame.addDialog:Hide() end
end

function Editor:DeferOpen(window, kind, id)
    local pending = self.pendingRestore or {}
    local wasPending = pending.conditions and pending.keepDraft and pending.kind == kind and pending.id == id
    self.pendingRestore = pending
    pending.main = true
    if window == "conditions" then
        pending.builderLink = nil
        pending.add, pending.conditions = nil, true
        pending.kind, pending.id = kind, id
        local dialog = self.frame and self.frame.conditionsDialog
        pending.keepDraft = dialog and (wasPending or dialog:IsVisible())
            and dialog.actionKind == kind and dialog.actionID == id
            and dialog.profile == addon:GetPriorityActionProfile() or false
    elseif window == "add" then
        pending.conditions, pending.builderLink, pending.add = nil, nil, true
    end
    return false
end

function Editor:OnCombatStarted()
    self.inCombat = true
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local requested = self.pendingRestore
    local pending = { main = true, add = frame.addDialog:IsShown() }
    local dialog = frame.conditionsDialog
    if dialog and dialog:IsShown() then
        pending.conditions, pending.keepDraft = true, true
        pending.kind, pending.id = dialog.actionKind, dialog.actionID
        pending.builderLink = (dialog.linkDialog and dialog.linkDialog:IsShown())
            or (requested and requested.builderLink and requested.keepDraft
                and requested.kind == dialog.actionKind and requested.id == dialog.actionID)
    end
    self.pendingRestore = pending
    self.combatHiding = true
    frame:Hide()
    self.combatHiding = nil
end

function Editor:OnCombatEnded()
    self.inCombat = nil
    if self:IsInCombat() then return end
    local pending = self.pendingRestore
    self.pendingRestore = nil
    if self.languageDirty then self:RefreshLanguage() end
    if self.frame then self:InitializeEscapeHandling() end
    if not pending or not pending.main then return end
    addon:ShowPriorityActionsEditor()
    if pending.conditions then
        local dialog = self.frame.conditionsDialog
        local profile = addon:GetPriorityActionProfile()
        local _, action = FindAction(profile.actions, pending.kind, pending.id)
        if action and pending.keepDraft and dialog and dialog.profile == profile and dialog.action == action then
            dialog:Show(); dialog:Raise(); self:FitEditorToScreen()
            if pending.builderLink then self:ShowRotationBuilderLink() end
        elseif action and not pending.keepDraft then self:ShowConditions(pending.kind, pending.id) end
    elseif pending.add then self:ShowAddDialog() end
end

FindAction = function(actions, kind, id)
    for index, action in ipairs(actions) do
        if action.kind == kind and action.id == id then return index, action end
    end
end

local function ProviderInfo()
    local id = addon:GetActiveProvider()
    local info = { id = id, label = id or L("No provider selected"), icon = UNKNOWN_ICON }
    for _, provider in ipairs(addon:GetAvailableProviders()) do
        if provider.id == id then info.label = provider.label; break end
    end
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if id == "AssistedCombat" and C_AssistedCombat and C_AssistedCombat.GetActionSpell then
        local ok, spellID = pcall(C_AssistedCombat.GetActionSpell)
        local texture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
        if ok and ValidID(spellID) and type(texture) == "function" then
            local iconOK, icon, originalIcon = pcall(texture, spellID)
            if iconOK then info.icon = originalIcon or icon or UNKNOWN_ICON end
        end
    elseif id and type(metadata) == "function" then
        local ok, icon = pcall(metadata, id, "IconTexture")
        if ok and (type(icon) == "number" or (type(icon) == "string" and icon ~= "")) then
            info.icon = tonumber(icon) or icon
        else
            local atlasOK, atlas = pcall(metadata, id, "IconAtlas")
            if atlasOK and type(atlas) == "string" and atlas ~= "" then info.atlas = atlas end
        end
    end
    return info
end

-- Spell cursors contain a spellbook slot in the second return on some clients.
function Editor:GetCursorSpellID()
    if type(GetCursorInfo) ~= "function" then return nil end
    local ok, kind, slot, book, id = pcall(GetCursorInfo)
    if not ok or kind ~= "spell" then return nil end
    if ValidID(id) then return id end
    if not ValidID(slot) then return nil end
    local banks = Enum and Enum.SpellBookSpellBank
    local types = Enum and Enum.SpellBookItemType
    if book == "pet" or (banks and book == banks.Pet) then return nil end
    if C_SpellBook and type(C_SpellBook.GetSpellBookItemInfo) == "function" and banks and types then
        local bank = (book == "spell" or book == BOOKTYPE_SPELL) and banks.Player or book
        if bank == banks.Player then
            local infoOK, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
            if infoOK and type(info) == "table" and
                (info.itemType == types.Spell or info.itemType == types.FutureSpell) then
                return ValidID(info.spellID)
            end
        end
    elseif type(GetSpellBookItemInfo) == "function" and (book == "spell" or book == BOOKTYPE_SPELL) then
        local infoOK, spellType, spellID = pcall(GetSpellBookItemInfo, slot, book)
        if infoOK and (spellType == "SPELL" or spellType == "FUTURESPELL") then return ValidID(spellID) end
    end
end

function Editor:GetCursorAction()
    if type(GetCursorInfo) ~= "function" then return nil end
    local ok, kind, id = pcall(GetCursorInfo)
    if not ok then return nil end
    if kind == "item" and ValidID(id) then return "item", id end
    if kind == "spell" then
        id = self:GetCursorSpellID()
        if id then return "spell", id end
    end
end

function Editor:GetDragAction()
    local kind, id = self:GetCursorAction()
    if kind then return kind, id end
    if self.drag and not self.drag.nativeCursor then return self.drag.kind, self.drag.id end
end

function Editor:SetStatus(text, isError)
    if not self.frame then return end
    self.statusKey, self.statusIsError = text, isError
    self.frame.status:SetText(text and L(text) or "")
    self.frame.status:SetTextColor(isError and 1 or 0.85, isError and 0.35 or 0.85, isError and 0.35 or 0.85)
end

local function RequestActionData(kind, id)
    local request = kind == "spell" and C_Spell and C_Spell.RequestLoadSpellData
        or kind == "item" and C_Item and C_Item.RequestLoadItemDataByID
    if request then pcall(request, id) end
end

function Editor:ValidateInput()
    local dialog = self.frame and self.frame.addDialog
    if not dialog then return nil end
    local text = dialog.input:GetText() or ""
    local kind = dialog.actionKind or "spell"
    dialog.icon:Hide()
    local function status(message, isError)
        dialog.status:SetText(message)
        dialog.status:SetTextColor(isError and 1 or 0.85, isError and 0.35 or 0.85, isError and 0.35 or 0.85)
    end
    SetEnabled(dialog.add, false)
    if text == "" then status(""); return nil end
    local id = tonumber(text)
    if not text:match("^%d+$") or not ValidID(id) then
        status(L("Enter a positive whole-number ID."), true); return nil
    end
    if FindAction(addon:GetPriorityActionProfile().actions, kind, id) then
        status(L("This action is already in your priority. Drag its icon to move it."), true); return nil
    end
    local name, icon = addon:GetPriorityActionInfo(kind, id)
    if not name then
        if dialog.requestedKind ~= kind or dialog.requestedID ~= id then
            dialog.requestedKind, dialog.requestedID = kind, id
            RequestActionData(kind, id)
        end
        status(L("No data found. Check the ID and try again."), true); return nil
    end
    dialog.icon:SetTexture(icon or UNKNOWN_ICON); dialog.icon:Show()
    SetEnabled(dialog.add, true)
    status(name .. " (" .. id .. ")")
    return id, kind
end

function Editor:AddAction()
    if self:IsInCombat() then return end
    local id, kind = self:ValidateInput()
    if not id then return end
    local ok, reason = addon:AddPriorityAction(kind, id)
    if not ok then self.frame.addDialog.status:SetText(L(reason or "This action could not be added.")); return end
    self.frame.addDialog:Hide()
    self.frame.input:SetText("")
    self:Refresh()
    self:SetScroll(self.frame.content:GetHeight())
    self:SetStatus()
end

Editor.AddSpell = Editor.AddAction

function Editor:SetScroll(value)
    local frame = self.frame
    local maximum = math.max(0, frame.content:GetHeight() - frame.scroll:GetHeight())
    value = math.max(0, math.min(value, maximum))
    frame.scroll:SetVerticalScroll(value)
    if frame.scroll.ScrollBar then frame.scroll.ScrollBar:SetValue(value) end
end

local function PositionCell(frame, index)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", Editor.frame.content, "TOPLEFT",
        ((index - 1) % COLUMNS) * CELL_WIDTH + 13,
        -(math.floor((index - 1) / COLUMNS) * CELL_HEIGHT + 10))
end

function Editor:ShowActionTooltip(cell)
    if self:GetDragAction() then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    local name = addon:GetPriorityActionInfo(cell.actionKind, cell.actionID)
    if cell.actionKind == "spell" and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(cell.actionID)
    elseif cell.actionKind == "item" and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(cell.actionID)
    else GameTooltip:SetText(name or L("Action %d", cell.actionID), 1, 1, 1) end
    GameTooltip:AddLine(L("Priority %d  |  %s ID: %d", cell.slotIndex, KindLabel(cell.actionKind), cell.actionID), 1, 0.82, 0)
    GameTooltip:AddLine(L("Click to edit conditions. Drag to move."), 0.85, 0.85, 0.85, true)
    GameTooltip:AddLine(L("Uncheck to disable. Right-click to remove."), 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
end

local function MakeIcon(parent)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(SLOT_SIZE, SLOT_SIZE)
    cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints(cell)
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    cell.border = cell:CreateTexture(nil, "OVERLAY")
    cell.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    cell.border:SetSize(80, 80); cell.border:SetPoint("CENTER")
    cell.number = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    cell.number:SetPoint("BOTTOMRIGHT", -3, 3)
    return cell
end

local function MakeCell(content)
    local cell = MakeIcon(content)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:RegisterForDrag("LeftButton")
    cell.enabled = CreateFrame("CheckButton", nil, cell, "UICheckButtonTemplate")
    cell.enabled:SetSize(24, 24); cell.enabled:SetPoint("BOTTOMLEFT", -7, -11)
    cell.enabled:SetScript("OnClick", function(button)
        if cell.actionID and not Editor:GetDragAction() then
            addon:SetPriorityActionEnabled(cell.actionKind, cell.actionID, not not button:GetChecked())
        end
    end)
    cell.enabled:SetScript("OnReceiveDrag", function() Editor:ReceiveDrop(cell.slotIndex) end)
    SetTooltip(cell.enabled, "Include this action in your priority.")
    cell.remove = CreateFrame("Button", nil, cell, "UIPanelCloseButton")
    cell.remove:SetSize(22, 22); cell.remove:SetPoint("TOPRIGHT", 9, 9)
    cell.remove:SetScript("OnClick", function()
        if cell.actionID and not Editor:GetDragAction() then addon:RemovePriorityAction(cell.actionKind, cell.actionID) end
    end)
    cell.remove:SetScript("OnReceiveDrag", function() Editor:ReceiveDrop(cell.slotIndex) end)
    SetTooltip(cell.remove, "Remove this action from your priority.")
    cell:SetScript("OnEnter", function(owner) Editor:ShowActionTooltip(owner); Editor:UpdateDragPreview() end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell:SetScript("OnMouseDown", function(owner) owner.suppressClick = nil end)
    cell:SetScript("OnDragStart", function(owner) Editor:BeginDrag(owner) end)
    cell:SetScript("OnDragStop", function() Editor:EndDrag() end)
    cell:SetScript("OnReceiveDrag", function(owner) Editor:ReceiveDrop(owner.slotIndex) end)
    cell:SetScript("OnClick", function(owner, button)
        if owner.suppressClick and button ~= "RightButton" then owner.suppressClick = nil; return end
        owner.suppressClick = nil
        if Editor:GetDragAction() or (GetCursorInfo and GetCursorInfo()) then Editor:ReceiveDrop(owner.slotIndex)
        elseif button == "RightButton" then addon:RemovePriorityAction(owner.actionKind, owner.actionID)
        else Editor:ShowConditions(owner.actionKind, owner.actionID) end
    end)
    return cell
end

function Editor:RenderGrid(previewIndex, cursorKind, cursorID)
    local frame = self.frame
    if not frame then return end
    local actions, display = addon:GetPriorityActionProfile().actions, {}
    for _, entry in ipairs(actions) do
        if not previewIndex or entry.kind ~= cursorKind or entry.id ~= cursorID then display[#display + 1] = entry end
    end
    if previewIndex then
        previewIndex = math.max(1, math.min(#display + 1, previewIndex))
        table.insert(display, previewIndex, { preview = true })
    end
    for index, entry in ipairs(display) do
        local cell = frame.cells[index] or MakeCell(frame.content)
        frame.cells[index] = cell
        cell.slotIndex, cell.actionKind, cell.actionID = index, entry.kind, entry.id
        cell.spellID = entry.kind == "spell" and entry.id or nil
        PositionCell(cell, index)
        if entry.id then
            local _, icon = addon:GetPriorityActionInfo(entry.kind, entry.id)
            cell.icon:SetTexture(icon or UNKNOWN_ICON)
            cell.icon:SetAlpha(entry.enabled and 1 or 0.35)
            if cell.icon.SetDesaturated then cell.icon:SetDesaturated(not entry.enabled) end
            cell.number:SetText(index)
            cell.enabled:SetChecked(entry.enabled)
            cell.icon:Show(); cell.number:Show(); cell.border:Show(); cell.enabled:Show(); cell.remove:Show()
            cell:Show()
        else
            -- Keep the drag source alive while its replacement ghost is shown.
            cell.icon:Hide(); cell.number:Hide(); cell.border:Hide(); cell.enabled:Hide(); cell.remove:Hide()
            cell:Show()
        end
    end
    for index = #display + 1, #frame.cells do frame.cells[index]:Hide() end
    -- The provider is the final action. The trailing + is an insertion control.
    PositionCell(frame.provider, #display + 1)
    PositionCell(frame.plus, #display + 2)
    frame.plus.slotIndex = #actions + (FindAction(actions, cursorKind, cursorID) and 0 or 1)
    frame.provider.slotIndex = #display + 1
    frame.provider.number:SetText(""); frame.provider.number:Hide()
    local provider = ProviderInfo()
    frame.provider.icon:SetTexture(provider.icon)
    if provider.atlas and frame.provider.icon.SetAtlas then pcall(frame.provider.icon.SetAtlas, frame.provider.icon, provider.atlas) end
    frame.provider.providerInfo = provider
    frame.content:SetHeight(math.max(132, math.ceil((#display + 2) / COLUMNS) * CELL_HEIGHT + 10))
    frame.scroll:UpdateScrollChildRect()
    self:SetScroll(frame.scroll:GetVerticalScroll())
    if previewIndex then
        local _, icon = addon:GetPriorityActionInfo(cursorKind, cursorID)
        frame.preview.index = previewIndex
        frame.preview.icon:SetTexture(icon or UNKNOWN_ICON)
        frame.preview.number:SetText(previewIndex)
        PositionCell(frame.preview, previewIndex)
        frame.preview:Show(); frame.empty:Hide()
    else
        frame.preview.index = nil; frame.preview:Hide()
        frame.empty:Hide()
    end
end

function Editor:GetDropIndex()
    local frame = self.frame
    if not frame or not frame:IsShown() then return nil end
    local kind, id = self:GetDragAction()
    if not kind then return nil end
    local x, y = GetCursorPosition()
    local scroll, content = frame.scroll, frame.content
    local sx, sy = x / scroll:GetEffectiveScale(), y / scroll:GetEffectiveScale()
    local left, right, top, bottom = scroll:GetLeft(), scroll:GetRight(), scroll:GetTop(), scroll:GetBottom()
    if not left or not top or not right or not bottom
        or sx < left or sx > right or sy > top or sy < bottom then return nil end
    local scale, contentLeft, contentTop = content:GetEffectiveScale(), content:GetLeft(), content:GetTop()
    if not contentLeft or not contentTop then return nil end
    local localX, localY = x / scale - contentLeft, contentTop - y / scale
    if localX < 0 or localX >= GRID_WIDTH or localY < 0 then return nil end
    local column, row = math.floor(localX / CELL_WIDTH), math.floor(localY / CELL_HEIGHT)
    local actions = addon:GetPriorityActionProfile().actions
    local maximum = #actions + (FindAction(actions, kind, id) and 0 or 1)
    return math.max(1, math.min(maximum, row * COLUMNS + column + 1))
end

function Editor:UpdateDragPreview()
    local frame = self.frame
    if not frame or not frame:IsShown() or self.picking or self.committing then return end
    local kind, id = self:GetDragAction()
    if self.drag and (self.drag.profile ~= addon:GetPriorityActionProfile() or kind ~= self.drag.kind or id ~= self.drag.id) then
        self:CancelDrag(); return
    end
    local index = kind and self:GetDropIndex() or nil
    if index and not FindAction(addon:GetPriorityActionProfile().actions, kind, id)
        and not addon:GetPriorityActionInfo(kind, id) then
        index = nil
        if self.requestedCursorKind ~= kind or self.requestedCursorID ~= id then
            self.requestedCursorKind, self.requestedCursorID = kind, id
            RequestActionData(kind, id)
        end
    end
    if index == self.previewIndex and kind == self.previewKind and id == self.previewID then return end
    self.previewIndex, self.previewKind, self.previewID = index, kind, id
    self:RenderGrid(index, kind, id)
    if index then GameTooltip:Hide() end
end

function Editor:CancelDrag(clearCursor)
    local drag = self.drag
    self.drag, self.previewIndex, self.previewKind, self.previewID = nil, nil, nil, nil
    local kind, id = self:GetCursorAction()
    if clearCursor ~= false and drag and kind == drag.kind and id == drag.id and ClearCursor then ClearCursor() end
    if self.frame then self:RenderGrid() end
end

function Editor:BeginDrag(cell)
    if not cell.actionID or self.drag or (GetCursorInfo and GetCursorInfo()) then return end
    cell.suppressClick = true
    local drag = { kind = cell.actionKind, id = cell.actionID, profile = addon:GetPriorityActionProfile() }
    self.drag = drag
    self.frame.input:ClearFocus()
    local pickup = cell.actionKind == "spell" and ((C_Spell and C_Spell.PickupSpell) or PickupSpell)
        or cell.actionKind == "item" and ((C_Item and C_Item.PickupItem) or PickupItem)
    self.picking = true
    if type(pickup) == "function" then pcall(pickup, cell.actionID) end
    self.picking = nil
    local kind, id = self:GetCursorAction()
    drag.nativeCursor = kind == drag.kind and id == drag.id
    if kind and not drag.nativeCursor then self:CancelDrag(false); return end
    self:UpdateDragPreview()
end

function Editor:EndDrag()
    local drag = self.drag
    if not drag then return end
    local destination = self:GetDropIndex()
    local function finish()
        if self.drag ~= drag then return end
        if destination then self:ReceiveDrop(destination) else self:CancelDrag() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, finish) else finish() end
end

function Editor:ReceiveDrop(index)
    if not self.frame or not self.frame:IsShown() then self:CancelDrag(); return false end
    if self.drag and self.drag.profile ~= addon:GetPriorityActionProfile() then self:CancelDrag(); return false end
    local kind, id = self:GetDragAction()
    index = index or self:GetDropIndex()
    if not kind then
        self:CancelDrag(false)
        self:SetStatus("Drag an individual spell or item here. Flyouts and pet abilities cannot be added.", true)
        return false
    end
    if not index then self:CancelDrag(); return false end
    self.committing = true
    local ok, reason = addon:PlacePriorityAction(kind, id, index)
    self.committing = nil
    if not ok then self:CancelDrag(false); self:SetStatus(reason or "This action could not be added.", true); return false end
    self.drag, self.previewIndex, self.previewKind, self.previewID = nil, nil, nil, nil
    if ClearCursor then ClearCursor() end
    self:Refresh()
    self:SetStatus()
    return true
end

local function MakeDialog(name, parent, width, height, title, onClose)
    local dialog = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    dialog:SetSize(width, height); dialog:SetPoint("CENTER", parent, "CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG"); dialog:SetFrameLevel(parent:GetFrameLevel() + 20)
    dialog:SetToplevel(true); dialog:SetClampedToScreen(true); dialog:EnableMouse(true)
    dialog:SetBackdrop(BACKDROP)
    dialog.title = Label(dialog, title, "GameFontNormalLarge")
    dialog.title:SetPoint("TOPLEFT", 22, -20)
    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", onClose or function() dialog:Hide() end)
    dialog.close = close
    dialog:Hide()
    return dialog
end

function Editor:RefreshRotationBuilderLink()
    local conditions = self.frame and self.frame.conditionsDialog
    local dialog = conditions and conditions.linkDialog
    if not dialog then return end
    dialog.url = BUILDER_URLS[Locale()] or BUILDER_URLS.enUS
    dialog.title:SetText("Rotation Builder")
    dialog.hint:SetText(L("Press Ctrl+C to copy the link."))
    dialog.dismiss:SetText(L("Close"))
    dialog.input:SetText(dialog.url)
    if dialog:IsVisible() then dialog.input:SetFocus(); dialog.input:HighlightText() end
end

function Editor:ShowRotationBuilderLink()
    local conditions = self.frame and self.frame.conditionsDialog
    if not conditions then return false end
    local profile = addon:GetPriorityActionProfile()
    local _, action = FindAction(profile.actions, conditions.actionKind, conditions.actionID)
    if conditions.profile ~= profile or conditions.action ~= action or not action then return false end
    if self:IsInCombat() then
        local pending = self.pendingRestore
        if conditions:IsVisible() or (pending and pending.conditions and pending.keepDraft
                and pending.kind == conditions.actionKind and pending.id == conditions.actionID) then
            self:DeferOpen("conditions", conditions.actionKind, conditions.actionID)
            self.pendingRestore.builderLink = true
        end
        return false
    end
    if not self.frame:IsShown() or not conditions:IsShown() then return false end
    self:HideConditionHelp()
    if CloseDropDownMenus then CloseDropDownMenus() end
    for _, row in ipairs(conditions.rows or {}) do
        for _, field in pairs(row.controls) do
            if field.definition.kind == "number" then field.widget:ClearFocus() end
        end
    end
    if not conditions.linkDialog then
        local dialog = MakeDialog("WoWHACv5RotationBuilderLink", conditions, 420, 166,
            "Rotation Builder", function() self:CloseRotationBuilderLink() end)
        conditions.linkDialog = dialog
        dialog.hint = Label(dialog, "Press Ctrl+C to copy the link.")
        dialog.hint:SetPoint("TOPLEFT", 28, -51); dialog.hint:SetSize(364, 20)
        dialog.input = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
        dialog.input:SetPoint("TOPLEFT", 30, -80); dialog.input:SetSize(360, 24)
        dialog.input:SetAutoFocus(false); dialog.input:SetMaxLetters(128)
        dialog.input:SetScript("OnTextChanged", function(input)
            if dialog.url and input:GetText() ~= dialog.url then
                input:SetText(dialog.url)
                input:HighlightText()
            end
        end)
        dialog.input:SetScript("OnEditFocusGained", function(input) input:HighlightText() end)
        dialog.input:SetScript("OnMouseUp", function(input) input:SetFocus(); input:HighlightText() end)
        dialog.input:SetScript("OnEscapePressed", function() self:CloseRotationBuilderLink() end)
        dialog.input:SetScript("OnEnterPressed", function() self:CloseRotationBuilderLink() end)
        dialog.dismiss = MakeButton(dialog, "Close", 84, function() self:CloseRotationBuilderLink() end)
        dialog.dismiss:SetPoint("BOTTOMRIGHT", -20, 16)
        dialog:SetScript("OnHide", function()
            dialog.input:ClearFocus()
            if self.pendingRestore and not self.combatHiding then self.pendingRestore.builderLink = nil end
        end)
    end
    local dialog = conditions.linkDialog
    self:RefreshRotationBuilderLink()
    dialog:Show(); dialog:Raise()
    dialog.input:SetFocus(); dialog.input:HighlightText()
    return true
end

function Editor:CreateAddDialog()
    local frame = self.frame
    local dialog = MakeDialog("WoWHACv5PriorityActionAdd", frame, 350, 224, "Add priority action",
        function() self:CloseAddDialog() end)
    frame.addDialog = dialog
    dialog.actionKind = "spell"
    dialog.kindButtons = {}
    for index, kind in ipairs({ "spell", "item" }) do
        local button = CreateFrame("CheckButton", nil, dialog, "UIRadioButtonTemplate")
        button:SetSize(20, 20); button:SetPoint("TOPLEFT", 24 + (index - 1) * 120, -57)
        button:SetHitRectInsets(0, -70, 0, 0)
        button.label = Label(button, KindLabel(kind), "GameFontHighlight")
        button.label:SetPoint("LEFT", button, "RIGHT", 5, 0)
        dialog.kindButtons[kind] = button
        button:SetScript("OnClick", function() self:SetAddKind(kind) end)
    end
    dialog.kindButtons.spell:SetChecked(true)
    local idLabel = Label(dialog, "ID", "GameFontNormal"); dialog.idLabel = idLabel
    idLabel:SetPoint("TOPLEFT", 26, -98)
    dialog.input = CreateFrame("EditBox", "WoWHACv5PriorityActionID", dialog, "InputBoxTemplate")
    dialog.input:SetSize(180, 24); dialog.input:SetPoint("LEFT", idLabel, "RIGHT", 18, 0)
    dialog.input:SetAutoFocus(false); dialog.input:SetMaxLetters(10)
    dialog.input:SetScript("OnTextChanged", function() self:ValidateInput() end)
    dialog.input:SetScript("OnEnterPressed", function() self:AddAction() end)
    dialog.input:SetScript("OnEscapePressed", function() self:CloseAddDialog() end)
    dialog.icon = dialog:CreateTexture(nil, "ARTWORK")
    dialog.icon:SetSize(24, 24); dialog.icon:SetPoint("LEFT", dialog.input, "RIGHT", 14, 0)
    dialog.status = Label(dialog, "")
    dialog.status:SetPoint("TOPLEFT", 26, -125); dialog.status:SetSize(298, 42); dialog.status:SetJustifyV("TOP")
    dialog.add = MakeButton(dialog, "Add", 84, function() self:AddAction() end)
    dialog.add:SetPoint("BOTTOMRIGHT", -22, 19)
    dialog.cancel = MakeButton(dialog, "Cancel", 84, function() self:CloseAddDialog() end)
    dialog.cancel:SetPoint("RIGHT", dialog.add, "LEFT", -8, 0)
    dialog:SetScript("OnHide", function() dialog.input:ClearFocus() end)
    frame.input, frame.add, frame.inputIcon = dialog.input, dialog.add, dialog.icon
    self:ValidateInput()
end

function Editor:SetAddKind(kind)
    if kind ~= "spell" and kind ~= "item" then return end
    local dialog = self.frame.addDialog
    dialog.actionKind = kind
    for value, button in pairs(dialog.kindButtons) do button:SetChecked(value == kind) end
    self:ValidateInput()
end

function Editor:ShowAddDialog()
    if self:IsInCombat() then return self:DeferOpen("add") end
    if not self.frame or not self.frame:IsShown() then addon:ShowPriorityActionsEditor() end
    self:CloseConditions()
    self.frame.addDialog:Show(); self.frame.addDialog:Raise()
    self.frame.input:SetFocus(); self.frame.input:HighlightText()
    self:ValidateInput()
    return true
end

function Editor:FitEditorToScreen()
    local frame = self.frame
    if not frame or self.fitting or self:IsInCombat() then return end
    self.fitting = true
    local docked = frame.conditionsDialog and frame.conditionsDialog:IsShown()
    local dockWidth = docked and (CONDITIONS_WIDTH + DOCK_GAP) or 0
    local parentScale = UIParent:GetEffectiveScale()
    local oldScale = frame:GetEffectiveScale() / parentScale
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local left, top = frame:GetLeft(), frame:GetTop()
    left = left and left * oldScale or (screenWidth - PANEL_WIDTH * oldScale) / 2
    top = top and top * oldScale or (screenHeight + PANEL_HEIGHT * oldScale) / 2
    self.baseScale = self.baseScale or (frame.GetScale and frame:GetScale()) or oldScale
    local scale = math.min(self.baseScale, (screenWidth - 24) / (PANEL_WIDTH + dockWidth), (screenHeight - 24) / PANEL_HEIGHT)
    scale = math.max(0.1, scale)
    frame:SetScale(scale)
    -- Positive right inset expands the main frame's clamped rectangle to
    -- include its attached child, so native dragging keeps the pair on screen.
    if frame.SetClampRectInsets then frame:SetClampRectInsets(0, dockWidth, 0, 0) end
    left = math.max(12, math.min(left, screenWidth - (PANEL_WIDTH + dockWidth) * scale - 12))
    top = math.min(screenHeight - 12, math.max(top, PANEL_HEIGHT * scale + 12))
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
    self.fitting = nil
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- Use Blizzard's dropdown implementation; SelectValue also provides one
-- deterministic path for keyboard/client adapters and the regression harness.
local choiceSerial = 0
local function MakeChoice(parent, width, values, callback)
    choiceSerial = choiceSerial + 1
    local choice = CreateFrame("Frame", "WoWHACv5PriorityChoice" .. choiceSerial, parent, "UIDropDownMenuTemplate")
    choice:SetSize(width + 28, 32)
    choice.values = values
    -- Scope the list elevation to this dropdown, using Blizzard's API rather
    -- than changing the shared DropDownList frames used by other addons.
    if UIDropDownMenu_SetFrameStrata then UIDropDownMenu_SetFrameStrata(choice, "TOOLTIP") end
    function choice:SelectValue(value, silent)
        self.value = value
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, value) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, self.values[value] or tostring(value or "")) end
        if not silent then callback(value) end
    end
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(choice, width) end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(choice, function()
            local keys = {}
            for key in pairs(choice.values) do keys[#keys + 1] = key end
            local rank = { player = 1, pet = 2, mouseover = 3, target = 4, lt = 1, lte = 2, eq = 3, gte = 4, gt = 5 }
            table.sort(keys, function(a, b)
                if rank[a] and rank[b] then return rank[a] < rank[b] end
                return tostring(choice.values[a]) < tostring(choice.values[b])
            end)
            for _, key in ipairs(keys) do
                local value = key
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value, info.checked = choice.values[value], value, choice.value == value
                info.func = function() choice:SelectValue(value) end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    return choice
end

function Editor:SetConditionScroll(value)
    local dialog = self.frame.conditionsDialog
    self:HideConditionHelp()
    local maximum = math.max(0, dialog.content:GetHeight() - dialog.scroll:GetHeight())
    value = math.max(0, math.min(value, maximum))
    dialog.scroll:SetVerticalScroll(value)
    if dialog.scroll.ScrollBar then dialog.scroll.ScrollBar:SetValue(value) end
end

function Editor:HideConditionHelp()
    local owner = self.conditionHelpOwner
    if owner and (not GameTooltip.IsOwned or GameTooltip:IsOwned(owner)) then GameTooltip:Hide() end
    self.conditionHelpOwner = nil
end

local function UpdateConditionDraft(dialog)
    local active = {}
    for _, option in ipairs(dialog.options or {}) do
        if option.enabled then active[#active + 1] = option end
    end
    table.sort(active, function(a, b) return a.order < b.order end)
    dialog.draft = {}
    for _, option in ipairs(active) do dialog.draft[#dialog.draft + 1] = option.condition end
    return active
end

function Editor:ValidateConditionDraft()
    local dialog = self.frame and self.frame.conditionsDialog
    if not dialog then return false end
    UpdateConditionDraft(dialog)
    local ok, reason = addon:ValidatePriorityConditions(dialog.draft)
    dialog.status:SetText(ok and "" or L(reason or "Check the condition values."))
    dialog.status:SetTextColor(ok and 0.85 or 1, ok and 0.85 or 0.35, ok and 0.85 or 0.35)
    return ok
end

local function SetArgumentEnabled(field, enabled)
    local widget = field.widget
    widget:SetAlpha(enabled and 1 or 0.45)
    if field.definition.kind == "select" then
        if enabled and UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(widget)
        elseif not enabled and UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(widget) end
        widget:EnableMouse(enabled)
    else
        SetEnabled(widget, enabled)
        if not enabled and field.definition.kind == "number" then widget:ClearFocus() end
    end
    if field.label then field.label:SetAlpha(enabled and 1 or 0.45) end
end

local function MakeConditionRow(dialog, definition)
    local row = CreateFrame("Frame", nil, dialog.content)
    row:SetSize(CONDITIONS_WIDTH - 62, CONDITION_ROW_HEIGHT)
    row:EnableMouse(true)
    row.controls = {}
    row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.enabled:SetSize(24, 24); row.enabled:SetPoint("LEFT", 0, 0)
    row.enabled:SetScript("OnClick", function(button)
        Editor:SetConditionEnabled(row.index, not not button:GetChecked())
    end)
    row.title = Label(row, definition.label, "GameFontHighlightSmall")
    row.title:SetPoint("LEFT", row.enabled, "RIGHT", 2, 0)
    local titleWidth = math.min(definition.type == "aura" and 104 or 132, math.ceil(row.title:GetStringWidth()))
    row.title:SetWidth(titleWidth); row.title:SetWordWrap(false)
    -- The checkbox includes its label, but ends before the separate help target.
    row.enabled:SetHitRectInsets(0, -(titleWidth + 2), 0, 0)
    row.help = CreateFrame("Button", nil, row)
    row.help:SetSize(20, 20); row.help:SetPoint("LEFT", row.title, "RIGHT", 4, 0)
    row.help.icon = row.help:CreateTexture(nil, "ARTWORK")
    row.help.icon:SetSize(16, 16); row.help.icon:SetPoint("CENTER")
    -- Blizzard's empty radio ring supplies the native circle; the literal
    -- question mark keeps this distinct from its separate information icon.
    row.help.icon:SetTexture("Interface\\Buttons\\UI-RadioButton")
    row.help.icon:SetTexCoord(0, 0.25, 0, 1)
    local highlight = row.help:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(16, 16); highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Buttons\\UI-RadioButton")
    highlight:SetTexCoord(0.5, 0.75, 0, 1)
    row.help:SetHighlightTexture(highlight, "ADD")
    row.help.mark = Label(row.help, "?", "GameFontNormalSmall")
    row.help.mark:SetPoint("CENTER", 0, 0)
    row.help:SetScript("OnEnter", function(owner)
        Editor:HideConditionHelp()
        Editor.conditionHelpOwner = owner
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(definition.label, 1, 0.82, 0)
        GameTooltip:AddLine(definition.description or definition.label, 1, 1, 1, true)
        if definition.available == false then
            GameTooltip:AddLine(definition.unavailableReason or
                L("This condition is unavailable on this client. The action will be skipped."), 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    local function hideHelp()
        if Editor.conditionHelpOwner == row.help then Editor:HideConditionHelp() end
    end
    row.help:SetScript("OnLeave", hideHelp)
    row.help:SetScript("OnHide", hideHelp)
    -- Aura needs room for two native dropdowns and a full ten-digit spell ID.
    local x = definition.type == "aura" and 170 or 200
    for _, field in ipairs(definition.fields or {}) do
        local fieldKey = field.key
        local control, suffix, step
        if field.kind == "select" then
            local width = fieldKey == "unit" and (definition.type == "combat" and 128 or 86)
                or fieldKey == "state" and 70 or 82
            control = MakeChoice(row, width, field.values, function(value)
                if not row.option.enabled or Editor:IsInCombat() then return end
                row.condition[fieldKey] = value; Editor:ApplyConditions()
            end)
            control:SetPoint("LEFT", row, "LEFT", x - 16, 0)
            -- The native dropdown frame includes 50px of chrome and padding.
            -- Reserve its full hit rectangle, including the arrow button.
            step = width + 50
        elseif field.kind == "boolean" then
            control = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            control:SetSize(22, 22); control:SetPoint("LEFT", row, "LEFT", x, 0)
            suffix = Label(row, fieldKey == "perTarget" and "per target" or field.label)
            suffix:SetPoint("LEFT", control, "RIGHT", 1, 0)
            control:SetHitRectInsets(0, -60, 0, 0)
            control:SetScript("OnClick", function(button)
                if not row.option.enabled or Editor:IsInCombat() then return end
                row.condition[fieldKey] = not not button:GetChecked(); Editor:ApplyConditions()
            end)
            step = 88
        else
            local width = (fieldKey == "windowMs" or fieldKey == "spellID") and 84
                or fieldKey == "allowance" and 70 or 50
            control = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            control:SetSize(width, 20); control:SetPoint("LEFT", row, "LEFT", x + 5, 0)
            control:SetAutoFocus(false); control:SetMaxLetters(10)
            control:SetScript("OnTextChanged", function(input)
                if dialog.rendering or not row.option.enabled or Editor:IsInCombat() then return end
                local text = input:GetText()
                -- Incomplete text must remain invalid instead of requesting a
                -- default from the normalizer. Unchecked rules are not saved.
                row.condition[fieldKey] = tonumber(text) or text
                Editor:ApplyConditions()
            end)
            control:SetScript("OnEnterPressed", function(input) input:ClearFocus() end)
            control:SetScript("OnEscapePressed", function() Editor:CloseConditions() end)
            local units = fieldKey == "spellID" and "ID" or fieldKey == "seconds" and "s" or fieldKey == "windowMs" and "ms"
                or fieldKey == "allowance" and "uses /" or definition.type == "enemies" and "enemies" or "%"
            suffix = Label(row, units)
            suffix:SetPoint("LEFT", control, "RIGHT", 5, 0)
            step = width + (fieldKey == "allowance" and 44 or 29)
        end
        local fieldHelp = field.label
        if field.min and field.max then fieldHelp = L("%s: %s to %s", fieldHelp, field.min, field.max) end
        SetTooltip(control, fieldHelp)
        row.controls[fieldKey] = { widget = control, definition = field, label = suffix }
        x = x + step
    end
    return row
end

function Editor:RenderConditions(inputTexts)
    local dialog = self.frame.conditionsDialog
    self:HideConditionHelp()
    dialog.rendering = true
    for _, row in pairs(dialog.rowCache) do row:Hide() end
    dialog.rows = {}
    local occurrences = {}
    for index, option in ipairs(dialog.options) do
        local condition = option.condition
        local definition = dialog.definitions[condition.type] or {
            label = L("Unavailable condition"), description = L("Uncheck this condition to remove it."), fields = {},
        }
        occurrences[condition.type] = (occurrences[condition.type] or 0) + 1
        local cacheKey = condition.type .. ":" .. occurrences[condition.type]
        local row = dialog.rowCache[cacheKey] or MakeConditionRow(dialog, definition)
        dialog.rowCache[cacheKey] = row
        dialog.rows[index] = row
        row.condition, row.option, row.index = condition, option, index
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(index - 1) * CONDITION_ROW_HEIGHT)
        row.enabled:SetChecked(option.enabled)
        for key, field in pairs(row.controls) do
            if field.definition.kind == "select" then field.widget:SelectValue(condition[key], true)
            elseif field.definition.kind == "boolean" then field.widget:SetChecked(condition[key] == true)
            else
                local value = condition[key]
                if key == "spellID" and value == 0 then value = nil end
                local texts = inputTexts and inputTexts[option]
                field.widget:SetText(texts and texts[key] or (value == nil and "" or tostring(value)))
            end
            SetArgumentEnabled(field, option.enabled)
        end
        row:Show()
    end
    dialog.content:SetHeight(math.max(CONDITION_ROW_HEIGHT, #dialog.options * CONDITION_ROW_HEIGHT))
    dialog.scroll:UpdateScrollChildRect()
    self:SetConditionScroll(dialog.scroll:GetVerticalScroll())
    dialog.rendering = nil
    self:ValidateConditionDraft()
end

function Editor:SetConditionEnabled(rowIndex, enabled)
    local dialog = self.frame and self.frame.conditionsDialog
    local option = dialog and dialog.options and dialog.options[rowIndex]
    if not option or self:IsInCombat() then return false end
    option.enabled = enabled == true
    if option.enabled and not option.order then
        dialog.nextConditionOrder = dialog.nextConditionOrder + 1
        option.order = dialog.nextConditionOrder
    end
    self:HideConditionHelp()
    local row = dialog.rows[rowIndex]
    row.enabled:SetChecked(option.enabled)
    for _, field in pairs(row.controls) do SetArgumentEnabled(field, option.enabled) end
    self:ApplyConditions()
    return true
end

-- Retain the existing programmatic entry point. The checklist itself needs
-- no Add menu: each catalog rule is present, and saved duplicates stay intact.
function Editor:AddCondition(conditionType)
    local dialog = self.frame and self.frame.conditionsDialog
    if not dialog or self:IsInCombat() then return false end
    for index, option in ipairs(dialog.options) do
        if option.condition.type == conditionType and not option.enabled then
            return self:SetConditionEnabled(index, true)
        end
    end
    return false
end

function Editor:ApplyConditions()
    local dialog = self.frame and self.frame.conditionsDialog
    if not dialog or not dialog:IsShown() or not self.frame:IsShown() or self:IsInCombat() or self.committing then return false end
    local profile = addon:GetPriorityActionProfile()
    local _, action = FindAction(profile.actions, dialog.actionKind, dialog.actionID)
    if dialog.profile ~= profile or dialog.action ~= action then self:CloseConditions(); return false end
    local valid = self:ValidateConditionDraft()
    local conditions, applied = {}, {}
    for _, option in ipairs(UpdateConditionDraft(dialog)) do
        local normalized = addon.PriorityConditions.Validate({ option.condition })
        -- Preserve this row's last usable settings during incomplete input.
        -- Other rows still apply immediately; a new invalid row waits for input.
        local condition = normalized and normalized[1] or option.applied
        if condition then
            conditions[#conditions + 1] = condition
            applied[option] = condition
        end
    end
    if not Equal(conditions, action.conditions) then
        self.committing = true
        local ok, reason = addon:SetPriorityActionConditions(dialog.actionKind, dialog.actionID, conditions)
        self.committing = nil
        if not ok then
            dialog.status:SetText(L(reason or "The conditions could not be applied."))
            dialog.status:SetTextColor(1, 0.35, 0.35)
            return false
        end
        self:RenderGrid()
    end
    for option, condition in pairs(applied) do option.applied = Copy(condition) end
    return valid
end

function Editor:CreateConditionsDialog()
    local dialog = MakeDialog("WoWHACv5PriorityActionConditions", self.frame, CONDITIONS_WIDTH, PANEL_HEIGHT,
        "Action conditions", function() self:CloseConditions() end)
    self.frame.conditionsDialog = dialog
    dialog:SetClampedToScreen(false)
    dialog:ClearAllPoints(); dialog:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", DOCK_GAP, 0)
    dialog.definitions, dialog.rowCache = {}, {}
    dialog.locale, dialog.localeRowCaches = Locale(), {}
    dialog.localeRowCaches[dialog.locale] = dialog.rowCache
    dialog.catalog = addon:GetPriorityConditionCatalog()
    for _, definition in ipairs(dialog.catalog) do dialog.definitions[definition.type] = definition end
    dialog.icon = dialog:CreateTexture(nil, "ARTWORK")
    dialog.icon:SetSize(26, 26); dialog.icon:SetPoint("TOPLEFT", 26, -51)
    dialog.actionName = Label(dialog, "", "GameFontHighlight")
    dialog.actionName:SetPoint("LEFT", dialog.icon, "RIGHT", 10, 0); dialog.actionName:SetWidth(CONDITIONS_WIDTH - 90)
    dialog.scroll = CreateFrame("ScrollFrame", "WoWHACv5PriorityConditionsScroll", dialog, "UIPanelScrollFrameTemplate")
    dialog.scroll:SetPoint("TOPLEFT", 24, -88); dialog.scroll:SetSize(CONDITIONS_WIDTH - 62, 314)
    dialog.content = CreateFrame("Frame", nil, dialog.scroll); dialog.content:SetSize(CONDITIONS_WIDTH - 62, CONDITION_ROW_HEIGHT)
    dialog.scroll:SetScrollChild(dialog.content); dialog.scroll:EnableMouseWheel(true)
    dialog.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        self:SetConditionScroll(scroll:GetVerticalScroll() - delta * CONDITION_ROW_HEIGHT * 2)
    end)
    local onVerticalScroll = dialog.scroll:GetScript("OnVerticalScroll")
    dialog.scroll:SetScript("OnVerticalScroll", function(scroll, offset)
        if onVerticalScroll then onVerticalScroll(scroll, offset) end
        self:HideConditionHelp()
    end)
    dialog.status = Label(dialog, "")
    dialog.status:SetPoint("BOTTOMLEFT", 28, 54); dialog.status:SetSize(CONDITIONS_WIDTH - 54, 20)
    dialog.status:SetJustifyV("TOP")
    dialog.builderHint = Label(dialog, BUILDER_HINT)
    dialog.builderHint:SetPoint("BOTTOMLEFT", 28, 22)
    dialog.builderHint:SetSize(dialog.builderHint:GetStringWidth(), 24)
    dialog.builderHint:SetJustifyV("MIDDLE"); dialog.builderHint:SetWordWrap(false)
    dialog.builderLink = CreateFrame("Button", nil, dialog)
    dialog.builderLink:SetPoint("LEFT", dialog.builderHint, "RIGHT", 4, 0); dialog.builderLink:SetSize(100, 24)
    dialog.builderLink:SetNormalFontObject("GameFontNormalSmall")
    dialog.builderLink:SetHighlightFontObject("GameFontHighlightSmall")
    dialog.builderLink:SetText("Rotation Builder")
    local builderText = dialog.builderLink:GetFontString()
    builderText:ClearAllPoints(); builderText:SetPoint("LEFT", 0, 0); builderText:SetJustifyH("LEFT")
    dialog.builderLink:SetScript("OnClick", function() self:ShowRotationBuilderLink() end)
    dialog:SetScript("OnShow", function() self:FitEditorToScreen() end)
    dialog:SetScript("OnHide", function()
        self:CloseRotationBuilderLink()
        self:HideConditionHelp()
        for _, row in pairs(dialog.rowCache) do
            for _, field in pairs(row.controls) do
                if field.definition.kind == "number" then field.widget:ClearFocus() end
            end
        end
        if CloseDropDownMenus then CloseDropDownMenus() end
        self:FitEditorToScreen()
    end)
end

function Editor:ShowConditions(kind, id)
    local profile = addon:GetPriorityActionProfile()
    local _, action = FindAction(profile.actions, kind, id)
    if not action then return false end
    if self:IsInCombat() then return self:DeferOpen("conditions", kind, id) end
    if not self.frame or not self.frame:IsShown() then addon:ShowPriorityActionsEditor() end
    if not self.frame.conditionsDialog then self:CreateConditionsDialog() end
    self:CloseAddDialog()
    self:CloseRotationBuilderLink()
    local dialog = self.frame.conditionsDialog
    dialog.actionKind, dialog.actionID, dialog.profile, dialog.action = kind, id, profile, action
    dialog.options, dialog.nextConditionOrder = {}, #(action.conditions or {})
    local grouped = {}
    for index, condition in ipairs(action.conditions or {}) do
        local option = { condition = Copy(condition), applied = Copy(condition), enabled = true, order = index }
        grouped[condition.type] = grouped[condition.type] or {}
        grouped[condition.type][#grouped[condition.type] + 1] = option
    end
    for _, definition in ipairs(dialog.catalog) do
        local existing = grouped[definition.type]
        if existing then
            for _, option in ipairs(existing) do dialog.options[#dialog.options + 1] = option end
            grouped[definition.type] = nil
        else
            local condition = Copy(definition.defaults or {}); condition.type = definition.type
            dialog.options[#dialog.options + 1] = { condition = condition, enabled = false }
        end
    end
    -- Unknown saved rules remain visible and checked until explicitly removed.
    for _, existing in pairs(grouped) do
        for _, option in ipairs(existing) do dialog.options[#dialog.options + 1] = option end
    end
    local name, icon = addon:GetPriorityActionInfo(kind, id)
    dialog.actionName:SetText(L("%s  |  %s ID: %d", name or L("Action"), KindLabel(kind), id))
    dialog.icon:SetTexture(icon or UNKNOWN_ICON)
    self:RenderConditions(); self:SetConditionScroll(0)
    dialog:Show(); dialog:Raise(); self:FitEditorToScreen()
    return true
end

function Editor:Refresh()
    local frame = self.frame
    if not frame or self.committing then return end
    local profile = addon:GetPriorityActionProfile()
    if self.displayProfile and self.displayProfile ~= profile then
        self:CancelDrag(); self:SetScroll(0)
        frame.addDialog:Hide()
        if frame.conditionsDialog then frame.conditionsDialog:Hide() end
    end
    self.displayProfile = profile
    frame.master:SetChecked(profile.enabled)
    self.previewIndex, self.previewKind, self.previewID = nil, nil, nil
    self:RenderGrid(); self:ValidateInput()
    if frame.conditionsDialog and frame.conditionsDialog:IsShown() then
        local dialog = frame.conditionsDialog
        if not FindAction(profile.actions, dialog.actionKind, dialog.actionID) then dialog:Hide() end
    end
end

function Editor:OnSpecializationChanged(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
    self:CancelDrag()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function Editor:OnProviderChanged()
    self:CancelDrag()
    self:Refresh()
end

function Editor:RefreshLanguage()
    if self:IsInCombat() then self.languageDirty = true; return end
    self.languageDirty = nil
    local frame = self.frame
    if not frame then return end
    self:HideConditionHelp()
    GameTooltip:Hide()
    if CloseDropDownMenus then CloseDropDownMenus() end
    frame.title:SetText(L("Priority actions"))
    frame.masterLabel:SetText(L("Enable priority actions"))
    frame.hint:SetText(L("Drag spells or items here."))
    frame.plus.label:SetText(L("Add action"))
    frame.provider.label:SetText(L("Provider"))
    frame.done:SetText(L("Done"))
    local add = frame.addDialog
    add.title:SetText(L("Add priority action"))
    add.idLabel:SetText(L("ID"))
    add.add:SetText(L("Add")); add.cancel:SetText(L("Cancel"))
    for kind, button in pairs(add.kindButtons) do button.label:SetText(KindLabel(kind)) end
    self:ValidateInput()
    self:SetStatus(self.statusKey, self.statusIsError)
    local dialog = frame.conditionsDialog
    if dialog then
        local scroll, inputTexts, focused = dialog.scroll:GetVerticalScroll(), {}, nil
        for _, row in ipairs(dialog.rows or {}) do
            local texts = {}; inputTexts[row.option] = texts
            for key, field in pairs(row.controls) do
                if field.definition.kind == "number" then
                    texts[key] = field.widget:GetText()
                    if field.widget.HasFocus and field.widget:HasFocus() then focused = { option = row.option, key = key } end
                    field.widget:ClearFocus()
                end
            end
        end
        for _, row in pairs(dialog.rowCache) do row:Hide() end
        dialog.locale = Locale()
        dialog.rowCache = dialog.localeRowCaches[dialog.locale] or {}
        dialog.localeRowCaches[dialog.locale] = dialog.rowCache
        dialog.catalog, dialog.definitions = addon:GetPriorityConditionCatalog(), {}
        for _, definition in ipairs(dialog.catalog) do dialog.definitions[definition.type] = definition end
        dialog.title:SetText(L("Action conditions"))
        dialog.builderHint:SetText(L(BUILDER_HINT))
        dialog.builderHint:SetWidth(dialog.builderHint:GetStringWidth())
        if dialog.actionID then
            local name = addon:GetPriorityActionInfo(dialog.actionKind, dialog.actionID)
            dialog.actionName:SetText(L("%s  |  %s ID: %d", name or L("Action"), KindLabel(dialog.actionKind), dialog.actionID))
        end
        if dialog.options then
            self:RenderConditions(inputTexts); self:SetConditionScroll(scroll)
            if focused and dialog:IsVisible() then
                for _, row in ipairs(dialog.rows) do
                    if row.option == focused.option then row.controls[focused.key].widget:SetFocus(); break end
                end
            end
        end
        self:RefreshRotationBuilderLink()
    end
    self:RenderGrid(self.previewIndex, self.previewKind, self.previewID)
end

function Editor:OnUpdate(elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.03 then return end
    local step = self.elapsed
    self.elapsed = 0
    if self:GetDragAction() and self:GetDropIndex() then
        local scroll = self.frame.scroll
        local _, y = GetCursorPosition(); y = y / scroll:GetEffectiveScale()
        local direction = y > scroll:GetTop() - 18 and -1 or y < scroll:GetBottom() + 18 and 1 or 0
        if direction ~= 0 then self:SetScroll(scroll:GetVerticalScroll() + direction * 180 * step) end
    end
    self:UpdateDragPreview()
end

function Editor:HandleEscape()
    local frame = self.frame
    if not frame or not frame:IsShown() then return false end
    local conditions = frame.conditionsDialog
    if conditions and conditions.linkDialog and conditions.linkDialog:IsShown() then self:CloseRotationBuilderLink()
    elseif conditions and conditions:IsShown() then self:CloseConditions()
    elseif frame.addDialog:IsShown() then self:CloseAddDialog()
    else self:Close() end
    return true
end

function Editor:InitializeEscapeHandling()
    if self.escapeHandlerReady then return end
    local frame = self.frame
    if type(RegisterGameMenuEscHandler) == "function" and GameMenuEscPriority and GameMenuEscPriority.AddOn then
        RegisterGameMenuEscHandler(GameMenuEscPriority.AddOn, function() return self:HandleEscape() end)
    elseif frame.SetPropagateKeyboardInput then
        if InCombatLockdown and InCombatLockdown() then return end
        frame:SetPropagateKeyboardInput(true); frame:EnableKeyboard(true)
        frame:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then self:HandleEscape() end end)
    end
    self.escapeHandlerReady = true
end

function Editor:Create()
    if self:IsInCombat() then return false end
    local frame = CreateFrame("Frame", "WoWHACv5OffensiveCooldownEditor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.frame = frame
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    -- Stay above the spellbook without registering a centered panel or special frame.
    frame:SetBackdrop(BACKDROP)
    frame.title = Label(frame, "Priority actions", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 24, -22)
    local subtitle = Label(frame, "WoWHACv5"); subtitle:SetPoint("TOPRIGHT", -50, -26)
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 12, -8); drag:SetPoint("TOPRIGHT", -40, -8); drag:SetHeight(38)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); self:FitEditorToScreen() end)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() self:Close() end)
    frame.master = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.master:SetSize(28, 28); frame.master:SetPoint("TOPLEFT", 20, -56)
    frame.master:SetHitRectInsets(0, -280, 0, 0)
    frame.master:SetScript("OnClick", function(button) addon:SetPriorityActionsEnabled(not not button:GetChecked()) end)
    frame.masterLabel = Label(frame.master, "Enable priority actions", "GameFontHighlight")
    frame.masterLabel:SetPoint("LEFT", frame.master, "RIGHT", 3, 0)
    frame.state = Label(frame, ""); frame.state:Hide()
    frame.count = Label(frame, ""); frame.count:Hide()
    frame.hint = Label(frame, "Drag spells or items here.")
    frame.hint:SetPoint("TOPLEFT", 26, -93)
    frame.actionArea = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame.actionArea:SetPoint("TOPLEFT", 22, -114); frame.actionArea:SetSize(GRID_WIDTH + 8, GRID_HEIGHT + 8)
    frame.actionArea:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame.actionArea:SetBackdropColor(0, 0, 0, 0.23)
    frame.actionArea:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.55)
    frame.scroll = CreateFrame("ScrollFrame", "WoWHACv5OffensiveCooldownScroll", frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 26, -118); frame.scroll:SetSize(GRID_WIDTH, GRID_HEIGHT)
    frame.content = CreateFrame("Frame", nil, frame.scroll); frame.content:SetSize(GRID_WIDTH, CELL_HEIGHT)
    frame.scroll:SetScrollChild(frame.content); frame.scroll:EnableMouseWheel(true)
    frame.scroll:EnableMouse(true); frame.content:EnableMouse(true)
    frame.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        self:SetScroll(scroll:GetVerticalScroll() - delta * CELL_HEIGHT); self:UpdateDragPreview()
    end)
    local function receive() self:ReceiveDrop(self:GetDropIndex()) end
    frame.scroll:SetScript("OnReceiveDrag", receive); frame.content:SetScript("OnReceiveDrag", receive)
    local function mouseUp(_, button) if button == "LeftButton" and self:GetDragAction() then receive() end end
    frame.scroll:SetScript("OnMouseUp", mouseUp); frame.content:SetScript("OnMouseUp", mouseUp)
    frame.cells = {}
    frame.plus = MakeIcon(frame.content)
    frame.plus.number:Hide()
    frame.plus.icon:SetColorTexture(0.20, 0.20, 0.20, 1)
    frame.plus.border:SetVertexColor(0.65, 0.65, 0.65)
    frame.plus:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    frame.plus.symbol = Label(frame.plus, "+", "GameFontHighlightLarge")
    frame.plus.symbol:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 34, "")
    frame.plus.symbol:SetPoint("CENTER", 0, 1)
    frame.plus:SetScript("OnClick", function()
        if self:GetDragAction() then self:ReceiveDrop(frame.plus.slotIndex) else self:ShowAddDialog() end
    end)
    local function releasePlus()
        frame.plus.symbol:ClearAllPoints(); frame.plus.symbol:SetPoint("CENTER", 0, 1)
    end
    frame.plus:SetScript("OnMouseDown", function()
        frame.plus.symbol:ClearAllPoints(); frame.plus.symbol:SetPoint("CENTER", 1, 0)
    end)
    frame.plus:SetScript("OnMouseUp", releasePlus)
    frame.plus:SetScript("OnHide", releasePlus)
    frame.plus:SetScript("OnReceiveDrag", function() self:ReceiveDrop(frame.plus.slotIndex) end)
    SetTooltip(frame.plus, "Add a spell or item before the rotation provider.")
    frame.plus.label = Label(frame.plus, "Add action"); frame.plus.label:SetPoint("TOP", frame.plus, "BOTTOM", 0, -5)
    frame.provider = MakeIcon(frame.content)
    frame.provider.label = Label(frame.provider, "Provider")
    frame.provider.label:SetPoint("TOP", frame.provider, "BOTTOM", 0, -5)
    frame.provider:SetScript("OnReceiveDrag", function() self:ReceiveDrop(frame.plus.slotIndex) end)
    frame.provider:SetScript("OnClick", function() if self:GetDragAction() then self:ReceiveDrop(frame.plus.slotIndex) end end)
    frame.provider:SetScript("OnEnter", function(owner)
        if self:GetDragAction() then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Rotation provider: %s", owner.providerInfo.label), 1, 0.82, 0)
        GameTooltip:AddLine(L("Runs after your priority actions when none of them applies."), 1, 1, 1, true)
        GameTooltip:AddLine(L("Fixed final action. Choose a provider from the minimap menu."), 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    frame.provider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.preview = CreateFrame("Frame", nil, frame.content)
    frame.preview:SetSize(SLOT_SIZE, SLOT_SIZE); frame.preview:SetFrameLevel(frame.content:GetFrameLevel() + 5)
    frame.preview:SetAlpha(0.45); frame.preview:EnableMouse(false)
    frame.preview.icon = frame.preview:CreateTexture(nil, "ARTWORK"); frame.preview.icon:SetAllPoints(frame.preview)
    frame.preview.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local previewBorder = frame.preview:CreateTexture(nil, "OVERLAY")
    previewBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    previewBorder:SetSize(82, 82); previewBorder:SetPoint("CENTER")
    frame.preview.number = Label(frame.preview, "", "NumberFontNormal"); frame.preview.number:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.preview:Hide()
    frame.empty = Label(frame.content, ""); frame.empty:Hide()
    frame.status = Label(frame, "")
    frame.status:SetPoint("TOPLEFT", 26, -405); frame.status:SetSize(PANEL_WIDTH - 52, 26); frame.status:SetJustifyV("TOP")
    frame.done = MakeButton(frame, "Done", 86, function() self:Close() end)
    frame.done:SetPoint("BOTTOMRIGHT", -22, 20)
    self:CreateAddDialog()
    frame:SetScript("OnShow", function()
        if self:IsInCombat() then self:OnCombatStarted(); return end
        self:InitializeEscapeHandling()
        self:FitEditorToScreen()
        frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    end)
    frame:SetScript("OnHide", function()
        if not self.combatHiding then self.pendingRestore = nil end
        frame:SetScript("OnUpdate", nil); self:CancelDrag()
        frame.addDialog:Hide()
        if frame.conditionsDialog then frame.conditionsDialog:Hide() end
        self:CloseRotationBuilderLink()
        frame.input:ClearFocus(); frame:StopMovingOrSizing(); GameTooltip:Hide()
        self:FitEditorToScreen()
    end)
    frame:SetScript("OnEvent", function(_, event)
        if event == "CURSOR_CHANGED" then self:UpdateDragPreview()
        elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then self:FitEditorToScreen()
        elseif frame:IsShown() then self:Refresh(); self:UpdateDragPreview() end
    end)
    pcall(frame.RegisterEvent, frame, "SPELL_DATA_LOAD_RESULT")
    pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
    pcall(frame.RegisterEvent, frame, "ITEM_DATA_LOAD_RESULT")
    pcall(frame.RegisterEvent, frame, "CURSOR_CHANGED")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    self:InitializeEscapeHandling(); frame:Hide()
    self:RegisterMessage("WOWHAC_PRIORITY_ACTIONS_CHANGED", "Refresh")
    self:RegisterMessage("WOWHAC_PROVIDER_CHANGED", "OnProviderChanged")
    pcall(self.RegisterEvent, self, "PLAYER_SPECIALIZATION_CHANGED", "OnSpecializationChanged")
    pcall(self.RegisterEvent, self, "ACTIVE_TALENT_GROUP_CHANGED", "OnSpecializationChanged")
end

function addon:ShowPriorityActionsEditor()
    if Editor:IsInCombat() then return Editor:DeferOpen("main") end
    if not Editor.frame then Editor:Create() end
    Editor:Refresh(); Editor.frame:Show(); Editor.frame:Raise(); Editor.frame.input:ClearFocus()
    return true
end

function addon:HidePriorityActionsEditor()
    Editor:Close()
end

addon.ShowOffensiveCooldownEditor = addon.ShowPriorityActionsEditor
addon.HideOffensiveCooldownEditor = addon.HidePriorityActionsEditor

-- Listen before creating the UI so an opening request made during combat can
-- be deferred without constructing a single editor frame.
Editor:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStarted")
Editor:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
Editor:RegisterMessage("WOWHAC_LANGUAGE_CHANGED", "RefreshLanguage")
