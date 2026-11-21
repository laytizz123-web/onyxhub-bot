-- Fenetres (2/2) : Quests, Trading, Boss, Daily, Leaderboard, Settings.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Window = require(script.Parent.Window)
local RelicView = require(script.Parent.RelicView)
local PanelsA = require(script.Parent.PanelsA)

local PanelsB = {}
local C = UI.C
local Z = 22
local player = Players.LocalPlayer
local GREY = Color3.fromRGB(110, 100, 130)

local function act(...)
	Remotes.Action:FireServer(...)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or Z
	return UI.text(props, parent)
end

local function section(parent, text, order)
	return label(parent, { Size = UDim2.new(1, -14, 0, 32), Text = text, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, StrokeThickness = 3 })
end

-- QUESTS ------------------------------------------------------------------------------------------------
local function milestoneValue(d, stat)
	if stat == "Equipped" then
		return #d.Equipped
	elseif stat == "Worlds" then
		local n = 0
		for _ in pairs(d.Worlds) do
			n += 1
		end
		return n
	elseif stat == "Discovered" then
		return State.extra.discovered or 0
	elseif stat == "Rebirths" then
		return d.Rebirths
	end
	return d.Stats[stat] or 0
end

Window.Register("Quests", {
	title = "QUETES",
	icon = "quests",
	refreshOn = { data = true },
	build = function(root)
		local d = State.data
		local list = UI.scroll({ Name = "QuestList", Size = UDim2.fromScale(1, 1), ZIndex = Z }, root)
		UI.list(list, 8)
		local nextDay = (math.floor(State.Now() / 86400) + 1) * 86400
		section(list, "Quetes du jour  (nouvelles dans " .. F.Time(nextDay - State.Now()) .. ")", 0)
		local mult = F.BestWorld(d).mult
		for i, q in ipairs(d.Quests.List or {}) do
			local def
			for _, x in ipairs(Config.DailyQuestPool) do
				if x.id == q.id then
					def = x
				end
			end
			if def then
				local goal = def.worldScaled and math.floor(def.goal * mult) or def.goal
				local progress = math.min(goal, (d.Stats[def.stat] or 0) - (d.Quests.Base[def.stat] or 0))
				local row = UI.card({ Size = UDim2.new(1, -14, 0, 76), LayoutOrder = i, ZIndex = Z }, list, C.Navy2)
				label(row, { Size = UDim2.new(0.6, 0, 0, 28), Position = UDim2.fromOffset(16, 8), Text = string.format(def.text, def.worldScaled and F.Format(goal) or goal), TextXAlignment = Enum.TextXAlignment.Left })
				local _, set = UI.bar({ Size = UDim2.new(0.55, 0, 0, 18), Position = UDim2.fromOffset(16, 46), ZIndex = Z + 1 }, row, C.Green)
				set(progress / goal, true)
				label(row, { Size = UDim2.new(0.55, 0, 0, 16), Position = UDim2.fromOffset(16, 47), Text = F.Format(progress) .. " / " .. F.Format(goal), ZIndex = Z + 3 })
				local reward = math.floor(Config.QuestRewardBase * def.reward * mult)
				local done = progress >= goal
				local b = UI.button({ Size = UDim2.fromOffset(200, 50), Position = UDim2.new(1, -214, 0.5, -25), Text = q.claimed and "RECUPEREE" or F.Format(reward), ZIndex = Z + 1 }, row, q.claimed and GREY or (done and C.Green or C.Navy2))
				if not q.claimed then
					Icons.Image("coin", b, { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(0, 5), ZIndex = Z + 3 })
					b.Activated:Connect(function()
						act("claimQuest", i)
					end)
				end
			end
		end
		section(list, "Succes permanents", 10)
		for i, m in ipairs(Config.Milestones) do
			local claimed = d.Milestones[m.id]
			local value = milestoneValue(d, m.stat)
			local done = value >= m.goal
			local row = UI.card({ Size = UDim2.new(1, -14, 0, 62), LayoutOrder = 10 + i, ZIndex = Z }, list, claimed and C.Purple2 or C.Navy2)
			label(row, { Size = UDim2.new(0.6, 0, 0, 26), Position = UDim2.fromOffset(16, 6), Text = m.text, TextXAlignment = Enum.TextXAlignment.Left })
			label(row, { Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(16, 34), Text = F.Format(math.min(value, m.goal)) .. " / " .. F.Format(m.goal), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
			local b = UI.button({ Size = UDim2.fromOffset(200, 44), Position = UDim2.new(1, -214, 0.5, -22), Text = claimed and "TERMINE" or F.Format(m.coins), ZIndex = Z + 1 }, row, claimed and GREY or (done and C.Green or C.Navy2))
			if not claimed then
				Icons.Image("coin", b, { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(0, 3), ZIndex = Z + 3 })
				b.Activated:Connect(function()
					act("claimMilestone", m.id)
				end)
			end
		end
	end,
})

-- TRADING ---------------------------------------------------------------------------------------------------
local function offerGrid(parent, items, pos, size, removable)
	local g = UI.new("Frame", { Size = size, Position = pos, BackgroundColor3 = C.Dark, BackgroundTransparency = 0.4, ZIndex = Z }, parent)
	UI.corner(g, 12)
	UI.pad(g, 6)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(72, 84), CellPadding = UDim2.fromOffset(6, 6) }, g)
	for i, it in ipairs(items) do
		local tile = PanelsA.RelicTile(g, it.id, { order = i })
		if removable then
			tile.Activated:Connect(function()
				act("tradeRemove", it.uid)
			end)
		end
	end
	return g
end

Window.Register("Trading", {
	title = "ECHANGES",
	icon = "trading",
	refreshOn = { data = true, trade = true },
	build = function(root)
		local d = State.data
		local t = State.trade
		if t then
			label(root, { Size = UDim2.new(0.5, -10, 0, 28), Text = "Ton offre", TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left })
			label(root, { Size = UDim2.new(0.5, -10, 0, 28), Position = UDim2.new(0.5, 10, 0, 0), Text = "Offre de " .. t.partner, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left })
			offerGrid(root, t.mine, UDim2.fromOffset(0, 32), UDim2.new(0.5, -10, 0, 186), true)
			offerGrid(root, t.theirs, UDim2.new(0.5, 10, 0, 32), UDim2.new(0.5, -10, 0, 186), false)
			label(root, { Size = UDim2.new(0.5, -10, 0, 22), Position = UDim2.fromOffset(0, 222), Text = t.myReady and "Tu as valide" or "Pas encore valide", TextColor3 = t.myReady and C.Green or C.Sub })
			label(root, { Size = UDim2.new(0.5, -10, 0, 22), Position = UDim2.new(0.5, 10, 0, 222), Text = t.theirReady and (t.partner .. " a valide") or "En attente...", TextColor3 = t.theirReady and C.Green or C.Sub })
			-- inventaire pour ajouter
			local inv = UI.scroll({ Name = "TradeInv", Size = UDim2.new(1, -240, 1, -258), Position = UDim2.fromOffset(0, 254), ZIndex = Z }, root)
			UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(72, 84), CellPadding = UDim2.fromOffset(6, 6) }, inv)
			local offered = {}
			for _, it in ipairs(t.mine) do
				offered[it.uid] = true
			end
			local list = {}
			for k, item in pairs(d.Relics) do
				local def = Config.RelicById[item.id]
				if def and not offered[tonumber(k)] and not item.locked then
					table.insert(list, { uid = tonumber(k), def = def })
				end
			end
			table.sort(list, function(a, b)
				return a.def.power > b.def.power
			end)
			for i, e in ipairs(list) do
				local tile = PanelsA.RelicTile(inv, e.def.id, { order = i })
				tile.Activated:Connect(function()
					act("tradeAdd", e.uid)
				end)
			end
			local status = t.countdown and ("Echange dans " .. math.max(0, t.countdown - os.time()) .. " s...") or "Clique sur tes reliques pour les proposer"
			label(root, { Size = UDim2.fromOffset(220, 60), Position = UDim2.new(1, -220, 0, 254), Text = status, TextWrapped = true, TextColor3 = t.countdown and C.Gold or C.Sub })
			local ready = UI.button({ Size = UDim2.fromOffset(220, 56), Position = UDim2.new(1, -220, 1, -132), Text = t.myReady and "ANNULER VALIDATION" or "VALIDER", ZIndex = Z }, root, t.myReady and C.Gold or C.Green)
			ready.Activated:Connect(function()
				act("tradeReady", not t.myReady)
			end)
			local cancel = UI.button({ Size = UDim2.fromOffset(220, 50), Position = UDim2.new(1, -220, 1, -62), Text = "QUITTER", ZIndex = Z }, root, C.Red)
			cancel.Activated:Connect(function()
				act("tradeCancel")
			end)
			return
		end
		local list = UI.scroll({ Name = "TradePlayers", Size = UDim2.fromScale(1, 1), ZIndex = Z }, root)
		UI.list(list, 8)
		local order = 0
		if next(State.requests) then
			section(list, "Demandes recues", 0)
			for fromId, r in pairs(State.requests) do
				order += 1
				local row = UI.card({ Size = UDim2.new(1, -14, 0, 64), LayoutOrder = order, ZIndex = Z }, list, C.Purple2)
				label(row, { Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(16, 17), Text = r.name, TextXAlignment = Enum.TextXAlignment.Left })
				local a = UI.button({ Size = UDim2.fromOffset(150, 46), Position = UDim2.new(1, -330, 0.5, -23), Text = "ACCEPTER", ZIndex = Z + 1 }, row, C.Green)
				a.Activated:Connect(function()
					act("tradeAccept", fromId)
					State.requests[fromId] = nil
				end)
				local dcl = UI.button({ Size = UDim2.fromOffset(150, 46), Position = UDim2.new(1, -164, 0.5, -23), Text = "REFUSER", ZIndex = Z + 1 }, row, C.Red)
				dcl.Activated:Connect(function()
					act("tradeDecline", fromId)
					State.requests[fromId] = nil
					Window.Render()
				end)
			end
		end
		section(list, "Joueurs du serveur", 100)
		local any = false
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				any = true
				order += 1
				local row = UI.card({ Size = UDim2.new(1, -14, 0, 64), LayoutOrder = 100 + order, ZIndex = Z }, list, C.Navy2)
				label(row, { Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(16, 6), Text = p.DisplayName, TextXAlignment = Enum.TextXAlignment.Left })
				label(row, { Size = UDim2.new(0.5, 0, 0, 20), Position = UDim2.fromOffset(16, 38), Text = "Puissance " .. F.Format(p:GetAttribute("Power") or 0), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
				local b = UI.button({ Size = UDim2.fromOffset(180, 46), Position = UDim2.new(1, -194, 0.5, -23), Text = "ECHANGER", ZIndex = Z + 1 }, row, C.Blue)
				b.Activated:Connect(function()
					act("tradeRequest", p.UserId)
				end)
			end
		end
		if not any then
			label(list, { Size = UDim2.new(1, -14, 0, 60), LayoutOrder = 200, Text = "Aucun autre joueur sur ce serveur pour l'instant.", TextColor3 = C.Sub })
		end
	end,
})

-- BOSS ------------------------------------------------------------------------------------------------------
Window.Register("Boss", {
	title = "BOSS",
	icon = "boss",
	refreshOn = { boss = true },
	build = function(root)
		local d = State.data
		label(root, { Size = UDim2.new(1, 0, 0, 26), Text = "Clique sur un boss pour que tes reliques l'attaquent. Recompenses partagees selon les degats !", TextColor3 = C.Sub })
		local list = UI.scroll({ Name = "BossList", Size = UDim2.new(1, 0, 1, -34), Position = UDim2.fromOffset(0, 34), ZIndex = Z }, root)
		UI.list(list, 8)
		for i, w in ipairs(Config.Worlds) do
			local st = State.boss[w.id] or {}
			local bossRelic
			for _, r in ipairs(Config.Relics) do
				if r.boss and r.world == w.id then
					bossRelic = r
				end
			end
			local row = UI.card({ Size = UDim2.new(1, -14, 0, 96), LayoutOrder = i, ZIndex = Z }, list, w.color:Lerp(C.Navy, 0.55))
			RelicView.Viewport(bossRelic.id, row, { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(6, 6), ZIndex = Z + 1 }, not d.Index[bossRelic.id], true)
			label(row, { Size = UDim2.new(0.45, 0, 0, 30), Position = UDim2.fromOffset(100, 8), Text = Config.Boss[w.id].name, TextXAlignment = Enum.TextXAlignment.Left })
			label(row, { Size = UDim2.new(0.45, 0, 0, 20), Position = UDim2.fromOffset(100, 40), Text = w.name .. "  -  relique : " .. bossRelic.name .. " (" .. math.floor(Config.BossRelicChance * 100) .. " %)", TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
			if st.alive and (st.maxHp or 0) > 0 then
				local _, set = UI.bar({ Size = UDim2.new(0.45, 0, 0, 16), Position = UDim2.fromOffset(100, 68), ZIndex = Z + 1 }, row, Color3.fromRGB(190, 90, 255))
				set(st.hp / st.maxHp, true)
			else
				local left = st.respawnAt and math.max(0, st.respawnAt - State.bossTime) or 0
				label(row, { Size = UDim2.new(0.45, 0, 0, 20), Position = UDim2.fromOffset(100, 66), Text = "Reapparait dans " .. F.Time(left), TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left })
			end
			local unlocked = d.Worlds[w.id]
			local b = UI.button({ Size = UDim2.fromOffset(180, 52), Position = UDim2.new(1, -194, 0.5, -26), Text = unlocked and "Y ALLER" or "VERROUILLE", ZIndex = Z + 1 }, row, unlocked and C.Purple or GREY)
			if unlocked then
				b.Activated:Connect(function()
					act("teleport", w.id)
					Window.Close()
				end)
			end
		end
	end,
})

-- DAILY REWARDS ------------------------------------------------------------------------------------------------
Window.Register("Daily", {
	title = "RECOMPENSES QUOTIDIENNES",
	icon = "daily",
	refreshOn = { data = true },
	build = function(root)
		local d = State.data
		local since = os.time() - d.LastDaily
		local ready = since >= Config.Daily.Cooldown
		local nextDay = (since < Config.Daily.Reset) and (d.DailyStreak % #Config.Daily.Days) + 1 or 1
		local grid = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 330), BackgroundTransparency = 1, ZIndex = Z }, root)
		local layout = UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 158), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local mult = F.BestWorld(d).mult
		for i, day in ipairs(Config.Daily.Days) do
			local claimedToday = not ready and i == d.DailyStreak
			local isNext = ready and i == nextDay
			local passed = (i < nextDay and ready) or (not ready and i <= d.DailyStreak)
			local card = UI.card({ LayoutOrder = i, ZIndex = Z }, grid, isNext and C.Purple or (passed and Color3.fromRGB(60, 120, 80) or C.Navy2))
			if isNext then
				UI.stroke(card, C.Gold, 4)
			end
			label(card, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), Text = "Jour " .. i, TextColor3 = C.Gold })
			local icon = day.crate and "crate" or (day.potion and "power" or "coin")
			Icons.Image(icon, card, { Size = UDim2.fromOffset(64, 64), Position = UDim2.new(0.5, -32, 0, 38), ZIndex = Z + 1 })
			local text = day.coins and F.Format(day.coins * mult) or ""
			if day.potion then
				for _, it in ipairs(Config.Shop) do
					if it.id == day.potion then
						text = it.name
					end
				end
			end
			if day.crate then
				text = day.crate .. " reliques + " .. F.Format(day.coins * mult)
			end
			label(card, { Size = UDim2.new(1, -12, 0, 36), Position = UDim2.fromOffset(6, 108), Text = text, TextWrapped = true })
			if passed or claimedToday then
				Icons.Image("check", card, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -40, 0, 4), ZIndex = Z + 2 })
			end
		end
		local b = UI.button({ Size = UDim2.fromOffset(340, 64), Position = UDim2.new(0.5, -170, 1, -72), Text = ready and "RECUPERER" or ("Prochaine dans " .. F.Time(Config.Daily.Cooldown - since)), ZIndex = Z }, root, ready and C.Green or GREY)
		b.Activated:Connect(function()
			if ready then
				act("daily")
			end
		end)
	end,
})

-- LEADERBOARD ------------------------------------------------------------------------------------------------
local topCache = {}
Window.Register("Leaderboard", {
	title = "CLASSEMENT",
	icon = "leaderboard",
	build = function(root, ctx)
		ctx.tab = ctx.tab or "Server"
		local tabs = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = Z }, root)
		UI.list(tabs, 8, true)
		for i, t in ipairs({ { "Server", "SERVEUR" }, { "Power", "PUISSANCE" }, { "Rebirths", "RENAISSANCES" }, { "Index", "INDEX" } }) do
			local b = UI.button({ Size = UDim2.fromOffset(170, 40), Text = t[2], LayoutOrder = i, ZIndex = Z }, tabs, ctx.tab == t[1] and C.Gold or C.Navy2)
			b.Activated:Connect(function()
				ctx.tab = t[1]
				Window.Render()
			end)
		end
		local list = UI.scroll({ Name = "Board", Size = UDim2.new(1, 0, 1, -54), Position = UDim2.fromOffset(0, 54), ZIndex = Z }, root)
		UI.list(list, 6)
		local rows = {}
		if ctx.tab == "Server" then
			for _, p in ipairs(Players:GetPlayers()) do
				table.insert(rows, { name = p.DisplayName, value = p:GetAttribute("Power") or 0, me = p == player, extra = "Renaissances " .. (p:GetAttribute("Rebirths") or 0) })
			end
			table.sort(rows, function(a, b)
				return a.value > b.value
			end)
		else
			local data = topCache[ctx.tab]
			if not data then
				label(list, { Size = UDim2.new(1, -14, 0, 40), Text = "Chargement du classement mondial...", TextColor3 = C.Sub })
				task.spawn(function()
					local ok, res = pcall(function()
						return Remotes.Query:InvokeServer("top", ctx.tab)
					end)
					topCache[ctx.tab] = ok and res or {}
					task.delay(60, function()
						topCache[ctx.tab] = nil
					end)
					if Window.Current == "Leaderboard" then
						Window.Render()
					end
				end)
				return
			end
			for _, e in ipairs(data) do
				table.insert(rows, { name = e.name, value = e.value, me = e.userId == player.UserId })
			end
			if #rows == 0 then
				label(list, { Size = UDim2.new(1, -14, 0, 40), Text = "Classement vide pour l'instant (sauvegarde requise).", TextColor3 = C.Sub })
			end
		end
		for i, r in ipairs(rows) do
			local medal = ({ C.Gold, Color3.fromRGB(200, 205, 220), Color3.fromRGB(220, 140, 80) })[i]
			local row = UI.card({ Size = UDim2.new(1, -14, 0, 54), LayoutOrder = i, ZIndex = Z }, list, r.me and C.Purple or C.Navy2)
			local badge = UI.new("Frame", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = medal or C.Navy, ZIndex = Z + 1 }, row)
			UI.corner(badge, 20)
			label(badge, { Size = UDim2.fromScale(1, 1), Text = tostring(i), ZIndex = Z + 2 })
			label(row, { Size = UDim2.new(0.5, 0, 0, 28), Position = UDim2.fromOffset(60, 13), Text = r.name, TextXAlignment = Enum.TextXAlignment.Left })
			label(row, { Size = UDim2.new(0.4, -20, 0, 28), Position = UDim2.new(0.6, 0, 0, 13), Text = F.Format(r.value), TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right })
		end
	end,
})

-- SETTINGS ------------------------------------------------------------------------------------------------------
Window.Register("Settings", {
	title = "PARAMETRES",
	icon = "settings",
	refreshOn = { data = true },
	build = function(root)
		local d = State.data
		local s = d.Settings
		local list = UI.scroll({ Name = "SettingsList", Size = UDim2.fromScale(1, 1), ZIndex = Z }, root)
		UI.list(list, 10)
		local function toggle(order, key, name, desc)
			local row = UI.card({ Size = UDim2.new(1, -14, 0, 70), LayoutOrder = order, ZIndex = Z }, list, C.Navy2)
			label(row, { Size = UDim2.new(0.6, 0, 0, 28), Position = UDim2.fromOffset(16, 8), Text = name, TextXAlignment = Enum.TextXAlignment.Left })
			label(row, { Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(16, 40), Text = desc, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
			local on = s[key] ~= false
			local b = UI.button({ Size = UDim2.fromOffset(150, 48), Position = UDim2.new(1, -164, 0.5, -24), Text = on and "ACTIVE" or "DESACTIVE", ZIndex = Z + 1 }, row, on and C.Green or GREY)
			b.Activated:Connect(function()
				act("settings", { [key] = not on })
			end)
		end
		local function slider(order, key, name)
			local row = UI.card({ Size = UDim2.new(1, -14, 0, 70), LayoutOrder = order, ZIndex = Z }, list, C.Navy2)
			label(row, { Size = UDim2.new(0.4, 0, 0, 28), Position = UDim2.fromOffset(16, 20), Text = name, TextXAlignment = Enum.TextXAlignment.Left })
			local v = s[key] or 0.5
			local _, set = UI.bar({ Size = UDim2.new(0, 220, 0, 20), Position = UDim2.new(1, -380, 0.5, -10), ZIndex = Z + 1 }, row, C.Gold)
			set(v, true)
			local minus = UI.button({ Size = UDim2.fromOffset(56, 48), Position = UDim2.new(1, -140, 0.5, -24), Text = "-", ZIndex = Z + 1 }, row, C.Purple)
			minus.Activated:Connect(function()
				act("settings", { [key] = math.max(0, math.floor((v - 0.1) * 10 + 0.5) / 10) })
			end)
			local plus = UI.button({ Size = UDim2.fromOffset(56, 48), Position = UDim2.new(1, -72, 0.5, -24), Text = "+", ZIndex = Z + 1 }, row, C.Purple)
			plus.Activated:Connect(function()
				act("settings", { [key] = math.min(1, math.floor((v + 0.1) * 10 + 0.5) / 10) })
			end)
		end
		slider(1, "Music", "Musique")
		slider(2, "Sfx", "Effets sonores")
		toggle(3, "ShowOthers", "Reliques des autres joueurs", "Afficher les reliques qui flottent autour des autres")
		toggle(4, "LowGraphics", "Mode performance", "Moins de particules et d'ombres (appareils modestes)")
		toggle(5, "DamageNumbers", "Chiffres de degats", "Afficher les degats au-dessus des cibles")
		if d.Perks.AutoHit then
			toggle(6, "AutoHit", "Frappe automatique", "Tes reliques attaquent seules le tresor le plus proche")
		end
	end,
})

return PanelsB
