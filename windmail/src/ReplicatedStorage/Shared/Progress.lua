-- Calculs partages client/serveur : rang a partir de l'XP, bonus de collection, format.
local Config = require(script.Parent.Config)

local Progress = {}

function Progress.XPForLevel(n)
	return math.floor(Config.Rank.Base * n ^ Config.Rank.Exponent)
end

-- renvoie rang, xp dans le rang, xp necessaire pour le suivant
function Progress.RankFromXP(xp)
	local rank = 1
	while rank < Config.Rank.Max do
		local need = Progress.XPForLevel(rank)
		if xp < need then
			return rank, xp, need
		end
		xp -= need
		rank += 1
	end
	return rank, 0, 1
end

function Progress.Title(rank)
	local title = Config.RankTitles[1][2]
	for _, t in ipairs(Config.RankTitles) do
		if rank >= t[1] then
			title = t[2]
		end
	end
	return title
end

-- Sets de timbres completes et bonus cumules
function Progress.SetBonuses(stamps)
	local coin, xp, trails, done = 0, 0, {}, {}
	for _, set in ipairs(Config.StampSets) do
		local complete = true
		for _, s in ipairs(Config.Stamps) do
			if s.set == set.id and not (stamps and stamps[s.id]) then
				complete = false
				break
			end
		end
		if complete then
			done[set.id] = true
			coin += set.coinBonus or 0
			xp += set.xpBonus or 0
			if set.trail then
				trails[set.trail] = true
			end
		end
	end
	return { coin = coin, xp = xp, trails = trails, done = done }
end

function Progress.Format(n)
	n = math.floor(n or 0)
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fk", n / 1e3)
	end
	local s = tostring(n)
	return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

return Progress
