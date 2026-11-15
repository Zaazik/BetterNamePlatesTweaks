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

-- Threat queries may return secret values (the game hides them in some
-- places, e.g. dungeons). Addon code may not compare them, and there is no
-- secret-safe way to test a number against a threshold (ColorCurve:Evaluate
-- refuses secret input from addon code), so a hidden value counts as unknown:
-- it is never passed on, only flagged. isSecret is issecretvalue in the game.
function Logic.VisibleThreat(status, percent, isSecret)
    local statusHidden = isSecret(status)
    local percentHidden = isSecret(percent)
    return {
        threatStatus = not statusHidden and status or nil,
        threatPercent = not percentHidden and percent or nil,
        threatStatusHidden = statusHidden,
        threatPercentHidden = percentHidden,
    }
end

-- Returns {r, g, b} to paint, or nil to keep BetterNamePlates' own color.
-- unit fields: canAttack, isPlayer, classColor, isTapDenied, isTank,
-- threatStatus (UnitThreatSituation), threatPercent (scaledPercent),
-- threatStatusHidden (see VisibleThreat; a hidden percent is just nil).
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

    -- Threat state unknown here: no threat colors.
    if unit.threatStatusHidden then
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

-- "%lvl %name": BetterNamePlates cuts names by bytes, which chops UTF-8
-- (Cyrillic) names, so the full name is rebuilt here.
function Logic.FormatName(name, level)
    if level == -1 then
        return "?? " .. name
    elseif type(level) == "number" and level > 0 then
        return tostring(level) .. " " .. name
    end
    return name
end

-- Current health: 900, 1.5к, 12к, 1.2м.
local function shortNumber(value, divisor, suffix)
    local text = string.format("%.1f", value / divisor):gsub("%.0$", "")
    return text .. suffix
end

function Logic.FormatHealth(health)
    if health < 1000 then
        return tostring(math.floor(health))
    elseif health < 999950 then -- 999950+ would round to "1000.0к"
        return shortNumber(health, 1000, "к")
    end
    return shortNumber(health, 1000000, "м")
end

ns.Logic = Logic

return Logic
