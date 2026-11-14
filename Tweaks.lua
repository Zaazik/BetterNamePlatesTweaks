-- Game glue: works on the frames BetterNamePlates exposes on each Blizzard
-- base plate (basePlate.BetterNamePlatesView). BetterNamePlates itself is not
-- modified.
local _, ns = ...
local Logic = ns.Logic

local CVARS = {
    {"nameplateMotion", "1"}, -- stack plates instead of piling them up
}

local hookedViews = setmetatable({}, {__mode = "k"})
local painting = false
local cvarsPending = false
local reported = {}

local function report(key, message)
    if reported[key] then
        return
    end
    reported[key] = true
    print("|cffff4040BetterNamePlatesTweaks:|r " .. message)
end

local function applyCVars()
    if InCombatLockdown() then
        cvarsPending = true
        return
    end
    cvarsPending = false
    for _, setting in ipairs(CVARS) do
        local name, value = setting[1], setting[2]
        SetCVar(name, value)
        if tonumber(GetCVar(name)) ~= tonumber(value) then
            report("cvar:" .. name, "could not set CVar " .. name .. " = " ..
                value .. " (current: " .. tostring(GetCVar(name)) .. ")")
        end
    end
end

-- Click area: make the Blizzard plate's hit rect cover our health/cast view.
-- In combat the client only allows this on the tick the unit is assigned,
-- so it must run synchronously inside NAME_PLATE_UNIT_ADDED.
local function applyHitTest(basePlate, view)
    if not basePlate.SetAllHitTestPoints then
        report("hit", "NamePlate:SetAllHitTestPoints is missing in this " ..
            "client; click area left unchanged (type /bnpt)")
        return true
    end
    if not basePlate:CanChangeHitTestPoints() then
        return false
    end
    basePlate:SetAllHitTestPoints(view)
    return true
end

local function isGroupTank()
    return IsInGroup() and UnitGroupRolesAssigned and
        UnitGroupRolesAssigned("player") == "TANK"
end

local function getClassColor(unit)
    local _, classFile = UnitClass(unit)
    local color = classFile and (
        (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile]) or
        RAID_CLASS_COLORS[classFile])
    return color and {color.r, color.g, color.b} or nil
end

local function getThreatPercent(unit)
    if not UnitDetailedThreatSituation then
        return nil
    end
    local _, _, scaledPercent = UnitDetailedThreatSituation("player", unit)
    return scaledPercent
end

local function paint(view)
    local unit = view.unit
    if not view:IsShown() or not unit or not UnitExists(unit) then
        return
    end
    local isPlayer = UnitIsPlayer(unit)
    local color = Logic.DecideColor({
        canAttack = UnitCanAttack("player", unit),
        isPlayer = isPlayer,
        classColor = isPlayer and getClassColor(unit) or nil,
        isTapDenied = UnitIsTapDenied and UnitIsTapDenied(unit),
        isTank = isGroupTank(),
        threatStatus = UnitThreatSituation("player", unit),
        threatPercent = getThreatPercent(unit),
    })
    if not color then
        return -- keep BetterNamePlates' own color
    end
    local _, _, _, alpha = view.health:GetStatusBarColor()
    painting = true
    local ok, err = pcall(view.health.SetStatusBarColor, view.health,
        color[1], color[2], color[3], alpha)
    painting = false
    if not ok then
        error(err)
    end
end

-- BetterNamePlates recolors the bar on every threat/flag event; repaint
-- right after it so our color wins.
local function hookView(view)
    if hookedViews[view] then
        return
    end
    hookedViews[view] = true
    hooksecurefunc(view.health, "SetStatusBarColor", function()
        if not painting then
            paint(view)
        end
    end)
end

-- Full name on one line; the font string itself truncates at the bar width.
local function applyFullName(view, unit)
    local name = UnitName(unit)
    if not name then
        return
    end
    local level = UnitEffectiveLevel and UnitEffectiveLevel(unit) or
        UnitLevel(unit)
    local text = Logic.FormatName(name, level, UnitClassification(unit))
    for _, layer in ipairs(view.nameLayers) do
        layer:SetWordWrap(false)
        layer:SetNonSpaceWrap(false)
        layer:SetMaxLines(1)
        layer:SetText(text)
    end
end

local hitTestPending = {}

-- Returns false when BetterNamePlates has not built the view yet.
local function handlePlate(unit)
    local basePlate = C_NamePlate.GetNamePlateForUnit(unit)
    local view = basePlate and basePlate.BetterNamePlatesView
    -- Friendly plates and BetterNamePlates' Blizzard mode have no active view.
    if not view or view.unit ~= unit or not view:IsShown() then
        return false
    end
    hookView(view)
    applyFullName(view, unit)
    if not applyHitTest(basePlate, view) then
        hitTestPending[basePlate] = view -- retried after combat
    end
    paint(view)
    return true
end

local function handleAllPlates()
    for _, basePlate in ipairs(C_NamePlate.GetNamePlates()) do
        local view = basePlate.BetterNamePlatesView
        if view and view.unit then
            handlePlate(view.unit)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        -- BetterNamePlates (loaded first) normally built the view already;
        -- if not, retry next frame.
        if not handlePlate(unit) then
            C_Timer.After(0, function() handlePlate(unit) end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        applyCVars()
        C_Timer.After(0, handleAllPlates)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if cvarsPending then
            applyCVars()
        end
        for basePlate, view in pairs(hitTestPending) do
            hitTestPending[basePlate] = nil
            if view:IsShown() then
                applyHitTest(basePlate, view)
            end
        end
    end
end)

-- /bnpt: show which nameplate APIs this client really has.
SLASH_BETTERNAMEPLATESTWEAKS1 = "/bnpt"
SlashCmdList.BETTERNAMEPLATESTWEAKS = function()
    local function has(value) return value and "yes" or "NO" end
    local version, build, _, interface = GetBuildInfo()
    print("BNPT client:", version, build, interface)
    print("BNPT C_NamePlate.SetNamePlateEnemySize:",
        has(C_NamePlate.SetNamePlateEnemySize))
    print("BNPT C_NamePlate.SetNamePlateSize:",
        has(C_NamePlate.SetNamePlateSize))
    if C_NamePlate.GetNamePlateSize then
        print("BNPT C_NamePlate.GetNamePlateSize:", C_NamePlate.GetNamePlateSize())
    end
    local plate = C_NamePlate.GetNamePlates()[1]
    if not plate then
        print("BNPT no nameplate on screen: stand near a mob and repeat /bnpt")
    else
        print("BNPT plate size:", plate:GetSize())
        for _, method in ipairs({"SetAllHitTestPoints", "SetHitTestPoints",
            "CanChangeHitTestPoints", "GetHitTestPoints",
            "SetStackingBoundsFrame", "SetHitRectInsets"}) do
            print("BNPT plate:" .. method .. ":", has(plate[method]))
        end
        if plate.GetHitTestPoints then
            print("BNPT hit-test points:", #plate:GetHitTestPoints())
        end
        print("BNPT BetterNamePlates view:", has(plate.BetterNamePlatesView))
    end
    print("BNPT nameplateMotion =", GetCVar("nameplateMotion"))
end
