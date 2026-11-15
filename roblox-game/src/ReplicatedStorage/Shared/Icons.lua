-- Icones vectorielles dessinees en UI (Frames + UICorner + UIGradient + UIStroke).
-- Style cartoon : couleurs vives, contours noirs, reflets. Aucune image a uploader.
-- Pour utiliser tes propres images : Config.IconImages[nom] = "rbxassetid://..." et l'icone devient une ImageLabel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Icons = {}

local BLACK = Color3.fromRGB(25, 20, 35)

local function el(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function outline(frame, thickness, color)
	return el("UIStroke", { Color = color or BLACK, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round }, frame)
end

local function shade(frame, color, rotation)
	return el("UIGradient", { Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color:Lerp(Color3.new(0, 0, 0), 0.25)), Rotation = rotation or 90 }, frame)
end

-- Toutes les coordonnees sont en fraction (0-1) de l'icone : elle s'adapte a toute taille.
local function shape(parent, x, y, w, h, color, radius, z, rotation)
	local f = el("Frame", {
		Size = UDim2.fromScale(w, h),
		Position = UDim2.fromScale(x, y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z or 2,
		Rotation = rotation or 0,
	}, parent)
	el("UICorner", { CornerRadius = radius or UDim.new(0.25, 0) }, f)
	return f
end

local CIRCLE = UDim.new(1, 0)

local function circle(parent, x, y, size, color, z, noOutline)
	local c = shape(parent, x, y, size, size, color, CIRCLE, z)
	if not noOutline then
		outline(c, 2)
	end
	shade(c, color)
	return c
end

local function ring(parent, x, y, size, color, thickness, z)
	local c = shape(parent, x, y, size, size, color, CIRCLE, z)
	c.BackgroundTransparency = 1
	outline(c, thickness, color)
	return c
end

local function highlight(parent, x, y, w, h, z)
	local hl = shape(parent, x, y, w, h, Color3.new(1, 1, 1), CIRCLE, z or 6)
	hl.BackgroundTransparency = 0.35
	hl.Rotation = -30
	return hl
end

local draw = {}

draw.coin = function(p)
	local c = circle(p, 0.5, 0.5, 0.9, Color3.fromRGB(255, 200, 40))
	outline(c, 3)
	ring(p, 0.5, 0.5, 0.62, Color3.fromRGB(230, 150, 20), 3, 3)
	local bar = shape(p, 0.5, 0.5, 0.14, 0.4, Color3.fromRGB(230, 150, 20), UDim.new(0.3, 0), 4)
	bar.BackgroundTransparency = 0.1
	highlight(p, 0.33, 0.3, 0.2, 0.1)
end

draw.paw = function(p)
	local color = Color3.fromRGB(255, 140, 190)
	local pad = shape(p, 0.5, 0.66, 0.56, 0.46, color, UDim.new(0.5, 0), 2)
	outline(pad, 2.5)
	shade(pad, color)
	for _, t in ipairs({ { 0.22, 0.42, 0.24 }, { 0.42, 0.22, 0.22 }, { 0.6, 0.22, 0.22 }, { 0.8, 0.42, 0.24 } }) do
		local toe = circle(p, t[1], t[2], t[3], color)
		outline(toe, 2.5)
	end
	highlight(p, 0.4, 0.58, 0.16, 0.08)
end

draw.egg = function(p, color)
	color = color or Color3.fromRGB(250, 245, 255)
	local body = shape(p, 0.5, 0.52, 0.66, 0.88, color, UDim.new(0.5, 0), 2)
	outline(body, 3)
	shade(body, color)
	for _, s in ipairs({ { 0.4, 0.4, 0.14 }, { 0.62, 0.6, 0.12 }, { 0.45, 0.72, 0.1 } }) do
		local spot = shape(p, s[1], s[2], s[3], s[3], color:Lerp(Color3.fromRGB(120, 180, 255), 0.6), CIRCLE, 3)
		spot.BackgroundTransparency = 0.2
	end
	highlight(p, 0.38, 0.26, 0.14, 0.2)
end

draw.chest = function(p)
	local wood = Color3.fromRGB(190, 110, 50)
	local gold = Color3.fromRGB(255, 200, 40)
	local body = shape(p, 0.5, 0.64, 0.84, 0.5, wood, UDim.new(0.12, 0), 2)
	outline(body, 3)
	shade(body, wood)
	local lid = shape(p, 0.5, 0.36, 0.86, 0.3, wood:Lerp(Color3.new(1, 1, 1), 0.1), UDim.new(0.4, 0), 3)
	outline(lid, 3)
	shade(lid, wood)
	local band = shape(p, 0.5, 0.5, 0.86, 0.1, gold, UDim.new(0.3, 0), 4)
	outline(band, 2)
	local lock = shape(p, 0.5, 0.56, 0.16, 0.18, gold, UDim.new(0.3, 0), 5)
	outline(lock, 2)
	highlight(p, 0.3, 0.32, 0.18, 0.07)
end

draw.trophy = function(p)
	local gold = Color3.fromRGB(255, 200, 40)
	local cup = shape(p, 0.5, 0.4, 0.5, 0.5, gold, UDim.new(0, 0), 3)
	el("UICorner", { CornerRadius = UDim.new(0.45, 0) }, cup)
	outline(cup, 3)
	shade(cup, gold)
	ring(p, 0.2, 0.4, 0.26, gold, 4, 2)
	ring(p, 0.8, 0.4, 0.26, gold, 4, 2)
	local stem = shape(p, 0.5, 0.72, 0.14, 0.18, gold, UDim.new(0.2, 0), 2)
	outline(stem, 2)
	local base = shape(p, 0.5, 0.86, 0.5, 0.14, Color3.fromRGB(230, 150, 20), UDim.new(0.3, 0), 3)
	outline(base, 3)
	highlight(p, 0.38, 0.3, 0.1, 0.2)
end

draw.flag = function(p)
	local pole = shape(p, 0.18, 0.52, 0.08, 0.9, Color3.fromRGB(230, 230, 240), UDim.new(0.3, 0), 2)
	outline(pole, 2)
	local flag = shape(p, 0.58, 0.32, 0.72, 0.46, Color3.new(1, 1, 1), UDim.new(0.1, 0), 3)
	outline(flag, 3)
	for row = 0, 2 do
		for col = 0, 3 do
			if (row + col) % 2 == 0 then
				local cell = el("Frame", { Size = UDim2.fromScale(0.25, 1 / 3), Position = UDim2.fromScale(col * 0.25, row / 3), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 4 }, flag)
				el("UICorner", { CornerRadius = UDim.new(0.15, 0) }, cell)
			end
		end
	end
	circle(p, 0.18, 0.08, 0.14, Color3.fromRGB(255, 200, 40))
end

draw.gift = function(p)
	local red = Color3.fromRGB(255, 80, 110)
	local gold = Color3.fromRGB(255, 220, 80)
	local box = shape(p, 0.5, 0.64, 0.74, 0.54, red, UDim.new(0.12, 0), 2)
	outline(box, 3)
	shade(box, red)
	local lid = shape(p, 0.5, 0.36, 0.86, 0.2, red:Lerp(Color3.new(1, 1, 1), 0.1), UDim.new(0.3, 0), 3)
	outline(lid, 3)
	local v = shape(p, 0.5, 0.6, 0.14, 0.72, gold, UDim.new(0.3, 0), 4)
	outline(v, 2)
	local hz = shape(p, 0.5, 0.36, 0.86, 0.08, gold, UDim.new(0.3, 0), 4)
	outline(hz, 1.5)
	local b1 = shape(p, 0.4, 0.16, 0.24, 0.18, gold, CIRCLE, 5, -20)
	outline(b1, 2)
	local b2 = shape(p, 0.6, 0.16, 0.24, 0.18, gold, CIRCLE, 5, 20)
	outline(b2, 2)
	highlight(p, 0.3, 0.56, 0.1, 0.16)
end

draw.book = function(p)
	local blue = Color3.fromRGB(80, 140, 255)
	local cover = shape(p, 0.5, 0.5, 0.74, 0.86, blue, UDim.new(0.12, 0), 2)
	outline(cover, 3)
	shade(cover, blue)
	local pages = shape(p, 0.54, 0.5, 0.6, 0.76, Color3.fromRGB(255, 250, 235), UDim.new(0.08, 0), 3)
	outline(pages, 2)
	for i = 0, 2 do
		local line = shape(p, 0.56, 0.36 + i * 0.14, 0.4, 0.05, Color3.fromRGB(200, 200, 215), UDim.new(0.5, 0), 4)
		line.BackgroundTransparency = 0.2
	end
	local spine = shape(p, 0.18, 0.5, 0.1, 0.86, blue:Lerp(Color3.new(0, 0, 0), 0.3), UDim.new(0.3, 0), 4)
	outline(spine, 2)
	circle(p, 0.5, 0.5, 0.2, Color3.fromRGB(255, 200, 40), 5)
end

draw.map = function(p)
	local colors = { Color3.fromRGB(230, 220, 170), Color3.fromRGB(210, 200, 150), Color3.fromRGB(230, 220, 170) }
	for i = 1, 3 do
		local fold = shape(p, 0.2 + (i - 1) * 0.3, 0.56, 0.3, 0.7, colors[i], UDim.new(0.1, 0), 2)
		outline(fold, 2.5)
	end
	local road = shape(p, 0.5, 0.62, 0.7, 0.07, Color3.fromRGB(120, 180, 255), UDim.new(0.5, 0), 4, -15)
	road.BackgroundTransparency = 0.1
	local pin = circle(p, 0.5, 0.3, 0.3, Color3.fromRGB(255, 80, 90), 5)
	outline(pin, 3)
	circle(p, 0.5, 0.29, 0.12, Color3.new(1, 1, 1), 6, true)
	local tip = shape(p, 0.5, 0.47, 0.16, 0.16, Color3.fromRGB(255, 80, 90), UDim.new(0.1, 0), 4, 45)
	outline(tip, 2)
end

draw.bolt = function(p)
	local y = Color3.fromRGB(255, 220, 60)
	local a = shape(p, 0.56, 0.3, 0.3, 0.5, y, UDim.new(0.15, 0), 3, 25)
	outline(a, 3)
	shade(a, y)
	local b = shape(p, 0.44, 0.7, 0.3, 0.5, y, UDim.new(0.15, 0), 3, 25)
	outline(b, 3)
	shade(b, y)
	local mid = shape(p, 0.5, 0.5, 0.5, 0.18, y, UDim.new(0.1, 0), 4, -20)
	outline(mid, 3)
	highlight(p, 0.52, 0.22, 0.08, 0.16)
end

draw.shield = function(p)
	local blue = Color3.fromRGB(80, 160, 255)
	local s = shape(p, 0.5, 0.5, 0.76, 0.88, blue, UDim.new(0, 0), 2)
	el("UICorner", { CornerRadius = UDim.new(0.42, 0) }, s)
	outline(s, 3)
	shade(s, blue)
	local inner = shape(p, 0.5, 0.48, 0.5, 0.6, blue:Lerp(Color3.new(1, 1, 1), 0.3), UDim.new(0, 0), 3)
	el("UICorner", { CornerRadius = UDim.new(0.42, 0) }, inner)
	local star = shape(p, 0.5, 0.48, 0.22, 0.22, Color3.fromRGB(255, 220, 80), UDim.new(0.15, 0), 4, 45)
	outline(star, 2)
	highlight(p, 0.34, 0.3, 0.1, 0.22)
end

draw.clover = function(p)
	local g = Color3.fromRGB(80, 200, 90)
	for _, c in ipairs({ { 0.5, 0.3 }, { 0.3, 0.5 }, { 0.7, 0.5 }, { 0.5, 0.68 } }) do
		local leaf = circle(p, c[1], c[2], 0.4, g)
		outline(leaf, 3)
	end
	local stem = shape(p, 0.56, 0.84, 0.1, 0.3, g:Lerp(Color3.new(0, 0, 0), 0.3), UDim.new(0.5, 0), 3, 20)
	outline(stem, 2)
	highlight(p, 0.42, 0.24, 0.1, 0.08)
end

draw.star = function(p, color)
	color = color or Color3.fromRGB(255, 220, 80)
	local a = shape(p, 0.5, 0.5, 0.62, 0.62, color, UDim.new(0.18, 0), 2, 0)
	outline(a, 3)
	shade(a, color)
	local b = shape(p, 0.5, 0.5, 0.62, 0.62, color, UDim.new(0.18, 0), 3, 45)
	outline(b, 3)
	shade(b, color, 45)
	local c = shape(p, 0.5, 0.5, 0.44, 0.44, color, UDim.new(0.18, 0), 4, 22)
	shade(c, color, 20)
	highlight(p, 0.4, 0.4, 0.14, 0.14)
end

draw.lock = function(p)
	local gold = Color3.fromRGB(255, 200, 40)
	local shackle = ring(p, 0.5, 0.36, 0.44, Color3.fromRGB(200, 200, 215), 6, 2)
	outline(shackle, 2)
	local body = shape(p, 0.5, 0.66, 0.64, 0.5, gold, UDim.new(0.15, 0), 3)
	outline(body, 3)
	shade(body, gold)
	local hole = circle(p, 0.5, 0.64, 0.16, BLACK, 4, true)
	local slot = shape(p, 0.5, 0.74, 0.07, 0.14, BLACK, UDim.new(0.3, 0), 4)
	slot.BackgroundTransparency = 0
	highlight(p, 0.36, 0.56, 0.08, 0.14)
end

draw.power = function(p)
	local grey = Color3.fromRGB(120, 125, 150)
	local red = Color3.fromRGB(255, 90, 100)
	local bar = shape(p, 0.5, 0.5, 0.6, 0.14, grey, UDim.new(0.5, 0), 2)
	outline(bar, 2.5)
	for _, x in ipairs({ 0.2, 0.8 }) do
		local w = shape(p, x, 0.5, 0.2, 0.6, red, UDim.new(0.2, 0), 3)
		outline(w, 3)
		shade(w, red)
	end
	highlight(p, 0.17, 0.32, 0.06, 0.1)
end

draw.close = function(p)
	for _, r in ipairs({ 45, -45 }) do
		local bar = shape(p, 0.5, 0.5, 0.18, 0.8, Color3.new(1, 1, 1), UDim.new(0.5, 0), 2, r)
		outline(bar, 2)
	end
end

draw.plus = function(p)
	for _, r in ipairs({ 0, 90 }) do
		local bar = shape(p, 0.5, 0.5, 0.22, 0.78, Color3.fromRGB(120, 240, 140), UDim.new(0.5, 0), 2, r)
		outline(bar, 2.5)
	end
end

draw.trash = function(p)
	local grey = Color3.fromRGB(200, 205, 220)
	local bin = shape(p, 0.5, 0.6, 0.56, 0.6, grey, UDim.new(0.15, 0), 2)
	outline(bin, 2.5)
	shade(bin, grey)
	local lid = shape(p, 0.5, 0.26, 0.7, 0.12, grey, UDim.new(0.4, 0), 3)
	outline(lid, 2.5)
	for _, x in ipairs({ 0.4, 0.6 }) do
		shape(p, x, 0.6, 0.06, 0.38, BLACK, UDim.new(0.5, 0), 4).BackgroundTransparency = 0.5
	end
end

draw.gem = function(p, color)
	color = color or Color3.fromRGB(120, 200, 255)
	local g = shape(p, 0.5, 0.5, 0.62, 0.62, color, UDim.new(0.2, 0), 2, 45)
	outline(g, 3)
	shade(g, color, 45)
	local facet = shape(p, 0.5, 0.5, 0.3, 0.3, color:Lerp(Color3.new(1, 1, 1), 0.4), UDim.new(0.2, 0), 3, 45)
	facet.BackgroundTransparency = 0.2
	highlight(p, 0.4, 0.36, 0.1, 0.1)
end

draw.sparkle = function(p, color)
	draw.star(p, color or Color3.fromRGB(255, 120, 255))
	local s = shape(p, 0.82, 0.2, 0.26, 0.26, Color3.new(1, 1, 1), UDim.new(0.2, 0), 5, 45)
	outline(s, 2)
end

draw.home = function(p)
	local wall = shape(p, 0.5, 0.64, 0.6, 0.46, Color3.fromRGB(255, 220, 170), UDim.new(0.1, 0), 2)
	outline(wall, 3)
	local roof = shape(p, 0.5, 0.36, 0.5, 0.5, Color3.fromRGB(255, 90, 90), UDim.new(0.15, 0), 3, 45)
	outline(roof, 3)
	local cover = shape(p, 0.5, 0.74, 0.8, 0.3, Color3.new(1, 1, 1), UDim.new(0, 0), 3)
	cover.BackgroundTransparency = 1
	local door = shape(p, 0.5, 0.74, 0.16, 0.26, Color3.fromRGB(140, 90, 50), UDim.new(0.3, 0), 4)
	outline(door, 2)
end

draw.tree = function(p)
	local trunk = shape(p, 0.5, 0.78, 0.18, 0.36, Color3.fromRGB(140, 90, 50), UDim.new(0.3, 0), 2)
	outline(trunk, 2.5)
	for i, c in ipairs({ { 0.5, 0.56, 0.6 }, { 0.36, 0.42, 0.42 }, { 0.64, 0.42, 0.42 }, { 0.5, 0.26, 0.4 } }) do
		local leaf = circle(p, c[1], c[2], c[3], Color3.fromRGB(80, 190, 90))
		outline(leaf, 2.5)
	end
end

draw.cactus = function(p)
	local g = Color3.fromRGB(90, 190, 100)
	local body = shape(p, 0.5, 0.56, 0.3, 0.8, g, UDim.new(0.5, 0), 2)
	outline(body, 3)
	shade(body, g)
	for _, x in ipairs({ 0.24, 0.76 }) do
		local arm = shape(p, x, 0.5, 0.2, 0.4, g, UDim.new(0.5, 0), 2)
		outline(arm, 2.5)
		local joint = shape(p, (x + 0.5) / 2, 0.64, 0.2, 0.14, g, UDim.new(0.5, 0), 3)
		outline(joint, 2)
	end
	local sand = shape(p, 0.5, 0.92, 0.9, 0.14, Color3.fromRGB(240, 210, 140), UDim.new(0.5, 0), 1)
	outline(sand, 2)
end

draw.skull = function(p)
	local head = circle(p, 0.5, 0.42, 0.7, Color3.fromRGB(240, 240, 250))
	outline(head, 3)
	local jaw = shape(p, 0.5, 0.74, 0.4, 0.26, Color3.fromRGB(240, 240, 250), UDim.new(0.2, 0), 2)
	outline(jaw, 2.5)
	circle(p, 0.38, 0.42, 0.18, BLACK, 4, true)
	circle(p, 0.62, 0.42, 0.18, BLACK, 4, true)
end

draw.crown = function(p)
	local gold = Color3.fromRGB(255, 200, 40)
	local base = shape(p, 0.5, 0.7, 0.8, 0.3, gold, UDim.new(0.15, 0), 2)
	outline(base, 3)
	shade(base, gold)
	for _, x in ipairs({ 0.18, 0.5, 0.82 }) do
		local spike = shape(p, x, 0.4, 0.22, 0.4, gold, UDim.new(0.2, 0), 2, 45)
		outline(spike, 2.5)
		circle(p, x, 0.22, 0.14, Color3.fromRGB(255, 90, 110), 4)
	end
	circle(p, 0.5, 0.7, 0.14, Color3.fromRGB(80, 160, 255), 4)
end

draw.timer = function(p)
	local c = circle(p, 0.5, 0.56, 0.74, Color3.fromRGB(240, 240, 250))
	outline(c, 3)
	shape(p, 0.5, 0.14, 0.2, 0.12, Color3.fromRGB(200, 200, 215), UDim.new(0.3, 0), 3)
	local hand = shape(p, 0.54, 0.5, 0.07, 0.28, BLACK, UDim.new(0.5, 0), 4, -40)
	hand.AnchorPoint = Vector2.new(0.5, 1)
	shape(p, 0.5, 0.56, 0.08, 0.08, BLACK, CIRCLE, 5)
end


-- Equivalent vectoriel (repli) pour les icones de la planche
local FALLBACK = {
	index = "paw", eggs = "egg", pets = "paw", shop = "chest", rewards = "gift", worlds = "map", race = "flag",
	leaderboard = "trophy", trading = "star", quests = "book", settings = "star", inventory = "chest",
	teleport = "gem", daily = "gift", codes = "star", ranks = "crown", achievements = "trophy", freegift = "gift",
	events = "star", exit = "close", coin = "coin", speed = "bolt", power = "power", stamina = "shield",
	luck = "clover", lock = "lock", gem = "gem", star = "star", close = "close", paw = "paw", egg = "egg",
}

-- Decodage des icones integrees (IconData) vers EditableImage ---------------------------

local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local IconData = nil
local editableCache = {} -- [name] = Content | false
local editableSupported = RunService:IsClient()

local B64 = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #chars do
		B64[string.byte(chars, i)] = i - 1
	end
end

local function b64decode(s)
	local len = #s
	local pad = 0
	if string.sub(s, -2) == "==" then
		pad = 2
	elseif string.sub(s, -1) == "=" then
		pad = 1
	end
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = bit32.lshift(B64[a], 18) + bit32.lshift(B64[b], 12) + bit32.lshift(B64[c] or 0, 6) + (B64[d] or 0)
		if o < outLen then
			buffer.writeu8(out, o, bit32.extract(n, 16, 8))
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, bit32.extract(n, 8, 8))
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, bit32.extract(n, 0, 8))
		end
		o += 3
	end
	return out
end

local function buildEditable(name)
	if editableCache[name] ~= nil then
		return editableCache[name]
	end
	editableCache[name] = false
	if not editableSupported then
		return false
	end
	if not IconData then
		local ok, data = pcall(require, script.Parent:WaitForChild("IconData", 5))
		IconData = ok and data or {}
	end
	local entry = IconData[name]
	if not entry then
		return false
	end
	local ok, content = pcall(function()
		local size = entry.size
		local palette = b64decode(entry.palette)
		local rle = b64decode(entry.data)
		local pixels = buffer.create(size * size * 4)
		local o = 0
		for i = 0, buffer.len(rle) - 2, 2 do
			local run = buffer.readu8(rle, i)
			local color = buffer.readu32(palette, buffer.readu8(rle, i + 1) * 4)
			for _ = 1, run do
				buffer.writeu32(pixels, o, color)
				o += 4
			end
		end
		local image = AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(size, size), pixels)
		return Content.fromObject(image)
	end)
	if ok and content then
		editableCache[name] = content
		return content
	end
	warn("[PetRush] Icone integree indisponible (" .. name .. ") : " .. tostring(content) .. ". Repli sur l'icone vectorielle.")
	editableSupported = false
	return false
end

-- Applique une icone sur une ImageLabel / ImageButton existante.
function Icons.Apply(target, name, color)
	for _, child in ipairs(target:GetChildren()) do
		if child.Name == "VectorIcon" then
			child:Destroy()
		end
	end
	local asset = Config.IconImages and Config.IconImages[name]
	if asset and asset ~= "" then
		target.Image = asset
		return target
	end
	local content = buildEditable(name)
	if content then
		target.Image = ""
		target.ImageContent = content
		return target
	end
	target.Image = ""
	local holder = el("Frame", { Name = "VectorIcon", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = target.ZIndex }, target)
	el("UIAspectRatioConstraint", { AspectRatio = 1 }, holder)
	local painter = draw[FALLBACK[name] or name] or draw.star
	painter(holder, color)
	return target
end

-- Cree une ImageLabel avec l'icone. props : proprietes de l'ImageLabel (Size, Position...).
function Icons.Image(name, parent, props, color)
	local label = Instance.new("ImageLabel")
	label.Name = "Icon_" .. name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.ScaleType = Enum.ScaleType.Fit
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	Icons.Apply(label, name, color)
	label.Parent = parent
	return label
end

-- Cree un ImageButton avec l'icone.
function Icons.Button(name, parent, props, color)
	local b = Instance.new("ImageButton")
	b.Name = "IconButton_" .. name
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.ScaleType = Enum.ScaleType.Fit
	b.AutoButtonColor = false
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Icons.Apply(b, name, color)
	b.Parent = parent
	return b
end

-- Gemme teintee a la couleur de la rarete
function Icons.Rarity(rarityId, parent, props)
	local rarity = Config.RarityById[rarityId]
	local label = Icons.Image("gem", parent, props, rarity and rarity.color)
	label.ImageColor3 = rarity and rarity.color or Color3.new(1, 1, 1)
	return label
end

-- Le dessin vectoriel en anneau doit garder son contour : expose pour d'autres modules
Icons.Draw = draw

return Icons
