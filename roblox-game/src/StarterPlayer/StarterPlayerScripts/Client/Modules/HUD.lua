-- Interface : phase/timer, cible, vitesse du ballon, capacites, stats, notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)

local HUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FONT = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold

local ui = {}
local Input -- injecte par Init

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0 }, parent)
end

local function label(props, parent)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function buildAbilityButton(parent, name, title, key, color, order)
	local button = new("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = Config.Colors.Dark,
		BackgroundTransparency = 0.15,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
	}, parent)
	corner(button, 14)
	stroke(button, color, 3)

	local fill = new("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(1, 0),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
	}, button)
	corner(fill, 14)

	label({
		Name = "Title",
		Size = UDim2.new(1, -8, 0, 26),
		Position = UDim2.new(0, 4, 0, 10),
		Text = title,
		TextColor3 = color,
	}, button)
	label({
		Name = "Key",
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.new(0, 4, 0, 40),
		Text = key,
		Font = FONT_BOLD,
		TextColor3 = Color3.fromRGB(220, 220, 230),
	}, button)
	label({
		Name = "Timer",
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.new(0, 4, 1, -24),
		Text = "",
		Font = FONT_BOLD,
		TextColor3 = Color3.new(1, 1, 1),
	}, button)
	return button
end

local function build()
	local gui = new("ScreenGui", {
		Name = "OnyxHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	ui.gui = gui

	-- Bandeau haut
	local top = new("Frame", {
		Name = "Top",
		Size = UDim2.fromOffset(420, 86),
		Position = UDim2.new(0.5, 0, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Config.Colors.Dark,
		BackgroundTransparency = 0.25,
	}, gui)
	corner(top, 16)
	stroke(top, Config.Colors.Accent, 2, 0.3)
	ui.phase = label({
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.new(0, 8, 0, 8),
		Text = Config.GameName,
		TextColor3 = Config.Colors.Accent,
	}, top)
	ui.timer = label({
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.new(0, 8, 0, 40),
		Text = "",
	}, top)

	-- Compteur de survivants
	local aliveFrame = new("Frame", {
		Size = UDim2.fromOffset(170, 44),
		Position = UDim2.new(1, -14, 0, 58),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Config.Colors.Dark,
		BackgroundTransparency = 0.25,
	}, gui)
	corner(aliveFrame, 12)
	stroke(aliveFrame, Config.Colors.Accent2, 2, 0.3)
	ui.alive = label({ Size = UDim2.new(1, -12, 1, -8), Position = UDim2.new(0, 6, 0, 4), Text = "" }, aliveFrame)

	-- Stats joueur
	local stats = new("Frame", {
		Size = UDim2.fromOffset(190, 96),
		Position = UDim2.new(0, 14, 0, 58),
		BackgroundColor3 = Config.Colors.Dark,
		BackgroundTransparency = 0.25,
	}, gui)
	corner(stats, 12)
	stroke(stats, Config.Colors.Gold, 2, 0.3)
	ui.coins = label({ Size = UDim2.new(1, -12, 0, 28), Position = UDim2.new(0, 8, 0, 4), Text = "0 pieces", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Gold }, stats)
	ui.wins = label({ Size = UDim2.new(1, -12, 0, 28), Position = UDim2.new(0, 8, 0, 34), Text = "0 victoires", TextXAlignment = Enum.TextXAlignment.Left }, stats)
	ui.streak = label({ Size = UDim2.new(1, -12, 0, 26), Position = UDim2.new(0, 8, 0, 64), Text = "Serie : 0", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Accent, Font = FONT_BOLD }, stats)

	-- Banniere CIBLE
	ui.targetBanner = label({
		Name = "TargetBanner",
		Size = UDim2.fromOffset(520, 70),
		Position = UDim2.new(0.5, 0, 0, 160),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "TU ES LA CIBLE !",
		TextColor3 = Config.Colors.Danger,
		Visible = false,
	}, gui)

	-- Vignette rouge
	ui.vignette = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Config.Colors.Danger,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, gui)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, 1),
			NumberSequenceKeypoint.new(0.75, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, ui.vignette)

	-- Barre de vitesse du ballon
	local speedFrame = new("Frame", {
		Size = UDim2.fromOffset(300, 40),
		Position = UDim2.new(0.5, 0, 1, -140),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Config.Colors.Dark,
		BackgroundTransparency = 0.25,
		Visible = false,
	}, gui)
	corner(speedFrame, 10)
	stroke(speedFrame, Config.Colors.Accent, 2, 0.3)
	ui.speedFrame = speedFrame
	ui.speedFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Config.Colors.Accent,
		BorderSizePixel = 0,
	}, speedFrame)
	corner(ui.speedFill, 10)
	ui.speedText = label({ Size = UDim2.fromScale(1, 1), Text = "Vitesse 0", Font = FONT_BOLD }, speedFrame)
	ui.speedText.ZIndex = 2

	-- Capacites
	local abilities = new("Frame", {
		Name = "Abilities",
		Size = UDim2.fromOffset(300, 90),
		Position = UDim2.new(0.5, 0, 1, -30),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
	}, gui)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
	}, abilities)

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	ui.buttons = {
		Deflect = buildAbilityButton(abilities, "Deflect", "RENVOI", touch and "TAP" or "F / CLIC", Config.Colors.Accent, 1),
		Dash = buildAbilityButton(abilities, "Dash", "DASH", touch and "TAP" or "Q", Config.Colors.Gold, 2),
		Pulse = buildAbilityButton(abilities, "Pulse", "PULSE", touch and "TAP" or "E", Config.Colors.Accent2, 3),
	}
	if touch then
		abilities.Position = UDim2.new(1, -20, 1, -40)
		abilities.AnchorPoint = Vector2.new(1, 1)
		for _, b in pairs(ui.buttons) do
			b.Size = UDim2.fromOffset(96, 96)
		end
	end

	-- Overdrive
	ui.overdrive = label({
		Size = UDim2.fromOffset(400, 40),
		Position = UDim2.new(0.5, 0, 0, 148),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "OVERDRIVE",
		TextColor3 = Config.Colors.Accent2,
		Visible = false,
	}, gui)

	-- Notifications
	local toasts = new("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(460, 200),
		Position = UDim2.new(0.5, 0, 0, 240),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	}, gui)
	new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, toasts)
	ui.toasts = toasts

	-- Ecran de fin
	ui.endScreen = label({
		Size = UDim2.fromOffset(700, 90),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		TextColor3 = Config.Colors.Gold,
		Visible = false,
	}, gui)
end

local toastCount = 0
function HUD.toast(text, kind)
	toastCount += 1
	local color = Color3.new(1, 1, 1)
	if kind == "danger" then
		color = Config.Colors.Danger
	elseif kind == "gold" then
		color = Config.Colors.Gold
	elseif kind == "overdrive" then
		color = Config.Colors.Accent2
	elseif kind == "good" then
		color = Config.Colors.Accent
	end
	local frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Config.Colors.Dark,
		BackgroundTransparency = 0.3,
		LayoutOrder = toastCount,
	}, ui.toasts)
	corner(frame, 8)
	stroke(frame, color, 2, 0.4)
	local l = label({ Size = UDim2.new(1, -12, 1, -6), Position = UDim2.new(0, 6, 0, 3), Text = text, TextColor3 = color, Font = FONT_BOLD }, frame)
	task.delay(3, function()
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
end

local function updateStats()
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local coins = ls:FindFirstChild("Coins")
	local wins = ls:FindFirstChild("Wins")
	local streak = ls:FindFirstChild("Streak")
	ui.coins.Text = (coins and coins.Value or 0) .. " pieces"
	ui.wins.Text = (wins and wins.Value or 0) .. " victoires"
	ui.streak.Text = "Serie : " .. (streak and streak.Value or 0)
end

local function hookStats()
	local ls = player:WaitForChild("leaderstats", 30)
	if not ls then
		return
	end
	for _, v in ipairs(ls:GetChildren()) do
		v.Changed:Connect(updateStats)
	end
	ls.ChildAdded:Connect(function(v)
		v.Changed:Connect(updateStats)
		updateStats()
	end)
	updateStats()
end

local function onRoundState(round)
	local previous = State.round
	State.round = round
	local phaseText = {
		Waiting = "EN ATTENTE",
		Intermission = "LOBBY",
		Starting = "DEPART",
		Playing = round.practice and "ENTRAINEMENT" or "MANCHE EN COURS",
		Ending = "FIN DE MANCHE",
	}
	ui.phase.Text = phaseText[round.phase] or Config.GameName
	if round.timer and round.timer > 0 then
		if round.phase == "Playing" then
			local m = math.floor(round.timer / 60)
			local s = round.timer % 60
			ui.timer.Text = string.format("%d:%02d", m, s)
		elseif round.phase == "Starting" then
			ui.timer.Text = round.message .. "  " .. round.timer
		else
			ui.timer.Text = round.message .. "  " .. round.timer .. "s"
		end
	else
		ui.timer.Text = round.message or ""
	end

	ui.alive.Text = (round.aliveCount or 0) .. " / " .. (round.totalCount or 0) .. " en vie"
	ui.alive.Parent.Visible = round.phase == "Playing" or round.phase == "Starting"
	ui.speedFrame.Visible = round.phase == "Playing"

	if round.phase ~= "Playing" then
		State.targetUserId = 0
		ui.targetBanner.Visible = false
		ui.overdrive.Visible = false
		State.overdrive = false
	end

	if round.phase == "Ending" then
		ui.endScreen.Text = round.message
		ui.endScreen.Visible = true
		ui.endScreen.TextColor3 = (round.winnerUserId == player.UserId) and Config.Colors.Gold or Color3.new(1, 1, 1)
		ui.endScreen.Size = UDim2.fromOffset(100, 20)
		TweenService:Create(ui.endScreen, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(700, 90) }):Play()
	else
		ui.endScreen.Visible = false
	end

	if round.phase == "Starting" and previous.phase ~= "Starting" then
		HUD.toast(round.practice and "Entrainement solo : le ballon ne t'elimine pas" or "Dernier survivant gagne !", "good")
	end
	State.Changed:Fire("round", round)
end

local function updateCooldowns()
	local durations = {
		Deflect = Config.Ball.DeflectCooldown,
		Dash = Config.Abilities.Dash.Cooldown,
		Pulse = Config.Abilities.Pulse.Cooldown,
	}
	for name, button in pairs(ui.buttons) do
		local left = State.cooldownLeft(name)
		local ratio = math.clamp(left / durations[name], 0, 1)
		button.Cooldown.Size = UDim2.fromScale(1, ratio)
		button.Timer.Text = left > 0.05 and string.format("%.1f", left) or ""
		button.BackgroundTransparency = left > 0 and 0.4 or 0.15
	end
end

local function updateBall()
	local ball = State.getBall()
	if not ball then
		ui.speedFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local speed = ball:GetAttribute("Speed") or 0
	local ratio = math.clamp((speed - Config.Ball.BaseSpeed) / (Config.Ball.MaxSpeed - Config.Ball.BaseSpeed), 0, 1)
	ui.speedFill.Size = UDim2.fromScale(math.max(ratio, 0.03), 1)
	ui.speedFill.BackgroundColor3 = Config.Colors.Accent:Lerp(Config.Colors.Danger, ratio)
	ui.speedText.Text = "Vitesse " .. speed .. "  |  Renvois " .. (ball:GetAttribute("Deflects") or 0)

	local targeted = State.targetUserId == player.UserId
	ui.targetBanner.Visible = targeted
	if targeted then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 10)
		ui.targetBanner.TextTransparency = pulse * 0.4
		local dist = 999
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			dist = (hrp.Position - ball.Position).Magnitude
		end
		local close = math.clamp(1 - (dist - Config.Ball.DeflectRange) / 40, 0, 1)
		ui.vignette.BackgroundTransparency = 1 - close * 0.55
		ui.targetBanner.Text = dist <= Config.Ball.DeflectRange and "RENVOIE MAINTENANT !" or "TU ES LA CIBLE !"
		ui.targetBanner.TextColor3 = dist <= Config.Ball.DeflectRange and Config.Colors.Accent or Config.Colors.Danger
	else
		ui.vignette.BackgroundTransparency = 1
	end

	if State.overdrive then
		ui.overdrive.Visible = true
		ui.overdrive.TextTransparency = 0.3 + 0.3 * math.sin(os.clock() * 6)
	end
end

function HUD.Init(inputModule)
	Input = inputModule
	build()
	task.spawn(hookStats)

	ui.buttons.Deflect.Activated:Connect(function()
		Input.deflect()
	end)
	ui.buttons.Dash.Activated:Connect(function()
		Input.dash()
	end)
	ui.buttons.Pulse.Activated:Connect(function()
		Input.pulse()
	end)

	Remotes.RoundState.OnClientEvent:Connect(onRoundState)
	Remotes.Notify.OnClientEvent:Connect(HUD.toast)

	RunService.RenderStepped:Connect(function()
		updateCooldowns()
		updateBall()
	end)
end

return HUD
