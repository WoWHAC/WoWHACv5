local _, WoWHACv5 = ...
WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["MaxDps"] = function(session)
    local modern = WoWHACv5:SupportsModernFeatures()
    local hooks = session or WoWHACv5
    if not MaxDps then return false end
    WoWHACv5:Log("Supplier found: MaxDps.")
    if not WeakAuras then
        if not MaxDps.db or not MaxDps.db.global or not MaxDps.db.global.spellFrame
            or not MaxDpsSpellFrame or not MaxDpsSpellFrame.bindText then return false end
        local settings = MaxDps.db.global
        local oldCombat, oldFrame, oldEnabled = settings.onCombatEnter, settings.spellFrame.enabled, settings.enabled
        local wasShown = MaxDpsSpellFrame:IsShown()
        if session then
            session:AddCleanup(function()
                if settings.onCombatEnter == false then settings.onCombatEnter = oldCombat end
                if settings.spellFrame.enabled == true then settings.spellFrame.enabled = oldFrame end
                if settings.enabled == true then settings.enabled = oldEnabled end
                if not wasShown then MaxDpsSpellFrame:Hide() end
            end)
        end
        MaxDps.db.global.onCombatEnter = false
        MaxDps.db.global.spellFrame.enabled = true
        MaxDps.db.global.enabled = true
        MaxDpsSpellFrame:Show()

        local provider = MaxDpsSpellFrame
        local Keybind = provider.bindText

        local function UpdateRecommendation(_, spellID)
            WoWHACv5:SetCurrentId(spellID)
            WoWHACv5:SetCurrentHotKey(spellID and spellID > 0 and Keybind:GetText() or nil)
        end
        hooks:SecureHook(MaxDps, "UpdateSpellFrame", UpdateRecommendation)
        if modern then UpdateRecommendation(MaxDps, MaxDps.Spell) end
    else
        local function InitializeWeakAuras()
            WoWHACv5.ToggleBurstFrame:Show()
            if session then session:AddCleanup(function() WoWHACv5.ToggleBurstFrame:Hide() end) end
            local function UpdateRecommendation(event)
                if event == "MAXDPS_COOLDOWN_UPDATE" then
                    for _, frame in pairs(MaxDps.Frames or {}) do
                        if frame and frame:IsVisible() and (WoWHACv5.burst or frame.ovType ~= "cooldown") then
                            local button = frame:GetParent()
                            WoWHACv5:SetCurrentHotKey(button.HotKey:GetText())
                            return
                        end
                    end
                    WoWHACv5:SetCurrentHotKey(nil)
                end
            end
            hooks:SecureHook(WeakAuras, "ScanEvents", UpdateRecommendation)
            if modern then UpdateRecommendation("MAXDPS_COOLDOWN_UPDATE") end
        end
        if modern then
            -- Provider switching may happen after the login message has fired.
            InitializeWeakAuras()
        else
            WoWHACv5:RegisterMessage("WOWHACV4_WA_PRESENTS", function(_, isLoaded)
                if isLoaded then InitializeWeakAuras()
                else WoWHACv5:Log("To use the MaxDps as rotation provider, you need to install WeakAuras.") end
            end)
        end
    end
end
