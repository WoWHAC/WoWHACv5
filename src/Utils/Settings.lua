local _, WoWHACv5 = ...

function WoWHACv5:GetSettings()
    if type(WoWHACv5DB) ~= "table" then
        WoWHACv5DB = {}
    end
    return WoWHACv5DB
end
