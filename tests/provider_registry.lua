local sourceRoot = _SOURCE_ROOT or (arg and arg[1]) or "."
local passed, failed = 0, 0

local function equal(actual, expected, label)
    if actual ~= expected then error((label or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual), 2) end
end

local function test(name, run)
    local ok, message = pcall(run)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(message)) end
end

local function loadSource(path, env, addon)
    local chunk, message
    if setfenv then
        chunk, message = loadfile(sourceRoot .. "/src/" .. path)
        if chunk then setfenv(chunk, env) end
    else chunk, message = loadfile(sourceRoot .. "/src/" .. path, "t", env) end
    assert(chunk, message); return chunk("WoWHACv5", addon)
end

local function fixture()
    local env = setmetatable({}, { __index = _G }); env._G = env
    local state = { settings = {}, loaded = {}, hooks = {}, timers = {}, logs = {}, messages = {},
        combat = false, icon = nil, iconClears = 0, cleanups = 0, initialized = {} }
    local addon = { providers = {} }
    function addon:SupportsModernFeatures() return true end
    function addon:Debug() end
    function addon:Log(message) state.logs[#state.logs + 1] = message end
    function addon:SendMessage(name, payload) state.messages[#state.messages + 1] = { name, payload } end
    function addon:GetSettings() return state.settings end
    function addon:ClearRecommendationProvider() state.icon = nil; state.iconClears = state.iconClears + 1 end
    function addon:SecureHook(target, method, callback)
        state.hooks[target] = state.hooks[target] or {}; state.hooks[target][method] = callback
    end
    function addon:Unhook(target, method) state.hooks[target][method] = nil end
    addon.pixel = { SetColor = function(_, red, green, blue) state.pixel = { red, green, blue } end }
    env.InCombatLockdown = function() return state.combat end
    env.UnitName = function() return "Tester" end
    env.UnitGUID = function() return "Player-Test" end
    env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_ID = 1, 1
    env.C_AddOns = { IsAddOnLoaded = function(id) return state.loaded[id] end,
        GetAddOnEnableState = function() return 2 end, GetAddOnLocalTable = function() return {} end }
    env.C_Timer = { NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback }
        function timer:Cancel() self.cancelled = true end
        state.timers[#state.timers + 1] = timer; return timer
    end }
    loadSource("Providers/Provider.lua", env, addon)
    loadSource("Providers/ProviderRegistry.lua", env, addon)
    function state.register(id, initialize)
        state.loaded[id] = true
        addon.providers[id] = function(session)
            state.initialized[id] = (state.initialized[id] or 0) + 1
            return initialize(session)
        end
    end
    function state.seed(id, key)
        addon:SetCurrentId(id or 101); addon:SetCurrentHotKey(key or "1")
        addon:SetNextId(202); addon:SetNextHotKey("2")
        addon.pixel:SetColor(1, 1, 1); state.icon = "old recommendation"
    end
    return env, addon, state
end

local function assertCleared(addon, state)
    equal(addon:GetCurrentId(), 0); equal(addon:GetCurrentHotKey(), nil)
    equal(addon:GetNextId(), nil); equal(addon:GetNextHotKey(), nil)
    equal(state.pixel[1], 0); equal(state.pixel[2], 0); equal(state.pixel[3], 0)
    equal(state.icon, nil, "recommendation icon")
end

test("transient getter failure clears stale output and recovers next tick in combat", function()
    local _, addon, state = fixture()
    state.register("Recover", function(session)
        session:AddCleanup(function() state.cleanups = state.cleanups + 1 end)
        function addon:GetCurrentSuggestion()
            if state.fail then error("temporary getter", 0) end
            return 303, "3"
        end
    end)
    assert(addon:SelectProvider("Recover")); state.seed(); state.combat, state.fail = true, true
    equal(addon:GetCurrentSuggestion(), nil); assertCleared(addon, state)
    equal(addon:GetActiveProvider(), "Recover"); equal(state.cleanups, 0)
    state.fail = false
    local id, key = addon:GetCurrentSuggestion(); equal(id, 303); equal(key, "3")
    equal(state.initialized.Recover, 1)
end)

test("repeated runtime error logs are deduplicated per guarded callback", function()
    local _, addon, state = fixture()
    state.register("Recover", function()
        function addon:GetCurrentSuggestion() error("same temporary error", 0) end
        function addon:GetCurrentId() error("same temporary error", 0) end
    end)
    assert(addon:SelectProvider("Recover"))
    for _ = 1, 3 do addon:GetCurrentSuggestion() end
    equal(#state.logs, 1); equal(addon:GetActiveProvider(), "Recover")
    for _ = 1, 3 do addon:GetCurrentId() end
    equal(#state.logs, 2, "independent getter error log")
end)

test("aggregated getters suppress the old key when a nested ID getter fails", function()
    local _, addon, state = fixture(); state.outputKey = "1"
    state.register("Recover", function()
        function addon:GetCurrentId()
            if state.fail then error("temporary ID getter", 0) end
            return 303
        end
        function addon:GetCurrentHotKey() return state.outputKey end
    end)
    assert(addon:SelectProvider("Recover")); state.seed(); state.fail = true
    assert(type(addon.GetCurrentSuggestion) == "function", "modern scalar getters need a paired reader")
    local id, key = addon:GetCurrentSuggestion(); equal(id, nil); equal(key, nil)
    equal(addon:GetActiveProvider(), "Recover"); equal(state.icon, nil)
    equal(addon:GetNextId(), nil); equal(state.pixel[1], 0)
    state.fail, state.outputKey = false, "3"
    id, key = addon:GetCurrentSuggestion(); equal(id, 303); equal(key, "3")
    equal(state.initialized.Recover, 1)
end)

test("hook recovery keeps hook ownership and original callback arguments", function()
    local _, addon, state = fixture(); local target = {}
    state.register("Hook", function(session)
        session:SecureHook(target, "SetText", function(self, text, extra)
            equal(self, target); equal(extra, 42)
            if state.fail then error("temporary hook", 0) end
            addon:SetCurrentId(303); addon:SetCurrentHotKey(text)
        end)
    end)
    assert(addon:SelectProvider("Hook")); state.seed(); state.fail = true
    local hook = state.hooks[target].SetText
    hook(target, "SHIFT-3", 42)
    equal(state.hooks[target].SetText, hook); equal(addon:GetActiveProvider(), "Hook")
    assertCleared(addon, state)
    state.fail = false; hook(target, "SHIFT-3", 42)
    equal(addon:GetCurrentId(), 303); equal(addon:GetCurrentHotKey(), "SHIFT-3")
end)

test("timer error keeps the session and other pending timers alive", function()
    local _, addon, state = fixture()
    state.register("Timer", function(session)
        session:After(0.1, function(value) equal(value, "tick"); error("temporary timer", 0) end)
        session:After(10, function(value) addon:SetCurrentId(404); addon:SetCurrentHotKey(value) end)
    end)
    assert(addon:SelectProvider("Timer")); state.seed()
    state.timers[1].callback("tick")
    equal(addon:GetActiveProvider(), "Timer"); equal(state.timers[2].cancelled, nil)
    assertCleared(addon, state)
    state.timers[2].callback("4")
    equal(addon:GetCurrentId(), 404); equal(addon:GetCurrentHotKey(), "4")
end)

test("closed session hook timer and getter callbacks remain inert", function()
    local _, addon, state = fixture(); local target = {}; local calls = 0
    state.register("Old", function(session)
        function addon:GetCurrentSuggestion() calls = calls + 1; return 101, "1" end
        session:SecureHook(target, "SetText", function() calls = calls + 1 end)
        session:After(1, function() calls = calls + 1 end)
    end)
    state.register("New", function() function addon:GetCurrentSuggestion() return 777, "7" end end)
    assert(addon:SelectProvider("Old"))
    local getter, hook, timer = addon.GetCurrentSuggestion, state.hooks[target].SetText, state.timers[1]
    assert(addon:SelectProvider("New")); equal(state.hooks[target].SetText, nil); equal(timer.cancelled, true)
    getter(addon); hook(target, "old"); timer.callback()
    equal(calls, 0); local id, key = addon:GetCurrentSuggestion(); equal(id, 777); equal(key, "7")
end)

test("old callback error after switching cannot clear the new provider", function()
    local _, addon, state = fixture()
    state.register("Old", function()
        function addon:GetCurrentSuggestion()
            assert(addon:SelectProvider("New")); error("late old callback error", 0)
        end
    end)
    state.register("New", function() state.seed(777, "7") end)
    assert(addon:SelectProvider("Old")); equal(addon:GetCurrentSuggestion(), nil)
    equal(addon:GetActiveProvider(), "New"); equal(addon:GetCurrentId(), 777)
    equal(addon:GetCurrentHotKey(), "7"); equal(state.icon, "old recommendation")
    equal(state.pixel[1], 1)
end)

test("temporarily unready saved provider uses fallback without losing the preference", function()
    local _, addon, state = fixture(); local ready = false
    state.register("Preferred", function() return ready end)
    state.register("Fallback", function() end)
    state.settings.selectedProvider = "Preferred"
    assert(addon:RefreshProviders()); equal(addon:GetActiveProvider(), "Fallback")
    equal(state.settings.selectedProvider, "Preferred")
    ready = true; assert(addon:RefreshProviders())
    equal(addon:GetActiveProvider(), "Preferred"); equal(state.settings.selectedProvider, "Preferred")
end)

test("missing saved provider allows fallback to become the saved choice", function()
    local _, addon, state = fixture()
    state.register("Fallback", function() end); state.settings.selectedProvider = "Missing"
    assert(addon:RefreshProviders()); equal(addon:GetActiveProvider(), "Fallback")
    equal(state.settings.selectedProvider, "Fallback")
end)

test("all unready initializers retain the still-present saved preference", function()
    local _, addon, state = fixture()
    state.register("Preferred", function() return false end)
    state.register("Fallback", function() return false end)
    state.settings.selectedProvider = "Preferred"
    equal(addon:RefreshProviders(), false); equal(addon:GetActiveProvider(), nil)
    equal(state.settings.selectedProvider, "Preferred")
end)

test("explicit failed selection rolls back to the previous provider", function()
    local _, addon, state = fixture()
    state.register("Fallback", function() state.seed(101, "1") end)
    state.register("Unready", function(session)
        session:AddCleanup(function() state.cleanups = state.cleanups + 1 end)
        return false
    end)
    assert(addon:SelectProvider("Fallback"))
    local ok, reason = addon:SelectProvider("Unready")
    equal(ok, false); equal(reason, "initialization_failed")
    equal(addon:GetActiveProvider(), "Fallback"); equal(state.settings.selectedProvider, "Fallback")
    equal(state.cleanups, 1); equal(addon:GetCurrentId(), 101)
end)

test("combat refresh cannot initialize or change a pending saved selection", function()
    local _, addon, state = fixture()
    state.register("Fallback", function() end); state.register("Preferred", function() return false end)
    assert(addon:SelectProvider("Fallback")); state.settings.selectedProvider = "Preferred"
    state.combat = true
    local ok, reason = addon:RefreshProviders()
    equal(ok, false); equal(reason, "combat"); equal(addon:GetActiveProvider(), "Fallback")
    equal(state.settings.selectedProvider, "Preferred"); equal(state.initialized.Preferred, nil)
    equal(state.initialized.Fallback, 1)
end)

test("initializer exception remains a terminal initialization failure with cleanup", function()
    local _, addon, state = fixture()
    state.register("Broken", function(session)
        session:AddCleanup(function() state.cleanups = state.cleanups + 1 end)
        state.seed(); error("initialization failed", 0)
    end)
    local ok, reason = addon:SelectProvider("Broken")
    equal(ok, false); equal(reason, "initialization_failed")
    equal(addon:GetActiveProvider(), nil); equal(state.cleanups, 1)
    equal(addon:GetCurrentId(), 0); equal(state.pixel[1], 0)
end)

print(string.format("\n%d passed; %d failed (%s)", passed, failed, _VERSION))
if failed > 0 then error("Provider registry regressions failed: " .. failed) end
