-- Interface : vie, ultimate, competences, combo, stats, selection de personnage, cosmetiques, notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)

local HUD = {}
local C = Config.Combat

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FONT = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ui = {}
local Input

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, p)
end
local function stroke(p, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0 }, p)
end
local function label(props, parent)
	local base = { BackgroundTransparency = 1, Font = FONT, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(0, 0, 0) }
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function button(props, parent)
	local base = { BackgroundColor3 = Config.Colors.Accent, Font = FONT, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, AutoButtonColor = true, Text = "" }
	for k, v in pairs(props) do
		base[k] = v
	end
	local b = new("TextButton", base, parent)
	corner(b, 10)
	return b
end
local function panel(name, size, title, color, parent)
	local frame = new("Frame", { Name = name, Size = size, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Config.Colors.Dark, BackgroundTransparency = 0.06, Visible = false }, parent)
	corner(frame, 18)
	stroke(frame, color, 3, 0.2)
	label({ Size = UDim2.new(1, -70, 0, 36), Position = UDim2.new(0, 16, 0, 10), Text = title, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color }, frame)
	local close = button({ Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -8, 0, 8), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Config.Colors.Danger, Text = "X" }, frame)
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	return frame
end
local function scrollList(parent, top, bottom)
	local scroll = new("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -(top + (bottom or 12))), Position = UDim2.new(0, 12, 0, top), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }, parent)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	return scroll
end

local function skillSlot(parent, index, key)
	local slot = new("TextButton", { Name = "Skill" .. index, Size = UDim2.fromOffset(92, 92), BackgroundColor3 = Config.Colors.Dark, BackgroundTransparency = 0.15, Text = "", AutoButtonColor = false, LayoutOrder = index }, parent)
	corner(slot, 14)
	local st = stroke(slot, Config.Colors.Accent, 3)
	local fill = new("Frame", { Name = "Cooldown", Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0 }, slot)
	corner(fill, 14)
	label({ Name = "Key", Size = UDim2.fromOffset(24, 20), Position = UDim2.new(0, 6, 0, 4), Text = key, Font = FONT_BOLD, TextColor3 = Color3.fromRGB(210, 210, 220) }, slot)
	label({ Name = "Title", Size = UDim2.new(1, -8, 0, 40), Position = UDim2.new(0, 4, 0, 26), Text = "", TextWrapped = true, Font = FONT_BOLD }, slot)
	label({ Name = "Timer", Size = UDim2.new(1, -8, 0, 20), Position = UDim2.new(0, 4, 1, -24), Text = "", Font = FONT_BOLD, TextColor3 = Config.Colors.Gold }, slot)
	return slot, st
end

local function build()
	local gui = new("ScreenGui", { Name = "OnyxHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	ui.gui = gui

	-- Stats (haut gauche)
	local stats = new("Frame", { Size = UDim2.fromOffset(260, 108), Position = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Config.Colors.Dark, BackgroundTransparency = 0.2 }, gui)
	corner(stats, 14)
	stroke(stats, Config.Colors.Gold, 2, 0.3)
	ui.levelText = label({ Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 6), Text = "Niveau 1", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Colors.Gold }, stats)
	local xpBg = new("Frame", { Size = UDim2.new(1, -16, 0, 10), Position = UDim2.new(0, 8, 0, 36), BackgroundColor3 = Color3.fromRGB(40, 40, 55), BorderSizePixel = 0 }, stats)
	corner(xpBg, 5)
	ui.xpFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Config.Colors.Gold, BorderSizePixel = 0 }, xpBg)
	corner(ui.xpFill, 5)
	ui.coinsText = label({ Size = UDim2.new(1, -16, 0, 24), Position = UDim2.new(0, 8, 0, 50), Text = "0 pieces", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left }, stats)
	ui.recordText = label({ Size = UDim2.new(1, -16, 0, 24), Position = UDim2.new(0, 8, 0, 76), Text = "", Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 220) }, stats)

	-- Boutons menus (haut droite)
	local right = new("Frame", { Size = UDim2.fromOffset(170, 110), Position = UDim2.new(1, -14, 0, 14), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
	ui.charButton = button({ Size = UDim2.fromOffset(170, 44), Text = TOUCH and "PERSONNAGE" or "PERSONNAGE (C)", LayoutOrder = 1 }, right)
	ui.cosmButton = button({ Size = UDim2.fromOffset(170, 44), Text = TOUCH and "COSMETIQUES" or "COSMETIQUES (K)", BackgroundColor3 = Config.Colors.Ult, LayoutOrder = 2 }, right)

	-- Vie + ultimate (bas centre)
	local bars = new("Frame", { Size = UDim2.fromOffset(460, 54), Position = UDim2.new(0.5, 0, 1, -136), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	local hpBg = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Color3.fromRGB(30, 30, 40), BorderSizePixel = 0 }, bars)
	corner(hpBg, 8)
	stroke(hpBg, Color3.new(0, 0, 0), 2, 0.4)
	ui.hpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Config.Colors.Health, BorderSizePixel = 0 }, hpBg)
	corner(ui.hpFill, 8)
	ui.hpText = label({ Size = UDim2.fromScale(1, 1), Text = "100 / 100", Font = FONT_BOLD }, hpBg)
	ui.hpText.ZIndex = 2
	local ultBg = new("Frame", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(30, 30, 40), BorderSizePixel = 0 }, bars)
	corner(ultBg, 8)
	stroke(ultBg, Color3.new(0, 0, 0), 2, 0.4)
	ui.ultFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Config.Colors.Ult, BorderSizePixel = 0 }, ultBg)
	corner(ui.ultFill, 8)
	ui.ultText = label({ Size = UDim2.fromScale(1, 1), Text = "ULTIMATE 0 %", Font = FONT_BOLD }, ultBg)
	ui.ultText.ZIndex = 2

	-- Competences (bas)
	local skills = new("Frame", { Name = "Skills", Size = UDim2.fromOffset(640, 100), Position = UDim2.new(0.5, 0, 1, -22), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, skills)
	ui.slots = {}
	ui.slotStrokes = {}
	for i = 1, 4 do
		local slot, st = skillSlot(skills, i, tostring(i))
		ui.slots[i] = slot
		ui.slotStrokes[i] = st
		slot.Activated:Connect(function()
			Input.skill(i)
		end)
	end
	ui.ultButton = button({ Size = UDim2.fromOffset(92, 92), Text = TOUCH and "ULT" or "ULT\n(G)", BackgroundColor3 = Config.Colors.Ult, LayoutOrder = 5 }, skills)
	stroke(ui.ultButton, Color3.new(1, 1, 1), 2, 0.5)
	ui.ultButton.Activated:Connect(function()
		Input.ultimate()
	end)

	-- Boutons tactiles M1 / bloquer / dash
	if TOUCH then
		local touch = new("Frame", { Size = UDim2.fromOffset(220, 160), Position = UDim2.new(1, -20, 1, -140), AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1 }, gui)
		local m1 = button({ Size = UDim2.fromOffset(110, 110), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1), Text = "M1", BackgroundColor3 = Config.Colors.Accent2 }, touch)
		m1.Activated:Connect(function()
			Input.m1()
		end)
		local dash = button({ Size = UDim2.fromOffset(80, 80), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), Text = "DASH" }, touch)
		dash.Activated:Connect(function()
			Input.dash()
		end)
		local block = button({ Size = UDim2.fromOffset(80, 60), Position = UDim2.new(0, 0, 0, 0), Text = "BLOC", BackgroundColor3 = Config.Colors.Gold }, touch)
		block.MouseButton1Down:Connect(function()
			Input.setBlock(true)
		end)
		block.MouseButton1Up:Connect(function()
			Input.setBlock(false)
		end)
		block.MouseLeave:Connect(function()
			Input.setBlock(false)
		end)
	end

	-- Combo + etat
	ui.combo = label({ Size = UDim2.fromOffset(300, 50), Position = UDim2.new(0.5, 0, 0.62, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", TextColor3 = Config.Colors.Accent2, Visible = false }, gui)
	ui.status = label({ Size = UDim2.fromOffset(400, 34), Position = UDim2.new(0.5, 0, 0.7, 0), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", Font = FONT_BOLD, TextColor3 = Config.Colors.Gold }, gui)
	ui.dashHint = label({ Size = UDim2.fromOffset(200, 22), Position = UDim2.new(0.5, 0, 1, -200), AnchorPoint = Vector2.new(0.5, 1), Text = "", Font = FONT_BOLD, TextColor3 = Color3.fromRGB(200, 200, 210) }, gui)

	-- Notifications
	ui.toasts = new("Frame", { Size = UDim2.fromOffset(560, 220), Position = UDim2.new(0.5, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, ui.toasts)

	-- Panneau personnages
	ui.characters = panel("Characters", UDim2.fromOffset(640, 420), "CHOISIS TON PERSONNAGE", Config.Colors.Accent, gui)
	ui.charGrid = new("Frame", { Size = UDim2.new(1, -24, 1, -70), Position = UDim2.new(0, 12, 0, 58), BackgroundTransparency = 1 }, ui.characters)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(296, 165), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, ui.charGrid)

	-- Panneau cosmetiques
	ui.cosmetics = panel("Cosmetics", UDim2.fromOffset(560, 520), "COSMETIQUES", Config.Colors.Ult, gui)
	ui.cosmList = scrollList(ui.cosmetics, 58)
end

-- Notifications ----------------------------------------------------------------

local toastCount = 0
function HUD.toast(text, kind)
	toastCount += 1
	local colors = { danger = Config.Colors.Danger, gold = Config.Colors.Gold, good = Config.Colors.Accent, kill = Config.Colors.Accent2, ult = Config.Colors.Ult }
	local color = colors[kind] or Color3.new(1, 1, 1)
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Config.Colors.Dark, BackgroundTransparency = 0.3, LayoutOrder = toastCount }, ui.toasts)
	corner(frame, 8)
	stroke(frame, color, 2, 0.4)
	local l = label({ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.new(0, 8, 0, 4), Text = text, TextColor3 = color, Font = FONT_BOLD }, frame)
	task.delay(3.5, function()
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
end

-- Personnages -----------------------------------------------------------------------

local function rebuildCharacters()
	for _, child in ipairs(ui.charGrid:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, def in ipairs(Config.Characters) do
		local selected = State.stats.character == def.id
		local card = new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 34, 46), LayoutOrder = i }, ui.charGrid)
		corner(card, 12)
		stroke(card, selected and Config.Colors.Gold or def.color, selected and 4 or 2)
		label({ Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 0, 6), Text = def.name .. (selected and "  (actuel)" or ""), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = def.color }, card)
		label({ Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 0, 38), Text = def.description, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 220) }, card)
		label({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0, 60), Text = string.format("Vie %d  |  Vitesse %d  |  M1 %d dmg", def.health, def.walkSpeed, def.m1Damage), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(180, 180, 190) }, card)
		local names = {}
		for _, s in ipairs(def.skills) do
			table.insert(names, s.name)
		end
		label({ Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 0, 80), Text = table.concat(names, "  •  "), TextWrapped = true, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 220, 230) }, card)
		local b = button({ Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 1, -42), Text = selected and "SELECTIONNE" or "CHOISIR", BackgroundColor3 = selected and Color3.fromRGB(60, 60, 70) or def.color }, card)
		b.Activated:Connect(function()
			Remotes.Menu:FireServer("character", def.id)
			ui.characters.Visible = false
		end)
	end
end

-- Cosmetiques -----------------------------------------------------------------------

local function rebuildCosmetics()
	for _, child in ipairs(ui.cosmList:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local order = 0
	local function section(title, kind, list, equipped, bag, color)
		order += 1
		label({ Size = UDim2.new(1, 0, 0, 28), Text = title, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, LayoutOrder = order }, ui.cosmList)
		for _, item in ipairs(list) do
			order += 1
			local owned = bag[item.id] == true
			local isEquipped = equipped == item.id
			local row = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(30, 34, 46), LayoutOrder = order }, ui.cosmList)
			corner(row, 8)
			if item.color then
				local dot = new("Frame", { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = item.color }, row)
				corner(dot, 11)
			end
			label({ Size = UDim2.new(0.5, 0, 1, -12), Position = UDim2.new(0, 42, 0, 6), Text = item.name, Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left }, row)
			local info
			if kind == "title" then
				local req = item.requirement
				info = (req.kind == "level" and ("Niveau " .. req.value)) or (req.kind == "kills" and (req.value .. " kills")) or (req.value .. " victoires")
			else
				info = owned and "Possede" or (item.price .. " pieces")
			end
			label({ Size = UDim2.new(0.25, 0, 1, -12), Position = UDim2.new(0.5, 0, 0, 6), Text = info, Font = FONT_BOLD, TextColor3 = Color3.fromRGB(190, 190, 200) }, row)
			local b = button({ Size = UDim2.fromOffset(100, 32), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Text = isEquipped and "EQUIPE" or (owned and "EQUIPER" or (kind == "title" and "VERROUILLE" or "ACHETER")), BackgroundColor3 = isEquipped and Color3.fromRGB(60, 60, 70) or (owned and Config.Colors.Accent or (kind == "title" and Color3.fromRGB(80, 80, 90) or Config.Colors.Gold)) }, row)
			b.Activated:Connect(function()
				if isEquipped then
					return
				end
				if owned then
					Remotes.Menu:FireServer("equip", kind, item.id)
				elseif kind ~= "title" then
					Remotes.Menu:FireServer("buy", kind, item.id)
				end
			end)
		end
	end
	local s = State.stats
	section("AURAS", "aura", Config.Auras, s.aura, s.unlocked.auras or {}, Config.Colors.Accent)
	section("EFFETS DE DASH", "trail", Config.Trails, s.trail, s.unlocked.trails or {}, Config.Colors.Accent2)
	section("TITRES", "title", Config.Titles, s.title, s.unlocked.titles or {}, Config.Colors.Gold)
end

-- Mises a jour -----------------------------------------------------------------------

local function onStats(stats)
	State.stats = stats
	ui.levelText.Text = "Niveau " .. stats.level .. "  -  " .. stats.character
	ui.xpFill.Size = UDim2.fromScale(math.clamp(stats.xp / math.max(1, stats.xpNext), 0, 1), 1)
	ui.coinsText.Text = stats.coins .. " pieces"
	ui.recordText.Text = string.format("%d kills  |  %d victoires  |  %d morts", stats.kills, stats.wins, stats.deaths)
	if ui.characters.Visible then
		rebuildCharacters()
	end
	if ui.cosmetics.Visible then
		rebuildCosmetics()
	end
	State.fire("stats", stats)
end

local function refreshSkillNames()
	local character = player.Character
	local id = (character and character:GetAttribute("CharacterId")) or State.stats.character
	local def = Config.CharacterById[id] or Config.Characters[1]
	local ult = character and character:GetAttribute("UltActive") == true
	local list = ult and def.ultSkills or def.skills
	for i = 1, 4 do
		local skill = list[i]
		ui.slots[i].Title.Text = skill and skill.name or ""
		ui.slotStrokes[i].Color = ult and Config.Colors.Ult or def.color
	end
end

local function toggle(name)
	if name == "close" then
		ui.characters.Visible = false
		ui.cosmetics.Visible = false
	elseif name == "characters" then
		ui.characters.Visible = not ui.characters.Visible
		ui.cosmetics.Visible = false
		if ui.characters.Visible then
			rebuildCharacters()
		end
	elseif name == "cosmetics" then
		ui.cosmetics.Visible = not ui.cosmetics.Visible
		ui.characters.Visible = false
		if ui.cosmetics.Visible then
			rebuildCosmetics()
			Remotes.Menu:FireServer("stats")
		end
	end
end

local function update()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		ui.hpFill.Size = UDim2.fromScale(ratio, 1)
		ui.hpFill.BackgroundColor3 = Config.Colors.Health:Lerp(Config.Colors.Danger, 1 - ratio)
		ui.hpText.Text = math.floor(humanoid.Health) .. " / " .. math.floor(humanoid.MaxHealth)
		local ult = character:GetAttribute("Ult") or 0
		local active = character:GetAttribute("UltActive") == true
		ui.ultFill.Size = UDim2.fromScale(ult / 100, 1)
		if active then
			ui.ultText.Text = "ULTIMATE MODE"
			ui.ultFill.BackgroundColor3 = Config.Colors.Gold
		elseif ult >= 100 then
			ui.ultText.Text = TOUCH and "ULTIMATE PRET !" or "ULTIMATE PRET !  (G)"
			ui.ultFill.BackgroundColor3 = Config.Colors.Ult:Lerp(Color3.new(1, 1, 1), 0.5 + 0.5 * math.sin(os.clock() * 8))
		else
			ui.ultText.Text = "ULTIMATE " .. math.floor(ult) .. " %"
			ui.ultFill.BackgroundColor3 = Config.Colors.Ult
		end
		ui.ultButton.BackgroundColor3 = (ult >= 100 and not active) and Config.Colors.Gold or Config.Colors.Ult

		local stunned = (character:GetAttribute("StunUntil") or 0) > os.clock()
		if stunned then
			ui.status.Text = "ETOURDI"
			ui.status.TextColor3 = Config.Colors.Danger
		elseif State.blocking then
			ui.status.Text = "BLOCAGE"
			ui.status.TextColor3 = Config.Colors.Gold
		else
			ui.status.Text = ""
		end
	end
	for i = 1, 4 do
		local cd = State.cooldowns[i]
		local slot = ui.slots[i]
		if cd and cd.untilTime > os.clock() then
			local left = cd.untilTime - os.clock()
			slot.Cooldown.Size = UDim2.fromScale(1, math.clamp(left / cd.duration, 0, 1))
			slot.Timer.Text = string.format("%.1f", left)
		else
			slot.Cooldown.Size = UDim2.fromScale(1, 0)
			slot.Timer.Text = ""
		end
	end
	local dashLeft = State.dashReadyAt - os.clock()
	ui.dashHint.Text = dashLeft > 0 and string.format("Dash %.1fs", dashLeft) or (TOUCH and "Dash pret" or "Dash pret (Q)")
	if os.clock() - State.comboAt > C.ComboReset then
		ui.combo.Visible = false
	end
end

function HUD.showCombo(count)
	State.combo = count
	State.comboAt = os.clock()
	ui.combo.Text = count .. " HIT" .. (count > 1 and "S" or "")
	ui.combo.Visible = true
	ui.combo.Size = UDim2.fromOffset(200, 30)
	TweenService:Create(ui.combo, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(300, 50) }):Play()
end

function HUD.Init(inputModule)
	Input = inputModule
	build()
	Remotes.Stats.OnClientEvent:Connect(onStats)
	Remotes.Notify.OnClientEvent:Connect(HUD.toast)
	ui.charButton.Activated:Connect(function()
		toggle("characters")
	end)
	ui.cosmButton.Activated:Connect(function()
		toggle("cosmetics")
	end)
	State.Changed.Event:Connect(function(what, data)
		if what == "toggle" then
			toggle(data)
		elseif what == "notify" then
			HUD.toast(data.text, data.kind)
		elseif what == "respawn" then
			task.delay(0.5, refreshSkillNames)
		end
	end)
	local function hookCharacter(character)
		task.wait(0.3)
		refreshSkillNames()
		character:GetAttributeChangedSignal("UltActive"):Connect(refreshSkillNames)
		character:GetAttributeChangedSignal("CharacterId"):Connect(refreshSkillNames)
	end
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
	RunService.RenderStepped:Connect(update)
end

return HUD
