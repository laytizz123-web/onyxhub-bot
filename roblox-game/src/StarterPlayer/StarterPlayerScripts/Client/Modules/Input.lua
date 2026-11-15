-- Clic / tap sur les cases, survol avec info-bulle, raccourcis clavier.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)

local Input = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local hoverBox = Instance.new("SelectionBox")
hoverBox.LineThickness = 0.06
hoverBox.Color3 = Config.Colors.Accent
hoverBox.SurfaceTransparency = 0.85
hoverBox.SurfaceColor3 = Config.Colors.Accent
hoverBox.Parent = workspace

local billboard = Instance.new("BillboardGui")
billboard.Name = "TileInfo"
billboard.Size = UDim2.fromOffset(200, 64)
billboard.StudsOffset = Vector3.new(0, 4.5, 0)
billboard.AlwaysOnTop = true
billboard.Enabled = false
billboard.Parent = player:WaitForChild("PlayerGui")
local infoTitle = Instance.new("TextLabel")
infoTitle.Size = UDim2.new(1, 0, 0.5, 0)
infoTitle.BackgroundTransparency = 1
infoTitle.Font = Enum.Font.FredokaOne
infoTitle.TextScaled = true
infoTitle.TextColor3 = Color3.new(1, 1, 1)
infoTitle.TextStrokeTransparency = 0.3
infoTitle.Parent = billboard
local infoSub = Instance.new("TextLabel")
infoSub.Size = UDim2.new(1, 0, 0.5, 0)
infoSub.Position = UDim2.new(0, 0, 0.5, 0)
infoSub.BackgroundTransparency = 1
infoSub.Font = Enum.Font.GothamBold
infoSub.TextScaled = true
infoSub.TextColor3 = Config.Colors.Accent
infoSub.TextStrokeTransparency = 0.3
infoSub.Parent = billboard

local function findTile(instance)
	local current = instance
	while current and current ~= workspace do
		if current:GetAttribute("PlotId") and current:GetAttribute("Index") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local mouse = player:GetMouse()
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

-- screenPos = nil : utilise la souris ; sinon position d'un tap (coordonnees ecran)
local function tileAt(screenPos)
	if not screenPos then
		return findTile(mouse.Target)
	end
	local char = player.Character
	params.FilterDescendantsInstances = char and { char } or {}
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if not result then
		return nil
	end
	return findTile(result.Instance)
end

local function describeTile(tile)
	local plantId = tile:GetAttribute("Plant") or ""
	local locked = tile:GetAttribute("Locked")
	if locked then
		return "Case verrouillee", State.inventory.expandPrice and ("Agrandir : " .. State.inventory.expandPrice .. " pieces") or ""
	end
	if plantId == "" then
		if State.selectedSeed then
			return "Planter : " .. State.selectedSeed, "Clique pour planter"
		end
		return "Case vide", "Choisis une graine (1-9)"
	end
	local progress = tile:GetAttribute("Progress") or 0
	local ripe = tile:GetAttribute("Ripe")
	local mutations = tile:GetAttribute("Mutations") or ""
	local title = plantId
	if mutations ~= "" then
		title = mutations:gsub(",", " ") .. " " .. plantId
	end
	if ripe then
		return title, "MUR ! Clique pour recolter"
	end
	local waterLeft = math.max(0, State.waterReadyAt - os.clock())
	local sub = math.floor(progress * 100) .. " %  |  " .. (waterLeft > 0 and string.format("arrosoir %.0fs", waterLeft) or "clique pour arroser")
	return title, sub
end

local function updateHover()
	local tile = tileAt(nil)
	if tile and tile:GetAttribute("PlotId") == State.inventory.plotId then
		hoverBox.Adornee = tile
		billboard.Adornee = tile
		billboard.Enabled = true
		local title, sub = describeTile(tile)
		infoTitle.Text = title
		infoSub.Text = sub
		local ripe = tile:GetAttribute("Ripe")
		local locked = tile:GetAttribute("Locked")
		local color = locked and Color3.fromRGB(160, 160, 160) or (ripe and Config.Colors.Gold or Config.Colors.Accent)
		hoverBox.Color3 = color
		hoverBox.SurfaceColor3 = color
		infoSub.TextColor3 = color
	else
		hoverBox.Adornee = nil
		billboard.Enabled = false
	end
end

local function act(screenPos)
	local tile = tileAt(screenPos)
	if not tile then
		return
	end
	if tile:GetAttribute("PlotId") ~= State.inventory.plotId then
		State.fire("notify", { text = "Ce n'est pas ta parcelle !", kind = "danger" })
		return
	end
	local plantId = tile:GetAttribute("Plant") or ""
	if plantId == "" and not State.selectedSeed and not tile:GetAttribute("Locked") then
		State.fire("notify", { text = "Selectionne une graine dans ta barre (touches 1-9).", kind = "info" })
		return
	end
	if plantId ~= "" and not tile:GetAttribute("Ripe") and not tile:GetAttribute("Locked") then
		if State.waterReadyAt > os.clock() then
			return
		end
		State.waterReadyAt = os.clock() + Config.Water.Cooldown
	end
	Remotes.Action:FireServer(tile:GetAttribute("PlotId"), tile:GetAttribute("Index"), State.selectedSeed)
	State.fire("tileAction", tile)
end

local touchStart = nil -- { pos = Vector2, time = number }

function Input.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			act(nil)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touchStart = { pos = Vector2.new(input.Position.X, input.Position.Y), time = os.clock() }
		elseif input.UserInputType == Enum.UserInputType.Keyboard then
			local code = input.KeyCode
			if code.Value >= Enum.KeyCode.One.Value and code.Value <= Enum.KeyCode.Nine.Value then
				State.fire("hotbar", code.Value - Enum.KeyCode.One.Value + 1)
			elseif code == Enum.KeyCode.B then
				State.fire("toggle", "backpack")
			elseif code == Enum.KeyCode.Escape then
				State.fire("toggle", "close")
			end
		end
	end)

	-- Tap court sur mobile (pas un glissement de camera)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or not touchStart then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local moved = (pos - touchStart.pos).Magnitude
		local held = os.clock() - touchStart.time
		touchStart = nil
		if moved < 12 and held < 0.35 then
			act(pos)
		end
	end)

	if UserInputService.MouseEnabled then
		RunService.RenderStepped:Connect(updateHover)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local stand = prompt.Parent
		if stand and CollectionService:HasTag(stand, "ShopStand") then
			State.fire("toggle", "shop")
		end
	end)
end

return Input
