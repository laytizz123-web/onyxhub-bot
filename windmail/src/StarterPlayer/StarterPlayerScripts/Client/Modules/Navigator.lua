-- Guidage : met en valeur les boites aux lettres de destination (contour, etiquette, drapeau leve),
-- trace un ruban de vent vers la destination principale et une fleche en bord d'ecran.
-- Sans colis : guide vers le guichet de poste le plus proche.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local Navigator = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local marks = {} -- [mailbox] = { highlight, billboard, flagCF }
local beam, a0, a1
local arrow, arrowLabel

Navigator.Target = nil -- Instance (BasePart) visee
Navigator.TargetText = ""

local function clearMarks()
	for m, info in pairs(marks) do
		info.highlight:Destroy()
		info.billboard:Destroy()
		local flag = m:FindFirstChild("Flag")
		if flag and info.flagCF then
			flag.CFrame = info.flagCF
		end
	end
	marks = {}
end

local function markMailbox(m, parcel, primary)
	local def = Config.ParcelById[parcel.type]
	local h = Instance.new("Highlight")
	h.FillTransparency = 0.75
	h.FillColor = def.color
	h.OutlineColor = primary and Color3.fromRGB(255, 255, 255) or def.color
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = m
	h.Parent = m
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(190, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = m.PrimaryPart
	local card = UI.panel({ Size = UDim2.fromScale(1, 1) }, bb)
	local strip = UI.new("Frame", { Size = UDim2.new(0, 6, 1, -12), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = def.color, BorderSizePixel = 0 }, card)
	UI.corner(strip, 3)
	UI.text({ Size = UDim2.new(1, -22, 0.5, -2), Position = UDim2.fromOffset(18, 4), Text = parcel.owner, TextXAlignment = Enum.TextXAlignment.Left }, card)
	local dist = UI.text({ Name = "Dist", Size = UDim2.new(1, -22, 0.42, 0), Position = UDim2.new(0, 18, 0.52, 0), Text = "", TextColor3 = UI.Colors.Sub, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, card)
	bb.Parent = player:WaitForChild("PlayerGui")
	local flag = m:FindFirstChild("Flag")
	local info = { highlight = h, billboard = bb, dist = dist, def = def }
	if flag then
		info.flagCF = flag.CFrame
		TweenService:Create(flag, TweenInfo.new(0.4, Enum.EasingStyle.Back), { CFrame = flag.CFrame * CFrame.new(0, 0.6, 0) }):Play()
	end
	marks[m] = info
end

local function nearestCounter(pos)
	local best, bd
	for _, c in ipairs(CollectionService:GetTagged("PostCounter")) do
		local d = (c.Position - pos).Magnitude
		if not bd or d < bd then
			best, bd = c, d
		end
	end
	return best
end

function Navigator.Refresh()
	clearMarks()
	for i, p in ipairs(State.parcels) do
		if p.mailbox and p.mailbox.Parent and not marks[p.mailbox] then
			markMailbox(p.mailbox, p, i == 1)
		end
	end
	-- le bouton "Livrer" n'apparait que sur les boites aux lettres attendues
	for _, m in ipairs(CollectionService:GetTagged("Mailbox")) do
		local prompt = m.PrimaryPart and m.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = marks[m] ~= nil
		end
	end
end

local function update()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	-- cible principale : premier colis (ou guichet)
	local target, text, color
	local first = State.parcels[1]
	if first and first.mailbox and first.mailbox.PrimaryPart then
		target = first.mailbox.PrimaryPart
		text = first.owner
		color = Config.ParcelById[first.type].color
	else
		local c = nearestCounter(hrp.Position)
		if c then
			target = c
			text = "Guichet de poste"
			color = UI.Colors.Post
		end
	end
	Navigator.Target = target
	for m, info in pairs(marks) do
		if m.PrimaryPart then
			local d = (m.PrimaryPart.Position - hrp.Position).Magnitude
			info.dist.Text = string.format("%d m  ·  %s", math.floor(d), info.def.name)
		end
	end
	if not target then
		arrow.Visible = false
		beam.Enabled = false
		return
	end
	-- ruban de vent
	a0.Parent = hrp
	a1.Parent = target
	beam.Color = ColorSequence.new(color)
	beam.Enabled = (target.Position - hrp.Position).Magnitude > 25
	-- fleche en bord d'ecran si la cible est hors champ
	local sp, onScreen = camera:WorldToViewportPoint(target.Position)
	local vs = camera.ViewportSize
	local dist = (target.Position - hrp.Position).Magnitude
	if onScreen and sp.X > 40 and sp.X < vs.X - 40 and sp.Y > 60 and sp.Y < vs.Y - 60 then
		arrow.Visible = false
	else
		arrow.Visible = true
		local rel = camera.CFrame:PointToObjectSpace(target.Position)
		local ang = math.atan2(-rel.Y, rel.X)
		local cx, cy = vs.X / 2, vs.Y / 2
		local rx, ry = cx - 70, cy - 80
		local x = cx + math.cos(ang) * rx
		local y = cy + math.sin(ang) * ry
		arrow.Position = UDim2.fromOffset(x, y)
		arrow.Rotation = math.deg(ang) + 90
		arrowLabel.Rotation = -arrow.Rotation
		arrowLabel.Text = string.format("%s\n%d m", text, math.floor(dist))
		arrow.TextColor3 = color
	end
end

function Navigator.Init(screen)
	a0 = Instance.new("Attachment")
	a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 1, 0)
	beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.FaceCamera = true
	beam.Segments = 20
	beam.CurveSize0 = 8
	beam.CurveSize1 = -8
	beam.LightEmission = 0.6
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.55), NumberSequenceKeypoint.new(0.85, 0.55), NumberSequenceKeypoint.new(1, 1) })
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.Parent = workspace.Terrain
	a0.Parent = workspace.Terrain
	a1.Parent = workspace.Terrain
	arrow = UI.text({
		Size = UDim2.fromOffset(46, 46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "▲",
		TextStrokeTransparency = 0.3,
		Visible = false,
	}, screen)
	arrowLabel = UI.text({ Size = UDim2.fromOffset(150, 40), Position = UDim2.new(0.5, -75, 1, 6), TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, Font = Enum.Font.GothamBold }, arrow)
	State.Changed.Event:Connect(function(what)
		if what == "parcels" then
			Navigator.Refresh()
		end
	end)
	RunService.RenderStepped:Connect(update)
	task.delay(3, Navigator.Refresh)
	CollectionService:GetInstanceAddedSignal("Mailbox"):Connect(function()
		task.defer(Navigator.Refresh)
	end)
end

return Navigator
