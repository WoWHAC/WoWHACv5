local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["Hekili"] = function(session)
    local modern = WoWHACv5:SupportsModernFeatures()
    local hooks = session or WoWHACv5
    WoWHACv5:Log("Supplier found: Hekili.")
    pcall(WoWHACv5.ToggleHekiliFrame.Init, WoWHACv5.ToggleHekiliFrame)
    if modern then WoWHACv5.ToggleHekiliFrame:Show() end
    if session then
        session:AddCleanup(function() WoWHACv5.ToggleHekiliFrame:Hide() end)
    end

    local hekili = Hekili
    local engine = hekili and hekili.Engine
    if modern and type(engine) == "table" and type(engine.Output) == "table"
        and type(engine.Output.Primary) == "table"
        and type(engine.Subscribe) == "function" and type(engine.Unsubscribe) == "function" then
        -- Forever publishes complete records independently of its display style.
        -- Subscribe as a consumer so recommendations also update with hidden UI.
        local active = true
        local function OnPublish() end
        if not engine.Subscribe("Primary", OnPublish, false) then return false end
        if session then
            session:AddCleanup(function()
                active = false
                engine.Unsubscribe("Primary", OnPublish)
            end)
        end

        -- Hekili abbreviates these key names for display. Keep this translation
        -- local to its new output API; the older adapters retain their labels.
        local keyAliases = {
            ["N+"] = "NUMPADPLUS", ["N-"] = "NUMPADMINUS",
            ["N*"] = "NUMPADMULTIPLY", ["N/"] = "NUMPADDIVIDE",
            ["N."] = "NUMPADDECIMAL", NENTER = "NUMPADENTER",
            M4 = "BUTTON4", M5 = "BUTTON5", DN = "DOWN",
        }
        local function NormalizeHotkey(hotkey)
            local key = WoWHACv5:NormalizeModifiers(hotkey)
            local modifiers = ""
            while true do
                local modifier = key:match("^([A-Z]+%-)")
                if modifier ~= "ALT-" and modifier ~= "CTRL-" and modifier ~= "SHIFT-" then break end
                modifiers = modifiers .. modifier
                key = key:sub(#modifier + 1)
            end
            local digit = key:match("^N([0-9])$")
            return modifiers .. (digit and "NUMPAD" .. digit or keyAliases[key] or key)
        end

        function WoWHACv5:GetCurrentSuggestion()
            local settings = engine.settings
            if not active or type(settings) ~= "table" or not settings.enabled or hekili.Pause then return nil end
            local output = engine.Output.Primary
            local rec = output and output.count > 0 and output.recs and output.recs[1]
            if not rec or not rec.actionName then return nil end
            -- The first record can be a future prediction. Read its absolute
            -- time so a waiting recommendation becomes ready between publishes.
            if type(rec.exact_time) == "number" and rec.exact_time > GetTime() + 0.05 then return nil end
            local id = rec.item and -rec.item or rec.actionID
            if type(id) ~= "number" or id == 0 or (not rec.item and id < 0) then return nil end
            local hotkey
            if type(hekili.GetBindingForAction) == "function" then
                local display = settings.displays and settings.displays.Primary
                if not display then return nil end
                hotkey = hekili:GetBindingForAction(rec.actionName, display, 1)
            else
                hotkey = rec.keybind
            end
            if type(hotkey) ~= "string" or hotkey == "" then return nil end
            return id, NormalizeHotkey(hotkey)
        end

        function WoWHACv5:GetCurrentId()
            local id = self:GetCurrentSuggestion()
            return id or 0
        end

        function WoWHACv5:GetCurrentHotKey()
            local _, hotkey = self:GetCurrentSuggestion()
            return hotkey
        end
        return true
    end

    local provider = Hekili_Primary_B1;
    if provider == nil then
        if not Hekili_D1_B1_KB or type(Hekili_GetRecommendedAbility) ~= "function" then return false end
        function WoWHACv5:GetCurrentHotKey()
            return Hekili_D1_B1_KB:GetText()
        end

        function WoWHACv5:GetCurrentId()
            return Hekili_GetRecommendedAbility(1, 1) or 0
        end
    else
        local Keybind = provider.Keybinding

        if not Keybind then return false end
        if modern then
            WoWHACv5:SetCurrentId(provider.Ability and provider.Ability.id or 0)
            WoWHACv5:SetCurrentHotKey(Keybind:GetText())
        end
        hooks:SecureHook(Keybind, "SetText", function(_, txt)
            if provider.Ability ~= nil then
                WoWHACv5:SetCurrentId(provider.Ability.id)
            end
            WoWHACv5:SetCurrentHotKey(txt)
        end)
    end
end
