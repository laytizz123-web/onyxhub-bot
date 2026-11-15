-- XP, niveaux, pieces, kills, victoires, titres, cosmetiques, classement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)

local ProgressionService = {}

local CharacterService -- injecte

local function findById(list, id)
	for _, item in ipairs(list) do
		if item.id == id then
			return item
		end
	end
	return nil
end

local function checkTitles(player, data)
	local newTitles = {}
	for _, title in ipairs(Config.Titles) do
		if not data.Unlocked.titles[title.id] then
			local req = title.requirement
			local value = (req.kind == "level" and data.Level) or (req.kind == "kills" and data.Kills) or (req.kind == "wins" and data.Wins) or 0
			if value >= req.value then
				data.Unlocked.titles[title.id] = true
				table.insert(newTitles, title.name)
			end
		end
	end
	for _, name in ipairs(newTitles) do
		Remotes.Notify:FireClient(player, "Nouveau titre debloque : " .. name, "gold")
	end
end

function ProgressionService.SyncStats(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	DataService.Sync(player)
	player:SetAttribute("Level", data.Level)
	local title = findById(Config.Titles, data.Title)
	player:SetAttribute("Title", title and title.name or "")
	player:SetAttribute("Aura", data.Aura)
	player:SetAttribute("Trail", data.Trail)
	player:SetAttribute("CharacterId", data.Character)
	Remotes.Stats:FireClient(player, {
		xp = data.XP,
		level = data.Level,
		xpNext = Config.Progression.XPForLevel(data.Level),
		coins = data.Coins,
		kills = data.Kills,
		deaths = data.Deaths,
		wins = data.Wins,
		character = data.Character,
		aura = data.Aura,
		trail = data.Trail,
		title = data.Title,
		unlocked = data.Unlocked,
	})
end

function ProgressionService.AddXP(player, amount)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.XP += amount
	local leveled = false
	while data.Level < Config.Progression.MaxLevel do
		local needed = Config.Progression.XPForLevel(data.Level)
		if data.XP < needed then
			break
		end
		data.XP -= needed
		data.Level += 1
		leveled = true
	end
	if leveled then
		Remotes.Notify:FireClient(player, "NIVEAU " .. data.Level .. " !", "gold")
		Remotes.CombatFX:FireAllClients("LevelUp", { userId = player.UserId })
		checkTitles(player, data)
	end
end

function ProgressionService.AddCoins(player, amount)
	local data = DataService.Get(player)
	if data then
		data.Coins += amount
	end
end

function ProgressionService.OnHit(player, damage)
	ProgressionService.AddXP(player, Config.Progression.XPPerHit)
	ProgressionService.AddCoins(player, Config.Progression.CoinsPerHit)
end

function ProgressionService.OnKill(killer, victim)
	local data = DataService.Get(killer)
	if not data then
		return
	end
	data.Kills += 1
	ProgressionService.AddXP(killer, Config.Progression.XPPerKill)
	ProgressionService.AddCoins(killer, Config.Progression.CoinsPerKill)
	local streak = (killer:GetAttribute("Streak") or 0) + 1
	killer:SetAttribute("Streak", streak)
	local victimName = victim and victim.DisplayName or "un mannequin"
	Remotes.Notify:FireAllClients(killer.DisplayName .. " a elimine " .. victimName, "kill")
	if streak % Config.Combat.StreakForWin == 0 then
		data.Wins += 1
		ProgressionService.AddXP(killer, Config.Progression.XPPerWin)
		ProgressionService.AddCoins(killer, Config.Progression.CoinsPerWin)
		Remotes.Notify:FireAllClients(killer.DisplayName .. " domine avec " .. streak .. " eliminations d'affilee ! (+1 victoire)", "gold")
		Remotes.CombatFX:FireAllClients("Win", { userId = killer.UserId })
	end
	checkTitles(killer, data)
	ProgressionService.SyncStats(killer)
end

function ProgressionService.OnDeath(player)
	local data = DataService.Get(player)
	if data then
		data.Deaths += 1
	end
	player:SetAttribute("Streak", 0)
	ProgressionService.SyncStats(player)
end

-- Menu (personnage, cosmetiques) --------------------------------------------------

local function onMenu(player, action, kind, id)
	local data = DataService.Get(player)
	if not data then
		return
	end
	if action == "character" then
		if not Config.CharacterById[kind] then
			return
		end
		data.Character = kind
		ProgressionService.SyncStats(player)
		CharacterService.Reload(player)
		Remotes.Notify:FireClient(player, "Personnage : " .. kind, "good")
	elseif action == "buy" then
		local list = (kind == "aura") and Config.Auras or (kind == "trail" and Config.Trails) or nil
		local item = list and findById(list, id)
		if not item then
			return
		end
		local bag = data.Unlocked[kind .. "s"]
		if bag[id] then
			return
		end
		if data.Coins < item.price then
			Remotes.Notify:FireClient(player, "Pas assez de pieces (" .. item.price .. " necessaires).", "danger")
			return
		end
		data.Coins -= item.price
		bag[id] = true
		Remotes.Notify:FireClient(player, item.name .. " debloque !", "gold")
		ProgressionService.SyncStats(player)
	elseif action == "equip" then
		local bag = data.Unlocked[kind .. "s"]
		if not bag or not bag[id] then
			return
		end
		if kind == "aura" then
			data.Aura = id
		elseif kind == "trail" then
			data.Trail = id
		elseif kind == "title" then
			data.Title = id
		end
		ProgressionService.SyncStats(player)
		CharacterService.RefreshCosmetics(player)
	elseif action == "stats" then
		ProgressionService.SyncStats(player)
	end
end

-- Classement en jeu -----------------------------------------------------------

local function updateLeaderboard()
	local label = MapBuilder.LeaderboardLabel
	if not label then
		return
	end
	local entries = {}
	local seen = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(p)
		if data then
			table.insert(entries, { name = p.DisplayName, wins = data.Wins, level = data.Level })
			seen[p.UserId] = true
		end
	end
	for _, entry in ipairs(DataService.GetTopWins(10)) do
		if not seen[entry.userId] then
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(entry.userId)
			end)
			table.insert(entries, { name = ok and name or "???", wins = entry.wins, level = 0 })
		end
	end
	table.sort(entries, function(a, b)
		return a.wins > b.wins
	end)
	local lines = {}
	for i = 1, math.min(10, #entries) do
		local e = entries[i]
		table.insert(lines, string.format("%d. %s  -  %d victoires", i, e.name, e.wins))
	end
	if #lines == 0 then
		lines[1] = "Aucun joueur classe pour l'instant"
	end
	label.Text = table.concat(lines, "\n")
end

function ProgressionService.Init(characterService)
	CharacterService = characterService
	Remotes.Menu.OnServerEvent:Connect(onMenu)
	task.spawn(function()
		while true do
			pcall(updateLeaderboard)
			task.wait(30)
		end
	end)
end

return ProgressionService
