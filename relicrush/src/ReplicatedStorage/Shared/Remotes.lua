-- RemoteEvents / RemoteFunctions de RELIC RUSH (crees par le serveur).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = { "Action", "Sync", "Notify", "FX", "Trade", "Boss" }
local FUNCTIONS = { "Query" }

local Remotes = {}
local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, n in ipairs(EVENTS) do
		if not folder:FindFirstChild(n) then
			Instance.new("RemoteEvent", folder).Name = n
		end
	end
	for _, n in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(n) then
			Instance.new("RemoteFunction", folder).Name = n
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end
for _, n in ipairs(EVENTS) do
	Remotes[n] = folder:WaitForChild(n)
end
for _, n in ipairs(FUNCTIONS) do
	Remotes[n] = folder:WaitForChild(n)
end
return Remotes
