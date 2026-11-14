-- Controles : renvoi, dash, double saut, pulse, jump pads, boutons tactiles.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)

local Input = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local character, humanoid, rootPart
local canDoubleJump = false
local lastJumpTime = 0
local lastSwing = 0

local sounds = {}
local function playSound(id, volume, pitch)
	local s = sounds[id]
	if not s then
		s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = workspace
		sounds[id] = s
	end
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s:Play()
end

local function fovPunch(amount, duration)
	local base = 70
	camera.FieldOfView = base + amount
	TweenService:Create(camera, TweenInfo.new(duration or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
end

-- Onde locale instantanee (feedback avant la reponse serveur)
local function localSwingRing()
	if not rootPart then
		return
	end
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Ball
	ring.Size = Vector3.new(3, 3, 3)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.new(1, 1, 1)
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CFrame = rootPart.CFrame
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(Config.Ball.DeflectRange * 1.6, 1, Config.Ball.DeflectRange * 1.6),
		Transparency = 1,
	}):Play()
	task.delay(0.3, function()
		ring:Destroy()
	end)
end

function Input.deflect()
	local now = os.clock()
	if now - lastSwing < Config.Ball.DeflectCooldown then
		return
	end
	lastSwing = now
	State.setCooldown("Deflect", Config.Ball.DeflectCooldown)
	localSwingRing()
	playSound("rbxasset://sounds/swoosh.wav", 0.6, 1.2)
	Remotes.Deflect:FireServer()
end

function Input.dash()
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end
	if State.cooldownLeft("Dash") > 0 then
		return
	end
	State.setCooldown("Dash", Config.Abilities.Dash.Cooldown)

	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.1 then
		dir = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	if dir.Magnitude < 0.01 then
		dir = rootPart.CFrame.LookVector
	end
	dir = dir.Unit
	rootPart.AssemblyLinearVelocity = dir * Config.Abilities.Dash.Speed + Vector3.new(0, Config.Abilities.Dash.Lift, 0)

	fovPunch(14, 0.4)
	playSound("rbxasset://sounds/swoosh.wav", 0.8, 0.8)
	Remotes.Ability:FireServer("Dash")
	State.Changed:Fire("dash")
end

function Input.pulse()
	if not rootPart or State.cooldownLeft("Pulse") > 0 then
		return
	end
	if State.round.phase ~= "Playing" then
		return
	end
	State.setCooldown("Pulse", Config.Abilities.Pulse.Cooldown)
	Remotes.Ability:FireServer("Pulse")
	fovPunch(-8, 0.5)
end

local function tryDoubleJump()
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end
	local stateName = humanoid:GetState()
	if stateName ~= Enum.HumanoidStateType.Freefall then
		return
	end
	if not canDoubleJump or os.clock() - lastJumpTime < 0.2 then
		return
	end
	canDoubleJump = false
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local v = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(v.X, Config.Abilities.DoubleJump.Power, v.Z)
	playSound("rbxasset://sounds/action_jump.mp3", 0.5, 1.3)
	State.Changed:Fire("doublejump")
end

local function onCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart")
	canDoubleJump = false

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			canDoubleJump = true
		elseif new == Enum.HumanoidStateType.Jumping then
			lastJumpTime = os.clock()
		end
	end)
end

-- Jump pads
local padDebounce = 0
local function hookPad(pad)
	pad.Touched:Connect(function(hit)
		if not character or hit.Parent ~= character or not rootPart then
			return
		end
		if os.clock() - padDebounce < 0.6 then
			return
		end
		padDebounce = os.clock()
		local power = pad:GetAttribute("Power") or Config.Arena.JumpPadPower
		local v = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(v.X * 0.6, power, v.Z * 0.6)
		canDoubleJump = true
		playSound("rbxasset://sounds/action_jump.mp3", 0.7, 0.7)
		fovPunch(10, 0.5)
	end)
end

function Input.Init()
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	for _, pad in ipairs(CollectionService:GetTagged("JumpPad")) do
		hookPad(pad)
	end
	CollectionService:GetInstanceAddedSignal("JumpPad"):Connect(hookPad)

	UserInputService.JumpRequest:Connect(tryDoubleJump)

	ContextActionService:BindAction("OnyxDeflect", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Input.deflect()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:BindAction("OnyxDash", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Input.dash()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)

	ContextActionService:BindAction("OnyxPulse", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Input.pulse()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
end

return Input
