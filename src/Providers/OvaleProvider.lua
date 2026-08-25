local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["Ovale"] = function()
    WoWHACv5:Log("Supplier found: Ovale.")

    function Ovale:ChercherShortcut(slot)
        return WoWHACv5.ActionBinding.ForSlot(slot)
    end

    WoWHACv5.ToggleBurstFrame:Show()

    local function GetSpellIdByName(name)
        return name and Ovale:GetSpellIdByName(name) or nil
    end

    -- Кэш для ItemName -> ItemID
    local itemCache = {}
    local originalGetItemSpell = GetItemSpell
    function GetItemSpell(id, ...)
        local spellName, spellId = originalGetItemSpell(id, ...)
        if spellName then
            itemCache[spellName] = id
        end
        return spellName, spellId
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
                local hotkey = WoWHACv5.ActionBinding.ForSpell(spellId)
                return hotkey and spellId or nil, hotkey
            end
        else
            local itemId = GetItemIdByName(spell.spellName)
            if itemId then
                local start, duration = GetItemCooldown(itemId)
                if IsReady(start, duration) then
                    local hotkey = WoWHACv5.ActionBinding.ForItem(itemId)
                    return hotkey and -itemId or nil, hotkey
                end
            end
        end
    end

    -- Хук обновления кадров Ovale
    WoWHACv5:SecureHook(Ovale.frame, "OnUpdate", function(frame)
        local actions = frame.actions
        local id, hotkey
        local order = { 4, 3, (WoWHACv5.burst and 2 or 6), 1 }
        for _, idx in ipairs(order) do
            id, hotkey = NormalizeSuggestion(actions[idx])
            if hotkey then
                break
            end
        end
        WoWHACv5:SetCurrentSuggestion(id, hotkey)
    end)
end
