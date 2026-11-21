-- Interface de WINDMAIL : profil (rang, XP), pieces, colis en cours, jauge de vol, evenements,
-- notifications, ecran de livraison (tampon de note), boutique, album de timbres, classement,
-- recompense quotidienne et tutoriel des premieres minutes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Glider = require(script.Parent.Glider)

local HUD = {}

local player = Players.LocalPlayer
local C = UI.Colors
local fmt = Progress.Format
local screen
local refs = {}

-- Notifications ----------------------------------------------------------------------------------
local KIND_COLORS = { info = C.Sky, good = C.Good, gold = C.Gold, danger = C.Bad }

function HUD.Toast(text, kind)
	local t = UI.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.08 }, refs.toasts)
	UI.pad(t, 10)
	local bar = UI.new("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = KIND_COLORS[kind] or C.Sky, BorderSizePixel = 0 }, t)
	UI.corner(bar, 2)
	UI.text({ Size = UDim2.new(1, -14, 0, 0), Position = UDim2.fromOffset(14, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text, TextScaled = false, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium }, t)
	local scale = UI.new("UIScale", { Scale = 0.6 }, t)
	UI.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(4.5, function()
		UI.tween(scale, 0.2, { Scale = 0 })
		task.wait(0.22)
		t:Destroy()
	end)
end

-- Profil, pieces ---------------------------------------------------------------------------------
local function buildProfile()
	local card = UI.panel({ Size = UDim2.fromOffset(290, 84), Position = UDim2.fromOffset(16, 14) }, screen)
	local badge = UI.new("Frame", { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(11, 11), BackgroundColor3 = C.Post, BorderSizePixel = 0 }, card)
	UI.corner(badge, 31)
	UI.gradient(badge, Color3.fromRGB(255, 205, 110), Color3.fromRGB(230, 120, 40), 90)
	UI.stroke(badge, Color3.new(1, 1, 1), 2.5, 0.1)
	refs.rank = UI.text({ Size = UDim2.fromScale(0.8, 0.6), Position = UDim2.fromScale(0.1, 0.2), Text = "1", TextColor3 = Color3.new(1, 1, 1) }, badge)
	refs.title = UI.text({ Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(84, 12), Text = "Apprenti facteur", TextXAlignment = Enum.TextXAlignment.Left }, card)
	local bar
	bar, refs.setXP = UI.bar({ Size = UDim2.fromOffset(194, 12), Position = UDim2.fromOffset(84, 40) }, card, C.Sky)
	refs.xpText = UI.text({ Size = UDim2.fromOffset(194, 16), Position = UDim2.fromOffset(84, 56), Text = "", TextColor3 = C.Sub, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left }, card)

	local coins = UI.panel({ Size = UDim2.fromOffset(190, 50), Position = UDim2.new(1, -206, 0, 14) }, screen)
	UI.text({ Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(8, 7), Text = "🪙" }, coins)
	refs.coins = UI.text({ Size = UDim2.new(1, -60, 0, 30), Position = UDim2.fromOffset(50, 10), Text = "0", TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left }, coins)
	local deliv = UI.panel({ Size = UDim2.fromOffset(190, 36), Position = UDim2.new(1, -206, 0, 70) }, screen)
	refs.deliveries = UI.text({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 8), Text = "📦 0 livraisons", TextColor3 = C.Text, Font = Enum.Font.GothamMedium }, deliv)
end

-- Colis en cours ---------------------------------------------------------------------------------
local function buildParcels()
	local holder = UI.new("Frame", { Size = UDim2.fromOffset(270, 400), Position = UDim2.new(1, -286, 0, 118), BackgroundTransparency = 1 }, screen)
	UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	refs.parcels = holder
	refs.parcelCards = {}
end

local function renderParcels()
	for _, c in ipairs(refs.parcelCards) do
		c.frame:Destroy()
	end
	refs.parcelCards = {}
	for i, p in ipairs(State.parcels) do
		local def = Config.ParcelById[p.type]
		local card = UI.panel({ Size = UDim2.new(1, 0, 0, 76), LayoutOrder = i }, refs.parcels)
		if i == 1 then
			UI.stroke(card, Color3.new(1, 1, 1), 2, 0.2)
		end
		local strip = UI.new("Frame", { Size = UDim2.new(0, 8, 1, -14), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = def.color, BorderSizePixel = 0 }, card)
		UI.corner(strip, 4)
		UI.text({ Size = UDim2.new(1, -86, 0, 20), Position = UDim2.fromOffset(24, 8), Text = def.name, TextColor3 = def.color, TextXAlignment = Enum.TextXAlignment.Left }, card)
		local zone = Config.ZoneById[p.zone]
		UI.text({ Size = UDim2.new(1, -86, 0, 18), Position = UDim2.fromOffset(24, 30), Text = p.owner .. "  ·  " .. (zone and zone.name or ""), TextColor3 = C.Text, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left }, card)
		local timer = UI.text({ Size = UDim2.fromOffset(60, 22), Position = UDim2.new(1, -68, 0, 8), Text = "", TextXAlignment = Enum.TextXAlignment.Right }, card)
		local gradeL = UI.text({ Size = UDim2.fromOffset(60, 28), Position = UDim2.new(1, -68, 0, 32), Text = "S", TextXAlignment = Enum.TextXAlignment.Right }, card)
		local integ
		if def.fragile then
			local _, set = UI.bar({ Size = UDim2.new(1, -100, 0, 8), Position = UDim2.fromOffset(24, 56) }, card, C.Good)
			set(p.integrity, true)
			integ = set
		else
			UI.text({ Size = UDim2.new(1, -100, 0, 14), Position = UDim2.fromOffset(24, 53), Text = def.desc, TextColor3 = C.Sub, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, card)
		end
		table.insert(refs.parcelCards, { frame = card, parcel = p, timer = timer, grade = gradeL })
	end
end

local function updateParcelTimers()
	local now = workspace:GetServerTimeNow()
	for _, c in ipairs(refs.parcelCards) do
		local p = c.parcel
		if p.deadline then
			local left = math.max(0, p.deadline - now)
			c.timer.Text = string.format("⏱ %d s", math.ceil(left))
			c.timer.TextColor3 = left < 15 and C.Bad or C.Post
		else
			c.timer.Text = string.format("%d s", math.floor(now - p.start))
			c.timer.TextColor3 = C.Sub
		end
		local ratio = (now - p.start) / p.par
		for _, g in ipairs(Config.Delivery.Grades) do
			if ratio <= g.max then
				c.grade.Text = g.grade
				c.grade.TextColor3 = g.color
				break
			end
		end
	end
end

-- Jauge de vol -----------------------------------------------------------------------------------
local function buildFlight()
	local f = UI.panel({ Size = UDim2.fromOffset(300, 62), Position = UDim2.new(0.5, -150, 1, -150), Visible = false }, screen)
	refs.flight = f
	refs.speed = UI.text({ Size = UDim2.fromOffset(110, 40), Position = UDim2.fromOffset(12, 10), Text = "0", TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left }, f)
	UI.text({ Size = UDim2.fromOffset(60, 14), Position = UDim2.fromOffset(12, 44), Text = "studs/s", TextColor3 = C.Sub, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, f)
	UI.text({ Size = UDim2.fromOffset(160, 14), Position = UDim2.fromOffset(126, 12), Text = "ELAN (Shift)", TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left }, f)
	local _, set, fill = UI.bar({ Size = UDim2.fromOffset(160, 14), Position = UDim2.fromOffset(126, 32) }, f, C.Sky)
	refs.setStamina = set
	refs.updraft = UI.text({ Size = UDim2.fromOffset(300, 22), Position = UDim2.new(0, 0, 0, -28), Text = "↑ Colonne de vent", TextColor3 = Color3.fromRGB(170, 230, 255), TextStrokeTransparency = 0.4, Visible = false }, f)
	refs.hint = UI.text({ Size = UDim2.fromOffset(520, 26), Position = UDim2.new(0.5, -260, 1, -186), Text = "", TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.35, Visible = false }, screen)
end

local function updateFlight()
	local g = Glider.Gliding
	refs.flight.Visible = g
	if g then
		refs.speed.Text = tostring(math.floor(Glider.Speed))
		refs.setStamina(Glider.Stamina / math.max(Glider.MaxStamina, 0.1), true)
		refs.updraft.Visible = Glider.InUpdraft
	end
	local hint = ""
	if not g and Glider.Airborne then
		hint = "[Espace] ou [Q] : ouvrir le planeur"
	elseif g then
		hint = ""
	end
	refs.hint.Text = hint
	refs.hint.Visible = hint ~= ""
end

-- Evenements -------------------------------------------------------------------------------------
local function buildEvent()
	local e = UI.panel({ Size = UDim2.fromOffset(420, 64), Position = UDim2.new(0.5, -210, 0, 14), Visible = false }, screen)
	refs.event = e
	refs.eventStroke = e:FindFirstChildOfClass("UIStroke")
	refs.eventTitle = UI.text({ Size = UDim2.new(1, -110, 0, 24), Position = UDim2.fromOffset(14, 8), Text = "", TextXAlignment = Enum.TextXAlignment.Left }, e)
	refs.eventDesc = UI.text({ Size = UDim2.new(1, -110, 0, 18), Position = UDim2.fromOffset(14, 36), Text = "", TextColor3 = C.Sub, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left }, e)
	refs.eventTime = UI.text({ Size = UDim2.fromOffset(90, 30), Position = UDim2.new(1, -100, 0, 16), Text = "", TextXAlignment = Enum.TextXAlignment.Right }, e)
	local bar
	bar, refs.setEventProgress = UI.bar({ Size = UDim2.new(1, -28, 0, 6), Position = UDim2.new(0, 14, 1, -10), Visible = false }, e, C.Good)
	refs.eventBar = bar
end

local function onEvent(kind, d)
	if kind == "start" then
		State.event = d
		refs.event.Visible = true
		refs.eventTitle.Text = "✨ " .. d.name
		refs.eventTitle.TextColor3 = d.color
		refs.eventDesc.Text = d.desc
		refs.eventStroke.Color = d.color
		refs.eventBar.Visible = d.goal ~= nil
		if d.goal then
			refs.setEventProgress((d.count or 0) / d.goal)
			refs.eventDesc.Text = d.desc .. "  (" .. (d.count or 0) .. "/" .. d.goal .. ")"
		end
		HUD.Toast("Evenement : " .. d.name .. " ! " .. d.desc, "gold")
		local scale = refs.event:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, refs.event)
		scale.Scale = 0.5
		UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		if d.target then
			HUD.MarkBalloon(d.target)
		end
	elseif kind == "balloon" then
		HUD.MarkBalloon(d.target)
	elseif kind == "progress" and State.event then
		refs.setEventProgress(d.count / d.goal)
		refs.eventDesc.Text = State.event.desc .. "  (" .. d.count .. "/" .. d.goal .. ")"
	elseif kind == "end" then
		State.event = nil
		refs.event.Visible = false
	end
end

function HUD.MarkBalloon(model)
	if not model or not model.PrimaryPart then
		return
	end
	local bb = UI.new("BillboardGui", { Size = UDim2.fromOffset(160, 50), AlwaysOnTop = true, Adornee = model.PrimaryPart, StudsOffsetWorldSpace = Vector3.new(0, 14, 0), LightInfluence = 0 }, player.PlayerGui)
	UI.text({ Size = UDim2.fromScale(1, 1), Text = "🎈 Ballon egare !", TextColor3 = Color3.fromRGB(255, 160, 180), TextStrokeTransparency = 0.3 }, bb)
	model.Destroying:Connect(function()
		bb:Destroy()
	end)
end

-- Ecrans de recompense ----------------------------------------------------------------------------
function HUD.ShowDelivery(d)
	local f = UI.panel({ Size = UDim2.fromOffset(380, 250), Position = UDim2.new(0.5, -190, 0.5, -170), BackgroundTransparency = 0.05 }, screen)
	f.ZIndex = 20
	local stamp = UI.new("Frame", { Size = UDim2.fromOffset(110, 110), Position = UDim2.new(0.5, -55, 0, -55), BackgroundColor3 = d.gradeColor, BorderSizePixel = 0, ZIndex = 22, Rotation = -14 }, f)
	UI.corner(stamp, 55)
	UI.stroke(stamp, Color3.new(1, 1, 1), 4, 0)
	UI.text({ Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = d.grade, TextColor3 = Color3.new(1, 1, 1), ZIndex = 23 }, stamp)
	UI.text({ Size = UDim2.new(1, -30, 0, 28), Position = UDim2.fromOffset(15, 62), Text = "Livre a " .. d.owner .. " !", ZIndex = 21 }, f)
	local lines = {
		{ "🪙 Pieces", "+" .. fmt(d.coins), C.Gold },
		{ "⭐ Experience", "+" .. fmt(d.xp), C.Sky },
		{ "⏱ Temps", string.format("%.1f s (par %d s)", d.time, math.floor(d.par)), C.Text },
	}
	if d.integrity < 1 then
		table.insert(lines, { "📦 Etat du colis", math.floor(d.integrity * 100) .. " %", C.Bad })
	end
	if d.convoy > 0 then
		table.insert(lines, { "🤝 Convoi", "+30 % (" .. d.convoy .. " ami" .. (d.convoy > 1 and "s" or "") .. ")", C.Good })
	end
	if d.event then
		table.insert(lines, { "✨ Vent dore", "x2", C.Gold })
	end
	for i, l in ipairs(lines) do
		local y = 96 + (i - 1) * 26
		UI.text({ Size = UDim2.new(0.5, -15, 0, 22), Position = UDim2.fromOffset(20, y), Text = l[1], TextColor3 = C.Sub, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 }, f)
		UI.text({ Size = UDim2.new(0.5, -15, 0, 22), Position = UDim2.new(0.5, 0, 0, y), Text = l[2], TextColor3 = l[3], TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 21 }, f)
	end
	f.Size = UDim2.fromOffset(380, 110 + #lines * 26)
	local scale = UI.new("UIScale", { Scale = 0.4 }, f)
	UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	stamp.Size = UDim2.fromOffset(220, 220)
	stamp.Position = UDim2.new(0.5, -110, 0, -110)
	UI.tween(stamp, 0.3, { Size = UDim2.fromOffset(110, 110), Position = UDim2.new(0.5, -55, 0, -55) }, Enum.EasingStyle.Back)
	task.delay(3.4, function()
		UI.tween(scale, 0.25, { Scale = 0 })
		task.wait(0.3)
		f:Destroy()
	end)
end

function HUD.ShowBig(title, sub, color)
	local f = UI.panel({ Size = UDim2.fromOffset(420, 100), Position = UDim2.new(0.5, -210, 0.25, 0), BackgroundTransparency = 0.05 }, screen)
	f.ZIndex = 25
	UI.stroke(f, color, 3, 0)
	UI.text({ Size = UDim2.new(1, -30, 0, 44), Position = UDim2.fromOffset(15, 12), Text = title, TextColor3 = color, ZIndex = 26 }, f)
	UI.text({ Size = UDim2.new(1, -30, 0, 26), Position = UDim2.fromOffset(15, 60), Text = sub, TextColor3 = C.Text, Font = Enum.Font.GothamMedium, ZIndex = 26 }, f)
	local scale = UI.new("UIScale", { Scale = 0.3 }, f)
	UI.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3, function()
		UI.tween(scale, 0.25, { Scale = 0 })
		task.wait(0.3)
		f:Destroy()
	end)
end

-- Fenetres (boutique, album, classement) ------------------------------------------------------------
local modal, modalTitle, modalBody, current

local function buildModal()
	modal = UI.panel({ Size = UDim2.fromOffset(700, 470), Position = UDim2.new(0.5, -350, 0.5, -235), Visible = false, BackgroundTransparency = 0.04 }, screen)
	modal.ZIndex = 10
	modalTitle = UI.text({ Size = UDim2.new(1, -120, 0, 36), Position = UDim2.fromOffset(22, 14), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, modal)
	local close = UI.button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -54, 0, 12), Text = "✕", ZIndex = 12 }, modal, C.Bad)
	close.Activated:Connect(function()
		HUD.Close()
	end)
	modalBody = UI.new("Frame", { Size = UDim2.new(1, -36, 1, -76), Position = UDim2.fromOffset(18, 62), BackgroundTransparency = 1, ZIndex = 11 }, modal)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(700, 470) }, modal)
	local scale = UI.new("UIScale", {}, modal)
	refs.modalScale = scale
	local function fit()
		local vs = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vs.X - 30) / 700, (vs.Y - 30) / 470)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

function HUD.Close()
	modal.Visible = false
	current = nil
end

local function scrolling(parent, size, pos)
	local s = UI.new("ScrollingFrame", { Size = size, Position = pos or UDim2.new(), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 11 }, parent)
	return s
end

local function statBar(parent, y, label, ratio, color)
	UI.text({ Size = UDim2.fromOffset(80, 14), Position = UDim2.fromOffset(12, y), Text = label, TextColor3 = C.Sub, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, parent)
	local b, set = UI.bar({ Size = UDim2.new(1, -110, 0, 8), Position = UDim2.fromOffset(96, y + 3), ZIndex = 13 }, parent, color)
	b.ZIndex = 13
	set(ratio, true)
end

local shopTab = "Planeurs"

local function renderShop()
	modalBody:ClearAllChildren()
	local tabs = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, ZIndex = 11 }, modalBody)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	for _, name in ipairs({ "Planeurs", "Sacoches", "Trainees" }) do
		local b = UI.button({ Size = UDim2.fromOffset(140, 36), Text = name, ZIndex = 12 }, tabs, name == shopTab and C.Post or C.Panel2)
		b.Activated:Connect(function()
			shopTab = name
			renderShop()
		end)
	end
	local list = scrolling(modalBody, UDim2.new(1, 0, 1, -48), UDim2.fromOffset(0, 48))
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(204, 176), CellPadding = UDim2.fromOffset(10, 10) }, list)
	local data = State.data
	local function card(title, color, owned, equipped, buttonText, buttonColor, onClick, fill)
		local c = UI.panel({ BackgroundColor3 = C.Panel2, ZIndex = 12 }, list)
		local head = UI.new("Frame", { Size = UDim2.new(1, -16, 0, 6), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 13 }, c)
		UI.corner(head, 3)
		UI.text({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 20), Text = title, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, c)
		fill(c)
		local b = UI.button({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 1, -44), Text = buttonText, ZIndex = 13 }, c, buttonColor)
		if onClick then
			b.Activated:Connect(onClick)
		end
	end
	if shopTab == "Planeurs" then
		for _, g in ipairs(Config.Gliders) do
			local owned = data.gliders[g.id]
			local equipped = data.glider == g.id
			local locked = data.rank < g.rank
			local text = equipped and "EQUIPE" or owned and "EQUIPER" or locked and ("Rang " .. g.rank .. " requis") or ("🪙 " .. fmt(g.price))
			local color = equipped and C.Good or owned and C.Sky or locked and Color3.fromRGB(80, 85, 100) or (data.coins >= g.price and C.Post or Color3.fromRGB(120, 100, 80))
			card(g.name, g.color, owned, equipped, text, color, function()
				if owned then
					Remotes.Request:FireServer("equipGlider", g.id)
				elseif not locked then
					Remotes.Request:FireServer("buyGlider", g.id)
				end
			end, function(c)
				statBar(c, 50, "Vitesse", g.cruise / 60, C.Sky)
				statBar(c, 70, "Pointe", g.max / 120, C.Post)
				statBar(c, 90, "Portance", (10 - g.sink) / 6, C.Good)
				statBar(c, 110, "Elan", g.stamina / 8, C.Gold)
			end)
		end
	elseif shopTab == "Sacoches" then
		for _, s in ipairs(Config.Satchels) do
			local owned = data.satchel >= s.level
			local isNext = data.satchel + 1 == s.level
			local locked = (s.rank or 1) > data.rank
			local text = owned and "POSSEDEE" or (not isNext) and "Achete la precedente" or locked and ("Rang " .. s.rank .. " requis") or ("🪙 " .. fmt(s.price))
			local color = owned and C.Good or (isNext and not locked) and C.Post or Color3.fromRGB(80, 85, 100)
			card(s.name, Color3.fromRGB(170, 120, 75), owned, owned, text, color, function()
				if isNext and not locked then
					Remotes.Request:FireServer("buySatchel")
				end
			end, function(c)
				UI.text({ Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 52), Text = s.capacity .. " colis\na la fois", TextColor3 = C.Text, ZIndex = 13 }, c)
			end)
		end
	else
		local setTrails = Progress.SetBonuses(data.stamps).trails
		for _, t in ipairs(Config.Trails) do
			local owned = data.trails[t.id] or setTrails[t.id]
			local equipped = data.trail == t.id
			local text = equipped and "EQUIPEE" or owned and "EQUIPER" or t.stampSet and ("Collection " .. t.stampSet) or ("🪙 " .. fmt(t.price))
			local color = equipped and C.Good or owned and C.Sky or t.stampSet and Color3.fromRGB(80, 85, 100) or C.Post
			card(t.name, t.color or Color3.fromRGB(120, 120, 130), owned, equipped, text, color, function()
				if owned then
					Remotes.Request:FireServer("equipTrail", t.id)
				elseif t.price then
					Remotes.Request:FireServer("buyTrail", t.id)
				end
			end, function(c)
				local sw = UI.new("Frame", { Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 56), BackgroundColor3 = t.color or Color3.fromRGB(60, 60, 70), BorderSizePixel = 0, ZIndex = 13 }, c)
				UI.corner(sw, 10)
				if t.color2 then
					UI.gradient(sw, t.color, t.color2, 0)
				end
			end)
		end
	end
end

local RARITY_LABEL = { Commun = "Commun", Rare = "Rare", Epique = "Epique", Legendaire = "Legendaire", Secret = "Secret" }
local SOURCE_HINT = { mystery = "Colis mystere", secret = "Cache quelque part...", event = "Evenement" }

local function renderAlbum()
	modalBody:ClearAllChildren()
	local list = scrolling(modalBody, UDim2.fromScale(1, 1))
	UI.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local bonuses = Progress.SetBonuses(State.data.stamps)
	for i, set in ipairs(Config.StampSets) do
		local section = UI.new("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 11 }, list)
		local done = bonuses.done[set.id]
		UI.text({ Size = UDim2.new(1, 0, 0, 24), Text = (done and "✅ " or "") .. set.name .. "   —   " .. set.bonus, TextColor3 = done and C.Good or C.Text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, section)
		local grid = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), Position = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 11 }, section)
		UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 96), CellPadding = UDim2.fromOffset(8, 8) }, grid)
		for _, s in ipairs(Config.Stamps) do
			if s.set == set.id then
				local count = State.data.stamps[s.id]
				local rc = Config.StampRarity[s.rarity].color
				local tile = UI.panel({ BackgroundColor3 = count and Color3.fromRGB(245, 235, 215) or C.Panel2, ZIndex = 12 }, grid)
				UI.stroke(tile, rc, 3, count and 0 or 0.5)
				UI.text({ Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 10), Text = count and s.name or "???", TextColor3 = count and Color3.fromRGB(40, 35, 30) or C.Sub, ZIndex = 13 }, tile)
				UI.text({ Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 40), Text = RARITY_LABEL[s.rarity], TextColor3 = rc, ZIndex = 13 }, tile)
				UI.text({ Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(6, 64), Text = count and ("x" .. count) or SOURCE_HINT[s.source], TextColor3 = count and Color3.fromRGB(90, 80, 70) or C.Sub, Font = Enum.Font.GothamMedium, ZIndex = 13 }, tile)
			end
		end
	end
end

local function renderRanking()
	modalBody:ClearAllChildren()
	UI.text({ Size = UDim2.new(1, 0, 0, 22), Text = "Facteurs de ce serveur  ·  le classement mondial est affiche dans la Poste des Vents", TextColor3 = C.Sub, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, modalBody)
	local list = scrolling(modalBody, UDim2.new(1, 0, 1, -32), UDim2.fromOffset(0, 32))
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ls = p:FindFirstChild("leaderstats")
		table.insert(rows, { name = p.DisplayName, deliveries = ls and ls.Livraisons.Value or 0, rank = ls and ls.Rang.Value or 1, me = p == player })
	end
	table.sort(rows, function(a, b)
		return a.deliveries > b.deliveries
	end)
	for i, r in ipairs(rows) do
		local row = UI.panel({ Size = UDim2.new(1, -10, 0, 46), LayoutOrder = i, BackgroundColor3 = r.me and Color3.fromRGB(40, 60, 90) or C.Panel2, ZIndex = 12 }, list)
		local medal = ({ "🥇", "🥈", "🥉" })[i] or ("#" .. i)
		UI.text({ Size = UDim2.fromOffset(50, 28), Position = UDim2.fromOffset(10, 9), Text = medal, ZIndex = 13 }, row)
		UI.text({ Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(70, 11), Text = r.name, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }, row)
		UI.text({ Size = UDim2.new(0.4, -20, 0, 22), Position = UDim2.new(0.6, 0, 0, 12), Text = "Rang " .. r.rank .. "  ·  " .. fmt(r.deliveries) .. " livraisons", TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 13 }, row)
	end
end

local RENDER = { Boutique = renderShop, Album = renderAlbum, Classement = renderRanking }

function HUD.Open(name)
	if current == name then
		return HUD.Close()
	end
	current = name
	modalTitle.Text = ({ Boutique = "🛒 Boutique de la Poste", Album = "✉️ Album de timbres", Classement = "🏆 Classement" })[name]
	modal.Visible = true
	RENDER[name]()
	local s = refs.modalScale.Scale
	refs.modalScale.Scale = s * 0.85
	UI.tween(refs.modalScale, 0.2, { Scale = s }, Enum.EasingStyle.Back)
end

local function buildMenu()
	local col = UI.new("Frame", { Size = UDim2.fromOffset(74, 330), Position = UDim2.new(0, 16, 0.5, -150), BackgroundTransparency = 1 }, screen)
	UI.new("UIListLayout", { Padding = UDim.new(0, 10) }, col)
	local items = { { "Boutique", "🛒", C.Post }, { "Album", "✉️", Color3.fromRGB(170, 120, 255) }, { "Classement", "🏆", C.Gold }, { "Cadeau", "🎁", C.Good } }
	for _, it in ipairs(items) do
		local b = UI.button({ Size = UDim2.fromOffset(70, 70), Text = "", Radius = 18 }, col, it[3])
		UI.stroke(b, Color3.new(1, 1, 1), 2, 0.3)
		UI.text({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 6), Text = it[2] }, b)
		UI.text({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 1, -22), Text = it[1], TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5 }, b)
		if it[1] == "Cadeau" then
			refs.dailyDot = UI.new("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.new(1, -12, 0, -4), BackgroundColor3 = C.Bad, Visible = false }, b)
			UI.corner(refs.dailyDot, 8)
			refs.dailyTimer = b:FindFirstChildWhichIsA("TextLabel")
			b.Activated:Connect(function()
				Remotes.Request:FireServer("daily")
			end)
		else
			b.Activated:Connect(function()
				HUD.Open(it[1])
			end)
		end
	end
end

-- Tutoriel ---------------------------------------------------------------------------------------
local tutorialStep = 0
local tutorialCard, tutorialText

local function buildTutorial()
	tutorialCard = UI.panel({ Size = UDim2.fromOffset(330, 92), Position = UDim2.new(0, 100, 1, -120), Visible = false }, screen)
	UI.stroke(tutorialCard, C.Post, 2, 0)
	UI.text({ Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 8), Text = "📮 Premiere tournee", TextColor3 = C.Post, TextXAlignment = Enum.TextXAlignment.Left }, tutorialCard)
	tutorialText = UI.text({ Size = UDim2.new(1, -24, 0, 56), Position = UDim2.fromOffset(12, 30), Text = "", TextScaled = false, TextSize = 15, TextWrapped = true, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, tutorialCard)
end

local TUTORIAL = {
	"Va au guichet de la Poste des Vents (suis la fleche) et prends ton premier colis.",
	"Cours jusqu'au Tremplin ou au bord de la falaise, saute puis appuie sur ESPACE pour planer. Regarde vers le bas pour accelerer !",
	"Suis le ruban de vent jusqu'a la boite aux lettres. Atterris a cote et appuie sur E pour livrer.",
	"Bravo ! Plus tu livres vite, meilleure est ta note. Les colonnes de vent te font remonter. Ameliore ton planeur dans la Boutique !",
}

local function updateTutorial()
	if State.data.tutorial or not State.ready then
		tutorialCard.Visible = false
		return
	end
	local step = 1
	if #State.parcels > 0 then
		step = Glider.Gliding and 3 or 2
	end
	if State.data.deliveries > 0 then
		step = 4
	end
	if step ~= tutorialStep then
		tutorialStep = step
		tutorialCard.Visible = true
		tutorialText.Text = TUTORIAL[step]
		if step == 4 then
			task.delay(9, function()
				Remotes.Request:FireServer("tutorialDone")
			end)
		end
	end
end

-- Mise a jour ------------------------------------------------------------------------------------
local function refreshProfile()
	local d = State.data
	refs.rank.Text = tostring(d.rank)
	refs.title.Text = Progress.Title(d.rank)
	refs.setXP(d.xpIn / math.max(d.xpNeed, 1))
	refs.xpText.Text = fmt(d.xpIn) .. " / " .. fmt(d.xpNeed) .. " XP"
	refs.coins.Text = fmt(d.coins)
	refs.deliveries.Text = "📦 " .. fmt(d.deliveries) .. " livraisons"
	if current then
		RENDER[current]()
	end
end

function HUD.Init()
	screen = UI.new("ScreenGui", { Name = "WindmailHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	refs.screen = screen
	buildProfile()
	buildParcels()
	buildFlight()
	buildEvent()
	buildModal()
	buildMenu()
	buildTutorial()
	refs.toasts = UI.new("Frame", { Size = UDim2.fromOffset(360, 300), Position = UDim2.new(0.5, -180, 0, 90), BackgroundTransparency = 1 }, screen)
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }, refs.toasts)

	Remotes.Sync.OnClientEvent:Connect(function(d)
		local before = State.data.coins
		State.data = d
		State.ready = true
		refreshProfile()
		if before and d.coins > before then
			local s = refs.coins:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, refs.coins)
			s.Scale = 1.25
			UI.tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		State.Changed:Fire("data")
	end)
	Remotes.Parcels.OnClientEvent:Connect(function(list)
		State.parcels = list
		renderParcels()
		State.Changed:Fire("parcels")
	end)
	Remotes.Notify.OnClientEvent:Connect(HUD.Toast)
	Remotes.Event.OnClientEvent:Connect(onEvent)
	Remotes.FX.OnClientEvent:Connect(function(kind, d)
		d = d or {}
		if kind == "Delivered" then
			HUD.ShowDelivery(d)
			if d.stamp then
				task.delay(3.6, function()
					local s = Config.StampById[d.stamp]
					HUD.ShowBig("✉️ " .. s.name, "Timbre " .. s.rarity .. " ajoute a ton album", Config.StampRarity[s.rarity].color)
				end)
			end
		elseif kind == "RankUp" then
			task.delay(3.5, HUD.ShowBig, "RANG " .. d.rank, d.title, C.Gold)
		elseif kind == "Stamp" and d.first then
			local s = Config.StampById[d.id]
			HUD.Toast("Nouveau timbre : " .. s.name .. " (" .. s.rarity .. ")", "gold")
		elseif kind == "Pickup" then
			HUD.Toast(d.count .. " colis dans ta sacoche ! Suis les fleches.", "good")
		elseif kind == "Purchase" then
			HUD.Toast(d.name .. " obtenu !", "good")
		elseif kind == "Daily" then
			HUD.ShowBig("🎁 +" .. fmt(d.coins) .. " pieces", "Serie de " .. d.streak .. " jour(s) - reviens demain !", C.Good)
		elseif kind == "Splash" then
			HUD.Toast(d.damaged and "Plouf ! Repeche au quai... ton colis fragile a pris l'eau." or "Plouf ! Un bateau t'a ramene au quai.", "info")
		elseif kind == "Impact" then
			HUD.Toast("Aie ! Le colis fragile s'abime.", "danger")
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		updateFlight()
		acc += dt
		if acc > 0.2 then
			acc = 0
			updateParcelTimers()
			updateTutorial()
			if State.event and State.event.endsAt then
				local left = math.max(0, State.event.endsAt - workspace:GetServerTimeNow())
				refs.eventTime.Text = string.format("%d:%02d", left // 60, left % 60)
			end
			local ready = (State.data.dailyIn or 1) <= 0
			refs.dailyDot.Visible = ready
		end
	end)
	-- le compte a rebours du cadeau avance localement entre deux synchronisations
	task.spawn(function()
		while true do
			task.wait(1)
			if State.data.dailyIn and State.data.dailyIn > 0 then
				State.data.dailyIn -= 1
			end
		end
	end)
end

return HUD
