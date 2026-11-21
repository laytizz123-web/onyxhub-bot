-- Panneau du classement global dans la poste (top 10 des livraisons).
local CollectionService = game:GetService("CollectionService")
local DataService = require(script.Parent.DataService)
local Progress = require(game:GetService("ReplicatedStorage").Shared.Progress)

local BoardService = {}

local function render(board)
	local gui = board:FindFirstChild("Board") or Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = gui
	local function line(text, color, h)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, h or 26)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color
		l.Text = text
		l.Parent = gui
	end
	line("MEILLEURS FACTEURS", Color3.fromRGB(255, 215, 120), 40)
	local top = DataService.GetTop()
	if #top == 0 then
		line("Classement en cours de chargement...", Color3.fromRGB(200, 205, 215))
	end
	for _, e in ipairs(top) do
		line(e.rank .. ".  " .. e.name .. "  -  " .. Progress.Format(e.value) .. " livraisons", e.rank <= 3 and Color3.fromRGB(255, 235, 180) or Color3.fromRGB(225, 230, 240))
	end
	gui.Parent = board
end

function BoardService.Init()
	task.spawn(function()
		while true do
			for _, b in ipairs(CollectionService:GetTagged("TopBoard")) do
				pcall(render, b)
			end
			task.wait(60)
		end
	end)
end

return BoardService
