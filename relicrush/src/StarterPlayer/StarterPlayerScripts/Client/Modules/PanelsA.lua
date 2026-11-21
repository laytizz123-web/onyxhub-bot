-- Fenetres (1/2) : Caisse, Index, Inventory, Shop, Worlds, Upgrades, Rebirth.
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

local PanelsA = {}
local C = UI.C
local Z = 22

local function act(...)
	Remotes.Action:FireServer(...)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or Z
	return UI.text(props, parent)
end

local function shopPrice(item, data)
	if item.kind == "potion" and item.scale then
		return math.floor(item.price * F.BestWorld(data).mult ^ 0.85)
	elseif item.kind == "inventory" then
		return math.floor(item.price * item.growth ^ (data.BagLevel or 0))
	end
	return item.price
end

-- Tuile de relique (3D + cadre de rarete)
local function relicTile(parent, relicId, opts)
	opts = opts or {}
	local def = Config.RelicById[relicId]
	local rc = Config.RarityById[def.rarity].color
	local tile = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = opts.silhouette and C.Navy or rc:Lerp(C.Navy, 0.55), LayoutOrder = opts.order or 0, ZIndex = Z }, parent)
	UI.corner(tile, 14)
	UI.gradient(tile, Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 190), 90)
	UI.stroke(tile, opts.selected and Color3.new(1, 1, 1) or rc, opts.selected and 4 or 3)
	RelicView.Viewport(relicId, tile, { Size = UDim2.new(1, -10, 1, -30), Position = UDim2.fromOffset(5, 4), ZIndex = Z + 1 }, opts.silhouette, opts.spin)
	label(tile, { Size = UDim2.new(1, -8, 0, 20), Position = UDim2.new(0, 4, 1, -24), Text = opts.caption or (opts.silhouette and "???" or F.Format(def.power)), TextColor3 = opts.captionColor or C.Text, ZIndex = Z + 2 })
	if opts.equipped then
		Icons.Image("check", tile, { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(4, 4), ZIndex = Z + 3 })
	end
	if opts.locked then
		Icons.Image("lock", tile, { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -28, 0, 4), ZIndex = Z + 3 })
	end
	return tile
end
PanelsA.RelicTile = relicTile

-- CAISSE --------------------------------------------------------------------------------------------
Window.Register("Crate", {
	title = "CAISSE DE RELIQUES",
	icon = "inventory",
	refreshOn = { data = true },
	build = function(root, ctx)
		local d = State.data
		local worldId = ctx.world or "Village"
		local crate = Config.Crates[worldId]
		local luck = F.Luck(d, State.Now())
		label(root, { Size = UDim2.new(1, 0, 0, 34), Text = crate.name .. "  -  chance x" .. string.format("%.2f", luck), TextColor3 = C.Gold })
		local grid = UI.scroll({ Name = "CrateGrid", Size = UDim2.new(1, 0, 1, -120), Position = UDim2.fromOffset(0, 40), ZIndex = Z }, root)
		UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(132, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local odds = F.CrateOdds(worldId, luck)
		local byRarity = {}
		for _, e in ipairs(odds) do
			byRarity[e.rarity] = e.pct
		end
		local i = 0
		for _, r in ipairs(Config.Relics) do
			if r.world == worldId and not r.boss and byRarity[r.rarity] then
				i += 1
				local count = 0
				for _, rel in ipairs(Config.Relics) do
					if rel.world == worldId and rel.rarity == r.rarity and not rel.boss then
						count += 1
					end
				end
				local pct = byRarity[r.rarity] / count
				local known = d.Index[r.id]
				relicTile(grid, r.id, { order = i, silhouette = not known, spin = true, caption = (pct >= 0.1 and string.format("%.1f%%", pct) or string.format("%.4f%%", pct)), captionColor = Config.RarityById[r.rarity].color })
			end
		end
		local can = d.Worlds[worldId]
		local b1 = UI.button({ Size = UDim2.fromOffset(260, 62), Position = UDim2.new(0.5, -275, 1, -66), Text = "OUVRIR x1  -  " .. F.Format(crate.price), ZIndex = Z }, root, (can and d.Coins >= crate.price) and C.Gold or Color3.fromRGB(110, 100, 130))
		b1.Activated:Connect(function()
			act("openCrate", worldId, 1)
		end)
		local b3 = UI.button({ Size = UDim2.fromOffset(260, 62), Position = UDim2.new(0.5, 15, 1, -66), Text = d.Perks.TripleOpen and ("OUVRIR x3  -  " .. F.Format(crate.price * 3)) or "x3 : voir Boutique", ZIndex = Z }, root, d.Perks.TripleOpen and C.Purple or Color3.fromRGB(110, 100, 130))
		b3.Activated:Connect(function()
			if d.Perks.TripleOpen then
				act("openCrate", worldId, 3)
			else
				Window.Open("Shop")
			end
		end)
	end,
})

-- INDEX -----------------------------------------------------------------------------------------------
Window.Register("Index", {
	title = "INDEX DES RELIQUES",
	icon = "index",
	refreshOn = { data = true },
	build = function(root, ctx)
		local d = State.data
		ctx.world = ctx.world or "Village"
		local total, found = 0, 0
		for _, r in ipairs(Config.Relics) do
			total += 1
			if d.Index[r.id] then
				found += 1
			end
		end
		label(root, { Size = UDim2.new(0.6, 0, 0, 30), Text = "Decouvertes : " .. found .. " / " .. total, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold })
		label(root, { Size = UDim2.new(0.4, 0, 0, 24), Position = UDim2.new(0.6, 0, 0, 4), Text = "Bonus d'index : +" .. math.floor(F.IndexBonus(d) * 100) .. " % puissance", TextColor3 = Color3.fromRGB(215, 160, 255), TextXAlignment = Enum.TextXAlignment.Right })
		local tabs = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1, ZIndex = Z }, root)
		UI.list(tabs, 6, true)
		for i, w in ipairs(Config.Worlds) do
			local b = UI.button({ Size = UDim2.fromOffset(100, 36), Text = w.id, LayoutOrder = i, ZIndex = Z }, tabs, ctx.world == w.id and w.color or C.Navy2)
			b.Activated:Connect(function()
				ctx.world = w.id
				Window.Render()
			end)
		end
		local grid = UI.scroll({ Name = "IndexGrid", Size = UDim2.new(1, 0, 1, -86), Position = UDim2.fromOffset(0, 84), ZIndex = Z }, root)
		UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(136, 160), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for i, r in ipairs(Config.Relics) do
			if r.world == ctx.world then
				local known = d.Index[r.id]
				local rar = Config.RarityById[r.rarity]
				local tile = relicTile(grid, r.id, { order = i, silhouette = not known, spin = known, caption = known and r.name or rar.name, captionColor = rar.color })
				label(tile, { Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 4), Text = known and ("P " .. F.Format(r.power)) or (r.boss and "BOSS" or (r.secret and "SECRET" or "")), TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = Z + 3 })
			end
		end
	end,
})

-- INVENTORY --------------------------------------------------------------------------------------------
Window.Register("Inventory", {
	title = "INVENTAIRE",
	icon = "inventory",
	refreshOn = { data = true },
	build = function(root, ctx)
		local d = State.data
		ctx.selected = ctx.selected or {}
		local equipped = {}
		for _, uid in ipairs(d.Equipped) do
			equipped[uid] = true
		end
		local list = {}
		for k, item in pairs(d.Relics) do
			local def = Config.RelicById[item.id]
			if def then
				table.insert(list, { uid = tonumber(k), item = item, def = def })
			end
		end
		table.sort(list, function(a, b)
			if equipped[a.uid] ~= equipped[b.uid] then
				return equipped[a.uid] == true
			end
			return a.def.power > b.def.power
		end)
		label(root, { Size = UDim2.new(0.5, 0, 0, 28), Text = "Reliques " .. #list .. " / " .. F.InventoryCap(d) .. "    Equipees " .. #d.Equipped .. " / " .. F.Slots(d), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold })
		local best = UI.button({ Size = UDim2.fromOffset(180, 40), Position = UDim2.new(1, -370, 0, -4), Text = "EQUIPER MEILLEURES", ZIndex = Z }, root, C.Green)
		best.Activated:Connect(function()
			act("equipBest")
		end)
		local rec = UI.button({ Size = UDim2.fromOffset(180, 40), Position = UDim2.new(1, -180, 0, -4), Text = ctx.recycle and "ANNULER" or "RECYCLER", ZIndex = Z }, root, ctx.recycle and C.Red or C.Purple)
		rec.Activated:Connect(function()
			ctx.recycle = not ctx.recycle
			ctx.selected = {}
			Window.Render()
		end)
		local grid = UI.scroll({ Name = "InvGrid", Size = UDim2.new(1, -250, 1, -50), Position = UDim2.fromOffset(0, 46), ZIndex = Z }, root)
		UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(110, 128), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for i, e in ipairs(list) do
			local tile = relicTile(grid, e.def.id, { order = i, equipped = equipped[e.uid], locked = e.item.locked, selected = ctx.recycle and ctx.selected[e.uid] or ctx.focus == e.uid })
			tile.Activated:Connect(function()
				if ctx.recycle then
					if not e.item.locked then
						ctx.selected[e.uid] = not ctx.selected[e.uid] or nil
					end
				else
					ctx.focus = e.uid
				end
				Window.Render()
			end)
		end
		-- panneau de detail
		local side = UI.card({ Size = UDim2.new(0, 238, 1, -50), Position = UDim2.new(1, -238, 0, 46), ZIndex = Z }, root, C.Navy2)
		if ctx.recycle then
			local n, value = 0, 0
			for uid in pairs(ctx.selected) do
				local item = d.Relics[tostring(uid)]
				if item then
					n += 1
					local def = Config.RelicById[item.id]
					value += math.floor(Config.Crates[def.world].price * 0.15 * Config.RarityById[def.rarity].index)
				end
			end
			label(side, { Size = UDim2.new(1, -20, 0, 60), Position = UDim2.fromOffset(10, 14), Text = "Selectionne les reliques a recycler (les verrouillees sont protegees)", TextScaled = true })
			label(side, { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 90), Text = n .. " relique(s)", TextColor3 = C.Gold })
			label(side, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 128), Text = "+" .. F.Format(value) .. " pieces", TextColor3 = C.Gold })
			local go = UI.button({ Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0, 10, 1, -62), Text = "RECYCLER", ZIndex = Z + 1 }, side, n > 0 and C.Red or Color3.fromRGB(110, 100, 130))
			go.Activated:Connect(function()
				local uids = {}
				for uid in pairs(ctx.selected) do
					table.insert(uids, uid)
				end
				ctx.selected = {}
				ctx.recycle = false
				act("recycle", uids)
			end)
			return
		end
		local focus = ctx.focus and d.Relics[tostring(ctx.focus)]
		if not focus then
			label(side, { Size = UDim2.new(1, -20, 0, 80), Position = UDim2.fromOffset(10, 20), Text = #list == 0 and "Ouvre des caisses pour obtenir tes premieres reliques !" or "Clique sur une relique pour voir ses details" })
			return
		end
		local def = Config.RelicById[focus.id]
		local rar = Config.RarityById[def.rarity]
		RelicView.Viewport(def.id, side, { Size = UDim2.new(1, -20, 0, 150), Position = UDim2.fromOffset(10, 8), ZIndex = Z + 1 }, false, true)
		label(side, { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 160), Text = def.name })
		label(side, { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 190), Text = rar.name .. "  -  " .. Config.WorldById[def.world].name, TextColor3 = rar.color })
		label(side, { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 216), Text = "Puissance " .. F.Format(def.power), TextColor3 = Color3.fromRGB(215, 160, 255) })
		local isEq = equipped[ctx.focus]
		local eb = UI.button({ Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 1, -150), Text = isEq and "RETIRER" or "EQUIPER", ZIndex = Z + 1 }, side, isEq and C.Red or C.Green)
		eb.Activated:Connect(function()
			act(isEq and "unequip" or "equip", ctx.focus)
		end)
		local lb = UI.button({ Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 1, -98), Text = focus.locked and "DEVERROUILLER" or "VERROUILLER", ZIndex = Z + 1 }, side, C.Blue)
		lb.Activated:Connect(function()
			act("lock", ctx.focus)
		end)
		local value = math.floor(Config.Crates[def.world].price * 0.15 * rar.index)
		local rb = UI.button({ Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 1, -50), Text = "RECYCLER  +" .. F.Format(value), ZIndex = Z + 1 }, side, focus.locked and Color3.fromRGB(110, 100, 130) or C.Purple)
		rb.Activated:Connect(function()
			if not focus.locked then
				act("recycle", { ctx.focus })
				ctx.focus = nil
			end
		end)
	end,
})

-- SHOP -----------------------------------------------------------------------------------------------------
Window.Register("Shop", {
	title = "BOUTIQUE",
	icon = "shop",
	refreshOn = { data = true },
	build = function(root)
		local d = State.data
		local grid = UI.scroll({ Name = "ShopGrid", Size = UDim2.fromScale(1, 1), ZIndex = Z }, root)
		UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(236, 200), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local now = State.Now()
		for i, item in ipairs(Config.Shop) do
			local card = UI.card({ LayoutOrder = i, ZIndex = Z }, grid, item.kind == "potion" and C.Purple2 or C.Navy2)
			local icon = item.kind == "potion" and (item.boost == "Coins" and "coin" or item.boost == "Luck" and "relic" or "power") or (item.kind == "inventory" and "inventory" or (item.id == "TripleOpen" and "crate" or "upgrades"))
			Icons.Image(icon, card, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(10, 8), ZIndex = Z + 1 })
			label(card, { Size = UDim2.new(1, -90, 0, 26), Position = UDim2.fromOffset(80, 12), Text = item.name, TextXAlignment = Enum.TextXAlignment.Left })
			label(card, { Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 78), Text = item.desc, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
			local status = ""
			if item.kind == "potion" and (d.Boosts[item.boost] or 0) > now then
				status = "Actif : " .. F.Time(d.Boosts[item.boost] - now)
			end
			label(card, { Size = UDim2.new(1, -90, 0, 20), Position = UDim2.fromOffset(80, 42), Text = status, TextColor3 = C.Green, TextXAlignment = Enum.TextXAlignment.Left })
			local owned = item.kind == "perk" and d.Perks[item.id]
			local price = shopPrice(item, d)
			local b = UI.button({ Size = UDim2.new(1, -20, 0, 46), Position = UDim2.new(0, 10, 1, -56), Text = owned and "POSSEDE" or F.Format(price), ZIndex = Z + 1 }, card, owned and C.Green or (d.Coins >= price and C.Gold or Color3.fromRGB(110, 100, 130)))
			if not owned then
				Icons.Image("coin", b, { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(0, 3), ZIndex = Z + 3 })
				b.Activated:Connect(function()
					act("buyShop", item.id)
				end)
			end
		end
	end,
})

-- WORLDS ---------------------------------------------------------------------------------------------------
Window.Register("Worlds", {
	title = "MONDES",
	icon = "worlds",
	refreshOn = { data = true },
	build = function(root)
		local d = State.data
		local list = UI.scroll({ Name = "WorldList", Size = UDim2.fromScale(1, 1), ZIndex = Z }, root)
		UI.list(list, 10)
		for i, w in ipairs(Config.Worlds) do
			local unlocked = d.Worlds[w.id]
			local prev = Config.Worlds[i - 1]
			local available = not prev or d.Worlds[prev.id]
			local row = UI.card({ Size = UDim2.new(1, -14, 0, 92), LayoutOrder = i, ZIndex = Z }, list, w.color:Lerp(C.Navy, 0.35))
			label(row, { Size = UDim2.new(0.5, 0, 0, 36), Position = UDim2.fromOffset(16, 10), Text = w.name, TextXAlignment = Enum.TextXAlignment.Left, StrokeThickness = 3 })
			label(row, { Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(16, 52), Text = "Tresors x" .. F.Format(w.mult) .. "  -  Boss : " .. Config.Boss[w.id].name, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
			local text, color, fn
			if unlocked then
				text, color = "VOYAGER", C.Green
				fn = function()
					act("teleport", w.id)
					Window.Close()
				end
			elseif available then
				text, color = F.Format(w.price), d.Coins >= w.price and C.Gold or Color3.fromRGB(110, 100, 130)
				fn = function()
					act("unlockWorld", w.id)
				end
			else
				text, color = "VERROUILLE", Color3.fromRGB(90, 85, 110)
			end
			local b = UI.button({ Size = UDim2.fromOffset(220, 56), Position = UDim2.new(1, -236, 0.5, -28), Text = text, ZIndex = Z + 1 }, row, color)
			if not unlocked and available then
				Icons.Image("coin", b, { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(0, 6), ZIndex = Z + 3 })
			elseif not unlocked then
				Icons.Image("lock", b, { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(0, 6), ZIndex = Z + 3 })
			end
			if fn then
				b.Activated:Connect(fn)
			end
		end
	end,
})

-- UPGRADES --------------------------------------------------------------------------------------------------
Window.Register("Upgrades", {
	title = "AMELIORATIONS",
	icon = "upgrades",
	refreshOn = { data = true },
	build = function(root)
		local d = State.data
		local list = UI.scroll({ Name = "UpgList", Size = UDim2.fromScale(1, 1), ZIndex = Z }, root)
		UI.list(list, 8)
		local icons = { Power = "power", Coins = "coin", Luck = "relic", Speed = "worlds", Magnet = "coin", Slots = "slot" }
		for i, u in ipairs(Config.Upgrades) do
			local lvl = d.Upgrades[u.id] or 0
			local row = UI.card({ Size = UDim2.new(1, -14, 0, 80), LayoutOrder = i, ZIndex = Z }, list, C.Navy2)
			Icons.Image(icons[u.id], row, { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(10, 10), ZIndex = Z + 1 })
			label(row, { Size = UDim2.new(0.4, 0, 0, 30), Position = UDim2.fromOffset(82, 8), Text = u.name .. "  " .. lvl .. "/" .. u.max, TextXAlignment = Enum.TextXAlignment.Left })
			label(row, { Size = UDim2.new(0.45, 0, 0, 22), Position = UDim2.fromOffset(82, 44), Text = u.desc .. (u.keepOnRebirth and "  (garde a la renaissance)" or ""), TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Left })
			local _, set = UI.bar({ Size = UDim2.new(0, 160, 0, 14), Position = UDim2.new(1, -400, 0.5, -7), ZIndex = Z + 1 }, row, C.Gold)
			set(lvl / u.max, true)
			local maxed = lvl >= u.max
			local cost = F.UpgradeCost(u.id, lvl)
			local b = UI.button({ Size = UDim2.fromOffset(200, 52), Position = UDim2.new(1, -214, 0.5, -26), Text = maxed and "MAX" or F.Format(cost), ZIndex = Z + 1 }, row, maxed and C.Green or (d.Coins >= cost and C.Gold or Color3.fromRGB(110, 100, 130)))
			if not maxed then
				Icons.Image("coin", b, { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(0, 5), ZIndex = Z + 3 })
				b.Activated:Connect(function()
					act("buyUpgrade", u.id)
				end)
			end
		end
	end,
})

-- REBIRTH -------------------------------------------------------------------------------------------------
Window.Register("Rebirth", {
	title = "RENAISSANCE",
	icon = "rebirth",
	refreshOn = { data = true },
	build = function(root)
		local d = State.data
		local cost = F.RebirthCost(d.Rebirths)
		local R = Config.Rebirth
		label(root, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 6), Text = "Renaissances : " .. d.Rebirths, TextColor3 = Color3.fromRGB(215, 160, 255), StrokeThickness = 3 })
		local function stat(y, name, now, after)
			local row = UI.card({ Size = UDim2.new(1, -120, 0, 60), Position = UDim2.new(0, 60, 0, y), ZIndex = Z }, root, C.Navy2)
			label(row, { Size = UDim2.new(0.4, 0, 0, 30), Position = UDim2.fromOffset(16, 15), Text = name, TextXAlignment = Enum.TextXAlignment.Left })
			label(row, { Size = UDim2.new(0.5, -20, 0, 30), Position = UDim2.new(0.5, 0, 0, 15), Text = now .. "   >   " .. after, TextColor3 = C.Green, TextXAlignment = Enum.TextXAlignment.Right })
		end
		stat(64, "Bonus de pieces", "+" .. math.floor(d.Rebirths * R.CoinBonus * 100) .. " %", "+" .. math.floor((d.Rebirths + 1) * R.CoinBonus * 100) .. " %")
		stat(134, "Bonus de puissance", "+" .. math.floor(d.Rebirths * R.PowerBonus * 100) .. " %", "+" .. math.floor((d.Rebirths + 1) * R.PowerBonus * 100) .. " %")
		label(root, { Size = UDim2.new(1, -60, 0, 50), Position = UDim2.fromOffset(30, 210), Text = "Tu gardes tes reliques, tes mondes et tes emplacements. Tes pieces et tes autres ameliorations repartent a zero.", TextColor3 = C.Sub, TextWrapped = true })
		local _, set = UI.bar({ Size = UDim2.new(1, -120, 0, 26), Position = UDim2.fromOffset(60, 280), ZIndex = Z }, root, Color3.fromRGB(190, 90, 255))
		set(d.Coins / cost, true)
		label(root, { Size = UDim2.new(1, -120, 0, 22), Position = UDim2.fromOffset(60, 282), Text = F.Format(d.Coins) .. " / " .. F.Format(cost), ZIndex = Z + 2 })
		local b = UI.button({ Size = UDim2.fromOffset(320, 66), Position = UDim2.new(0.5, -160, 1, -80), Text = "RENAITRE", ZIndex = Z }, root, d.Coins >= cost and C.Purple or Color3.fromRGB(110, 100, 130))
		b.Activated:Connect(function()
			if d.Coins >= cost then
				act("rebirth")
			end
		end)
	end,
})

return PanelsA
