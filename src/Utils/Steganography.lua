local _, WoWHACv5 = ...

--========================================
-- Steganography без 30log
--========================================
local Steganography = {}
Steganography.__index = Steganography

setmetatable(Steganography, {
    __call = function(cls, ...)
        local self = setmetatable({}, cls)
        if self.init then self:init(...) end
        return self
    end
})

function Steganography:init(keybind)
    if keybind then
        keybind = WoWHACv5:NormalizeModifiers(keybind)
    end
    local encoded = WoWHACv5.Protocol.EncodeBinding(keybind)
    self.keybind = keybind
    self.red = encoded.red
    self.green = encoded.green
    self.blue = encoded.blue
end

WoWHACv5.Steganography = Steganography
