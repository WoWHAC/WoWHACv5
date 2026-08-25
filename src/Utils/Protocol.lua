local _, WoWHACv5 = ...

local Protocol = {}

Protocol.CALIBRATION_BYTES = { 0, 64, 128, 192, 255 }

local GRAY_INVERSE_4 = {
    [0] = 0,
    [1] = 1,
    [2] = 3,
    [3] = 2,
    [4] = 7,
    [5] = 6,
    [6] = 4,
    [7] = 5,
    [8] = 15,
    [9] = 14,
    [10] = 12,
    [11] = 13,
    [12] = 8,
    [13] = 9,
    [14] = 11,
    [15] = 10,
}

local function Xor(left, right)
    local result = 0
    local place = 1
    while left > 0 or right > 0 do
        if left % 2 ~= right % 2 then
            result = result + place
        end
        left = math.floor(left / 2)
        right = math.floor(right / 2)
        place = place * 2
    end
    return result
end

local function CalculateCRC2(payload)
    local remainder = payload * 4
    for position = 11, 2, -1 do
        local power = 2 ^ position
        if math.floor(remainder / power) % 2 == 1 then
            remainder = Xor(remainder, 7 * (2 ^ (position - 2)))
        end
    end
    return remainder % 4
end

local function NormalizeAction(action, modifiers)
    if type(action) ~= "number"
        or action ~= math.floor(action)
        or not WoWHACv5.Binding.IsActionCodeSupported(action) then
        return 0, 0
    end
    if action == 0 then
        return 0, 0
    end
    if type(modifiers) ~= "number" or modifiers ~= math.floor(modifiers) then
        return 0, 0
    end
    return action, modifiers % 8
end

local function EncodeNibble(nibble)
    return 64 + 12 * GRAY_INVERSE_4[nibble]
end

function Protocol.Encode(action, modifiers)
    action, modifiers = NormalizeAction(action, modifiers)

    local payload = modifiers * 128 + action
    local crc = CalculateCRC2(payload)
    local word = payload * 4 + crc
    local redNibble = math.floor(word / 256) % 16
    local greenNibble = math.floor(word / 16) % 16
    local blueNibble = word % 16
    local redByte = EncodeNibble(redNibble)
    local greenByte = EncodeNibble(greenNibble)
    local blueByte = EncodeNibble(blueNibble)

    return {
        action = action,
        modifiers = modifiers,
        payload = payload,
        crc = crc,
        word = word,
        redByte = redByte,
        greenByte = greenByte,
        blueByte = blueByte,
        red = redByte / 255,
        green = greenByte / 255,
        blue = blueByte / 255,
    }
end

function Protocol.EncodeBinding(rawBinding)
    local action, modifiers = WoWHACv5.Binding.Parse(rawBinding)
    return Protocol.Encode(action, modifiers)
end

Protocol.NO_OP = Protocol.Encode(0, 0)

WoWHACv5.Protocol = Protocol
