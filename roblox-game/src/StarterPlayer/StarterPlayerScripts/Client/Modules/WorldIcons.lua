-- Icones 3D flottantes au-dessus des stands, des portes et des coffres (rendu client).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(ReplicatedStorage.Shared.Icons)
local State = require(script.Parent.State)

local WorldIcons = {}

local DARK = Color3.fromRGB(22, 24, 52)
local floaters = {}

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do
		l[k] = v
	end
	local st = Instance.new("UIStroke")
	st.Color = DARK
	st.Thickness = 3
	st.Parent = l
	l.Parent = parent
	return l
end

local function billboard(part, iconName, title, sub, height, size)
	local gui = Instance.new("BillboardGui")
	gui.Name = "WorldIcon"
	gui.Size = UDim2.fromOffset(size or 170, (size or 170) + 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height or 9, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Adornee = part
	local icon = Icons.Image(iconName, gui, { Size = UDim2.new(1, 0, 1, -50) })
	if title then
		label(gui, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -50), Text = title })
	end
	local subLabel
	if sub then
		subLabel = label(gui, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22), Text = sub, TextColor3 = Config.Colors.Gold })
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(floaters, { gui = gui, icon = icon, phase = math.random() * 6, base = height or 9 })
	return gui, subLabel
end

local gateLabels = {}

local function refreshGates()
	for gate, sub in pairs(gateLabels) do
		local zone = Config.ZoneById[gate:GetAttribute("ZoneId")]
		local unlocked = State.data.zones and State.data.zones[zone.id]
		sub.Text = unlocked and "OUVERT" or (zone.price .. " coins")
		sub.TextColor3 = unlocked and Color3.fromRGB(120, 255, 140) or Config.Colors.Gold
		gate.Transparency = unlocked and 1 or 0.35
		gate.CanCollide = not unlocked
	end
end

function WorldIcons.Init()
	for _, s in ipairs(CollectionService:GetTagged("EggStand")) do
		local egg = Config.EggById[s:GetAttribute("EggId")]
		local gui = billboard(s, "eggs", string.upper(egg.name), egg.price .. " coins", 12, 150)
	end
	for _, s in ipairs(CollectionService:GetTagged("RaceStand")) do
		billboard(s, "race", "COURSES", nil, 11, 170)
	end
	for _, s in ipairs(CollectionService:GetTagged("DailyStand")) do
		billboard(s, "daily", "CADEAU DU JOUR", nil, 11, 150)
	end
	for _, gate in ipairs(CollectionService:GetTagged("Gate")) do
		local zone = Config.ZoneById[gate:GetAttribute("ZoneId")]
		local _, sub = billboard(gate, "lock", string.upper(zone.name), zone.price .. " coins", 12, 120)
		gateLabels[gate] = sub
	end
	State.Changed.Event:Connect(function(what)
		if what == "sync" then
			refreshGates()
		end
	end)
	-- Icone de coffre au-dessus des coffres rares
	local coins = workspace:WaitForChild("Coins")
	coins.ChildAdded:Connect(function(child)
		if child.Name == "Chest" then
			local gui = billboard(child, "rewards", "COFFRE RARE", nil, 6, 130)
			gui.MaxDistance = 600
			gui.AlwaysOnTop = true
			child.Destroying:Connect(function()
				gui:Destroy()
			end)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for i = #floaters, 1, -1 do
			local f = floaters[i]
			if not f.gui.Parent then
				table.remove(floaters, i)
			else
				f.gui.StudsOffsetWorldSpace = Vector3.new(0, f.base + math.sin(t * 2 + f.phase) * 0.6, 0)
				f.icon.Rotation = math.sin(t * 1.6 + f.phase) * 5
			end
		end
	end)
end

return WorldIcons
