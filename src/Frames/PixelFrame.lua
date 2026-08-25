local _, WoWHACv5 = ...

local STRIP_WIDTH = #WoWHACv5.Protocol.CALIBRATION_BYTES + 2
local DATA_PIXEL_INDICES = { 1, STRIP_WIDTH }

local PixelFrame = {}
PixelFrame.__index = PixelFrame

setmetatable(PixelFrame, {
    __call = function(class, ...)
        local instance = setmetatable({}, class)
        instance:init(...)
        return instance
    end,
})

local function GetPixelSize(frame)
    local effectiveScale = frame:GetEffectiveScale()
    if type(effectiveScale) ~= "number" or effectiveScale <= 0 then
        effectiveScale = 1
    end

    local pixelToUI
    if PixelUtil and type(PixelUtil.GetPixelToUIUnitFactor) == "function" then
        local ok, factor = pcall(PixelUtil.GetPixelToUIUnitFactor)
        if ok and type(factor) == "number" and factor > 0 then
            pixelToUI = factor
        end
    end

    if not pixelToUI and type(GetPhysicalScreenSize) == "function" then
        local ok, _, physicalHeight = pcall(GetPhysicalScreenSize)
        if ok and type(physicalHeight) == "number" and physicalHeight > 0 then
            pixelToUI = 768 / physicalHeight
        end
    end

    return (pixelToUI or 1) / effectiveScale
end

local function SetTextureColor(texture, legacy, red, green, blue)
    if legacy then
        texture:SetTexture(red, green, blue)
    else
        texture:SetColorTexture(red, green, blue)
    end
end

function PixelFrame:init()
    WoWHACv5:Debug("Creating 7x1 physical pixel strip at top-left corner")
    self.frame = CreateFrame("Frame", "PixelFrame", UIParent)
    self.frame:SetFrameStrata("TOOLTIP")
    self.pixels = {}

    for index = 1, STRIP_WIDTH do
        local texture = self.frame:CreateTexture(nil, "OVERLAY")
        if texture.SetSnapToPixelGrid then
            texture:SetSnapToPixelGrid(false)
        end
        if texture.SetTexelSnappingBias then
            texture:SetTexelSnappingBias(0)
        end
        self.pixels[index] = texture
    end

    self.legacy = not self.pixels[1].SetColorTexture
    self.frame:RegisterEvent("UI_SCALE_CHANGED")
    self.frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:SetScript("OnEvent", function()
        self:RefreshLayout()
    end)

    self:RefreshLayout()
    self:SetCalibrationColors()
    self:SetNoOp()
end

function PixelFrame:RefreshLayout()
    local pixelSize = GetPixelSize(self.frame)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    self.frame:SetSize(STRIP_WIDTH * pixelSize, pixelSize)

    for index, texture in ipairs(self.pixels) do
        texture:ClearAllPoints()
        texture:SetSize(pixelSize, pixelSize)
        texture:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (index - 1) * pixelSize, 0)
    end
end

local function SetDataColor(pixelFrame, r, g, b)
    local changed = (r ~= pixelFrame.previousR)
        or (g ~= pixelFrame.previousG)
        or (b ~= pixelFrame.previousB)
    if changed then
        WoWHACv5:Debug("Change pixel color to R: " .. r .. " G: " .. g .. " B: " .. b)
    end

    pixelFrame.previousR, pixelFrame.previousG, pixelFrame.previousB = r, g, b
    for _, index in ipairs(DATA_PIXEL_INDICES) do
        SetTextureColor(pixelFrame.pixels[index], pixelFrame.legacy, r, g, b)
    end

    return changed
end

function PixelFrame:SetEncoded(encoded)
    encoded = encoded or WoWHACv5.Protocol.NO_OP
    return SetDataColor(self, encoded.red, encoded.green, encoded.blue)
end

function PixelFrame:SetNoOp()
    return self:SetEncoded(WoWHACv5.Protocol.NO_OP)
end

function PixelFrame:SetCalibrationColors()
    for index, byte in ipairs(WoWHACv5.Protocol.CALIBRATION_BYTES) do
        local level = byte / 255
        SetTextureColor(self.pixels[index + 1], self.legacy, level, level, level)
    end
end

WoWHACv5.pixel = PixelFrame()
