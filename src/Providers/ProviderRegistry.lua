local _, WoWHACv5 = ...
if not WoWHACv5:SupportsModernFeatures() then return end

-- Adapter files register as the TOC loads them. This is the only ordering
-- source; OptionalDeps controls loading dependencies, not provider preference.
local providerOrder = {}
setmetatable(WoWHACv5.providers, {
    __newindex = function(registry, id, initialize)
        if type(initialize) == "function" then
            providerOrder[#providerOrder + 1] = id
        end
        rawset(registry, id, initialize)
    end,
})

local activeProvider
local activeSession
local availableSignature
local initialized = false

local function IsAvailable(id)
    if id == "AssistedCombat" then
        -- Built into the client, so it has no addon enable/load state. The
        -- recommendation may be temporarily unavailable without losing a
        -- user's selection.
        return C_AssistedCombat ~= nil
            and type(C_AssistedCombat.IsAvailable) == "function"
            and type(C_AssistedCombat.GetNextCastSpell) == "function"
    end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(loaded) ~= "function" then return false end
    local ok, present = pcall(loaded, id)
    if not ok or not present then return false end

    local character = type(UnitName) == "function" and UnitName("player") or nil
    local enabled
    if C_AddOns and type(C_AddOns.GetAddOnEnableState) == "function" then
        -- Retail's 11.1.7 addon-system update switched character settings to
        -- GUIDs and introduced GetAddOnLocalTable. Forever uses the same API.
        -- Keep the name-based lookup for older Retail and Classic clients.
        local retail = WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
        local forever = WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
        if (retail or forever) and type(C_AddOns.GetAddOnLocalTable) == "function" and type(UnitGUID) == "function" then
            character = UnitGUID("player") or character
        end
        ok, enabled = pcall(C_AddOns.GetAddOnEnableState, id, character)
    elseif type(GetAddOnEnableState) == "function" then
        ok, enabled = pcall(GetAddOnEnableState, character, id)
    end
    return not (ok and (enabled == 0 or enabled == false))
end

function WoWHACv5:GetAvailableProviders()
    local available = {}
    for _, id in ipairs(providerOrder) do
        if type(self.providers[id]) == "function" and IsAvailable(id) then
            available[#available + 1] = {
                id = id,
                label = id == "AssistedCombat" and "Assisted Combat (Blizzard)" or id,
            }
        end
    end
    return available
end

function WoWHACv5:GetActiveProvider()
    return activeProvider
end

local Session = {}
Session.__index = Session

function Session:AddCleanup(callback)
    self.cleanups[#self.cleanups + 1] = callback
end

function Session:Close()
    self.active = false
    for timer in pairs(self.timers) do pcall(timer.Cancel, timer) end
    self.timers = {}
    for index = #self.cleanups, 1, -1 do
        local ok, message = pcall(self.cleanups[index])
        if not ok then WoWHACv5:Debug("Provider cleanup: " .. tostring(message)) end
    end
    self.cleanups = {}
end

local function StopProvider()
    if activeSession then activeSession:Close() end
    activeSession, activeProvider = nil, nil
    WoWHACv5:ResetProviderState()
end

function Session:Guard(callback)
    local lastError
    return function(...)
        if not self.active or activeSession ~= self then return end
        local generation = self.errorGeneration or 0
        local ok, first, second = pcall(callback, ...)
        if not self.active or activeSession ~= self then return end
        if not ok then
            -- An upstream frame/API can be unavailable for one update. Clear
            -- stale output, but keep this session's hooks for the next update.
            self.errorGeneration = (self.errorGeneration or 0) + 1
            WoWHACv5:ClearProviderOutput()
            if WoWHACv5.ClearRecommendationProvider then WoWHACv5:ClearRecommendationProvider() end
            local message = tostring(first)
            if message ~= lastError then
                WoWHACv5:Log("Provider " .. self.id .. " update failed: " .. message)
            end
            lastError = message
            return
        end
        -- A nested getter may have failed while its caller returned normally.
        -- Never publish a half-valid ID/key pair from that same update.
        if (self.errorGeneration or 0) ~= generation then return end
        lastError = nil
        return first, second
    end
end

function Session:SecureHook(target, method, callback)
    -- Each hook has an explicit owner and is individually removed. Core hooks,
    -- events and the 100 ms pixel timer never belong to this session.
    WoWHACv5:SecureHook(target, method, self:Guard(callback))
    self:AddCleanup(function() WoWHACv5:Unhook(target, method) end)
end

function Session:After(delay, callback)
    local guarded = self:Guard(callback)
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        local timer
        timer = C_Timer.NewTimer(delay, function(...)
            self.timers[timer] = nil
            guarded(...)
        end)
        self.timers[timer] = true
    else
        -- Legacy After cannot be cancelled, so its closed-session callback is
        -- inert even if it fires after a different provider has been selected.
        C_Timer.After(delay, guarded)
    end
end

local getterNames = { "GetCurrentHotKey", "GetCurrentId", "GetNextHotKey", "GetNextId", "GetCurrentSuggestion" }

local function Activate(id)
    if activeProvider == id and activeSession then return true end
    local previous = activeProvider
    StopProvider()
    if not id then
        if previous then WoWHACv5:SendMessage("WOWHAC_PROVIDER_CHANGED", nil) end
        return true
    end

    local session = setmetatable({ id = id, active = true, cleanups = {}, timers = {} }, Session)
    activeSession = session
    local ok, result = pcall(WoWHACv5.providers[id], session)
    if not ok or result == false or activeSession ~= session then
        if activeSession == session then StopProvider() end
        WoWHACv5:Log("Unable to initialize provider " .. id .. ": " .. tostring(ok and "not ready" or result))
        if previous then WoWHACv5:SendMessage("WOWHAC_PROVIDER_CHANGED", nil) end
        return false, "initialization_failed"
    end

    for _, name in ipairs(getterNames) do
        if type(WoWHACv5[name]) == "function" then
            WoWHACv5[name] = session:Guard(WoWHACv5[name])
        end
    end
    if type(WoWHACv5.GetCurrentSuggestion) ~= "function" then
        function WoWHACv5:GetCurrentSuggestion()
            return self:GetCurrentId(), self:GetCurrentHotKey()
        end
        WoWHACv5.GetCurrentSuggestion = session:Guard(WoWHACv5.GetCurrentSuggestion)
    end
    activeProvider = id
    WoWHACv5:SendMessage("WOWHAC_PROVIDER_CHANGED", id)
    return true
end

function WoWHACv5:SelectProvider(id)
    if type(id) ~= "string" or type(self.providers[id]) ~= "function" or not IsAvailable(id) then
        return false, "unavailable"
    end
    if id ~= activeProvider and type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "combat"
    end
    local previous = activeProvider
    local ok, reason = Activate(id)
    if ok then
        self:GetSettings().selectedProvider = id
    elseif previous and previous ~= id and IsAvailable(previous) then
        -- Failed switches leave the saved choice intact. Rebuild the former
        -- provider only after the failed session has been fully released.
        Activate(previous)
    end
    return ok, reason
end

function WoWHACv5:RefreshProviders()
    local available = self:GetAvailableProviders()
    local ids, present = {}, {}
    for _, provider in ipairs(available) do
        ids[#ids + 1] = provider.id
        present[provider.id] = true
    end
    local signature = table.concat(ids, "\031")
    if signature ~= availableSignature then
        availableSignature = signature
        self:SendMessage("WOWHAC_PROVIDERS_CHANGED", available)
    end

    local settings = self:GetSettings()
    local selected = settings.selectedProvider
    local preferred = present[selected] and selected or ids[1]
    if preferred == activeProvider and activeSession then return true end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        -- Login during combat retries on PLAYER_REGEN_ENABLED. A provider that
        -- became unavailable is silenced immediately, without initializing UI.
        if activeProvider and not present[activeProvider] then
            StopProvider()
            self:SendMessage("WOWHAC_PROVIDER_CHANGED", nil)
        end
        return false, "combat"
    end

    local attempts = {}
    if preferred then attempts[#attempts + 1] = preferred end
    for _, id in ipairs(ids) do
        if id ~= preferred then attempts[#attempts + 1] = id end
    end
    for _, id in ipairs(attempts) do
        if Activate(id) then
            -- An installed provider can be temporarily unready. Keep an
            -- explicit choice so a later refresh retries it after the fallback.
            if not present[selected] or id == selected then settings.selectedProvider = id end
            initialized = true
            return true
        end
    end
    Activate(nil)
    if not present[selected] then settings.selectedProvider = nil end
    if not initialized then
        self:Log("No rotation suppliers found. A list of available suppliers can be found at https://wowhac.fun/")
    end
    initialized = true
    return false, "unavailable"
end
