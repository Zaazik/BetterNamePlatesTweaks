-- Game glue: works on the frames BetterNamePlates exposes on each Blizzard
-- base plate (basePlate.BetterNamePlatesView). BetterNamePlates itself is not
-- modified.
local _, ns = ...
local Logic = ns.Logic

local CVARS = {
    {"nameplateMotion", "1"},   -- stack plates instead of piling them up
    {"nameplateMinScale", "1"}, -- keep the click box the same size at any
    {"nameplateMaxScale", "1"}, -- distance (our bars ignore this scale anyway)
}

local hookedViews = setmetatable({}, {__mode = "k"})
local painting = false
local cvarsPending = false
local desiredWidth, desiredHeight
local appliedWidth, appliedHeight
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

-- Base plate size = click area and stacking box.
local function applySize()
    if not desiredWidth then
        return
    end
    if not (C_NamePlate and C_NamePlate.SetNamePlateEnemySize) then
        report("size", "C_NamePlate.SetNamePlateEnemySize is missing in this " ..
            "client; click area left unchanged")
        return
    end
    if appliedWidth and math.abs(appliedWidth - desiredWidth) < 0.5 and
        math.abs(appliedHeight - desiredHeight) < 0.5 then
        return
    end
    if InCombatLockdown() then
        return -- retried on PLAYER_REGEN_ENABLED
    end
    C_NamePlate.SetNamePlateEnemySize(desiredWidth, desiredHeight)
    appliedWidth, appliedHeight = desiredWidth, desiredHeight
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

local function layout(view, basePlate)
    local plateUnitScale = basePlate:GetEffectiveScale() / basePlate:GetScale()
    local ratio = view:GetEffectiveScale() / plateUnitScale
    local width, height, offsetY = Logic.ClickBox(
        view:GetWidth(), view:GetHeight(), view.name:GetHeight(), ratio)
    view:ClearAllPoints()
    view:SetPoint("CENTER", basePlate, "CENTER", 0, offsetY)
    desiredWidth, desiredHeight = width, height
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

local function handlePlate(unit)
    local basePlate = C_NamePlate.GetNamePlateForUnit(unit)
    local view = basePlate and basePlate.BetterNamePlatesView
    -- Friendly plates and BetterNamePlates' Blizzard mode have no active view.
    if not view or view.unit ~= unit or not view:IsShown() then
        return
    end
    hookView(view)
    applyFullName(view, unit)
    layout(view, basePlate)
    applySize()
    paint(view)
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
        -- Run after BetterNamePlates has built the view for this plate.
        C_Timer.After(0, function() handlePlate(unit) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        applyCVars()
        C_Timer.After(0, handleAllPlates)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if cvarsPending then
            applyCVars()
        end
        applySize()
    end
end)

-- Blizzard resets the base plate size when nameplate options change.
if NamePlateDriverFrame and NamePlateDriverFrame.UpdateNamePlateOptions then
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
        appliedWidth, appliedHeight = nil, nil
        applySize()
    end)
end
