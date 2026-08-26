local _, WoWHACv5 = ...

function WoWHACv5:NormalizeModifiers(keyBind)
    if keyBind == nil then
        return nil
    end
    keyBind = keyBind:upper()
    local modifiers = 0
    local patterns = { "^ALT%-?", "^A%-?", "^CTRL%-?", "^C%-?", "^SHIFT%-?", "^S%-?" }
    while keyBind:len() > 1 do
        local matched = false
        for index, pattern in ipairs(patterns) do
            keyBind, count = keyBind:gsub(pattern, "")
            if keyBind:len() == 0 then
                keyBind = "-"
            end
            if count > 0 then
                local modifier = bit.lshift(1, bit.rshift(index - 1, 1))
                modifiers = bit.bor(modifiers, modifier)
                matched = true
                break
            end
        end
        if not matched then
            break
        end
    end
    return ((bit.band(modifiers, 1) ~= 0) and "ALT\-" or "") ..
            ((bit.band(modifiers, 2) ~= 0) and "CTRL\-" or "") ..
            ((bit.band(modifiers, 4) ~= 0) and "SHIFT\-" or "") ..
            keyBind
end
