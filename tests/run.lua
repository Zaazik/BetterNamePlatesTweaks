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

local w, h, y = Logic.ClickBox(94.5, 20.7, 7, 2)
check("click width", w, 189)
check("click height (view + name + gap)", h, (20.7 + 8) * 2)
check("offset centers stack", y, -4)

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
