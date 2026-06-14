local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local night = ReplicatedStorage.Night

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
local autoSell = false
local autoSellInventorySize = 100

local noclip = false
local walkSpeed = 16
local jumpHeight = 7.5

local stealTarget = nil
local stealTargetToggled = false

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

local function noclipLoop()
	local character = player.Character
	if character ~= nil then
		for _, child in pairs(character:GetDescendants()) do
			if child:IsA("BasePart") and child.CanCollide == true then
				child.CanCollide = false
			end
		end
	end
end

local function FindFirstDescendantOfClass(parent, className)
	for _, obj in ipairs(parent:GetDescendants()) do
		if obj.ClassName == className then
			return obj
		end
	end
	return nil
end

local function collect(p, maxAtt)
	local char, root = getCharacter()
	if not char or not char:FindFirstChild("Head") then return end
	if not p or not p.Parent then return end

	local prompt = FindFirstDescendantOfClass(p, "ProximityPrompt")
	if not prompt then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	prompt.HoldDuration = 0

	local savedGravity = workspace.Gravity
	workspace.Gravity = 0

	local oldPos = char:GetPivot()
	local targetCF = CFrame.new(
		(p:IsA("Model") and p:GetPivot().Position or p.Position) - Vector3.new(0, 4, 0)
	)

	local conn = RunService.Heartbeat:Connect(function()
		if hrp and hrp.Parent then
			hrp.CFrame = targetCF
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end)

	local att = 0
	while prompt.Parent do
		if att == maxAtt or math.huge() then break end
		att += 1
		fireproximityprompt(prompt)
		noclipLoop()
		task.wait()
	end

	conn:Disconnect()
	char:PivotTo(oldPos)
	workspace.Gravity = savedGravity
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
		if v.m == p then return end
	end
	table.insert(queue, { m = p, t = tier })
	sortQueue()
end

local function loopAdd(f, tier)
	for _, item in pairs(f:GetChildren()) do
		addQueue(item, tier)
	end
end

local function getPlayerList()
	local pt = {}
	for _, p in pairs(game.Players:GetChildren()) do
		if p == player then continue end
		table.insert(pt, p.Name)
	end
	return pt
end

local function getTargetGarden(t)
	local tPlayer = game.Players:FindFirstChild(t)
	if not tPlayer then return end
	local plotId = tPlayer:GetAttribute("PlotId")
	return workspace.Gardens:FindFirstChild("Plot"..plotId)
end

local function getTargetFruit(t)
	local garden = getTargetGarden(t)
	if not garden then return end

	for _, target in pairs(garden.Plants:GetChildren()) do
		local fruits = target:FindFirstChild("Fruits")
		if not fruits then continue end
		for _, targetFruit in pairs(fruits:GetChildren()) do
			local hp = targetFruit:FindFirstChild("HarvestPart")
			if hp and FindFirstDescendantOfClass(hp, "ProximityPrompt") and FindFirstDescendantOfClass(hp, "ProximityPrompt").Enabled == true then
				return targetFruit
			end
		end
	end
end

local function maxInventory()
	local maxSize = player:GetAttribute("MaxFruitCapacity")
	local current = player:GetAttribute("FruitCount")
	return current >= maxSize - 1
end

local function isInGarden(t)
	return game.Players:FindFirstChild(t):GetAttribute("IsInOwnGarden")
end

local function canSteal(t)
	if not isInGarden(t) and night.Value then
		return true
	end
end

task.spawn(function()
	while true do
		if stealTarget and game.Players:FindFirstChild(stealTarget) and stealTargetToggled and canSteal(stealTarget) then
			local item = getTargetFruit(stealTarget)
			if item and item.Parent then
				local ok, err = pcall(collect, item, 10)
				if not ok then warn("collect (steal) error:", err) end
			end
		elseif #queue > 0 then
			local item = table.remove(queue, 1)
			if item and item.m and item.m.Parent then
				local ok, err = pcall(collect, item.m)
				if not ok then warn("collect (queue) error:", err) end
			end
		end

		task.wait()
	end
end)

task.spawn(function()
	while task.wait() do
		if noclip then
			noclipLoop()
		end
		local char, root = getCharacter()
		if char and char:FindFirstChild("Humanoid") then
			local hum = char:FindFirstChild("Humanoid")
			hum.WalkSpeed = walkSpeed
			hum.JumpHeight = jumpHeight
		end
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

local PlayerTab = Window:CreateTab("Player", 4483362458)
local AutoTab = Window:CreateTab("Auto", 4483362458)
local AutoMainSection = AutoTab:CreateSection("Main")
local StealTab = Window:CreateTab("Steal", 4483362458)
local StealTargetSection = StealTab:CreateSection("Target")

local NoclipToggle = PlayerTab:CreateToggle({
	Name = "Noclip",
	CurrentValue = noclip,
	Flag = "noclip",
	Callback = function(Value)
		noclip = Value
	end,
})

local WalkSpeedSlider = PlayerTab:CreateSlider({
   Name = "Walk Speed",
   Range = {0, 100},
   Increment = 1,
   Suffix = nil,
   CurrentValue = walkSpeed,
   Flag = "walkspeedslider",
   Callback = function(Value)
		walkSpeed = Value
   end,
})

local JumpHeightSlider = PlayerTab:CreateSlider({
   Name = "Jump Height",
   Range = {0, 50},
   Increment = 0.5,
   Suffix = nil,
   CurrentValue = jumpHeight,
   Flag = "jumpheightslider",
   Callback = function(Value)
		jumpHeight = Value
   end,
})

local StealTargetSelect = StealTab:CreateDropdown({
	Name = "Select Target",
	Options = {},
	CurrentOption = {},
	MultipleOptions = false,
	Flag = nil,
	Callback = function(Options)
		stealTarget = Options[1]
	end,
})

local StealTargetToggled = StealTab:CreateToggle({
	Name = "Steal Target",
	CurrentValue = stealTargetToggled,
	Flag = "stealtargettoggled",
	Callback = function(Value)
		stealTargetToggled = Value
	end,
})

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

local AutoSellSection = AutoTab:CreateSection("Selling (WIP)")

local AutoSellToggle = AutoTab:CreateToggle({
	Name = "Auto Sell",
	CurrentValue = autoSell,
	Flag = "autosell",
	Callback = function(Value)
		autoSell = Value
	end,
})

local AutoSellSizeSlider = AutoTab:CreateSlider({
   Name = "Sell at",
   Range = {0, 100},
   Increment = 1,
   Suffix = "Fruits",
   CurrentValue = autoSellInventorySize,
   Flag = "autosellinventorysize",
   Callback = function(Value)
		autoSellInventorySize = Value
   end,
})

StealTargetSelect:Refresh(getPlayerList())

game.Players.PlayerAdded:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

game.Players.PlayerRemoving:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

Rayfield:LoadConfiguration()
