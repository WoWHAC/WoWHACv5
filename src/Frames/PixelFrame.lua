local _, WoWHACv5 = ...

-- Класс без 30log
local PixelFrame = {}
PixelFrame.__index = PixelFrame

-- Вызываемый конструктор: PixelFrame()
setmetatable(PixelFrame, {
    __call = function(cls, ...)
        local self = setmetatable({}, cls)
        if self.init then self:init(...) end
        return self
    end
})

function PixelFrame:init()
    WoWHACv5:Debug("Creating pixel frame at top-left corner")
    self.frame = CreateFrame("Frame", "PixelFrame", UIParent)
    self.frame.back = self.frame:CreateTexture(nil, "BACKGROUND", nil, -1)

    -- Поддержка старого API
    self.legacy = not self.frame.back.SetColorTexture

    self:SetSize(2, 2)
    self.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", self.legacy and -1 or 0, self.legacy and 1 or 0)
    self.frame:SetFrameStrata("TOOLTIP")
    self.frame.back:SetAllPoints(self.frame)

    -- Пер-экземплярное предыдущее значение цвета
    self.previousR, self.previousG, self.previousB = 0, 0, 0

    self:SetColor(0, 0, 0)
end

function PixelFrame:SetSize(x, y)
    self.frame:SetSize(x, y)
end

function PixelFrame:SetColor(r, g, b)
    local changed = (r ~= self.previousR) or (g ~= self.previousG) or (b ~= self.previousB)
    if changed then
        WoWHACv5:Debug("Change pixel color to R: " .. r .. " G: " .. g .. " B: " .. b)
    end

    -- Обновляем предыдущее значение и применяем цвет (как и в исходнике — всегда)
    self.previousR, self.previousG, self.previousB = r, g, b
    if self.legacy then
        self.frame.back:SetTexture(r, g, b)
    else
        self.frame.back:SetColorTexture(r, g, b)
    end

    return changed
end

WoWHACv5.pixel = PixelFrame()
