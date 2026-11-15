local root = _TEST_ROOT or (arg and arg[1]) or "."
local baselineRoot = _BASELINE_ROOT or (arg and arg[2]) or ""
local candidateRoot = _CANDIDATE_ROOT or (arg and arg[3]) or root
local registryRoot = _REGISTRY_ROOT or (arg and arg[4]) or root
local passed, failed = 0, 0

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function test(name, run)
    local ok, message = pcall(run)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(message)) end
end

local function load(path, env, addon)
    local chunk, message
    if setfenv then
        chunk, message = loadfile(path)
        if chunk then setfenv(chunk, env) end
    else chunk, message = loadfile(path, "t", env) end
    assert(chunk, message)
    return chunk("WoWHACv5", addon)
end

local function source(path, env, addon)
    local base = path == "Providers/ProviderRegistry.lua" and registryRoot or root
    return load(base .. "/src/" .. path, env, addon)
end

local function fixture(id, modern, providerRoot)
    local env = setmetatable({}, { __index = _G }); env._G = env
    local state = { now = 100, settings = {}, hooks = {}, timers = {}, frames = {}, bindings = { "1", "2", "3" },
        loaded = { AethysRotation = true, AssistedCombat = true, BetterAssistant = true, RotationHelper = true, Other = true } }
    local addon = { providers = {} }
    function addon:Log() end
    function addon:Debug() end
    function addon:SendMessage() end
    function addon:GetSettings() return state.settings end
    function addon:SecureHook(target, method, callback)
        assert(type(target[method]) == "function", "missing hook target " .. method)
        state.hooks[target] = state.hooks[target] or {}
        assert(not state.hooks[target][method], "duplicate hook " .. method)
        local original = target[method]
        state.hooks[target][method] = original
        target[method] = function(...)
            local first, second = original(...)
            callback(...)
            return first, second
        end
    end
    function addon:Unhook(target, method)
        target[method] = state.hooks[target][method]
        state.hooks[target][method] = nil
    end
    function addon:IsHooked(target, method) return state.hooks[target] and state.hooks[target][method] ~= nil end
    addon.pixel = { SetColor = function() end }
    env.GetTime = function() return state.now end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CAMELOT = 1, 1, 9
    env.GetBuildInfo = function() return "test", "test", "test", modern and 120100 or 110000 end
    env.UnitName = function() return "Tester" end
    env.UnitGUID = function() return "Player-Test" end
    env.InCombatLockdown = function() return false end
    env.C_AddOns = { IsAddOnLoaded = function(name) return state.loaded[name] == true end,
        GetAddOnEnableState = function() return 2 end, GetAddOnLocalTable = function() return {} end }
    local function queue(callback)
        local timer = { callback = callback, Cancel = function(self) self.cancelled = true end }
        state.timers[#state.timers + 1] = timer
        return timer
    end
    env.C_Timer = { After = function(_, callback) queue(callback) end,
        NewTimer = function(_, callback) return queue(callback) end }
    function state.flush()
        local timers = state.timers; state.timers = {}
        for _, timer in ipairs(timers) do if not timer.cancelled then timer.callback() end end
    end
    env.CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        function frame:Hide() end
        function frame:CreateFontString() return { GetFontObject = function() return true end } end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    source("Utils/ClientFeatures.lua", env, addon)
    source("Providers/Provider.lua", env, addon)
    source("Providers/ProviderRegistry.lua", env, addon)
    source("Utils/OffensiveCooldowns.lua", env, addon)
    local configure
    if id == "AethysRotation" then
        env.AethysRotation = { GetTexture = function(action) return action.texture end,
            ResetIcons = function() end, Cast = function() end, CastQueue = function() end, CastSuggested = function() end }
        env.AethysCore = { FindKeyBinding = function(texture) return state.bindings[texture] end }
    elseif id == "AssistedCombat" or id == "BetterAssistant" then
        state.available, state.spell, state.spellCalls = true, 101, 0
        env.C_AssistedCombat = { IsAvailable = function() return state.available end,
            GetNextCastSpell = function()
                state.spellCalls = state.spellCalls + 1
                if state.sequence then return state.sequence[state.spellCalls] end
                return state.spell
            end }
        env.FindBaseSpellByID = function(spell) return spell end
        env.C_ActionBar = { FindSpellActionButtons = function(spell)
            local slot = ({ [101] = 1, [202] = 2, [303] = 3 })[spell]
            return slot and { slot } or {}
        end, IsAssistedCombatAction = function() return false end }
        env.GetBindingKey = function(command)
            local slot = tonumber(command:match("^ACTIONBUTTON(%d+)$"))
            return slot and state.bindings[slot]
        end
        env.GetBindingText = function(key) return key end
        env.GetActionInfo = function(slot)
            local spell = ({ 101, 202, 303 })[slot]
            if spell then return "spell", spell, "spell" end
        end
        env.HasAction = function(slot) return slot <= 3 end
        env.GetActionBarPage = function() return 1 end
        for slot = 1, 3 do env["ActionButton" .. slot] = { action = slot } end
        if id == "BetterAssistant" then
            local function frame(alpha) return { alpha = alpha, GetAlpha = function(self) return self.alpha end } end
            function state.core(spell)
                local core = frame(1)
                core.dbgPctBg, core.overlay, core.interruptFrame = {}, {}, frame(0)
                core.defensivesFrames, core.defensivesSlotData, core.currentSpellID = {}, {}, spell
                function core:GetMainIconReadiness() return true, 1, 1 end
                return core
            end
            state.currentCore = state.core(101)
            env.UIParent = { GetChildren = function() state.scans = (state.scans or 0) + 1; return state.currentCore end }
            env.C_StringUtil = { TruncateWhenZero = function() end, CreateNumericRuleFormatter = function()
                return { AddBreakpoint = function() end, FormatNumber = function(_, value) return tostring(value) end }
            end }
            env.Enum = { NumericRuleFormatRounding = { Down = 0 } }
        end
    elseif id == "RotationHelper" then
        state.key = "9"
        state.suggestion = { keybindLabel = { GetText = function() return state.key end }, tooltipData = { type = "spell", id = 909 } }
        env.RotationHelper = { modules = { SpellSuggestion = state.suggestion } }
    end
    local file = id == "AssistedCombat" and id or id .. "Provider"
    load((providerRoot or candidateRoot) .. "/src/Providers/" .. file .. ".lua", env, addon)
    function state.activate()
        if modern then return addon:SelectProvider(id) end
        return addon.providers[id]()
    end
    function state.other()
        addon.providers.Other = function() function addon:GetCurrentHotKey() return "OTHER" end end
        return addon:SelectProvider("Other")
    end
    return env, addon, state
end

local function pair(addon)
    if addon.GetCurrentSuggestion then return addon:GetCurrentSuggestion() end
    return addon:GetCurrentId(), addon:GetCurrentHotKey()
end

local function parity(name, run)
    test(name, function()
        for _, modern in ipairs({ false, true }) do
            if baselineRoot ~= "" then run(modern, baselineRoot) end
            run(modern, candidateRoot)
        end
    end)
end

parity("Aethys preserves suggested, off-GCD and queued priority", function(modern, providerRoot)
    local env, addon, state = fixture("AethysRotation", modern, providerRoot); state.activate()
    local rotation = env.AethysRotation
    local first, second, suggested = { SpellID = 101, texture = 1 }, { SpellID = 202, texture = 2 }, { SpellID = 303, texture = 3 }
    rotation.ResetIcons(); rotation.CastQueue(first, second); state.flush()
    equal(addon:GetCurrentId(), 101); equal(addon:GetCurrentHotKey(), "1"); equal(addon:GetNextId(), 202)
    rotation.ResetIcons(); rotation.Cast(first, false); rotation.Cast(second, true); state.flush()
    equal(addon:GetCurrentId(), 202); equal(addon:GetNextHotKey(), nil)
    rotation.ResetIcons(); rotation.Cast(second, true); rotation.CastSuggested(suggested); state.flush()
    equal(addon:GetCurrentId(), 303); equal(addon:GetCurrentHotKey(), "3")
end)

parity("Aethys suppresses stale generations and clears empty recommendations", function(modern, providerRoot)
    local env, addon, state = fixture("AethysRotation", modern, providerRoot); state.activate()
    env.AethysRotation.ResetIcons(); env.AethysRotation.Cast({ SpellID = 101, texture = 1 })
    env.AethysRotation.ResetIcons(); state.flush()
    equal(addon:GetCurrentId(), 0); equal(addon:GetCurrentHotKey(), nil)
end)

test("Aethys timers and hooks cannot republish after a provider switch", function()
    local env, addon, state = fixture("AethysRotation", true); state.activate()
    env.AethysRotation.ResetIcons(); env.AethysRotation.Cast({ SpellID = 101, texture = 1 })
    assert(state.other()); state.flush(); equal(addon:GetCurrentHotKey(), "OTHER")
    equal(addon:IsHooked(env.AethysRotation, "ResetIcons"), false)
    assert(state.activate()); env.AethysRotation.ResetIcons(); env.AethysRotation.Cast({ SpellID = 202, texture = 2 }); state.flush()
    equal(addon:GetCurrentId(), 202); equal(addon:GetCurrentHotKey(), "2")
end)

parity("Assisted Combat preserves its current spell and matching action-bar key", function(modern, providerRoot)
    local _, addon, state = fixture("AssistedCombat", modern, providerRoot); state.activate()
    local id, key = pair(addon); equal(id, 101); equal(key, "1")
    state.spell = 202; id, key = pair(addon); equal(id, 202); equal(key, "2")
    state.available = false; equal(addon:GetCurrentHotKey(), nil)
end)

test("Assisted Combat paired result reads an advancing native recommendation once", function()
    local _, addon, state = fixture("AssistedCombat", true); state.activate()
    state.sequence = { 101, 202 }
    local id, key = addon:GetCurrentSuggestion()
    equal(id, 101); equal(key, "1"); equal(state.spellCalls, 1)
    assert(state.other()); assert(state.activate())
    state.sequence, state.spell = nil, 303
    id, key = addon:GetCurrentSuggestion(); equal(id, 303); equal(key, "3")
end)

test("native Assisted Combat recovers from a transient recommendation API failure", function()
    local env, addon, state = fixture("AssistedCombat", true); state.activate()
    local getter = env.C_AssistedCombat.GetNextCastSpell
    env.C_AssistedCombat.GetNextCastSpell = function() error("temporary native recommendation failure") end
    equal(addon:GetCurrentSuggestion(), nil)
    equal(addon:GetActiveProvider(), "AssistedCombat", "transient failure must retain selection")
    env.C_AssistedCombat.GetNextCastSpell = getter
    state.spell = 202
    local id, key = addon:GetCurrentSuggestion(); equal(id, 202); equal(key, "2")
end)

test("Aethys recovers from a transient binding lookup failure without reselecting", function()
    local env, addon, state = fixture("AethysRotation", true); state.activate()
    local lookup = env.AethysCore.FindKeyBinding
    env.AethysRotation.ResetIcons()
    env.AethysCore.FindKeyBinding = function() error("temporary Aethys binding failure") end
    env.AethysRotation.Cast({ SpellID = 101, texture = 1 }); state.flush()
    equal(addon:GetActiveProvider(), "AethysRotation", "hook failure must retain selection")
    equal(addon:GetCurrentHotKey(), nil)
    env.AethysCore.FindKeyBinding = lookup
    env.AethysRotation.ResetIcons(); env.AethysRotation.Cast({ SpellID = 202, texture = 2 }); state.flush()
    equal(addon:GetCurrentId(), 202); equal(addon:GetCurrentHotKey(), "2")
end)

parity("BetterAssistant preserves interrupt, defensive and rotation ordering", function(modern, providerRoot)
    local _, addon, state = fixture("BetterAssistant", modern, providerRoot); state.activate()
    local id, key = pair(addon); equal(id, 101); equal(key, "1")
    state.currentCore.interruptFrame.alpha, state.currentCore.interruptSpellID = 1, 202
    state.now = state.now + 0.06; id, key = pair(addon); equal(id, 202); equal(key, "2")
    state.currentCore.interruptFrame.alpha = 0
    state.currentCore.defensivesFrames[1] = { GetAlpha = function() return 1 end, iconColorAlpha = 1 }
    state.currentCore.defensivesSlotData[1] = { active = true, spellID = 303 }
    state.now = state.now + 0.06; id, key = pair(addon); equal(id, 303); equal(key, "3")
end)

parity("BetterAssistant binding events invalidate the short recommendation cache", function(modern, providerRoot)
    local _, addon, state = fixture("BetterAssistant", modern, providerRoot); state.activate()
    equal(addon:GetCurrentHotKey(), "1"); state.bindings[1] = "CTRL-1"
    for _, frame in ipairs(state.frames) do
        if frame.events.UPDATE_BINDINGS then frame.scripts.OnEvent(frame, "UPDATE_BINDINGS") end
    end
    equal(addon:GetCurrentHotKey(), "CTRL-1")
end)

test("BetterAssistant switchback reacquires its core and releases old event handlers", function()
    local _, addon, state = fixture("BetterAssistant", true); state.activate()
    equal(addon:GetCurrentId(), 101)
    local eventFrame
    for _, frame in ipairs(state.frames) do if frame.events.UPDATE_BINDINGS then eventFrame = frame end end
    assert(eventFrame)
    local stale = eventFrame.scripts.OnEvent
    assert(state.other()); equal(eventFrame.scripts.OnEvent, nil); equal(next(eventFrame.events), nil)
    stale(eventFrame, "UPDATE_BINDINGS"); equal(addon:GetCurrentHotKey(), "OTHER")
    state.currentCore = state.core(202)
    assert(state.activate()); equal(addon:GetCurrentId(), 202); equal(addon:GetCurrentHotKey(), "2")
    equal(eventFrame.events.UPDATE_BINDINGS, true)
end)

parity("RotationHelper preserves dynamic recommendation and empty-label behavior", function(modern, providerRoot)
    local _, addon, state = fixture("RotationHelper", modern, providerRoot); state.activate()
    equal(addon:GetCurrentId(), 909); equal(addon:GetCurrentHotKey(), "9")
    state.key, state.suggestion.tooltipData = "", nil
    equal(addon:GetCurrentId(), nil); equal(addon:GetCurrentHotKey(), "")
end)

test("RotationHelper switchback installs fresh getters and ignores a closed session", function()
    local _, addon, state = fixture("RotationHelper", true); state.activate()
    local old = addon.GetCurrentHotKey
    assert(state.other()); equal(old(addon), nil)
    state.key = "CTRL-9"; assert(state.activate()); equal(addon:GetCurrentHotKey(), "CTRL-9")
end)

print(string.format("\n%d passed; %d failed (%s)", passed, failed, _VERSION))
if failed > 0 then error("Query-provider regressions failed: " .. failed) end
