local root = _TEST_ROOT or arg[1]
local baselinePath = _BASELINE_PATH or arg[2]
local candidatePath = _CANDIDATE_PATH or arg[3]
local pipelineDir = _PIPELINE_DIR or (arg and arg[4]) or ""
local passed, failed = 0, 0

local function equal(actual, expected, description)
    if actual ~= expected then error((description or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual), 2) end
end

local function test(name, callback)
    local ok, message = pcall(callback)
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
    local base = root
    if pipelineDir ~= "" and (path == "Utils/PriorityOverlays.lua" or path == "Rotation.lua") then base = pipelineDir end
    return load(base .. "/src/" .. path, env, addon)
end

local function icon(values)
    values = values or {}
    function values:IsShown() return self.shown ~= false end
    function values:GetAlpha() return self.alpha == nil and 1 or self.alpha end
    return values
end

local function fixture(providerPath, client)
    local env = setmetatable({}, { __index = _G }); env._G = env
    local state = { now = 100, queue = { 101 }, queueCalls = 0, low = false, ready = true,
        bindings = { [101] = "1", [202] = "2", [303] = "3", [888] = "8", [999] = "9" },
        itemBindings = { [5512] = "SHIFT-1" }, scannerCalls = {}, cvarWrites = 0,
        loaded = { JustAC = true, Other = true }, settings = {}, frames = {} }
    local addon = { providers = {}, modules = {} }
    function addon:Log() end
    function addon:Debug() end
    function addon:GetSettings() return state.settings end
    function addon:SendMessage() end
    function addon:NewModule(name)
        local module = { RegisterEvent = function() end, RegisterMessage = function() end }
        self.modules[name] = module; return module
    end
    function addon:ScheduleRepeatingTimer() end
    function addon:RegisterEvent() end
    local nativePixel = { GetFrameLevel = function() return 1 end }
    addon.pixel = { frame = nativePixel, pixels = { {}, {} },
        SetColor = function(_, red, green, blue) state.color = { red, green, blue } end }
    env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CAMELOT = 1, 9
    env.WOW_PROJECT_ID = client == "forever" and 9 or 1
    env.GetBuildInfo = function() return "test", "test", "test", client == "forever" and 16001 or 120100 end
    env.GetTime = function() return state.now end
    env.UnitName = function() return "Tester" end
    env.UnitGUID = function() return "Player-Test" end
    env.UnitAffectingCombat = function() return true end
    env.InCombatLockdown = function() return false end
    env.UnitCastingInfo = function()
        if state.casting then return "Cast", nil, nil, nil, (state.now + 1) * 1000 end
    end
    env.UnitChannelInfo = function()
        if state.channelError then error("channel API unavailable") end
        if state.channelRemaining then return "Channel", nil, nil, nil,
            state.channelEnd or state.now * 1000 + state.channelRemaining, nil, nil, nil, nil, nil, 123 end
    end
    env.C_AddOns = { IsAddOnLoaded = function(id) return state.loaded[id] end,
        GetAddOnEnableState = function() return 2 end, GetAddOnLocalTable = function() return {} end }
    env.C_CVar = { GetCVarBool = function() return state.suppressed == true end,
        SetCVar = function(name, value)
            equal(name, "doNotFlashLowHealthWarning"); equal(value, "0")
            state.cvarWrites = state.cvarWrites + 1
        end }
    env.LowHealthFrame = { IsShown = function() return state.low end }
    local jac = { spellIcons = { icon({ spellID = 101, cachedHotkey = "STALE" }) } }
    function jac:GetProfile() return { showMaintenanceSlot = true } end
    local scanner = {
        GetSpellHotkey = function(id)
            state.scannerCalls[#state.scannerCalls + 1] = { "spell", id }
            return state.bindings[id]
        end,
        GetItemHotkey = function(id, castID)
            state.scannerCalls[#state.scannerCalls + 1] = { "item", id, castID }
            return state.itemBindings[id]
        end,
    }
    local libraries = {
        ["AceAddon-3.0"] = { GetAddon = function() return jac end },
        ["JustAC-SpellQueue"] = { WAIT_SENTINEL = -999999999, GetCurrentSpellQueue = function()
            state.queueCalls = state.queueCalls + 1
            if state.onQueue then return state.onQueue(state.queueCalls) end
            return state.queue
        end },
        ["JustAC-ActionBarScanner"] = scanner,
        ["JustAC-BlizzardAPI"] = { IsSpellReady = function() return state.ready end,
            IsSpellUsable = function() return true end },
        ["JustAC-DefensiveEngine"] = { GetEmergencyHealID = function() return state.emergency end },
        ["JustAC-MaintenanceTracker"] = { GetState = function() return state.maintenance, { cast = 888 } end },
    }
    env.LibStub = function(name) return libraries[name] end
    source("Utils/ClientFeatures.lua", env, addon)
    source("Providers/Provider.lua", env, addon)
    source("Providers/ProviderRegistry.lua", env, addon)
    source("Utils/Binding.lua", env, addon)
    source("Utils/Protocol.lua", env, addon)
    source("Utils/Keybinds.lua", env, addon)
    source("Utils/Steganography.lua", env, addon)
    load(providerPath, env, addon)
    assert(addon:SelectProvider("JustAC"))
    return env, addon, state, jac, scanner
end

local function pair(addon)
    local id, key
    if addon.GetCurrentSuggestion then id, key = addon:GetCurrentSuggestion()
    else id, key = addon:GetCurrentId(), addon:GetCurrentHotKey() end
    return id, key or ""
end

local function differential(name, arrange, expectedID, expectedKey)
    test(name, function()
        for _, client in ipairs({ "midnight", "forever" }) do
            local _, baseline, baseState, baseJac, baseScanner = fixture(baselinePath, client)
            arrange(baseState, baseJac, baseScanner)
            local id, key = pair(baseline)
            equal(id, expectedID, "stable ID"); equal(key, expectedKey, "stable key")
            local _, candidate, state, jac, scanner = fixture(candidatePath, client)
            arrange(state, jac, scanner)
            local nextID, nextKey = pair(candidate)
            equal(nextID, id, client .. " candidate ID against stable")
            equal(nextKey, key, client .. " candidate key against stable")
        end
    end)
end

differential("rotation remains primary when optional emergency API returns a heal", function(state)
    state.emergency = 999
end, 101, "1")

differential("low-health visible defensive is not preempted by an automatic heal", function(state, jac)
    state.emergency, state.low = 999, true
    jac.defensiveIcons = { icon({ currentID = 303 }) }
end, 303, "3")

for _, status in ipairs({ "down", "refresh" }) do
    differential("maintenance " .. status .. " does not preempt rotation", function(state)
        state.maintenance = status
    end, 101, "1")
end

differential("ready visible interrupt wins over defensive and rotation", function(state, jac)
    state.emergency, state.maintenance, state.low = 999, "down", true
    jac.interruptIcon = icon({ spellID = 202 }); jac.defensiveIcons = { icon({ currentID = 303 }) }
end, 202, "2")

differential("defensives stay gated by low-health warning", function(_, jac)
    jac.defensiveIcons = { icon({ currentID = 303 }) }
end, 101, "1")

differential("waiting unusable and transparent suggestions are skipped", function(state, jac)
    state.low = true; jac.interruptIcon = icon({ spellID = 202, alpha = 0 })
    jac.defensiveIcons = { icon({ currentID = 303, isWaiting = true }),
        icon({ currentID = 303, cachedDefUsable = false }), icon({ currentID = 303, shown = false }) }
end, 101, "1")

differential("defensive items retain negative IDs", function(state, jac)
    state.low = true
    jac.defensiveIcons = { icon({ currentID = 5512, isItem = true, itemCastSpellID = 6262 }) }
end, -5512, "SHIFT-1")

for _, waiting in ipairs({ 0, -999999999 }) do
    differential("WAIT queue entry " .. waiting .. " has no suggestion", function(state)
        state.queue = { waiting }
    end, nil, "")
end

differential("unbound scanner result is authoritative over stale icon text", function(state)
    state.bindings[101] = ""
end, 101, "")

differential("older editions without scanner getter use matching cached icon", function(_, jac, scanner)
    scanner.GetSpellHotkey = nil; jac.spellIcons[1].cachedHotkey = "CTRL-1"
end, 101, "CTRL-1")

test("rotation item forwards positive item and cast IDs to scanner", function()
    local _, addon, state, jac = fixture(candidatePath)
    state.queue = { -5512 }; jac.spellIcons[1] = icon({ spellID = -5512, itemCastSpellID = 6262 })
    local id, key = pair(addon); equal(id, -5512); equal(key, "SHIFT-1")
    equal(state.scannerCalls[1][1], "item"); equal(state.scannerCalls[1][2], 5512)
    equal(state.scannerCalls[1][3], 6262)
end)

test("paired output reads an advancing queue exactly once", function()
    local _, addon, state = fixture(candidatePath)
    state.onQueue = function(count) return { count == 1 and 101 or 202 } end
    assert(type(addon.GetCurrentSuggestion) == "function")
    local id, key = addon:GetCurrentSuggestion()
    equal(id, 101); equal(key, "1"); equal(state.queueCalls, 1)
end)

test("provider switching closes guarded JustAC getters", function()
    local _, addon, state = fixture(candidatePath)
    local stale = addon.GetCurrentSuggestion
    addon.providers.Other = function() function addon:GetCurrentSuggestion() return 777, "7" end end
    assert(addon:SelectProvider("Other"))
    local before = state.queueCalls; equal(stale(addon), nil); equal(state.queueCalls, before)
    local id, key = pair(addon); equal(id, 777); equal(key, "7")
    assert(addon:SelectProvider("JustAC")); equal(pair(addon), 101)
end)

test("low-health CVar enforcement remains throttled", function()
    local _, addon, state = fixture(candidatePath)
    equal(state.cvarWrites, 0); state.suppressed = true; state.now = 101
    pair(addon); equal(state.cvarWrites, 1)
    pair(addon); equal(state.cvarWrites, 1)
    state.now = 102; pair(addon); equal(state.cvarWrites, 2)
end)

local function installPipeline(env, addon, state, realBindings)
    env.CreateFrame = function()
        local frame = { alpha = 0 }
        function frame:SetAlpha(alpha) self.alpha = alpha end
        function frame:SetAllPoints() end
        function frame:SetFrameStrata() end
        function frame:SetFrameLevel() end
        function frame:CreateTexture()
            return { SetAllPoints = function() end, SetColorTexture = function() end }
        end
        state.frames[#state.frames + 1] = frame; return frame
    end
    source("Utils/OffensiveCooldowns.lua", env, addon)
    local profile = addon:GetPriorityActionProfile()
    profile.actions[1] = { kind = "spell", id = 555, enabled = true }
    if realBindings then source("Utils/PriorityBindings.lua", env, addon)
    else addon.PriorityBindings = { Build = function() return { ["spell:555"] = { hotkey = "5" } } end,
        IsCurrent = function() return true end } end
    addon.PriorityConditions = { Build = function() return { { type = "combat" } } end,
        Apply = function(gate) state.evaluations = (state.evaluations or 0) + 1; gate:SetAlpha(1) end }
    source("Utils/PriorityOverlays.lua", env, addon)
    source("Rotation.lua", env, addon)
    return profile
end

local function assertPixel(addon, state, binding)
    addon:UpdatePixel()
    local expected = binding and addon.Protocol.EncodeBinding(binding) or { red = 0, green = 0, blue = 0 }
    equal(state.color[1], expected.red, "pixel red")
    equal(state.color[2], expected.green, "pixel green")
    equal(state.color[3], expected.blue, "pixel blue")
end

test("disabled custom priority profile leaves paired JustAC pixel output intact", function()
    local env, addon, state = fixture(candidatePath)
    local profile = installPipeline(env, addon, state)
    equal(profile.enabled, false)
    state.onQueue = function(count) return { count == 1 and 101 or 202 } end
    assertPixel(addon, state, "1")
    equal(state.queueCalls, 1)
    equal(addon:GetPriorityOverlayCount(), 1)
    for _, frame in ipairs(state.frames) do equal(frame.alpha, 0, "disabled layer alpha") end
    equal(state.evaluations, nil)
end)

test("Midnight provider retains the 300 ms channel readiness boundary", function()
    local env, addon, state = fixture(candidatePath)
    installPipeline(env, addon, state)
    for _, remaining in ipairs({ 299, 300, 0 }) do
        state.channelRemaining = remaining
        assertPixel(addon, state, remaining < 300 and "1" or nil)
    end
    state.channelRemaining = nil; state.casting = true
    assertPixel(addon, state)
end)

test("unreadable or unavailable channel data fails closed", function()
    local env, addon, state = fixture(candidatePath)
    installPipeline(env, addon, state)
    state.channelRemaining, state.channelEnd = 299, "redacted timestamp"
    assertPixel(addon, state)
    local secret = {}; state.channelEnd = secret
    env.issecretvalue = function(value) return value == secret end
    assertPixel(addon, state)
    state.channelError = true; assertPixel(addon, state)
end)

test("priority actions and Forever remain strict through the channel tail", function()
    for _, client in ipairs({ "midnight", "forever" }) do
        local env, addon, state = fixture(candidatePath, client)
        local profile = installPipeline(env, addon, state); profile.enabled = true
        state.channelRemaining = 299
        equal(addon:IsPriorityPlayerIdle(), false)
        assertPixel(addon, state, client == "midnight" and "1" or nil)
        equal(state.frames[1].alpha, 0, "priority root stays hidden")
        equal(state.evaluations, nil)
    end
end)

test("initial secure binding override hides custom action and preserves provider fallback", function()
    local env, addon, state = fixture(candidatePath)
    env.GetActionInfo = function(slot) if slot == 1 then return "spell", 555 end end
    env.GetActionBarPage = function() return 1 end
    env.GetBindingKey = function(command) if command == "ACTIONBUTTON1" then return "1" end end
    env.GetBindingAction = function(key, checkOverride)
        equal(key, "1"); equal(checkOverride, true)
        state.overrideChecks = (state.overrideChecks or 0) + 1
        return state.effectiveCommand or "CLICK SecureOverride:LeftButton"
    end
    local profile = installPipeline(env, addon, state, true); profile.enabled = true
    assertPixel(addon, state, "1")
    assert((state.overrideChecks or 0) > 0, "initial binding override was never checked")
    equal(state.frames[1].alpha, 0, "overridden action root stays hidden")
    equal(state.evaluations, nil)
    local frameCount = #state.frames
    state.effectiveCommand = "ACTIONBUTTON1"
    env.InCombatLockdown = function() return true end
    assertPixel(addon, state, "1")
    equal(state.frames[1].alpha, 1, "restored mapping recovers without a binding event")
    equal(state.evaluations, 1)
    equal(#state.frames, frameCount, "binding recovery allocates no frames in combat")
end)

print(string.format("\n%d passed; %d failed (%s)", passed, failed, _VERSION))
if failed > 0 then error("JustAC regressions failed: " .. failed) end
