-- Icones de RELIC RUSH (planche fournie + petites icones), affichees via EditableImage
-- a partir de IconData (aucun upload necessaire). Si tu uploades les PNG de assets/icons,
-- renseigne leurs IDs dans Icons.AssetIds pour les utiliser a la place.

local AssetService = game:GetService("AssetService")

local Icons = {}
Icons.AssetIds = {
	-- index = "rbxassetid://123456",
}

local IconData
local cache = {}
local supported = true

local B64 = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #chars do
		B64[string.byte(chars, i)] = i - 1
	end
end

local function b64decode(s)
	local len = #s
	local pad = (string.sub(s, -2) == "==") and 2 or ((string.sub(s, -1) == "=") and 1 or 0)
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = (B64[a] or 0) * 262144 + (B64[b] or 0) * 4096 + (B64[c] or 0) * 64 + (B64[d] or 0)
		if o < outLen then
			buffer.writeu8(out, o, n // 65536)
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

local function content(name)
	if cache[name] ~= nil then
		return cache[name]
	end
	cache[name] = false
	if not supported then
		return false
	end
	if not IconData then
		local ok, data = pcall(require, script.Parent:WaitForChild("IconData", 10))
		IconData = ok and data or {}
	end
	local entry = IconData[name]
	if not entry then
		return false
	end
	local ok, result = pcall(function()
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
	if ok then
		cache[name] = result
		return result
	end
	warn("[RelicRush] Icone " .. name .. " indisponible : " .. tostring(result))
	supported = false
	return false
end

function Icons.Apply(target, name)
	local id = Icons.AssetIds[name]
	if id then
		target.Image = id
		return target
	end
	local c = content(name)
	if c then
		local ok = pcall(function()
			target.ImageContent = c
		end)
		if ok then
			return target
		end
	end
	-- repli : etiquette texte (jamais d'emoji)
	local l = Instance.new("TextLabel")
	l.Name = "IconFallback"
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 210, 90)
	l.Text = string.upper(name)
	l.ZIndex = target.ZIndex + 1
	l.Parent = target
	return target
end

function Icons.Image(name, parent, props)
	local img = Instance.new("ImageLabel")
	img.Name = "Icon_" .. name
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	for k, v in pairs(props or {}) do
		img[k] = v
	end
	Icons.Apply(img, name)
	img.Parent = parent
	return img
end

function Icons.Button(name, parent, props)
	local b = Instance.new("ImageButton")
	b.Name = "Btn_" .. name
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.ScaleType = Enum.ScaleType.Fit
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Icons.Apply(b, name)
	b.Parent = parent
	return b
end

return Icons
