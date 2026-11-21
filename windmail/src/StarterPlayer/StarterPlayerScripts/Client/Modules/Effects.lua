-- Sons, camera (champ de vision selon la vitesse), vent, confettis, eclaboussures.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Glider = require(script.Parent.Glider)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SOUNDS = {
	click = "rbxasset://sounds/electronicpingshort.wav",
	deliver = "rbxasset://sounds/electronicpingshort.wav",
	whoosh = "rbxasset://sounds/swoosh.wav",
	land = "rbxasset://sounds/action_jump_land.mp3",
	wind = "rbxasset://sounds/action_falling.mp3",
	splash = "rbxasset://sounds/action_swim.mp3",
}

function Effects.Play(name, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = SOUNDS[name] or name
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(6, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function Effects.Confetti(position, big)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Speed = NumberRange.new(18, 30)
	e.SpreadAngle = Vector2.new(50, 50)
	e.Acceleration = Vector3.new(0, -35, 0)
	e.Drag = 1.5
	e.Size = NumberSequence.new(0.35)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-300, 300)
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 210, 70)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 200, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 230, 130)),
	})
	e.Parent = p
	e:Emit(big and 120 or 60)
	task.delay(3, function()
		p:Destroy()
	end)
end

function Effects.Shake(intensity, duration)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = 1 - (os.clock() - t0) / duration
		if k <= 0 then
			conn:Disconnect()
			return
		end
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * intensity * k), math.rad((math.random() - 0.5) * intensity * k), 0)
	end)
end

function Effects.Init()
	local wind = Instance.new("Sound")
	wind.SoundId = SOUNDS.wind
	wind.Looped = true
	wind.Volume = 0
	wind.Parent = SoundService
	wind:Play()
	local baseFov = 70
	RunService.RenderStepped:Connect(function(dt)
		local target = baseFov
		local vol = 0
		if Glider.Gliding then
			target = baseFov + math.clamp((Glider.Speed - 30) * 0.35, 0, 24)
			vol = math.clamp(Glider.Speed / 90, 0.15, 0.8)
		end
		camera.FieldOfView += (target - camera.FieldOfView) * math.clamp(dt * 3, 0, 1)
		wind.Volume += (vol - wind.Volume) * math.clamp(dt * 3, 0, 1)
		wind.PlaybackSpeed = 0.8 + math.clamp(Glider.Speed / 150, 0, 0.6)
	end)
	Glider.Signal.Event:Connect(function(kind)
		if kind == "ring" then
			Effects.Play("whoosh", 0.7, 1.2)
			camera.FieldOfView += 8
		elseif kind == "open" then
			Effects.Play("whoosh", 0.4, 0.8)
		elseif kind == "close" then
			Effects.Play("land", 0.4)
		end
	end)
	Remotes.FX.OnClientEvent:Connect(function(kind, data)
		data = data or {}
		if kind == "Confetti" then
			Effects.Confetti(data.position, data.userId == player.UserId)
		elseif kind == "Delivered" then
			Effects.Play("deliver", 0.8, 1.1)
			task.delay(0.12, Effects.Play, "deliver", 0.6, 1.5)
		elseif kind == "Impact" then
			Effects.Shake(3, 0.35)
			Effects.Play("land", 0.8, 0.7)
		elseif kind == "Splash" then
			Effects.Play("splash", 0.8)
		elseif kind == "Pickup" or kind == "Purchase" or kind == "Stamp" then
			Effects.Play("click", 0.6, 1.3)
		elseif kind == "RankUp" or kind == "Daily" then
			Effects.Play("deliver", 0.9, 0.8)
			task.delay(0.15, Effects.Play, "deliver", 0.9, 1.2)
			task.delay(0.3, Effects.Play, "deliver", 0.9, 1.6)
		end
	end)
end

return Effects
