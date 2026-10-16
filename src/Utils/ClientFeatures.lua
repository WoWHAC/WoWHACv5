local _, addon = ...

-- Project identity distinguishes Forever from Classic builds with similar
-- interface numbers. Retail's Midnight boundary is interface 120000.
local forever = type(WOW_PROJECT_CAMELOT) == "number" and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local modern = forever
if not modern and type(WOW_PROJECT_MAINLINE) == "number" and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    and type(GetBuildInfo) == "function" then
    local ok, _, _, _, interface = pcall(GetBuildInfo)
    modern = ok and type(interface) == "number" and interface >= 120000 and interface < math.huge
        and interface == math.floor(interface)
end

function addon:SupportsModernFeatures()
    return modern == true
end
