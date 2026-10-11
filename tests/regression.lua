local root = _TEST_ROOT or (arg and arg[1]) or "."
local passed, failed = 0, 0

local function equal(actual, expected, description)
    if actual ~= expected then
        error((description or "value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function test(name, run)
    local ok, message = pcall(run)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(message))
    end
end

local function loadAddon(path, env, addon)
    local chunk, message
    if setfenv then
        chunk, message = loadfile(root .. "/src/" .. path)
        if chunk then setfenv(chunk, env) end
    else
        chunk, message = loadfile(root .. "/src/" .. path, "t", env)
    end
    assert(chunk, message)
    return chunk("WoWHACv5", addon)
end

local function band(a, b)
    local result, place = 0, 1
    while a > 0 or b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

local function environment()
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.bit = {
        band = band,
        bor = function(a, b) return a + b - band(a, b) end,
        lshift = function(a, b) return a * 2 ^ b end,
        rshift = function(a, b) return math.floor(a / 2 ^ b) end,
    }
    return env
end

local function addonFixture()
    local addon = { providers = {}, modules = {}, messages = {} }
    function addon:NewModule(name)
        local module = { RegisterEvent = function() end }
        self.modules[name] = module
        return module
    end
    function addon:Print(message) self.messages[#self.messages + 1] = message end
    function addon:Log(message) self:Print(message) end
    function addon:Debug() end
    function addon:RegisterEvent() end
    function addon:ScheduleRepeatingTimer(name, interval) self.timer = { name, interval } end
    function addon:SendMessage(name, value) self.sentMessage = { name, value } end
    return addon
end

local function loadKeyboard(env, addon)
    loadAddon("Utils/Keybinds.lua", env, addon)
    loadAddon("Utils/Binding.lua", env, addon)
    loadAddon("Utils/Protocol.lua", env, addon)
    loadAddon("Utils/Steganography.lua", env, addon)
end

test("legacy spell backports forward arguments and cooldown results", function()
    local env = environment()
    local rangeArguments
    env.GetSpellInfo = function(id) return "Spell " .. id, "Rank 1" end
    env.GetSpellCooldown = function(id) equal(id, 101); return 8, 4, 1 end
    env.IsUsableSpell = function(id) equal(id, 101); return true, false end
    env.IsSpellInRange = function(id, unit) rangeArguments = { id, unit }; return 0 end
    env.IsHarmfulSpell = function(id) return id == 101 end
    env.UnitIsVisible = function(unit) return unit == "focus" end
    loadAddon("Backports/CSpell.lua", env, {})
    local name, rank = env.C_Spell.GetSpellInfo(101)
    equal(name, "Spell 101"); equal(rank, "Rank 1")
    local cooldown = env.C_Spell.GetSpellCooldown(101)
    equal(cooldown.startTime, 8); equal(cooldown.duration, 4); equal(cooldown.isEnabled, true)
    local usable, noMana = env.C_Spell.IsSpellUsable(101)
    equal(usable, true); equal(noMana, false)
    equal(env.C_Spell.IsSpellInRange(101, "focus"), 0)
    equal(rangeArguments[1], 101); equal(rangeArguments[2], "focus")
    equal(env.C_Spell.IsSpellHarmful(101), true)
    equal(env.C_Spell.CanSpellBeCastOnUnit(101, "focus"), true)
    equal(env.GetUnitEmpowerStageDuration("player", 3), 0)
end)

test("legacy cooldown defaults handle absent data and disabled spells", function()
    local env = environment()
    env.GetSpellCooldown = function(id) if id == 1 then return nil, nil, nil end; return 0, 0, 0 end
    loadAddon("Backports/CSpell.lua", env, {})
    for id = 1, 2 do
        local cooldown = env.C_Spell.GetSpellCooldown(id)
        equal(cooldown.startTime, 0); equal(cooldown.duration, 0); equal(cooldown.isEnabled, false)
    end
end)

test("backports preserve every native spell method and empower API", function()
    local env = environment()
    local native = {}
    for _, name in ipairs({ "GetSpellInfo", "GetSpellCooldown", "IsSpellUsable", "IsSpellInRange",
        "IsSpellHarmful", "CanSpellBeCastOnUnit" }) do
        native[name] = function() return name end
    end
    env.C_Spell = native
    local empower = function() return 123 end
    env.GetUnitEmpowerStageDuration = empower
    local expected = {}
    for name, method in pairs(native) do expected[name] = method end
    loadAddon("Backports/CSpell.lua", env, {})
    equal(env.C_Spell, native)
    for name, method in pairs(expected) do equal(env.C_Spell[name], method, name) end
    equal(env.GetUnitEmpowerStageDuration, empower)
end)

test("partial native spell tables receive only missing methods", function()
    local env = environment()
    local nativeRange = function() return true end
    env.C_Spell = { IsSpellInRange = nativeRange }
    env.GetSpellCooldown = function() return 1, 2, true end
    loadAddon("Backports/CSpell.lua", env, {})
    equal(env.C_Spell.IsSpellInRange, nativeRange)
    equal(env.C_Spell.GetSpellCooldown(101).isEnabled, true)
end)

test("addon backport preserves native and forwards legacy addon lookups", function()
    local env = environment()
    env.IsAddOnLoaded = function(name) return name == "JustAC" end
    loadAddon("Backports/CAddOns.lua", env, {})
    equal(env.C_AddOns.IsAddOnLoaded("JustAC"), true)
    equal(env.C_AddOns.IsAddOnLoaded("Other"), false)
    local native = env.C_AddOns.IsAddOnLoaded
    loadAddon("Backports/CAddOns.lua", env, {})
    equal(env.C_AddOns.IsAddOnLoaded, native)
end)

local function rotationFixture(version, projectID, camelotID)
    local env, addon = environment(), addonFixture()
    local state = { now = 100, id = 101, hotkey = "CTRL-1", usable = true, range = 1,
        visible = true, combat = false, cooldownStart = 0, cooldownDuration = 0, apiCalls = 0 }
    env.GetBuildInfo = function() return "test", "70245", "test", version end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT = projectID, camelotID
    env.GetTime = function() return state.now end
    env.UnitCastingInfo = function()
        if state.casting then return "Cast", nil, nil, nil, state.castEnd or state.now * 1000 + 500 end
    end
    env.UnitChannelInfo = function()
        if state.channel then return "Channel", nil, nil, nil, state.channelEnd or state.now * 1000 + state.channel end
    end
    env.GetItemInfo = function(id) state.apiCalls = state.apiCalls + 1; if state.itemID == id then return "Item" end end
    env.GetItemCooldown = function() return state.cooldownStart, state.cooldownDuration, 1 end
    env.GetUnitEmpowerStageDuration = function() return state.empower or 0 end
    env.UnitAffectingCombat = function() return state.combat end
    env.C_Spell = {
        IsSpellUsable = function() state.apiCalls = state.apiCalls + 1; return state.usable end,
        GetSpellCooldown = function() return { startTime = state.cooldownStart, duration = state.cooldownDuration } end,
        IsSpellHarmful = function() return true end,
        IsSpellInRange = function(_, unit) equal(unit, "target"); return state.range end,
        CanSpellBeCastOnUnit = function() return state.visible end,
    }
    function addon:GetCurrentId()
        if state.throwId then error("current ID is unavailable") end
        return state.id
    end
    function addon:GetCurrentHotKey() return state.hotkey end
    function addon:GetNextHotKey() return state.nextHotkey end
    function addon:GetNextId() return state.nextId end
    function addon:SetCurrentHotKey(value) state.hotkey = value end
    function addon:SetCurrentId(value) state.id = value end
    addon.pixel = { SetColor = function(_, red, green, blue) state.color = { red, green, blue } end }
    loadKeyboard(env, addon)
    loadAddon("Rotation.lua", env, addon)
    return env, addon, state
end

local function assertPixel(addon, state, binding)
    addon:UpdatePixel()
    local expected = binding and addon.Protocol.EncodeBinding(binding) or { red = 0, green = 0, blue = 0 }
    assert(state.color, "pixel was not updated")
    equal(state.color[1], expected.red, "red"); equal(state.color[2], expected.green, "green")
    equal(state.color[3], expected.blue, "blue")
end

for _, client in ipairs({
    { "Forever project identity", 16001, 9, 9 },
    { "Forever project identity on a future interface", 16002, 9, 9 },
}) do
    test(client[1] .. " trusts supplier without legacy castability or ID reads", function()
        local _, addon, state = rotationFixture(client[2], client[3], client[4])
        state.usable, state.range, state.throwId = false, false, true
        assertPixel(addon, state, state.hotkey)
        equal(state.apiCalls, 0)
    end)
    test(client[1] .. " blocks active casts and channels without timestamp arithmetic", function()
        local _, addon, state = rotationFixture(client[2], client[3], client[4])
        state.throwId = true
        state.casting, state.castEnd = true, "inaccessible timestamp"
        assertPixel(addon, state)
        state.casting, state.channel, state.channelEnd = false, 299, "inaccessible timestamp"
        assertPixel(addon, state)
        state.channel = nil; assertPixel(addon, state, state.hotkey)
        equal(state.apiCalls, 0)
    end)
end

for _, client in ipairs({
    { "modern Retail", 120100, 1, 9 },
    { "existing TBC exception", 20505, 5, 9 },
}) do
    test(client[1] .. " trusts supplier readiness without legacy API reads", function()
        local _, addon, state = rotationFixture(client[2], client[3], client[4])
        state.usable, state.range = false, false
        assertPixel(addon, state, state.hotkey)
        equal(state.apiCalls, 0)
    end)
    test(client[1] .. " still blocks active casts and channels", function()
        local _, addon, state = rotationFixture(client[2], client[3], client[4])
        state.casting = true; assertPixel(addon, state)
        state.casting = false; state.channel = 300; assertPixel(addon, state)
        state.channel = 299; assertPixel(addon, state, state.hotkey)
        equal(state.apiCalls, 0)
    end)
end

for _, client in ipairs({
    { "interface 16001 without a Forever marker", 16001 },
    { "interface 16001 with a different project identity", 16001, 1, 9 },
}) do
    test(client[1] .. " retains original pixel gate", function()
        local _, addon, state = rotationFixture(client[2], client[3], client[4])
        state.usable = false; assertPixel(addon, state)
        assert(state.apiCalls > 0, "legacy castability API was bypassed")
        state.usable = true; state.casting = true; assertPixel(addon, state)
        state.casting = false; state.channel = 300; assertPixel(addon, state)
        state.channel = 299; assertPixel(addon, state, state.hotkey)
    end)
end

test("older clients retain spell usability, range, visibility and cooldown checks", function()
    local _, addon, state = rotationFixture(110000, 1, 9)
    assertPixel(addon, state, state.hotkey)
    state.usable = false; assertPixel(addon, state)
    state.usable = true; state.range = 0; assertPixel(addon, state)
    state.range = false; assertPixel(addon, state)
    state.range = nil; state.visible = false; assertPixel(addon, state)
    state.visible = true; state.cooldownStart = 100; state.cooldownDuration = 1; assertPixel(addon, state)
    state.cooldownDuration = 0.2; assertPixel(addon, state, state.hotkey)
end)

test("older clients retain their combat range bypass and item-ID bypass", function()
    local _, addon, state = rotationFixture(110000)
    state.combat = true; state.range = false; state.visible = false
    assertPixel(addon, state, state.hotkey)
    state.combat = false; state.usable = false; state.id = -5512
    assertPixel(addon, state, state.hotkey)
end)

test("Forever item suggestions encode without treating items as spells", function()
    local _, addon, state = rotationFixture(16001, 9, 9)
    state.id, state.hotkey = -5512, "SHIFT-F2"
    assertPixel(addon, state, state.hotkey)
    equal(state.apiCalls, 0)
    equal(addon.timer[1], "UpdatePixel"); equal(addon.timer[2], 0.1)
end)

test("spell events preserve advancing queued hotkeys", function()
    local _, addon, state = rotationFixture(16001, 9, 9)
    state.nextId, state.nextHotkey = 202, "ALT-2"
    addon:OnSpellcast("UNIT_SPELLCAST_SENT", "player")
    equal(state.color[1], 0); equal(state.id, 202); equal(state.hotkey, "ALT-2")
end)

for _, binding in ipairs({ "SPACE", "SCROLLLOCK", "CAPSLOCK", "APPLICATION", "ALT-SPACE",
    "CTRL-SCROLLLOCK", "ALT-CTRL-SHIFT-F1", "SHIFT-NUMPADPLUS", "CTRL-C", "SHIFT-S" }) do
    test("canonical binding survives normalization: " .. binding, function()
        local env, addon = environment(), addonFixture()
        loadKeyboard(env, addon)
        equal(addon:NormalizeModifiers(binding), binding)
        local expected, actual = addon.Protocol.EncodeBinding(binding), addon.Steganography(binding)
        assert(expected.action ~= 0, "binding has no action code")
        equal(actual.red, expected.red); equal(actual.green, expected.green); equal(actual.blue, expected.blue)
    end)
end

for _, binding in ipairs({ { "S1", "SHIFT-1" }, { "C1", "CTRL-1" }, { "SC1", "CTRL-SHIFT-1" },
    { "AS1", "ALT-SHIFT-1" }, { "C-SPACE", "CTRL-SPACE" }, { "CTRL-CTRL-1", "CTRL-1" } }) do
    test("legacy compact binding survives: " .. binding[1], function()
        local env, addon = environment(), addonFixture()
        loadKeyboard(env, addon)
        equal(addon:NormalizeModifiers(binding[1]), binding[2])
        local expected, actual = addon.Protocol.EncodeBinding(binding[2]), addon.Steganography(binding[1])
        equal(actual.red, expected.red); equal(actual.green, expected.green); equal(actual.blue, expected.blue)
        equal(env.count, nil, "normalization must not write global count")
    end)
end

local function frame(properties)
    properties = properties or {}
    properties.IsShown = properties.IsShown or function(self) return self.shown ~= false end
    properties.GetAlpha = properties.GetAlpha or function(self) return self.alpha or 1 end
    return properties
end

local function justACFixture(options)
    options = options or {}
    local env, addon = environment(), addonFixture()
    local state = { now = 100, queue = { 101 }, spellKeys = { [101] = "1", [202] = "2", [303] = "3" },
        itemKeys = { [5512] = "SHIFT-1" }, ready = true, low = false, cvarWrites = {}, scannerCalls = {} }
    local jac = { spellIcons = { frame({ spellID = 101, cachedHotkey = "STALE" }) } }
    local scanner = {
        GetSpellHotkey = function(id) state.scannerCalls[#state.scannerCalls + 1] = { "spell", id }; return state.spellKeys[id] end,
        GetItemHotkey = function(id, castID) state.scannerCalls[#state.scannerCalls + 1] = { "item", id, castID }; return state.itemKeys[id] end,
    }
    if options.normalize then scanner.GetNormalizedHotkey = options.normalize end
    if options.noSpellScanner then scanner.GetSpellHotkey = nil end
    env.GetTime = function() return state.now end
    env.LowHealthFrame = { IsShown = function() return state.low end }
    local getter = function() return state.suppressed == true end
    local setter = function(name, value) state.cvarWrites[#state.cvarWrites + 1] = { name, value } end
    if options.legacyCVar then env.GetCVarBool, env.SetCVar = getter, setter
    else env.C_CVar = { GetCVarBool = getter, SetCVar = setter } end
    local libraries = {
        ["AceAddon-3.0"] = { GetAddon = function(_, name) equal(name, "JustAssistedCombat"); return jac end },
        ["JustAC-SpellQueue"] = { WAIT_SENTINEL = -999999999, GetCurrentSpellQueue = function() return state.queue end },
        ["JustAC-ActionBarScanner"] = scanner,
        ["JustAC-BlizzardAPI"] = { IsSpellReady = function() return state.ready end },
    }
    env.LibStub = function(name) return libraries[name] end
    loadKeyboard(env, addon)
    loadAddon("Providers/JustACProvider.lua", env, addon)
    addon.providers.JustAC()
    return env, addon, state, jac, scanner
end

local function assertSuggestion(addon, id, hotkey)
    equal(addon:GetCurrentId(), id, "suggestion id")
    equal(addon:GetCurrentHotKey(), hotkey, "suggestion hotkey")
end

test("JustAC preserves interrupt > defensive > rotation priority", function()
    local _, addon, state, jac = justACFixture()
    jac.interruptIcon = frame({ spellID = 202 })
    jac.defensiveIcons = { frame({ currentID = 303 }) }
    state.low = true; assertSuggestion(addon, 202, "2")
    state.ready = false; assertSuggestion(addon, 303, "3")
    state.low = false; assertSuggestion(addon, 101, "1")
end)

test("JustAC skips hidden, transparent, waiting and unusable suggestions", function()
    local _, addon, state, jac = justACFixture()
    jac.interruptIcon = frame({ spellID = 202, alpha = 0 })
    jac.defensiveIcons = { frame({ currentID = 303, isWaiting = true }),
        frame({ currentID = 303, cachedDefUsable = false }), frame({ currentID = 303, shown = false }) }
    state.low = true; assertSuggestion(addon, 101, "1")
end)

test("JustAC uses displayed interrupt when alpha comparison is inaccessible", function()
    local _, addon, _, jac = justACFixture()
    jac.interruptIcon = frame({ spellID = 202, GetEffectiveAlpha = function() error("secret alpha") end })
    assertSuggestion(addon, 202, "2")
end)

test("JustAC defensive items use negative IDs and forward cast spell IDs", function()
    local _, addon, state, jac = justACFixture()
    jac.defensiveIcons = { frame({ currentID = 5512, isItem = true, itemCastSpellID = 6262 }) }
    state.low = true; assertSuggestion(addon, -5512, "SHIFT-1")
    equal(state.scannerCalls[1][1], "item"); equal(state.scannerCalls[1][2], 5512)
    equal(state.scannerCalls[1][3], 6262)
end)

test("JustAC rotation items use positive scanner IDs", function()
    local _, addon, state, jac = justACFixture()
    state.queue = { -5512 }; jac.spellIcons[1] = frame({ spellID = -5512, itemCastSpellID = 6262 })
    assertSuggestion(addon, -5512, "SHIFT-1")
    equal(state.scannerCalls[1][2], 5512); equal(state.scannerCalls[1][3], 6262)
end)

for _, value in ipairs({ 0, -999999999 }) do
    test("JustAC ignores waiting queue entry " .. value, function()
        local _, addon, state = justACFixture()
        state.queue = { value }; assertSuggestion(addon, nil, "")
        equal(#state.scannerCalls, 0)
    end)
end

test("JustAC ignores missing and empty queues", function()
    local _, addon, state = justACFixture()
    state.queue = nil; assertSuggestion(addon, nil, "")
    state.queue = {}; assertSuggestion(addon, nil, "")
end)

test("JustAC scanner emptiness stays authoritative over stale cached labels", function()
    local _, addon, state, jac = justACFixture()
    state.spellKeys[101] = ""
    equal(addon:GetCurrentHotKey(), "")
    state.low = true; jac.defensiveIcons = { frame({ currentID = 303, cachedHotkey = "OLD" }) }
    state.spellKeys[303] = ""; equal(addon:GetCurrentHotKey(), "")
end)

test("JustAC legacy scanners retain label and unavailable scanners use matching cache", function()
    local _, addon, state = justACFixture()
    state.spellKeys[101] = "C1"; assertSuggestion(addon, 101, "C1")
    local _, cachedAddon, cachedState, jac = justACFixture({ noSpellScanner = true })
    jac.spellIcons[1].cachedHotkey = "S1"; assertSuggestion(cachedAddon, 101, "S1")
    cachedState.queue = { 404 }; equal(cachedAddon:GetCurrentHotKey(), "")
end)

test("JustAC normalized scanner labels encode named keys end to end", function()
    local env, addon, state = justACFixture({ normalize = function(label)
        return ({ Spc = "SPACE", SL = "SCROLLLOCK", texture = "ALT-CTRL-SHIFT-F1" })[label]
    end })
    for label, binding in pairs({ Spc = "SPACE", SL = "SCROLLLOCK", texture = "ALT-CTRL-SHIFT-F1" }) do
        state.spellKeys[101] = label; assertSuggestion(addon, 101, binding)
        local actual, expected = addon.Steganography(addon:GetCurrentHotKey()), addon.Protocol.EncodeBinding(binding)
        equal(actual.red, expected.red); equal(actual.green, expected.green); equal(actual.blue, expected.blue)
    end
    equal(env.count, nil)
end)

test("JustAC optional normalization can preserve unknown labels and normalize cached labels", function()
    local _, addon, state = justACFixture({ normalize = function() return nil end })
    state.spellKeys[101] = "C1"; assertSuggestion(addon, 101, "C1")
    local _, cachedAddon, _, jac = justACFixture({ noSpellScanner = true, normalize = function() return "SPACE" end })
    jac.spellIcons[1].cachedHotkey = "Spc"; assertSuggestion(cachedAddon, 101, "SPACE")
end)

for _, legacy in ipairs({ false, true }) do
    test("JustAC low-health CVar remains enabled and throttled (legacy=" .. tostring(legacy) .. ")", function()
        local _, addon, state = justACFixture({ legacyCVar = legacy })
        equal(#state.cvarWrites, 0)
        state.suppressed = true; state.now = 101
        addon:GetCurrentHotKey(); equal(#state.cvarWrites, 1)
        equal(state.cvarWrites[1][1], "doNotFlashLowHealthWarning"); equal(state.cvarWrites[1][2], "0")
        addon:GetCurrentId(); equal(#state.cvarWrites, 1)
        state.now = 102; addon:GetCurrentId(); equal(#state.cvarWrites, 2)
    end)
end

test("login selects loaded JustAC and preserves WeakAuras message", function()
    local env, addon = environment(), addonFixture()
    local calls = 0
    addon.providers.JustAC = function() calls = calls + 1 end
    addon.Provider = function() error("fallback should not run") end
    env.C_AddOns = { IsAddOnLoaded = function(name) return name == "JustAC" or name == "WeakAuras" end }
    loadAddon("Handlers/PlayerLoginHandler.lua", env, addon)
    addon.modules.PlayerLoginHandler:PLAYER_ENTERING_WORLD()
    equal(calls, 1); equal(addon.sentMessage[1], "WOWHACV4_WA_PRESENTS"); equal(addon.sentMessage[2], true)
end)

print(string.format("\n%d passed; %d failed (%s)", passed, failed, _VERSION))
if failed > 0 then error("regressions failed: " .. failed) end
