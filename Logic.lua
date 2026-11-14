-- Pure decision logic (no WoW API calls) so it can be tested outside the game.
local _, ns = ...
ns = ns or {}

local Logic = {}

-- Health bar colors (r, g, b), edit to taste.
Logic.COLORS = {
    pullWarning = {1, 0.45, 0.45}, -- almost pulled aggro: light red
    playerAggro = {1, 0, 0},       -- mob is attacking you: bright red
}

-- UnitDetailedThreatSituation scaledPercent: 100 = you pull aggro.
Logic.PULL_WARNING_PERCENT = 80

-- Gap between the name and the health bar inside BetterNamePlates (nameGap).
Logic.NAME_GAP = 1

-- Returns {r, g, b} to paint, or nil to keep BetterNamePlates' own color.
-- unit fields: canAttack, isPlayer, classColor, isTapDenied, isTank,
-- threatStatus (UnitThreatSituation), threatPercent (scaledPercent).
function Logic.DecideColor(unit)
    if not unit.canAttack then
        return nil
    end

    if unit.isPlayer then
        if not unit.classColor then
            error("BetterNamePlatesTweaks: enemy player without class color")
        end
        return unit.classColor
    end

    -- Tapped mobs keep the gray, a group tank keeps BetterNamePlates' tank colors.
    if unit.isTapDenied or unit.isTank then
        return nil
    end

    local status = unit.threatStatus
    if status and status >= 2 then
        return Logic.COLORS.playerAggro
    end

    if status == 1 or
        (unit.threatPercent and unit.threatPercent >= Logic.PULL_WARNING_PERCENT) then
        return Logic.COLORS.pullWarning
    end

    return nil
end

-- Click box for a BetterNamePlates view.
-- view* are in the view's own units; the name sits above the view's top edge.
-- Returns the base-plate size (in base-plate units) and the Y offset that
-- centers the whole name + health + cast stack on the base plate.
function Logic.ClickBox(viewWidth, viewHeight, nameHeight, viewToPlateRatio)
    local nameExtra = nameHeight + Logic.NAME_GAP
    local stackHeight = viewHeight + nameExtra

    return viewWidth * viewToPlateRatio,
        stackHeight * viewToPlateRatio,
        -nameExtra / 2
end

ns.Logic = Logic

return Logic
