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

-- Same format as BetterNamePlates on Classic clients ("8 Name (E)"), but
-- without its byte-based 16-char cut that chops UTF-8 (Cyrillic) names.
local CLASSIFICATION_SUFFIXES = {
    elite = " (E)",
    rare = " (R)",
    rareelite = " (RE)",
}

function Logic.FormatName(name, level, classification)
    local prefix = ""
    if level == -1 then
        prefix = "?? "
    elseif type(level) == "number" and level > 0 then
        prefix = tostring(level) .. " "
    end
    return prefix .. name .. (CLASSIFICATION_SUFFIXES[classification] or "")
end

ns.Logic = Logic

return Logic
