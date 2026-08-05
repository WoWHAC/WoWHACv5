local _, WoWHACv5 = ...

local LOW_HEALTH_WARNING_CVAR = "doNotFlashLowHealthWarning"
local CVAR_CHECK_INTERVAL = 1

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["JustAC"] = function()
    WoWHACv5:Log("Supplier found: JustAC.")

    local JustACAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

    if not JustACAddon or not SpellQueue or not SpellQueue.GetCurrentSpellQueue then
        return
    end

    local nextCVarCheck = 0

    local function IsHotkeyAvailable(hotkey)
        return type(hotkey) == "string" and hotkey ~= ""
    end

    local function IsFrameDisplayed(frame)
        if not frame then
            return false
        end

        local visibilityGetter = frame.IsVisible or frame.IsShown
        if not visibilityGetter then
            return false
        end

        local visibilityOk, isVisible = pcall(visibilityGetter, frame)
        if not visibilityOk or not isVisible then
            return false
        end

        local alphaGetter = frame.GetEffectiveAlpha or frame.GetAlpha
        if not alphaGetter then
            return true
        end

        local alphaOk, hasVisibleAlpha = pcall(function()
            return alphaGetter(frame) > 0
        end)

        -- Alpha can be a secret value in combat. In that case the frame's own
        -- visibility state is the strongest signal available to addons.
        return not alphaOk or hasVisibleAlpha
    end

    local function GetCachedHotkey(icon)
        if not icon then
            return nil
        end

        if IsHotkeyAvailable(icon.cachedHotkey) then
            return icon.cachedHotkey
        end

        local hotkeyText = icon.hotkeyText
        if hotkeyText and hotkeyText.GetText then
            local hotkey = hotkeyText:GetText()
            if IsHotkeyAvailable(hotkey) then
                return hotkey
            end
        end
    end

    local function GetHotkey(id, isItem, icon, itemCastSpellID)
        local hotkey
        local scannerAvailable = false

        if ActionBarScanner then
            if isItem and ActionBarScanner.GetItemHotkey then
                scannerAvailable = true
                hotkey = ActionBarScanner.GetItemHotkey(id, itemCastSpellID)
            elseif not isItem and ActionBarScanner.GetSpellHotkey then
                scannerAvailable = true
                hotkey = ActionBarScanner.GetSpellHotkey(id)
            end
        end

        if IsHotkeyAvailable(hotkey) then
            return hotkey
        end

        -- An empty scanner result is authoritative. Falling back to a pooled
        -- icon's old text could press the previous defensive suggestion.
        return not scannerAvailable and GetCachedHotkey(icon) or nil
    end

    local function GetIconSuggestion(icon, id, isItem)
        if not id then
            return nil
        end

        local hotkey = GetHotkey(id, isItem, icon, icon and icon.itemCastSpellID)
        if not IsHotkeyAvailable(hotkey) then
            return nil
        end

        return isItem and -id or id, hotkey
    end

    local function IsSpellReady(spellId)
        if not spellId or not BlizzardAPI or not BlizzardAPI.IsSpellReady then
            return false
        end

        local ok, isReady = pcall(BlizzardAPI.IsSpellReady, spellId)
        return ok and isReady == true
    end

    local function GetInterruptSuggestion()
        local icon = JustACAddon.interruptIcon
        if not IsFrameDisplayed(icon) or not IsSpellReady(icon.spellID) then
            return nil
        end

        return GetIconSuggestion(icon, icon.spellID, false)
    end

    local function IsLowHealthWarningVisible()
        local lowHealthFrame = _G.LowHealthFrame
        return lowHealthFrame and lowHealthFrame.IsShown and lowHealthFrame:IsShown()
    end

    local function GetDefensiveSuggestion()
        if not IsLowHealthWarningVisible() then
            return nil
        end

        for _, icon in ipairs(JustACAddon.defensiveIcons or {}) do
            if IsFrameDisplayed(icon)
                and icon.currentID
                and not icon.isWaiting
                and icon.cachedDefUsable ~= false then
                local id, hotkey = GetIconSuggestion(icon, icon.currentID, icon.isItem == true)
                if hotkey then
                    return id, hotkey
                end
            end
        end
    end

    local function GetRotationSuggestion()
        local queue = SpellQueue.GetCurrentSpellQueue()
        local id = queue and queue[1]
        if not id then
            return nil
        end

        local icon = JustACAddon.spellIcons and JustACAddon.spellIcons[1]
        if icon and icon.spellID ~= id then
            icon = nil
        end

        if id < 0 then
            return id, GetHotkey(-id, true, icon, icon and icon.itemCastSpellID)
        end

        return id, GetHotkey(id, false, icon)
    end

    local function IsLowHealthWarningSuppressed()
        local getter = C_CVar and C_CVar.GetCVarBool or GetCVarBool
        if not getter then
            return nil
        end

        local ok, value = pcall(getter, LOW_HEALTH_WARNING_CVAR)
        return ok and value or nil
    end

    local function EnsureLowHealthWarningEnabled(force)
        local now = GetTime()
        if not force and now < nextCVarCheck then
            return
        end
        nextCVarCheck = now + CVAR_CHECK_INTERVAL

        if IsLowHealthWarningSuppressed() ~= true then
            return
        end

        local setter = C_CVar and C_CVar.SetCVar or SetCVar
        if setter then
            pcall(setter, LOW_HEALTH_WARNING_CVAR, "0")
        end
    end

    local function GetCurrentSuggestion()
        EnsureLowHealthWarningEnabled(false)

        local id, hotkey = GetInterruptSuggestion()
        if hotkey then
            return id, hotkey
        end

        id, hotkey = GetDefensiveSuggestion()
        if hotkey then
            return id, hotkey
        end

        return GetRotationSuggestion()
    end

    EnsureLowHealthWarningEnabled(true)

    function WoWHACv5:GetCurrentHotKey()
        local _, hotkey = GetCurrentSuggestion()
        return hotkey or ""
    end

    function WoWHACv5:GetCurrentId()
        local id = GetCurrentSuggestion()
        return id
    end
end
