local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local RunService = game:GetService("RunService")

local player = game.Players.LocalPlayer
local cam = workspace.CurrentCamera

local function getCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart")
	return char, root
end

local dropped = workspace.DroppedItems
local seeds = workspace.Map.SeedPackSpawnServerLocations

local collectSeeds = false
local collectDropped = false
local movingConnection = nil
local oldPos = nil
local queue = {}

local Window = Rayfield:CreateWindow({
	Name = "Gag2 Hub",
	Icon = 0, 
	LoadingTitle = "Gag2 Hub",
	LoadingSubtitle = "tuff",
	ShowText = "Rayfield", 
	Theme = "Amethyst",

	ToggleUIKeybind = "K", 

	ConfigurationSaving = {
		Enabled = true,
		FolderName = nil,
		FileName = "g2h"
	},
})

Rayfield:Notify({
	Title = "Loading...",
	Content = "Please wait.",
	Duration = 5,
	Image = 4483362458,
})

local AutoTab = Window:CreateTab("Auto", 4483362458)
local AutoMainSection = AutoTab:CreateSection("Main")

local function FindFirstDescendantOfClass(parent, className)
	for _, obj in ipairs(parent:GetDescendants()) do
		if obj.ClassName == className then
			return obj
		end
	end

	return nil
end

local function collect(p)
	local char, root = getCharacter()

	if not p or not p.Parent then
		return
	end

	local prompt = FindFirstDescendantOfClass(p, "ProximityPrompt")
	if not prompt then return end

	while prompt.Parent do
		prompt.HoldDuration = 0

		local oldPos = char:GetPivot()
		local targetPos = p:IsA("Model") and p:GetPivot().Position or p.Position
		char:PivotTo(CFrame.new(targetPos - Vector3.new(0, 4, 0)))
		task.wait(.05)
		fireproximityprompt(prompt)
	end
	
	char:PivotTo(oldPos)
end

local function sortQueue()
	table.sort(queue, function(a, b)
		return a.t > b.t
	end)
end

local function removeTier(tier)
	for i = #queue, 1, -1 do
		if queue[i].t == tier then
			table.remove(queue, i)
		end
	end
end

local function addQueue(p, tier)
	for _, v in ipairs(queue) do
		if v.m == p then
			return
		end
	end

	table.insert(queue, {
		m = p,
		t = tier
	})

	sortQueue()
end

local function loopAdd(f, tier)
	for _, item in pairs(f:GetChildren()) do
		addQueue(item, tier)
	end
end

task.spawn(function()
	while true do
		for i, v in pairs(queue) do
			print(i, v.t)
		end

		if #queue > 0 then
			local item = table.remove(queue, 1)

			if item and item.m and item.m.Parent then
				collect(item.m)
			end
		end

		task.wait(0.1)
	end
end)

dropped.ChildAdded:Connect(function(p)
	if collectDropped then
		addQueue(p, 1)
	end
end)

seeds.ChildAdded:Connect(function(p)
	if collectSeeds then
		addQueue(p, 2)
	end
end)

local AutoCollectDroppedToggle = AutoTab:CreateToggle({
	Name = "Collect Dropped Items",
	CurrentValue = collectDropped,
	Flag = "autocollectdropped",
	Callback = function(Value)
		collectDropped = Value
		if Value then
			loopAdd(dropped, 1)
		else
			removeTier(1)
		end
	end,
})

local AutoCollectSeedsToggle = AutoTab:CreateToggle({
	Name = "Collect Seeds",
	CurrentValue = collectSeeds,
	Flag = "autocollectseeds",
	Callback = function(Value)
		collectSeeds = Value
		if Value then
			loopAdd(seeds, 2)
		else
			removeTier(2)
		end
	end,
})

Rayfield:LoadConfiguration()
