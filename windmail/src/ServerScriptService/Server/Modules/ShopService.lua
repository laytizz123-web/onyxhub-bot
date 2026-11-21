-- Boutique, equipement, recompense quotidienne, etat de vol (pour les ailes et trainees visibles).
-- Tout s'achete avec les pieces gagnees en jouant : aucun objet payant ne donne d'avantage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local ShopService = {}

local function notify(player, text, kind)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

local function rankOf(data)
	return (Progress.RankFromXP(data.XP))
end

-- Trainee sur le personnage (activee seulement en vol)
local function applyTrail(player)
	local data = DataService.Get(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (data and hrp) then
		return
	end
	for _, n in ipairs({ "WindTrail", "TrailA0", "TrailA1" }) do
		local o = hrp:FindFirstChild(n)
		if o then
			o:Destroy()
		end
	end
	local def = Config.TrailById[data.Trail]
	if not def or not def.color then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA0"
	a0.Position = Vector3.new(-2.8, 0.6, 0.6)
	a0.Parent = hrp
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailA1"
	a1.Position = Vector3.new(2.8, 0.6, 0.6)
	a1.Parent = hrp
	local t = Instance.new("Trail")
	t.Name = "WindTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.9
	t.LightEmission = 0.6
	t.Color = ColorSequence.new(def.color, def.color2 or def.color)
	t.Transparency = NumberSequence.new(0.35, 1)
	t.WidthScale = NumberSequence.new(1, 0.2)
	t.Enabled = player:GetAttribute("Gliding") == true
	t.Parent = hrp
end

local handlers = {}

function handlers.buyGlider(player, data, id)
	local g = Config.GliderById[id]
	if not g or data.Gliders[id] then
		return
	end
	if rankOf(data) < g.rank then
		return notify(player, "Rang " .. g.rank .. " requis pour " .. g.name .. ".", "danger")
	end
	if data.Coins < g.price then
		return notify(player, "Il te manque " .. Progress.Format(g.price - data.Coins) .. " pieces.", "danger")
	end
	data.Coins -= g.price
	data.Gliders[id] = true
	data.Glider = id
	Remotes.FX:FireClient(player, "Purchase", { name = g.name })
end

function handlers.equipGlider(player, data, id)
	if data.Gliders[id] then
		data.Glider = id
	end
end

function handlers.buySatchel(player, data)
	local nextS = Config.Satchels[data.Satchel + 1]
	if not nextS then
		return
	end
	if rankOf(data) < (nextS.rank or 1) then
		return notify(player, "Rang " .. nextS.rank .. " requis.", "danger")
	end
	if data.Coins < nextS.price then
		return notify(player, "Il te manque " .. Progress.Format(nextS.price - data.Coins) .. " pieces.", "danger")
	end
	data.Coins -= nextS.price
	data.Satchel += 1
	Remotes.FX:FireClient(player, "Purchase", { name = nextS.name })
end

function handlers.buyTrail(player, data, id)
	local t = Config.TrailById[id]
	if not t or data.Trails[id] or not t.price then
		return
	end
	if data.Coins < t.price then
		return notify(player, "Il te manque " .. Progress.Format(t.price - data.Coins) .. " pieces.", "danger")
	end
	data.Coins -= t.price
	data.Trails[id] = true
	data.Trail = id
	Remotes.FX:FireClient(player, "Purchase", { name = t.name })
	applyTrail(player)
end

function handlers.equipTrail(player, data, id)
	local unlocked = data.Trails[id] or Progress.SetBonuses(data.Stamps).trails[id]
	if unlocked and Config.TrailById[id] then
		data.Trails[id] = true
		data.Trail = id
		applyTrail(player)
	end
end

function handlers.daily(player, data)
	local since = os.time() - data.LastDaily
	if since < Config.Daily.Cooldown then
		return notify(player, "Reviens plus tard pour ta recompense !", "info")
	end
	data.DailyStreak = (since < Config.Daily.Reset) and math.min(data.DailyStreak + 1, #Config.Daily.Coins) or 1
	data.LastDaily = os.time()
	local coins = Config.Daily.Coins[data.DailyStreak]
	DataService.AddCoins(player, coins)
	Remotes.FX:FireClient(player, "Daily", { coins = coins, streak = data.DailyStreak })
end

function handlers.tutorialDone(player, data)
	data.Tutorial = true
end

local lastGlide = {}
function handlers.glide(player, data, on)
	if lastGlide[player] and os.clock() - lastGlide[player] < 0.15 then
		return
	end
	lastGlide[player] = os.clock()
	player:SetAttribute("Gliding", on == true)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local trail = hrp and hrp:FindFirstChild("WindTrail")
	if trail then
		trail.Enabled = on == true
	end
	return true -- pas de resynchronisation necessaire
end

function ShopService.Init()
	Remotes.Request.OnServerEvent:Connect(function(player, action, arg)
		local data = DataService.Get(player)
		local fn = handlers[action]
		if not (data and fn) or (arg ~= nil and type(arg) ~= "string" and type(arg) ~= "boolean") then
			return
		end
		local ok, skipSync = pcall(fn, player, data, arg)
		if not ok then
			warn("[Windmail] Action " .. tostring(action) .. " : " .. tostring(skipSync))
		end
		if not skipSync then
			DataService.Sync(player)
		end
	end)
	local function onChar(player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Gliding", false)
			task.wait(0.3)
			applyTrail(player)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onChar(p)
	end
	Players.PlayerAdded:Connect(onChar)
	Players.PlayerRemoving:Connect(function(p)
		lastGlide[p] = nil
	end)
	DataService.Loaded:Connect(function(player)
		applyTrail(player)
	end)
end

return ShopService
