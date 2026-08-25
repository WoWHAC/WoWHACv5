local _, WoWHACv5 = ...

local Binding = {}

local ACTION_CODES = {
    ENTER = 0x28,
    ESCAPE = 0x29,
    BACKSPACE = 0x2A,
    TAB = 0x2B,
    SPACE = 0x2C,
    ["-"] = 0x2D,
    MINUS = 0x2D,
    ["="] = 0x2E,
    EQUAL = 0x2E,
    EQUALS = 0x2E,
    PLUS = 0x2E,
    ["["] = 0x2F,
    LEFTBRACKET = 0x2F,
    OEM4 = 0x2F,
    ["]"] = 0x30,
    RIGHTBRACKET = 0x30,
    OEM6 = 0x30,
    ["\\"] = 0x31,
    BACKSLASH = 0x31,
    OEM5 = 0x31,
    [";"] = 0x33,
    SEMICOLON = 0x33,
    OEM1 = 0x33,
    ["'"] = 0x34,
    APOSTROPHE = 0x34,
    OEM7 = 0x34,
    ["`"] = 0x35,
    GRAVE = 0x35,
    TILDE = 0x35,
    OEM3 = 0x35,
    [","] = 0x36,
    COMMA = 0x36,
    OEMCOMMA = 0x36,
    ["."] = 0x37,
    PERIOD = 0x37,
    OEMPERIOD = 0x37,
    ["/"] = 0x38,
    SLASH = 0x38,
    OEM2 = 0x38,
    CAPSLOCK = 0x39,
    PRINTSCREEN = 0x46,
    SCROLLLOCK = 0x47,
    PAUSE = 0x48,
    INSERT = 0x49,
    HOME = 0x4A,
    PAGEUP = 0x4B,
    DELETE = 0x4C,
    END = 0x4D,
    PAGEDOWN = 0x4E,
    RIGHT = 0x4F,
    LEFT = 0x50,
    DOWN = 0x51,
    UP = 0x52,
    NUMLOCK = 0x53,
    NUMPADDIVIDE = 0x54,
    NUMPADMULTIPLY = 0x55,
    NUMPADMINUS = 0x56,
    NUMPADPLUS = 0x57,
    NUMPADENTER = 0x58,
    NUMPADDECIMAL = 0x63,
    NONUSBACKSLASH = 0x64,
    OEM102 = 0x64,
    APPLICATION = 0x65,
    NUMPADEQUAL = 0x67,
    NUMPADEQUALS = 0x67,
    BUTTON4 = 0x74,
    BUTTON5 = 0x75,
}

local MODIFIERS = {
    { prefix = "ALT-", bit = 1 },
    { prefix = "CTRL-", bit = 2 },
    { prefix = "SHIFT-", bit = 4 },
}

for index = 0, 25 do
    ACTION_CODES[string.char(string.byte("A") + index)] = 0x04 + index
end

for digit = 1, 9 do
    ACTION_CODES[tostring(digit)] = 0x1D + digit
    ACTION_CODES["NUMPAD" .. digit] = 0x58 + digit
end
ACTION_CODES["0"] = 0x27
ACTION_CODES.NUMPAD0 = 0x62

for number = 1, 24 do
    ACTION_CODES["F" .. number] = number <= 12
        and 0x39 + number
        or 0x5B + number
end

local SUPPORTED_ACTION_CODES = {}
for _, action in pairs(ACTION_CODES) do
    SUPPORTED_ACTION_CODES[action] = true
end

local function SplitModifiers(rawBinding)
    if type(rawBinding) ~= "string" or rawBinding == "" then
        return nil
    end

    local key = rawBinding:upper()
    local modifiers = 0
    local consumed = {}

    while true do
        local matched = false
        for _, modifier in ipairs(MODIFIERS) do
            if key:sub(1, #modifier.prefix) == modifier.prefix then
                if consumed[modifier.bit] then
                    return nil
                end
                consumed[modifier.bit] = true
                modifiers = modifiers + modifier.bit
                key = key:sub(#modifier.prefix + 1)
                matched = true
                break
            end
        end
        if not matched then
            break
        end
    end

    if key == "" then
        return nil
    end
    return key, modifiers
end

function Binding.Parse(rawBinding)
    local key, modifiers = SplitModifiers(rawBinding)
    if not key then
        return 0, 0
    end

    local action = ACTION_CODES[key]
    if not action then
        return 0, 0
    end
    return action, modifiers, key
end

function Binding.IsSupported(rawBinding)
    local action = Binding.Parse(rawBinding)
    return action ~= 0
end

function Binding.IsActionCodeSupported(action)
    return action == 0 or SUPPORTED_ACTION_CODES[action] == true
end

WoWHACv5.Binding = Binding
