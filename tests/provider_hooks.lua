local root = _TEST_ROOT or (arg and arg[1]) or "."
local adapters = _ADAPTER_ROOT or (arg and arg[2]) or (root .. "/src")
local passed, failed = 0, 0

local function equal(actual, expected, description)
    if actual ~= expected then
        error((description or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
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

local function fixture(modern)
    if modern == nil then modern = true end
    local env = setmetatable({}, { __index = _G }); env._G = env
    local state = { hooks = {}, messages = {}, settings = {}, burstShown = false, hekiliShown = false }
    local addon = { providers = {}, burst = false }
    function addon:SupportsModernFeatures() return modern end
    function addon:Log() end
    function addon:Debug() end
    function addon:SendMessage() end
    function addon:GetSettings() return state.settings end
    function addon:SecureHook(target, method, callback)
        assert(type(target[method]) == "function", "Hook target must be a method")
        state.hooks[target] = state.hooks[target] or {}
        assert(not state.hooks[target][method], "Duplicate hook")
        state.hooks[target][method] = callback
    end
    function addon:Unhook(target, method) state.hooks[target][method] = nil end
    function addon:RegisterMessage(message, callback) state.messages[message] = callback end
    addon.pixel = { SetColor = function(_, r, g, b) state.color = { r, g, b } end }
    addon.ToggleBurstFrame = {
        Show = function() state.burstShown = true end,
        Hide = function() state.burstShown = false end,
    }
    addon.ToggleHekiliFrame = {
        Init = function() end,
        Show = function() state.hekiliShown = true end,
        Hide = function() state.hekiliShown = false end,
    }
    env.C_AddOns = { IsAddOnLoaded = function() return true end, GetAddOnEnableState = function() return 2 end }
    env.InCombatLockdown = function() return false end
    env.GetTime = function() return 100 end
    env.GetBindingKey = function(command) return command == "ACTIONBUTTON1" and "1" or nil end
    env.C_Spell = { GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
    env.GetItemCooldown = function() return 0, 0, 1 end
    load(root .. "/src/Providers/Provider.lua", env, addon)
    load(root .. "/src/Providers/ProviderRegistry.lua", env, addon)
    addon.providers.Other = function()
        function addon:GetCurrentHotKey() return "OTHER" end
    end
    function state.emit(target, method, ...)
        local callback = state.hooks[target] and state.hooks[target][method]
        if callback then return callback(...) end
    end
    function state.text(value, visible)
        local text = { value = value, visible = visible ~= false }
        function text:GetText() return self.value end
        function text:IsVisible() return self.visible end
        function text:SetText(nextValue)
            self.value = nextValue
            state.emit(self, "SetText", self, nextValue)
        end
        return text
    end
    function state.activate(id, file)
        if file then load(adapters .. "/Providers/" .. file .. ".lua", env, addon) end
        if modern then return addon:SelectProvider(id) end
        return addon.providers[id]()
    end
    function state.other() assert(addon:SelectProvider("Other")) end
    return env, addon, state
end

for _, id in ipairs({ "ConRO", "ConROC" }) do
    test(id .. " publishes both already visible recommendations on activation", function()
        local env, addon, state = fixture()
        env[id] = { Spell = 101, SuggestedSpells = { 101, 202 } }
        env[id .. "Window"] = { fontkey = state.text("1") }
        env[id .. "Window2"] = { fontkey = state.text("2") }
        assert(state.activate(id, id .. "Provider"))
        equal(addon:GetCurrentId(), 101); equal(addon:GetCurrentHotKey(), "1")
        equal(addon:GetNextId(), 202); equal(addon:GetNextHotKey(), "2")
    end)
    test(id .. " refreshes IDs even when the displayed key is unchanged", function()
        local env, addon, state = fixture()
        env[id] = { Spell = 101, SuggestedSpells = { 101, 202 } }
        local key = state.text("1"); env[id .. "Window"] = { fontkey = key }
        assert(state.activate(id, id .. "Provider"))
        env[id].Spell = 303; key:SetText("1"); equal(addon:GetCurrentId(), 303)
        local stale = state.hooks[key].SetText; state.other()
        stale(key, "STALE"); equal(addon:GetCurrentHotKey(), "OTHER")
    end)
    test(id .. " retains legacy callback output without the registry", function()
        local env, addon, state = fixture(false)
        env[id] = { Spell = 101 }; local key = state.text("1")
        env[id .. "Window"] = { fontkey = key }
        state.activate(id, id .. "Provider"); key:SetText("2")
        equal(addon:GetCurrentId(), 101); equal(addon:GetCurrentHotKey(), "2")
    end)
end

test("HeroRotation preserves suggested/right/burst/main priority", function()
    local env, addon, state = fixture()
    local main, right, suggested, burst = state.text("1"), state.text("2"), state.text("3"), state.text("4")
    env.HeroRotation = { MainIconFrame = { Keybind = main }, RightSuggestedIconFrame = { Keybind = right },
        SuggestedIconFrame = { Keybind = suggested }, SmallIconFrame = { Icon = { { Keybind = burst } } } }
    assert(state.activate("HeroRotation", "HeroRotationProvider")); equal(addon:GetCurrentHotKey(), "2")
    right.visible = false; main:SetText("1"); equal(addon:GetCurrentHotKey(), "3")
    suggested.visible = false; main:SetText("1"); equal(addon:GetCurrentHotKey(), "4")
    burst.visible = false; main:SetText("1"); equal(addon:GetCurrentHotKey(), "1")
end)

test("HeroRotation closes hooks and seeds state again on reactivation", function()
    local env, addon, state = fixture(); local main = state.text("1")
    env.HeroRotation = { MainIconFrame = { Keybind = main } }
    assert(state.activate("HeroRotation", "HeroRotationProvider")); local stale = state.hooks[main].SetText
    state.other(); stale(main, "STALE"); equal(addon:GetCurrentHotKey(), "OTHER")
    main.value = "2"; assert(state.activate("HeroRotation")); equal(addon:GetCurrentHotKey(), "2")
end)

local function maxDpsFixture(weakAuras, modern)
    local env, addon, state = fixture(modern)
    local text = state.text("1")
    env.MaxDpsSpellFrame = { bindText = text, shown = false }
    function env.MaxDpsSpellFrame:IsShown() return self.shown end
    function env.MaxDpsSpellFrame:Show() self.shown = true end
    function env.MaxDpsSpellFrame:Hide() self.shown = false end
    env.MaxDps = { Spell = 101, Frames = {}, db = { global = { onCombatEnter = true, enabled = false,
        spellFrame = { enabled = false } } } }
    function env.MaxDps:UpdateSpellFrame(id)
        self.Spell = id; text.value = id == 202 and "2" or "1"
        state.emit(self, "UpdateSpellFrame", self, id)
    end
    if weakAuras then
        env.WeakAuras = { ScanEvents = function(event) state.emit(env.WeakAuras, "ScanEvents", event) end }
        state.normalKey = state.text("2")
        state.glow = { visible = true, ovType = "normal", IsVisible = function(self) return self.visible end,
            GetParent = function() return { HotKey = state.normalKey } end }
        env.MaxDps.Frames = { state.glow }
    end
    return env, addon, state
end

test("MaxDps direct mode immediately resumes an already published spell", function()
    local env, addon, state = maxDpsFixture()
    assert(state.activate("MaxDps", "MaxDpsProvider"))
    equal(addon:GetCurrentId(), 101); equal(addon:GetCurrentHotKey(), "1")
    state.other(); env.MaxDps.Spell = 202; env.MaxDpsSpellFrame.bindText.value = "2"
    assert(state.activate("MaxDps")); equal(addon:GetCurrentHotKey(), "2")
end)

test("MaxDps direct updates clear unavailable recommendations", function()
    local env, addon, state = maxDpsFixture()
    assert(state.activate("MaxDps", "MaxDpsProvider"))
    env.MaxDps:UpdateSpellFrame(202); equal(addon:GetCurrentId(), 202); equal(addon:GetCurrentHotKey(), "2")
    env.MaxDps:UpdateSpellFrame(0); equal(addon:GetCurrentHotKey(), nil)
end)

test("MaxDps direct cleanup restores settings and removes the callback", function()
    local env, addon, state = maxDpsFixture()
    assert(state.activate("MaxDps", "MaxDpsProvider")); local stale = state.hooks[env.MaxDps].UpdateSpellFrame
    state.other()
    equal(env.MaxDps.db.global.enabled, false); equal(env.MaxDps.db.global.onCombatEnter, true)
    equal(env.MaxDps.db.global.spellFrame.enabled, false); equal(env.MaxDpsSpellFrame.shown, false)
    stale(env.MaxDps, 101); equal(addon:GetCurrentHotKey(), "OTHER")
end)

test("MaxDps WeakAuras mode consumes the existing eligible glow immediately", function()
    local env, addon, state = maxDpsFixture(true)
    assert(state.activate("MaxDps", "MaxDpsProvider")); equal(addon:GetCurrentHotKey(), "2")
end)

test("MaxDps WeakAuras updates filter cooldowns and clear missing glows", function()
    local env, addon, state = maxDpsFixture(true)
    assert(state.activate("MaxDps", "MaxDpsProvider"))
    state.glow.ovType = "cooldown"; env.WeakAuras.ScanEvents("MAXDPS_COOLDOWN_UPDATE")
    equal(addon:GetCurrentHotKey(), nil)
    addon.burst = true; env.WeakAuras.ScanEvents("MAXDPS_COOLDOWN_UPDATE"); equal(addon:GetCurrentHotKey(), "2")
    state.glow.visible = false; env.WeakAuras.ScanEvents("MAXDPS_COOLDOWN_UPDATE"); equal(addon:GetCurrentHotKey(), nil)
    state.other(); equal(state.burstShown, false)
end)

local function ovaleFixture(namespaceOnly)
    local env, addon, state = fixture()
    state.itemGetter = function(id) equal(id, 5512); return "Health spell", 6262 end
    if namespaceOnly then
        env.C_Item = { GetItemSpell = state.itemGetter, GetItemCooldown = function() return 0, 0, 1 end }
        env.GetItemCooldown = nil
    else env.GetItemSpell = state.itemGetter end
    state.shortcut = function() return "ORIGINAL" end
    env.Ovale = { frame = { actions = {} }, ChercherShortcut = state.shortcut,
        GetSpellIdByName = function(_, name) if name == "Attack" then return 101 end end }
    function env.Ovale.frame:OnUpdate() state.emit(self, "OnUpdate", self) end
    function state.suggestion(name, key, index)
        env.Ovale.frame.actions[index or 1] = { spellName = name, icons = { { shortcut = state.text(key) } } }
    end
    return env, addon, state
end

test("Ovale initializes spell output with only the namespaced item API", function()
    local env, addon, state = ovaleFixture(true); state.suggestion("Attack", "1")
    assert(state.activate("Ovale", "OvaleProvider")); env.Ovale.frame:OnUpdate()
    equal(addon:GetCurrentHotKey(), "1")
end)

test("Ovale spell recommendations do not require an item API", function()
    local env, addon, state = ovaleFixture(); env.GetItemSpell = nil; state.suggestion("Attack", "1")
    assert(state.activate("Ovale", "OvaleProvider")); env.Ovale.frame:OnUpdate()
    equal(addon:GetCurrentHotKey(), "1")
end)

test("Ovale retains observed item identities across provider switching", function()
    local env, addon, state = ovaleFixture(); state.suggestion("Health spell", "F1")
    assert(state.activate("Ovale", "OvaleProvider")); equal(env.GetItemSpell(5512), "Health spell")
    env.Ovale.frame:OnUpdate(); equal(addon:GetCurrentHotKey(), "F1")
    state.other(); assert(state.activate("Ovale")); env.Ovale.frame:OnUpdate()
    equal(addon:GetCurrentHotKey(), "F1")
end)

test("Ovale restores only the overrides owned by its closed session", function()
    local env, addon, state = ovaleFixture()
    assert(state.activate("Ovale", "OvaleProvider")); local oldGetter = env.GetItemSpell
    local name, id = oldGetter(5512); equal(name, "Health spell"); equal(id, 6262)
    state.other(); equal(env.GetItemSpell, state.itemGetter); equal(env.Ovale.ChercherShortcut, state.shortcut)
    equal(oldGetter(5512), "Health spell"); equal(state.burstShown, false)
end)

test("Ovale uses modern item spell and cooldown functions together", function()
    local env, addon, state = ovaleFixture(true); state.suggestion("Health spell", "F1")
    assert(state.activate("Ovale", "OvaleProvider")); env.C_Item.GetItemSpell(5512)
    env.Ovale.frame:OnUpdate(); equal(addon:GetCurrentHotKey(), "F1")
    state.other(); equal(env.C_Item.GetItemSpell, state.itemGetter)
end)

test("Ovale skips an unavailable spell cooldown and uses the next ready icon", function()
    local env, addon, state = ovaleFixture(); state.suggestion("Attack", "4", 4)
    state.suggestion("Attack", "1", 1); local reads = 0
    env.C_Spell.GetSpellCooldown = function()
        reads = reads + 1; if reads == 1 then return nil end; return { startTime = 0, duration = 0 }
    end
    assert(state.activate("Ovale", "OvaleProvider")); env.Ovale.frame:OnUpdate()
    equal(addon:GetCurrentHotKey(), "1")
end)

test("Hekili frame adapter seeds visible state and closes its hook", function()
    local env, addon, state = fixture(); local key = state.text("1")
    env.Hekili = {}; env.Hekili_Primary_B1 = { Keybinding = key, Ability = { id = 101 } }
    assert(state.activate("Hekili", "HekiliProvider")); equal(addon:GetCurrentId(), 101)
    env.Hekili_Primary_B1.Ability.id = 202; key:SetText("2"); equal(addon:GetCurrentId(), 202)
    state.other(); equal(state.hekiliShown, false); key:SetText("STALE"); equal(addon:GetCurrentHotKey(), "OTHER")
end)

test("older Hekili API adapter still queries the live recommendation", function()
    local env, addon, state = fixture(false); env.Hekili_D1_B1_KB = state.text("1")
    env.Hekili_GetRecommendedAbility = function(display, position) equal(display, 1); equal(position, 1); return 101 end
    state.activate("Hekili", "HekiliProvider")
    equal(addon:GetCurrentId(), 101); equal(addon:GetCurrentHotKey(), "1")
end)

for _, modern in ipairs({ true, false }) do
    test("SimpleAssistedCombat tracks spellID without requiring Ability (modern=" .. tostring(modern) .. ")", function()
        local env, addon, state = fixture(modern); local key = state.text("1")
        env.AssistedCombatIconFrame = { spellID = 101, Keybind = key }
        state.activate("SimpleAssistedCombatIcon", "SimpleAssistedCombat")
        env.AssistedCombatIconFrame.spellID = 202; key:SetText("2")
        equal(addon:GetCurrentId(), 202); equal(addon:GetCurrentHotKey(), "2")
    end)
end

print(string.format("\n%d passed; %d failed (%s)", passed, failed, _VERSION))
if failed > 0 then error("Hook provider regressions failed: " .. failed) end
