-- Affiche les pets equipes qui suivent chaque joueur (rendu local, fluide, sans replication).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetModel = require(ReplicatedStorage.Shared.PetModel)

local PetFollow = {}

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

local tracked = {} -- [player] = { models = { {model=, id=, evo=, pos=CFrame} }, json = string }

local function rebuild(player)
	local entry = tracked[player]
	if not entry then
		entry = { models = {}, json = "" }
		tracked[player] = entry
	end
	local json = player:GetAttribute("EquippedPets") or "[]"
	if json == entry.json then
		return
	end
	entry.json = json
	for _, m in ipairs(entry.models) do
		m.model:Destroy()
	end
	entry.models = {}
	local ok, list = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for i, pet in ipairs(list) do
		local cf = hrp and hrp.CFrame or CFrame.new(0, 5, 0)
		local model = PetModel.Build(pet.id, pet.evo, cf)
		model.Parent = folder
		table.insert(entry.models, { model = model, id = pet.id, evo = pet.evo, index = i, current = cf })
	end
end

local function update(dt)
	local now = os.clock()
	for player, entry in pairs(tracked) do
		if player.Parent ~= Players then
			for _, m in ipairs(entry.models) do
				m.model:Destroy()
			end
			tracked[player] = nil
		else
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local count = #entry.models
			for _, m in ipairs(entry.models) do
				if hrp then
					local angle = math.pi + (m.index - (count + 1) / 2) * 0.9
					local offset = Vector3.new(math.sin(angle) * 5, 0, math.cos(angle) * 5 * -1)
					local target = hrp.CFrame * CFrame.new(offset.X, -1.2, -offset.Z)
					local bob = math.sin(now * 6 + m.index * 1.5) * 0.35 + 0.35
					local goal = CFrame.new(target.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, select(2, hrp.CFrame:ToEulerAnglesYXZ()), 0)
					m.current = m.current:Lerp(goal, math.clamp(dt * 6, 0, 1))
					m.model:PivotTo(m.current)
					-- Rainbow : couleur qui cycle
					if m.evo == 3 then
						local hue = (now * 0.4 + m.index * 0.2) % 1
						for _, part in ipairs(m.model:GetChildren()) do
							if part:IsA("BasePart") and part.Name ~= "Eye" then
								part.Color = Color3.fromHSV(hue, 0.7, 1)
							end
						end
					end
				end
			end
		end
	end
end

function PetFollow.Init()
	local function hook(player)
		rebuild(player)
		player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
			rebuild(player)
		end)
		player.CharacterAdded:Connect(function()
			local entry = tracked[player]
			if entry then
				entry.json = ""
			end
			task.wait(0.5)
			rebuild(player)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	RunService.RenderStepped:Connect(update)
end

return PetFollow
