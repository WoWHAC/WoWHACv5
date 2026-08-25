local _, WoWHACv5 = ...

WoWHACv5.providers = WoWHACv5.providers or {}
WoWHACv5.providers["HeroRotation"] = function()
    WoWHACv5:Log("Supplier found: HeroRotation.")

    local frameIds = {}
    local smallIconIds = {}

    local function IsVisible(frame)
        return frame and frame.IsVisible and frame:IsVisible()
    end

    local function GetPreferredId()
        local right = HeroRotation.RightSuggestedIconFrame
        if IsVisible(right) and frameIds[right] then
            return frameIds[right]
        end

        local suggested = HeroRotation.SuggestedIconFrame
        if IsVisible(suggested) and frameIds[suggested] then
            return frameIds[suggested]
        end

        local small = HeroRotation.SmallIconFrame
        local firstSmallIcon = small and small.Icon and small.Icon[1]
        if IsVisible(firstSmallIcon) and smallIconIds[1] then
            return smallIconIds[1]
        end

        return frameIds[HeroRotation.MainIconFrame]
    end

    local function LastArgument(...)
        local count = select("#", ...)
        return count > 0 and select(count, ...) or nil
    end

    local function HookIconFrame(frame)
        if not frame or type(frame.ChangeIcon) ~= "function" then
            return
        end
        WoWHACv5:SecureHook(frame, "ChangeIcon", function(_, ...)
            frameIds[frame] = LastArgument(...)
        end)
    end

    HookIconFrame(HeroRotation.MainIconFrame)
    HookIconFrame(HeroRotation.SuggestedIconFrame)
    HookIconFrame(HeroRotation.RightSuggestedIconFrame)

    local small = HeroRotation.SmallIconFrame
    if small and type(small.ChangeIcon) == "function" then
        WoWHACv5:SecureHook(small, "ChangeIcon", function(_, index, ...)
            if type(index) == "number" then
                smallIconIds[index] = LastArgument(...)
            end
        end)
    end

    WoWHACv5:SetSuggestionResolver(function()
        return WoWHACv5.ActionBinding.ForUntypedId(GetPreferredId())
    end)
end
