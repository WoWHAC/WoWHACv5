local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["HeroRotation"] = function()
    WoWHACv5:Log("Supplier found: HeroRotation.")

    local Keybind = HeroRotation.MainIconFrame.Keybind
    local last = Keybind:GetText()

    WoWHACv5:SecureHook(Keybind, "SetText", function(_, txt)
        -- Правый рекомендуемый
        local rightSuggest = HeroRotation.RightSuggestedIconFrame and HeroRotation.RightSuggestedIconFrame.Keybind
        if rightSuggest and rightSuggest:IsVisible() then
            local suggestedHotkey = rightSuggest:GetText()
            if suggestedHotkey and suggestedHotkey ~= "" then
                WoWHACv5:SetCurrentHotKey(suggestedHotkey)
                return
            end
        end

        -- Центральный рекомендуемый
        local suggested = HeroRotation.SuggestedIconFrame and HeroRotation.SuggestedIconFrame.Keybind
        if suggested and suggested:IsVisible() then
            local suggestedHotkey = suggested:GetText()
            if suggestedHotkey and suggestedHotkey ~= "" then
                WoWHACv5:SetCurrentHotKey(suggestedHotkey)
                return
            end
        end

        -- Малый (burst)
        local burst = HeroRotation.SmallIconFrame
                and HeroRotation.SmallIconFrame.Icon
                and HeroRotation.SmallIconFrame.Icon[1]
                and HeroRotation.SmallIconFrame.Icon[1].Keybind
        if burst and burst:IsVisible() then
            local burstHotkey = burst:GetText()
            if burstHotkey and burstHotkey ~= "" then
                WoWHACv5:SetCurrentHotKey(burstHotkey)
                return
            end
        end

        if txt ~= last then
            WoWHACv5:SetCurrentHotKey(txt)
        end
    end)
end
