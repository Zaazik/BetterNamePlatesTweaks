-- lua tests/run.lua  (from the addon folder)
local ns = {}
local Logic = assert(loadfile("Logic.lua"))("BetterNamePlatesTweaks", ns)
local C = Logic.COLORS
local failures = 0

local function check(name, got, want)
    if got ~= want then
        failures = failures + 1
        print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
    else
        print("ok   " .. name)
    end
end

local hunter = {0.67, 0.83, 0.45}
check("friendly unit untouched", Logic.DecideColor({canAttack = false, threatStatus = 3}), nil)
check("enemy player -> class color", Logic.DecideColor({canAttack = true, isPlayer = true, classColor = hunter, threatStatus = 3}), hunter)
check("enemy player w/o class color errors", pcall(Logic.DecideColor, {canAttack = true, isPlayer = true}), false)
check("mob not on threat list -> keep", Logic.DecideColor({canAttack = true}), nil)
check("low threat -> keep", Logic.DecideColor({canAttack = true, threatStatus = 0, threatPercent = 50}), nil)
check("80% threat -> pull warning", Logic.DecideColor({canAttack = true, threatStatus = 0, threatPercent = 80}), C.pullWarning)
check("status 1 -> pull warning", Logic.DecideColor({canAttack = true, threatStatus = 1}), C.pullWarning)
check("status 2 -> aggro", Logic.DecideColor({canAttack = true, threatStatus = 2}), C.playerAggro)
check("status 3 -> aggro", Logic.DecideColor({canAttack = true, threatStatus = 3, threatPercent = 100}), C.playerAggro)
check("tapped -> keep gray", Logic.DecideColor({canAttack = true, isTapDenied = true, threatStatus = 3}), nil)
check("group tank -> keep", Logic.DecideColor({canAttack = true, isTank = true, threatStatus = 3}), nil)

check("lvl name", Logic.FormatName("Старый кабан", 8), "8 Старый кабан")
check("elite has no suffix", Logic.FormatName("Огр", 30), "30 Огр")
check("skull level", Logic.FormatName("Босс", -1), "?? Босс")
check("hp 900", Logic.FormatHealth(900), "900")
check("hp 1500", Logic.FormatHealth(1500), "1.5к")
check("hp 2000", Logic.FormatHealth(2000), "2к")
check("hp 12345", Logic.FormatHealth(12345), "12.3к")
check("hp 999960", Logic.FormatHealth(999960), "1м")
check("hp 999949", Logic.FormatHealth(999949), "999.9к")
check("hp 1234567", Logic.FormatHealth(1234567), "1.2м")

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
