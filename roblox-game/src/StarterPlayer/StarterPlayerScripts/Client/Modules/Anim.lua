-- Animations procedurales : on tween les Motor6D (C0) des personnages, R15 et R6.
-- Aucun asset d'animation necessaire ; fonctionne sur son propre perso et ceux des autres.

local TweenService = game:GetService("TweenService")

local Anim = {}

local originals = {} -- [Motor6D] = C0 d'origine

local function joint(character, r15Name, r15Parent, r6Name)
	local part = character:FindFirstChild(r15Parent)
	local motor = part and part:FindFirstChild(r15Name)
	if not motor and r6Name then
		local torso = character:FindFirstChild("Torso")
		motor = torso and torso:FindFirstChild(r6Name)
	end
	if motor and motor:IsA("Motor6D") then
		if not originals[motor] then
			originals[motor] = motor.C0
		end
		return motor
	end
	return nil
end

local function joints(character)
	return {
		rightArm = joint(character, "RightShoulder", "RightUpperArm", "Right Shoulder"),
		leftArm = joint(character, "LeftShoulder", "LeftUpperArm", "Left Shoulder"),
		waist = joint(character, "Waist", "UpperTorso", nil),
		neck = joint(character, "Neck", "Head", "Neck"),
		rightLeg = joint(character, "RightHip", "RightUpperLeg", "Right Hip"),
	}
end

local function tweenTo(motor, offset, duration, style)
	if not motor then
		return
	end
	TweenService:Create(motor, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = originals[motor] * offset }):Play()
end

local function reset(motor, duration)
	if motor then
		TweenService:Create(motor, TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = originals[motor] }):Play()
	end
end

local R = math.rad
local FWD = CFrame.Angles(R(90), 0, 0) -- bras tendu devant

local poses = {}

-- M1 : alternance droite / gauche / coup de pied / coup lourd
poses.m1 = function(j, combo)
	combo = ((combo or 1) - 1) % 4 + 1
	if combo == 1 then
		tweenTo(j.rightArm, FWD * CFrame.Angles(0, 0, R(-15)), 0.08)
		tweenTo(j.waist, CFrame.Angles(0, R(-25), 0), 0.08)
		task.delay(0.18, function() reset(j.rightArm, 0.2); reset(j.waist, 0.2) end)
	elseif combo == 2 then
		tweenTo(j.leftArm, FWD * CFrame.Angles(0, 0, R(15)), 0.08)
		tweenTo(j.waist, CFrame.Angles(0, R(25), 0), 0.08)
		task.delay(0.18, function() reset(j.leftArm, 0.2); reset(j.waist, 0.2) end)
	elseif combo == 3 then
		tweenTo(j.rightLeg, CFrame.Angles(R(70), 0, 0), 0.1)
		tweenTo(j.waist, CFrame.Angles(R(-15), 0, 0), 0.1)
		task.delay(0.22, function() reset(j.rightLeg, 0.25); reset(j.waist, 0.25) end)
	else
		tweenTo(j.rightArm, CFrame.Angles(R(160), 0, R(-20)), 0.1)
		tweenTo(j.waist, CFrame.Angles(R(10), R(-30), 0), 0.1)
		task.delay(0.12, function()
			tweenTo(j.rightArm, FWD * CFrame.Angles(0, 0, R(-10)), 0.08, Enum.EasingStyle.Back)
			tweenTo(j.waist, CFrame.Angles(R(-10), R(20), 0), 0.08)
		end)
		task.delay(0.4, function() reset(j.rightArm, 0.25); reset(j.waist, 0.25) end)
	end
end

poses.jab = function(j)
	tweenTo(j.rightArm, FWD, 0.07)
	tweenTo(j.waist, CFrame.Angles(0, R(-30), 0), 0.07)
	task.delay(0.25, function() reset(j.rightArm, 0.2); reset(j.waist, 0.2) end)
end

poses.uppercut = function(j)
	tweenTo(j.rightArm, CFrame.Angles(R(-40), 0, R(-10)), 0.15)
	tweenTo(j.waist, CFrame.Angles(R(15), 0, 0), 0.15)
	task.delay(0.2, function()
		tweenTo(j.rightArm, CFrame.Angles(R(170), 0, R(-10)), 0.1, Enum.EasingStyle.Back)
		tweenTo(j.waist, CFrame.Angles(R(-15), 0, 0), 0.1)
	end)
	task.delay(0.6, function() reset(j.rightArm, 0.3); reset(j.waist, 0.3) end)
end

poses.heavy = function(j)
	tweenTo(j.rightArm, CFrame.Angles(R(170), 0, R(-30)), 0.25)
	tweenTo(j.leftArm, CFrame.Angles(R(60), 0, R(30)), 0.25)
	tweenTo(j.waist, CFrame.Angles(R(10), R(-40), 0), 0.25)
	task.delay(0.4, function()
		tweenTo(j.rightArm, FWD * CFrame.Angles(0, 0, R(-10)), 0.08, Enum.EasingStyle.Back)
		tweenTo(j.waist, CFrame.Angles(R(-15), R(25), 0), 0.08)
	end)
	task.delay(0.8, function() reset(j.rightArm, 0.3); reset(j.leftArm, 0.3); reset(j.waist, 0.3) end)
end

poses.rush = function(j)
	tweenTo(j.waist, CFrame.Angles(R(-30), 0, 0), 0.1)
	tweenTo(j.rightArm, FWD, 0.1)
	tweenTo(j.leftArm, CFrame.Angles(R(-50), 0, R(20)), 0.1)
	task.delay(0.5, function() reset(j.waist, 0.3); reset(j.rightArm, 0.3); reset(j.leftArm, 0.3) end)
end

poses.slam = function(j)
	tweenTo(j.rightArm, CFrame.Angles(R(175), 0, R(-15)), 0.3)
	tweenTo(j.leftArm, CFrame.Angles(R(175), 0, R(15)), 0.3)
	tweenTo(j.waist, CFrame.Angles(R(15), 0, 0), 0.3)
	task.delay(0.45, function()
		tweenTo(j.rightArm, CFrame.Angles(R(40), 0, R(-15)), 0.1, Enum.EasingStyle.Back)
		tweenTo(j.leftArm, CFrame.Angles(R(40), 0, R(15)), 0.1, Enum.EasingStyle.Back)
		tweenTo(j.waist, CFrame.Angles(R(-35), 0, 0), 0.1)
	end)
	task.delay(0.9, function() reset(j.rightArm, 0.3); reset(j.leftArm, 0.3); reset(j.waist, 0.3) end)
end

poses.cast = function(j)
	tweenTo(j.rightArm, CFrame.Angles(R(120), 0, R(-30)), 0.15)
	tweenTo(j.leftArm, CFrame.Angles(R(120), 0, R(30)), 0.15)
	tweenTo(j.waist, CFrame.Angles(R(8), 0, 0), 0.15)
	task.delay(0.25, function()
		tweenTo(j.rightArm, FWD * CFrame.Angles(0, 0, R(-10)), 0.08)
		tweenTo(j.leftArm, FWD * CFrame.Angles(0, 0, R(10)), 0.08)
		tweenTo(j.waist, CFrame.Angles(R(-10), 0, 0), 0.08)
	end)
	task.delay(0.65, function() reset(j.rightArm, 0.3); reset(j.leftArm, 0.3); reset(j.waist, 0.3) end)
end

poses.power = function(j)
	tweenTo(j.rightArm, CFrame.Angles(R(30), 0, R(-70)), 0.2)
	tweenTo(j.leftArm, CFrame.Angles(R(30), 0, R(70)), 0.2)
	tweenTo(j.waist, CFrame.Angles(R(-12), 0, 0), 0.2)
	tweenTo(j.neck, CFrame.Angles(R(25), 0, 0), 0.2)
	task.delay(0.7, function() reset(j.rightArm, 0.3); reset(j.leftArm, 0.3); reset(j.waist, 0.3); reset(j.neck, 0.3) end)
end

poses.hit = function(j)
	tweenTo(j.waist, CFrame.Angles(R(18), 0, R(math.random(-10, 10))), 0.06)
	tweenTo(j.neck, CFrame.Angles(R(20), 0, 0), 0.06)
	task.delay(0.2, function() reset(j.waist, 0.25); reset(j.neck, 0.25) end)
end

poses.dash = function(j)
	tweenTo(j.waist, CFrame.Angles(R(-25), 0, 0), 0.08)
	task.delay(0.25, function() reset(j.waist, 0.25) end)
end

function Anim.play(character, poseName, arg)
	if not character then
		return
	end
	local pose = poses[poseName]
	if not pose then
		return
	end
	local ok, err = pcall(pose, joints(character), arg)
	if not ok then
		warn("[OnyxBG] Animation " .. poseName .. " : " .. tostring(err))
	end
end

-- Garde de blocage maintenue
function Anim.block(character, enabled)
	if not character then
		return
	end
	local j = joints(character)
	if enabled then
		tweenTo(j.rightArm, CFrame.Angles(R(110), 0, R(-35)), 0.12)
		tweenTo(j.leftArm, CFrame.Angles(R(110), 0, R(35)), 0.12)
		tweenTo(j.waist, CFrame.Angles(R(6), 0, 0), 0.12)
	else
		reset(j.rightArm, 0.15)
		reset(j.leftArm, 0.15)
		reset(j.waist, 0.15)
	end
end

return Anim
