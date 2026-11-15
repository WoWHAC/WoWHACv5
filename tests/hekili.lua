local root = _TEST_ROOT or (arg and arg[1]) or "."
local hekiliRoot = _HEKILI_ROOT or (arg and arg[2]) or ""
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

local function load(path, env, addon, name)
    local chunk, message
    if setfenv then
        chunk, message = loadfile(path)
        if chunk then setfenv(chunk, env) end
    else chunk, message = loadfile(path, "t", env) end
    assert(chunk, message)
    return chunk(name or "WoWHACv5", addon)
end

local function source(path, env, addon) return load(root .. "/src/" .. path, env, addon) end

local function band(left, right)
    local result, place = 0, 1
    while left > 0 or right > 0 do
        if left % 2 == 1 and right % 2 == 1 then result = result + place end
        left, right, place = math.floor(left / 2), math.floor(right / 2), place * 2
    end
    return result
end

local function makeEngine(env, state)
    local engine, private = {}, {}
    env.Hekili.Engine = engine
    if hekiliRoot ~= "" then
        load(hekiliRoot .. "/Engine/Output.lua", env, private, "Hekili")
        private.Output.steady = false
        private = private.Output
    else
        local out = { count = 0, recs = {}, wanted = 0 }
        local subscribers = {}
        engine.Output = { Primary = out }
        function engine.Subscribe(name, callback, passive)
            equal(name, "Primary")
            subscribers[callback] = passive == true
            if not passive then out.wanted = out.wanted + 1 end
            return true
        end
        function engine.Unsubscribe(name, callback)
            equal(name, "Primary")
            if subscribers[callback] == false then out.wanted = out.wanted - 1 end
            subscribers[callback] = nil
        end
        function private.Begin() return {} end
        function private.Publish(_, count)
            out.count, out.recs = count, state.pending
            for callback in pairs(subscribers) do callback("Primary", 1, out) end
        end
    end
    engine.settings = { enabled = true, displays = { Primary = {} } }
    local subscribe, unsubscribe = engine.Subscribe, engine.Unsubscribe
    function engine.Subscribe(name, callback, passive, needs)
        state.subscription = { name, callback, passive }
        if state.subscriptionFailure then return false end
        return subscribe(name, callback, passive, needs)
    end
    function engine.Unsubscribe(name, callback)
        equal(callback, state.subscription[2], "cleanup callback identity")
        state.unsubscribed = state.unsubscribed + 1
        return unsubscribe(name, callback)
    end
    function state.publish(record, count)
        local records = private.Begin("Primary")
        if record then
            records[1] = records[1] or {}
            for key, value in pairs(record) do records[1][key] = value end
        end
        state.pending = records
        private.Publish("Primary", count or (record and 1 or 0))
    end
    return engine
end

local function fixture(mode)
    mode = mode or "forever"
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.bit = {
        band = band,
        bor = function(a, b) return a + b - band(a, b) end,
        lshift = function(a, b) return a * 2 ^ b end,
        rshift = function(a, b) return math.floor(a / 2 ^ b) end,
    }
    local state = { now = 100, bindings = { attack = "CTRL-1", potion = "SHIFT-2" }, hooks = {},
        settings = {}, unsubscribed = 0, shown = false, loaded = { Hekili = true, Other = true } }
    local addon = { providers = {} }
    function addon:Log() end
    function addon:Debug() end
    function addon:SendMessage() end
    function addon:GetSettings() return state.settings end
    function addon:SecureHook(target, method, callback)
        state.hooks[target] = state.hooks[target] or {}; state.hooks[target][method] = callback
    end
    function addon:Unhook(target, method) state.hooks[target][method] = nil end
    addon.ToggleHekiliFrame = {
        Init = function() end,
        Show = function() state.shown = true end,
        Hide = function() state.shown = false end,
    }
    addon.pixel = { SetColor = function(_, r, g, b) state.color = { r, g, b } end }
    env.WOW_PROJECT_CAMELOT, env.WOW_PROJECT_MAINLINE = 9, 1
    env.WOW_PROJECT_ID = mode == "forever" and 9 or 1
    env.GetBuildInfo = function() return "test", "test", "test", mode == "retail" and 120100 or 16001 end
    env.GetTime = function() return state.now end
    env.UnitName = function() return "Tester" end
    env.UnitGUID = function() return "Player-Test" end
    env.InCombatLockdown = function() return false end
    env.C_AddOns = {
        IsAddOnLoaded = function(id) return state.loaded[id] end,
        GetAddOnEnableState = function() return 2 end,
        GetAddOnLocalTable = function() return {} end,
    }
    env.Hekili = { DB = { profile = { enabled = true, displays = { Primary = {} } } } }
    source("Utils/ClientFeatures.lua", env, addon)
    source("Providers/Provider.lua", env, addon)
    source("Providers/ProviderRegistry.lua", env, addon)
    source("Utils/Binding.lua", env, addon)
    source("Utils/Protocol.lua", env, addon)
    source("Utils/Keybinds.lua", env, addon)
    source("Utils/Steganography.lua", env, addon)
    if mode == "forever" then
        state.engine = makeEngine(env, state)
        function env.Hekili:GetBindingForAction(action, display, index)
            equal(display, state.engine.settings.displays.Primary, "current display settings")
            equal(index, 1)
            return state.bindings[action]
        end
    end
    source("Providers/HekiliProvider.lua", env, addon)
    function state.activate()
        if addon:SupportsModernFeatures() then return addon:SelectProvider("Hekili") end
        return addon.providers.Hekili()
    end
    function state.ready(overrides)
        local record = { actionID = 101, actionName = "attack", keybind = "STALE", exact_time = state.now }
        for key, value in pairs(overrides or {}) do record[key] = value end
        state.publish(record)
    end
    return env, addon, state
end

local function suggestion(addon, id, key)
    local actualID, actualKey = addon:GetCurrentSuggestion()
    equal(actualID, id, "paired ID"); equal(actualKey, key, "paired binding")
end

test("Forever activates from Engine API without legacy UI frames", function()
    local _, addon, state = fixture()
    assert(state.activate()); equal(addon:GetActiveProvider(), "Hekili")
    equal(state.subscription[1], "Primary"); equal(state.subscription[3], false)
    equal(state.engine.Output.Primary.wanted, 1)
    suggestion(addon, nil, nil)
    state.ready(); suggestion(addon, 101, "CTRL-1")
    equal(addon:GetCurrentId(), 101); equal(addon:GetCurrentHotKey(), "CTRL-1")
end)

test("paired recommendations follow the published buffer swap", function()
    local _, addon, state = fixture(); assert(state.activate())
    state.ready(); suggestion(addon, 101, "CTRL-1")
    state.bindings.attack = "ALT-F3"; state.ready({ actionID = 202 })
    suggestion(addon, 202, "ALT-F3")
end)

test("empty output count invalidates a retained recommendation record", function()
    local _, addon, state = fixture(); assert(state.activate())
    state.ready(); suggestion(addon, 101, "CTRL-1")
    state.engine.Output.Primary.count = 0; suggestion(addon, nil, nil)
    state.publish(nil); suggestion(addon, nil, nil)
end)

test("disabled engine and pause silence output immediately", function()
    local env, addon, state = fixture(); assert(state.activate()); state.ready()
    state.engine.settings.enabled = false; suggestion(addon, nil, nil)
    state.engine.settings.enabled = true; env.Hekili.Pause = true; suggestion(addon, nil, nil)
    env.Hekili.Pause = false; suggestion(addon, 101, "CTRL-1")
end)

test("future recommendations wait until their readiness window", function()
    local _, addon, state = fixture(); assert(state.activate())
    state.ready({ exact_time = 101 }); suggestion(addon, nil, nil)
    state.now = 100.96; suggestion(addon, 101, "CTRL-1")
end)

test("unbound current action does not reuse its published keybind", function()
    local _, addon, state = fixture(); assert(state.activate()); state.ready()
    state.bindings.attack = ""; suggestion(addon, nil, nil)
    state.bindings.attack = nil; suggestion(addon, nil, nil)
    state.bindings.attack = "SHIFT-4"; suggestion(addon, 101, "SHIFT-4")
end)

test("older Engine API without binding getter uses record keybind", function()
    local env, addon, state = fixture(); env.Hekili.GetBindingForAction = nil
    assert(state.activate()); state.ready({ keybind = "CTRL-SPACE" })
    suggestion(addon, 101, "CTRL-SPACE")
end)

test("item recommendations return negative item IDs", function()
    local _, addon, state = fixture(); assert(state.activate())
    state.ready({ actionName = "potion", actionID = -5512, item = 5512 })
    suggestion(addon, -5512, "SHIFT-2")
end)

test("blank and invalid actions cannot emit a bound key", function()
    local _, addon, state = fixture(); assert(state.activate())
    state.ready({ actionID = 0 }); suggestion(addon, nil, nil)
    state.ready({ actionID = -5 }); suggestion(addon, nil, nil)
    state.ready({ actionName = "" }); suggestion(addon, nil, nil)
end)

test("binding changes encode exact canonical keys", function()
    local _, addon, state = fixture(); assert(state.activate()); state.ready()
    for _, key in ipairs({ "SPACE", "CTRL-SCROLLLOCK", "ALT-CTRL-SHIFT-F1" }) do
        state.bindings.attack = key; suggestion(addon, 101, key)
        local actual = addon.Steganography(select(2, addon:GetCurrentSuggestion()))
        local expected = addon.Protocol.EncodeBinding(key)
        assert(expected.action ~= 0)
        equal(actual.red, expected.red); equal(actual.green, expected.green); equal(actual.blue, expected.blue)
    end
end)

test("Forever binding abbreviations encode their actual keyboard keys", function()
    local _, addon, state = fixture(); assert(state.activate()); state.ready()
    for _, binding in ipairs({
        { "N1", "NUMPAD1" }, { "CN1", "CTRL-NUMPAD1" }, { "SM4", "SHIFT-BUTTON4" },
        { "AN-", "ALT-NUMPADMINUS" }, { "N+", "NUMPADPLUS" }, { "N*", "NUMPADMULTIPLY" },
        { "N/", "NUMPADDIVIDE" }, { "N.", "NUMPADDECIMAL" }, { "NENTER", "NUMPADENTER" },
        { "Dn", "DOWN" }, { "N", "N" }, { "CTRL-M", "CTRL-M" }, { "SPACE", "SPACE" },
    }) do
        state.bindings.attack = binding[1]; suggestion(addon, 101, binding[2])
        local actual = addon.Steganography(select(2, addon:GetCurrentSuggestion()))
        local expected = addon.Protocol.EncodeBinding(binding[2])
        assert(expected.action ~= 0, binding[1] .. " has no action code")
        equal(actual.red, expected.red, binding[1] .. " red")
        equal(actual.green, expected.green, binding[1] .. " green")
        equal(actual.blue, expected.blue, binding[1] .. " blue")
    end
end)

test("minor cooldown toggle selects Forever name and preserves legacy fallback", function()
    for _, forever in ipairs({ false, true }) do
        local env, addon = fixture("legacy")
        env.UIParent = {}
        env.Hekili.DB.profile.toggles = { essences = {}, custom1 = { name = "one" }, custom2 = { name = "two" } }
        if forever then env.Hekili.DB.profile.toggles.minor_cooldowns = {} end
        env.CreateFrame = function()
            local frame = {}
            for _, method in ipairs({ "SetClampedToScreen", "SetMovable", "EnableMouse", "SetWidth",
                "SetHeight", "ClearAllPoints", "SetPoint", "Show" }) do frame[method] = function() end end
            return frame
        end
        source("Frames/ToggleHekiliFrame.lua", env, addon)
        local buttons = {}
        function addon.ToggleHekiliFrame:AddButton(toggle, text) buttons[text] = toggle end
        addon.ToggleHekiliFrame:Init()
        equal(buttons.E, forever and "minor_cooldowns" or "essences")
        for text, toggle in pairs({ C = "cooldowns", I = "interrupts", D = "defensives", P = "potions",
            ["1"] = "custom1", ["2"] = "custom2" }) do equal(buttons[text], toggle) end
    end
end)

test("provider switch unsubscribes and makes old callbacks inert", function()
    local _, addon, state = fixture(); assert(state.activate()); state.ready()
    local staleGetter, staleCallback = addon.GetCurrentSuggestion, state.subscription[2]
    addon.providers.Other = function() function addon:GetCurrentSuggestion() return 909, "9" end end
    assert(addon:SelectProvider("Other")); equal(state.unsubscribed, 1)
    equal(state.engine.Output.Primary.wanted, 0); equal(state.shown, false)
    staleCallback("Primary", 2, state.engine.Output.Primary)
    equal(staleGetter(addon), nil); suggestion(addon, 909, "9")
    assert(addon:SelectProvider("Hekili")); equal(state.engine.Output.Primary.wanted, 1)
end)

test("unavailable provider stops and releases its active subscription", function()
    local _, addon, state = fixture(); assert(state.activate()); state.ready()
    state.loaded.Hekili = false; addon:RefreshProviders()
    equal(state.unsubscribed, 1); equal(addon:GetActiveProvider(), nil)
    equal(addon.GetCurrentSuggestion, nil); equal(addon:GetCurrentId(), 0)
end)

test("full subscriber slots reject initialization cleanly", function()
    local _, addon, state = fixture(); state.subscriptionFailure = true
    equal(state.activate(), false); equal(addon:GetActiveProvider(), nil)
    equal(addon:GetCurrentId(), 0); equal(state.shown, false)
end)

for _, mode in ipairs({ "legacy", "retail" }) do
    test(mode .. " primary keybinding hook retains previous integration", function()
        local env, addon, state = fixture(mode)
        local keybind = { GetText = function() return "C1" end }
        env.Hekili_Primary_B1 = { Keybinding = keybind, Ability = { id = 101 } }
        assert(state.activate() ~= false)
        if mode == "retail" then equal(addon:GetCurrentId(), 101); equal(addon:GetCurrentHotKey(), "C1") end
        env.Hekili_Primary_B1.Ability.id = 202
        state.hooks[keybind].SetText(keybind, "S2")
        equal(addon:GetCurrentId(), 202); equal(addon:GetCurrentHotKey(), "S2")
        if mode == "retail" then
            state.loaded.Hekili = false; addon:RefreshProviders()
            equal(state.hooks[keybind].SetText, nil)
        end
    end)
    test(mode .. " older D1 function and text getters retain previous integration", function()
        local env, addon, state = fixture(mode)
        env.Hekili_D1_B1_KB = { GetText = function() return "A1" end }
        env.Hekili_GetRecommendedAbility = function(display, slot) equal(display, 1); equal(slot, 1); return 303 end
        assert(state.activate() ~= false)
        equal(addon:GetCurrentId(), 303); equal(addon:GetCurrentHotKey(), "A1")
    end)
end

print(string.format("\n%d passed; %d failed (%s, %s)", passed, failed, _VERSION,
    hekiliRoot ~= "" and "real Hekili Output" or "public API fixture"))
if failed > 0 then error("Hekili regressions failed: " .. failed) end
