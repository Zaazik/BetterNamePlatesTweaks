-- Game glue: works on the frames BetterNamePlates exposes on each Blizzard
-- base plate (basePlate.BetterNamePlatesView). BetterNamePlates itself is not
-- modified.
local _, ns = ...
local Logic = ns.Logic

local hookedViews = setmetatable({}, {__mode = "k"})
local painting = false
local reported = {}

local function report(key, message)
    if reported[key] then
        return
    end
    reported[key] = true
    print("|cffff4040BetterNamePlatesTweaks:|r " .. message)
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

-- Room kept free on the right of the bar for the health number.
local HEALTH_TEXT_ROOM = 30
local GOLD = {0.91, 0.72, 0.17}
local GLOW_SIZE = 1.5   -- view units (~3 px on 1440p)
local GLOW_ALPHA = 0.6

-- Name stops short of the health number. BetterNamePlates resets the width
-- on resize, so this also runs from a SetWidth hook (see styleView).
local settingNameWidth = false
local function applyNameWidth(view)
    local width = view.healthForeground:GetWidth() - HEALTH_TEXT_ROOM
    settingNameWidth = true
    local ok, err = pcall(function()
        for _, layer in ipairs(view.nameLayers) do
            layer:SetWidth(width)
        end
    end)
    settingNameWidth = false
    if not ok then
        error(err)
    end
end

-- "%lvl %name" on one line; the font string truncates at its width, which
-- stops short of the health number on the right of the bar.
local function applyFullName(view, unit)
    local name = UnitName(unit)
    if not name then
        return
    end
    local level = UnitEffectiveLevel and UnitEffectiveLevel(unit) or
        UnitLevel(unit)
    local text = Logic.FormatName(name, level)
    for _, layer in ipairs(view.nameLayers) do
        layer:SetWordWrap(false)
        layer:SetNonSpaceWrap(false)
        layer:SetMaxLines(1)
        layer:SetText(text)
    end
    applyNameWidth(view)
end

-- Right-hand text shows current health (900, 1.5к) instead of percent.
local writingHealth = false
local function applyHealthText(view)
    local unit = view.unit
    if not view:IsShown() or not unit or not UnitExists(unit) then
        return
    end
    local health = UnitHealth(unit)
    local text
    if issecretvalue and issecretvalue(health) then
        text = AbbreviateNumbers(health) -- secret values: Blizzard formatter only
    else
        text = Logic.FormatHealth(health)
    end
    writingHealth = true
    local ok, err = pcall(view.healthPercentage.SetText,
        view.healthPercentage, text)
    writingHealth = false
    if not ok then
        error(err)
    end
end

local function createGlow(indicator, bar)
    local glow = CreateFrame("Frame", nil, indicator)
    glow:SetAllPoints(bar)
    if not glow:CreateTexture().SetGradient then
        glow:Hide()
        report("glow", "Texture:SetGradient is missing; target glow disabled")
        return
    end
    local function edge(orientation, inner, outer, ...)
        local texture = glow:CreateTexture(nil, "BACKGROUND")
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetGradient(orientation, inner, outer)
        for _, point in ipairs({...}) do
            texture:SetPoint(point[1], bar, point[2], point[3], point[4])
        end
    end
    local solid = CreateColor(GOLD[1], GOLD[2], GOLD[3], GLOW_ALPHA)
    local clear = CreateColor(GOLD[1], GOLD[2], GOLD[3], 0)
    local g = GLOW_SIZE
    -- VERTICAL gradient: first color = bottom; HORIZONTAL: first = left.
    edge("VERTICAL", solid, clear,
        {"BOTTOMLEFT", "TOPLEFT", 0, 0}, {"TOPRIGHT", "TOPRIGHT", 0, g})
    edge("VERTICAL", clear, solid,
        {"TOPLEFT", "BOTTOMLEFT", 0, 0}, {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, -g})
    edge("HORIZONTAL", clear, solid,
        {"TOPRIGHT", "TOPLEFT", 0, 0}, {"BOTTOMLEFT", "BOTTOMLEFT", -g, 0})
    edge("HORIZONTAL", solid, clear,
        {"TOPLEFT", "TOPRIGHT", 0, 0}, {"BOTTOMRIGHT", "BOTTOMRIGHT", g, 0})
end

-- One-time restyle of a BetterNamePlates view.
local styledViews = setmetatable({}, {__mode = "k"})
local function styleView(view)
    if styledViews[view] then
        return
    end
    styledViews[view] = true

    for _, layer in ipairs(view.nameLayers) do
        hooksecurefunc(layer, "SetWidth", function()
            if not settingNameWidth then
                applyNameWidth(view)
            end
        end)
    end

    -- Health number moves to the right-hand (percent) slot.
    -- Hide the left health number; BetterNamePlates never shows it again
    -- itself, the hook covers any other caller.
    view.healthText:Hide()
    hooksecurefunc(view.healthText, "Show", function(text) text:Hide() end)
    hooksecurefunc(view.healthPercentage, "SetText", function()
        if not writingHealth then
            applyHealthText(view)
        end
    end)

    -- Target: gold border + soft gold glow (indicator is shown only on target).
    local indicator = view.targetIndicator
    local arrows = {[indicator.leftArrow] = true, [indicator.rightArrow] = true}
    local borderRegions = {indicator:GetRegions()}
    for _, region in ipairs({indicator.corners:GetRegions()}) do
        borderRegions[#borderRegions + 1] = region
    end
    for _, region in ipairs(borderRegions) do
        if not arrows[region] and region.SetColorTexture then
            region:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        end
    end
    createGlow(indicator, view.healthForeground)
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
    styleView(view)
    applyFullName(view, unit)
    applyHealthText(view)
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
        C_Timer.After(0, handleAllPlates)
    elseif event == "PLAYER_REGEN_ENABLED" then
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
    local plates = C_NamePlate.GetNamePlates()
    local first = plates[1]
    if first then
        print("BNPT plate API: SetAllHitTestPoints", has(first.SetAllHitTestPoints),
            "CanChangeHitTestPoints", has(first.CanChangeHitTestPoints),
            "SetStackingBoundsFrame", has(first.SetStackingBoundsFrame))
    end
    local enemies = 0
    for _, plate in ipairs(plates) do
        local view = plate.BetterNamePlatesView
        if view and view:IsShown() and view.unit then
            enemies = enemies + 1
            -- Print the error text instead of aborting the whole report.
            local ok, points = pcall(function()
                return #plate:GetHitTestPoints()
            end)
            print("BNPT", view.unit, "hit-test points:",
                ok and points or ("ERROR " .. tostring(points)))
        end
    end
    if enemies == 0 then
        print("BNPT no enemy plates on screen: stand near hostile mobs and repeat /bnpt")
    end
end
