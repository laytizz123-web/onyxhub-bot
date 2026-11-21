-- Reliques equipees de TOUS les joueurs : elles tournent et flottent autour du personnage.
-- Quand le joueur vise un tresor ou un boss, elles volent autour de la cible et foncent dessus
-- a chaque coup (etincelles). Calcul local, aucun cout reseau ; parametre "voir les reliques des autres".

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicModel = require(ReplicatedStorage.Shared.RelicModel)
local State = require(script.Parent.State)

local RelicOrbit = {}

local local_ = Players.LocalPlayer
local folder
local entries = {} -- [player] = { json, relics = { {model, parts, offsets, pos} } }

local function settings()
	return State.data and State.data.Settings or {}
end

local function clear(entry)
	for _, r in ipairs(entry.relics) do
		r.model:Destroy()
	end
	entry.relics = {}
end

local function rebuild(player)
	local entry = entries[player]
	if not entry then
		entry = { json = "", relics = {} }
		entries[player] = entry
	end
	local json = player:GetAttribute("Relics") or "[]"
	local hidden = player ~= local_ and settings().ShowOthers == false
	local key = json .. tostring(hidden) .. tostring(settings().LowGraphics)
	if key == entry.json then
		return
	end
	entry.json = key
	clear(entry)
	if hidden then
		return
	end
	local ok, ids = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(ids) ~= "table" then
		return
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for i, id in ipairs(ids) do
		local model = RelicModel.Build(id, { effects = not settings().LowGraphics })
		model:ScaleTo(0.85)
		local parts, offsets = RelicModel.Parts(model)
		model.Parent = folder
		table.insert(entry.relics, {
			model = model,
			parts = parts,
			offsets = offsets,
			pos = hrp and hrp.Position or Vector3.zero,
			phase = i * 1.7,
			rarity = Config.RarityById[Config.RelicById[id] and Config.RelicById[id].rarity or "Common"].index,
		})
	end
end

local function hook(player)
	player:GetAttributeChangedSignal("Relics"):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

local lastHit = 0
local function update(dt)
	local now = os.clock()
	local targets = workspace:FindFirstChild("Targets")
	local allParts, allCFs = {}, {}
	local camPos = workspace.CurrentCamera.CFrame.Position
	local hitPhase = (now % Config.HitInterval) / Config.HitInterval
	for player, entry in pairs(entries) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if player.Parent ~= Players then
			clear(entry)
			entries[player] = nil
		elseif hrp and #entry.relics > 0 and (hrp.Position - camPos).Magnitude < 300 then
			local tname = player:GetAttribute("Target")
			local target = tname and targets and targets:FindFirstChild(tname)
			local tbox = target and target.PrimaryPart
			local n = #entry.relics
			for i, r in ipairs(entry.relics) do
				local a = now * 1.4 + i / n * math.pi * 2
				local goal
				if tbox then
					local radius = math.max(tbox.Size.X, tbox.Size.Z) / 2 + 2.5
					local dash = math.sin(hitPhase * math.pi) ^ 4 -- foncer sur la cible a chaque coup
					local rr = radius * (1 - dash * 0.55)
					goal = tbox.Position + Vector3.new(math.cos(a) * rr, -tbox.Size.Y * 0.15 + math.sin(now * 3 + i) * 0.8, math.sin(a) * rr)
				else
					local radius = 3.6 + n * 0.25
					goal = hrp.Position + Vector3.new(math.cos(a) * radius, 1.2 + math.sin(now * 2 + r.phase) * 0.7, math.sin(a) * radius)
				end
				local alpha = math.clamp(dt * (tbox and 10 or 7), 0, 1)
				r.pos = r.pos:Lerp(goal, alpha)
				if (r.pos - goal).Magnitude > 120 then
					r.pos = goal
				end
				local cf = CFrame.new(r.pos) * CFrame.Angles(math.sin(now + i) * 0.3, now * (1.5 + r.rarity * 0.15) + i, 0)
				for k, p in ipairs(r.parts) do
					table.insert(allParts, p)
					table.insert(allCFs, cf * r.offsets[k])
				end
			end
		end
	end
	if #allParts > 0 then
		workspace:BulkMoveTo(allParts, allCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function RelicOrbit.Refresh()
	for p in pairs(entries) do
		rebuild(p)
	end
end

function RelicOrbit.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientRelics"
	folder.Parent = workspace
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	State.Changed.Event:Connect(function(what)
		if what == "data" then
			RelicOrbit.Refresh()
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return RelicOrbit
