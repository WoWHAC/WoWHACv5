local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["Ovale"] = function(session)
    local hooks = session or WoWHACv5
    if not Ovale or not Ovale.frame or type(GetItemSpell) ~= "function" then return false end
    WoWHACv5:Log("Supplier found: Ovale.")
    local KEY_REPLACEMENTS = {
        ["ALT%-"] = "A",
        ["CTRL%-"] = "C",
        ["SHIFT%-"] = "S",
        ["NUMPAD"] = "N",
        ["PLUS"] = "+",
        ["MINUS"] = "-",
        ["MULTIPLY"] = "*",
        ["DIVIDE"] = "/",
    }
    -- Переопределяем shortcut-резолвер для Ovale
    local previousShortcut = Ovale.ChercherShortcut
    local function FindShortcut(_, slot)
        if session and not session.active then
            return previousShortcut and previousShortcut(Ovale, slot)
        end
        local name
        if slot > 12 and Bartender4 then
            name = "CLICK BT4Button" .. slot .. ":LeftButton"
        else
            if slot <= 24 or slot > 72 then
                name = "ACTIONBUTTON" .. (((slot - 1) % 12) + 1)
            elseif slot <= 36 then
                name = "MULTIACTIONBAR3BUTTON" .. (slot - 24)
            elseif slot <= 48 then
                name = "MULTIACTIONBAR4BUTTON" .. (slot - 36)
            elseif slot <= 60 then
                name = "MULTIACTIONBAR2BUTTON" .. (slot - 48)
            else
                name = "MULTIACTIONBAR1BUTTON" .. (slot - 60)
            end
        end

        local key = name and GetBindingKey(name)
        if key then
            key = key:upper():gsub("%s+", "")
            for pat, repl in pairs(KEY_REPLACEMENTS) do
                key = key:gsub(pat, repl)
            end
        end
        return key
    end
    Ovale.ChercherShortcut = FindShortcut
    if session then
        session:AddCleanup(function()
            if Ovale.ChercherShortcut == FindShortcut then Ovale.ChercherShortcut = previousShortcut end
        end)
    end

    WoWHACv5.ToggleBurstFrame:Show()
    if session then session:AddCleanup(function() WoWHACv5.ToggleBurstFrame:Hide() end) end

    local function GetSpellIdByName(name)
        return name and Ovale:GetSpellIdByName(name) or nil
    end

    -- Кэш для ItemName -> ItemID
    local itemCache = {}
    local _GetItemSpell = GetItemSpell
    local function TrackItemSpell(id, ...)
        if session and not session.active then return _GetItemSpell(id, ...) end
        local name, spellId = _GetItemSpell(id, ...)
        if name then
            itemCache[name] = id
        end
        return name, spellId
    end
    GetItemSpell = TrackItemSpell
    if session then
        session:AddCleanup(function()
            if GetItemSpell == TrackItemSpell then GetItemSpell = _GetItemSpell end
        end)
    end

    local function GetItemIdByName(name)
        return name and itemCache[name] or nil
    end

    local function IsReady(start, duration)
        return (start or 0) <= 0 or ((start + (duration or 0) - GetTime()) <= 0)
    end

    local function NormalizeSuggestion(spell)
        if not spell or not spell.spellName then
            return
        end

        local spellId = GetSpellIdByName(spell.spellName)
        if not spell.icons[1].shortcut:IsVisible() then
            return
        end
        if spellId then
            local cd = C_Spell.GetSpellCooldown(spellId)
            if IsReady(cd.startTime, cd.duration) then
                return spell.icons[1].shortcut:GetText()
            end
        else
            local itemId = GetItemIdByName(spell.spellName)
            if itemId then
                local start, duration = GetItemCooldown(itemId)
                if IsReady(start, duration) then
                    return spell.icons[1].shortcut:GetText()
                end
            end
        end
    end

    -- Хук обновления кадров Ovale
    hooks:SecureHook(Ovale.frame, "OnUpdate", function(frame)
        local actions = frame.actions
        local spell
        local order = { 4, 3, (WoWHACv5.burst and 2 or 6), 1 }
        for _, idx in ipairs(order) do
            spell = NormalizeSuggestion(actions[idx])
            if spell then
                break
            end
        end
        WoWHACv5:SetCurrentHotKey(spell)
    end)
end
