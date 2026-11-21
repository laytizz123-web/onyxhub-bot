-- RemoteEvents de Windmail (crees par le serveur, recuperes par le client).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = { "Request", "Sync", "Notify", "FX", "Event", "Parcels" }
local Remotes = {}
local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, n in ipairs(NAMES) do
		if not folder:FindFirstChild(n) then
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end
for _, n in ipairs(NAMES) do
	Remotes[n] = folder:WaitForChild(n)
end
return Remotes
