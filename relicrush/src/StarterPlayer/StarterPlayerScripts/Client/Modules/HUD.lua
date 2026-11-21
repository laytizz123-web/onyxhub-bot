-- HUD de RELIC RUSH : pieces, puissance, reliques equipees, boutons des 12 interfaces (icones de la
-- planche), barre de vie de la cible, boss du monde, potions actives, notifications, recompenses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Window = require(script.Parent.Window)

local HUD = {}
local C = UI.C
local player = Players.LocalPlayer
local screen
local refs = {}

-- Notifications ------------------------------------------------------------------------------------
local KIND = { info = C.Blue, good = C.Green, gold = C.Gold, danger = C.Red }
function HUD.Toast(text, kind)
	local t = UI.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 40 }, refs.toasts, true)
	t.BackgroundColor3 = C.Navy
	t.BackgroundTransparency = 0.05
	UI.stroke(t, KIND[kind] or C.Blue, 3)
	UI.pad(t, 10)
	UI.text({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text, TextScaled = false, TextSize = 19, TextWrapped = true, ZIndex = 41 }, t)
	local s = UI.new("UIScale", { Scale = 0.5 }, t)
	UI.tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(4, function()
		UI.tween(s, 0.2, { Scale = 0 })
		task.wait(0.22)
		t:Destroy()
	end)
end

-- Grande annonce (recompense, renaissance...)
function HUD.Big(title, sub, color)
	local f = UI.panel({ Size = UDim2.fromOffset(460, 120), Position = UDim2.new(0.5, 0, 0.3, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 60 }, screen)
	UI.stroke(f, color or C.Gold, 4)
	UI.text({ Size = UDim2.new(1, -30, 0, 52), Position = UDim2.fromOffset(15, 12), Text = title, TextColor3 = color or C.Gold, ZIndex = 61, StrokeThickness = 3 }, f)
	UI.text({ Size = UDim2.new(1, -30, 0, 32), Position = UDim2.fromOffset(15, 70), Text = sub or "", ZIndex = 61 }, f)
	local s = UI.new("UIScale", { Scale = 0.3 }, f)
	UI.tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.8, function()
		UI.tween(s, 0.2, { Scale = 0 })
		task.wait(0.25)
		f:Destroy()
	end)
end

-- Barre du haut -------------------------------------------------------------------------------------
local function pill(icon, color, order)
	local f = UI.panel({ Size = UDim2.fromOffset(190, 54), LayoutOrder = order }, refs.top)
	Icons.Image(icon, f, { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(-14, -5), ZIndex = 3 })
	local t = UI.text({ Size = UDim2.new(1, -62, 0, 34), Position = UDim2.fromOffset(52, 10), Text = "0", TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, StrokeThickness = 3 }, f)
	return t, f
end

local function buildTop()
	refs.top = UI.new("Frame", { Size = UDim2.fromOffset(640, 60), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, screen)
	local l = UI.list(refs.top, 26, true)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	refs.coins, refs.coinPill = pill("coin", C.Gold, 1)
	refs.power, refs.powerPill = pill("power", Color3.fromRGB(215, 160, 255), 2)
	refs.slots = pill("relic", Color3.fromRGB(140, 220, 255), 3)
	refs.boosts = UI.new("Frame", { Size = UDim2.fromOffset(640, 30), Position = UDim2.new(0.5, 0, 0, 74), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, screen)
	UI.list(refs.boosts, 8, true).HorizontalAlignment = Enum.HorizontalAlignment.Center
end

-- Boutons lateraux (icones de la planche) ---------------------------------------------------------------
local BUTTONS_LEFT = { { "index", "Index" }, { "inventory", "Inventory" }, { "shop", "Shop" }, { "worlds", "Worlds" }, { "upgrades", "Upgrades" }, { "rebirth", "Rebirth" } }
local BUTTONS_RIGHT = { { "quests", "Quests" }, { "trading", "Trading" }, { "boss", "Boss" }, { "daily", "Daily" }, { "leaderboard", "Leaderboard" }, { "settings", "Settings" } }

local function sideColumn(list, right)
	local col = UI.new("Frame", { Size = UDim2.fromOffset(200, 330), Position = right and UDim2.new(1, -8, 0.5, 20) or UDim2.new(0, 8, 0.5, 20), AnchorPoint = Vector2.new(right and 1 or 0, 0.5), BackgroundTransparency = 1 }, screen)
	local grid = UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(96, 104), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, col)
	refs.badges = refs.badges or {}
	for i, b in ipairs(list) do
		local btn = Icons.Button(b[1], col, { LayoutOrder = i })
		local s = UI.new("UIScale", {}, btn)
		btn.MouseEnter:Connect(function()
			UI.tween(s, 0.12, { Scale = 1.1 })
		end)
		btn.MouseLeave:Connect(function()
			UI.tween(s, 0.12, { Scale = 1 })
		end)
		btn.MouseButton1Down:Connect(function()
			UI.tween(s, 0.06, { Scale = 0.92 })
		end)
		btn.Activated:Connect(function()
			UI.tween(s, 0.12, { Scale = 1.1 })
			Window.Open(b[2])
		end)
		local badge = UI.new("Frame", { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -24, 0, 0), BackgroundColor3 = C.Red, Visible = false, ZIndex = 5 }, btn)
		UI.corner(badge, 14)
		UI.stroke(badge, Color3.new(1, 1, 1), 2)
		local bt = UI.text({ Size = UDim2.fromScale(1, 1), Text = "!", ZIndex = 6 }, badge)
		refs.badges[b[2]] = { frame = badge, text = bt }
	end
	return col
end

local function fitColumns()
	local vs = workspace.CurrentCamera.ViewportSize
	local s = math.clamp(vs.Y / 820, 0.55, 1)
	for _, c in ipairs({ refs.left, refs.right }) do
		local sc = c:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, c)
		sc.Scale = s
	end
	local tsc = refs.top:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, refs.top)
	tsc.Scale = math.clamp(vs.X / 1100, 0.6, 1)
end

-- Barre de la cible ------------------------------------------------------------------------------------
local function buildTarget()
	local f = UI.panel({ Size = UDim2.fromOffset(420, 70), Position = UDim2.new(0.5, 0, 1, -24), AnchorPoint = Vector2.new(0.5, 1), Visible = false }, screen)
	refs.target = f
	refs.targetName = UI.text({ Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 6), Text = "", TextXAlignment = Enum.TextXAlignment.Left }, f)
	local _, set, fill = UI.bar({ Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 38) }, f, C.Green)
	refs.setTarget = set
	refs.targetFill = fill
	refs.targetHP = UI.text({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 40), Text = "", ZIndex = 3 }, f)
	refs.boss = UI.panel({ Size = UDim2.fromOffset(300, 58), Position = UDim2.new(1, -12, 0, 8), AnchorPoint = Vector2.new(1, 0), Visible = false }, screen)
	UI.stroke(refs.boss, Color3.fromRGB(200, 110, 255), 3)
	Icons.Image("boss", refs.boss, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(-10, -6), ZIndex = 3 })
	refs.bossName = UI.text({ Size = UDim2.new(1, -70, 0, 22), Position = UDim2.fromOffset(60, 5), Text = "", TextXAlignment = Enum.TextXAlignment.Left }, refs.boss)
	local _, setB = UI.bar({ Size = UDim2.new(1, -74, 0, 16), Position = UDim2.fromOffset(60, 33) }, refs.boss, Color3.fromRGB(190, 90, 255))
	refs.setBoss = setB
end

local function worldOfPlayer()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	for _, w in ipairs(Config.Worlds) do
		if math.abs(hrp.Position.X - w.center.X) < w.size / 2 + 40 and math.abs(hrp.Position.Z - w.center.Z) < w.size / 2 + 40 then
			return w
		end
	end
end
HUD.WorldOfPlayer = worldOfPlayer

local function updateTarget()
	local name = player:GetAttribute("Target")
	local targets = workspace:FindFirstChild("Targets")
	local m = name and targets and targets:FindFirstChild(name)
	if m then
		refs.target.Visible = true
		local hp, max = m:GetAttribute("HP") or 0, m:GetAttribute("MaxHP") or 1
		refs.targetName.Text = m:GetAttribute("Label") or "Tresor"
		refs.setTarget(hp / max)
		refs.targetHP.Text = F.Format(hp) .. " / " .. F.Format(max)
		refs.targetFill.BackgroundColor3 = m:GetAttribute("Kind") == "boss" and Color3.fromRGB(190, 90, 255) or C.Green
	else
		refs.target.Visible = false
	end
	local w = worldOfPlayer()
	local st = w and State.boss[w.id]
	if st and st.alive and st.maxHp > 0 then
		refs.boss.Visible = true
		refs.bossName.Text = st.name
		refs.setBoss(st.hp / st.maxHp)
	else
		refs.boss.Visible = false
	end
end

-- Mise a jour ---------------------------------------------------------------------------------------------
function HUD.Refresh()
	local d = State.data
	if not d then
		return
	end
	refs.coins.Text = F.Format(d.Coins)
	refs.power.Text = F.Format(State.extra.power)
	refs.slots.Text = #d.Equipped .. " / " .. F.Slots(d)
	-- potions actives
	refs.boosts:ClearAllChildren()
	UI.list(refs.boosts, 8, true).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local now = State.Now()
	for kind, t in pairs(d.Boosts) do
		if t > now then
			local b = UI.panel({ Size = UDim2.fromOffset(150, 28) }, refs.boosts, true)
			b.BackgroundColor3 = C.Purple2
			UI.stroke(b, C.Gold, 2)
			UI.text({ Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Text = ({ Coins = "Pieces x2", Luck = "Chance x2", Power = "Force x2" })[kind] .. "  " .. F.Time(t - now) }, b)
		end
	end
	-- pastilles
	local dailyReady = os.time() - d.LastDaily >= Config.Daily.Cooldown
	refs.badges.Daily.frame.Visible = dailyReady
	local claimable = 0
	for _, q in ipairs(d.Quests.List or {}) do
		local def
		for _, x in ipairs(Config.DailyQuestPool) do
			if x.id == q.id then
				def = x
			end
		end
		if def and not q.claimed then
			local goal = def.worldScaled and math.floor(def.goal * F.BestWorld(d).mult) or def.goal
			if (d.Stats[def.stat] or 0) - (d.Quests.Base[def.stat] or 0) >= goal then
				claimable += 1
			end
		end
	end
	refs.badges.Quests.frame.Visible = claimable > 0
	refs.badges.Quests.text.Text = tostring(claimable)
	refs.badges.Trading.frame.Visible = next(State.requests) ~= nil or State.trade ~= nil
end

function HUD.Init()
	screen = UI.new("ScreenGui", { Name = "RelicRushHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = false }, player:WaitForChild("PlayerGui"))
	HUD.Screen = screen
	buildTop()
	refs.left = sideColumn(BUTTONS_LEFT, false)
	refs.right = sideColumn(BUTTONS_RIGHT, true)
	buildTarget()
	refs.toasts = UI.new("Frame", { Size = UDim2.fromOffset(420, 300), Position = UDim2.new(0.5, 0, 0, 110), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 40 }, screen)
	UI.list(refs.toasts, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
	fitColumns()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitColumns)
	Window.Init(screen)

	Remotes.Sync.OnClientEvent:Connect(function(data, extra)
		local before = State.data and State.data.Coins
		State.data = data
		State.extra = extra
		State.syncClock = os.clock()
		HUD.Refresh()
		if before and data.Coins > before then
			local s = refs.coinPill:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, refs.coinPill)
			s.Scale = 1.15
			UI.tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		State.Changed:Fire("data")
	end)
	Remotes.Notify.OnClientEvent:Connect(HUD.Toast)
	Remotes.Boss.OnClientEvent:Connect(function(status, t)
		State.boss = status
		State.bossTime = t
		State.Changed:Fire("boss")
	end)
	Remotes.Trade.OnClientEvent:Connect(function(kind, d)
		if kind == "request" then
			State.requests[d.fromId] = { name = d.from, at = os.clock() }
			HUD.Toast(d.from .. " veut echanger avec toi ! (menu Trading)", "gold")
		elseif kind == "session" then
			State.requests = {}
			State.trade = d
			if Window.Current ~= "Trading" then
				Window.Open("Trading")
			end
		elseif kind == "closed" then
			State.trade = nil
			HUD.Toast(d.reason, "info")
		end
		HUD.Refresh()
		State.Changed:Fire("trade")
	end)
	-- invites du monde -> interfaces
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local panel = prompt:GetAttribute("Panel")
		if not panel then
			return
		end
		if panel == "Crate" then
			Window.Open("Crate", { world = prompt:GetAttribute("World") })
		elseif panel == "Worlds" then
			local target = prompt:GetAttribute("Target")
			if not (State.data and State.data.Worlds[target]) then
				Window.Open("Worlds", { focus = target })
			end
		else
			Window.Open(panel, {})
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		updateTarget()
		acc += dt
		if acc > 1 then
			acc = 0
			HUD.Refresh()
		end
	end)
end

return HUD
