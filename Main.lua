local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.SharedModules.Networking)
local SeedData = require(ReplicatedStorage.SharedModules.SeedData)
local GearData = require(ReplicatedStorage.SharedModules.GearShopData)

local night = ReplicatedStorage.Night
local player = game.Players.LocalPlayer

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
local autoBuy = false
local autoBuySelected = {}
local autoBuyGear = false
local autoBuySelectedGear = {}
local noclip = false
local walkSpeed = 16
local jumpHeight = 7.5
local stealTarget = nil
local stealTargetToggled = false

local function waitForAttribute(inst, attr, timeout)
	timeout = timeout or 30
	local t0 = tick()
	local v = inst:GetAttribute(attr)
	while v == nil and tick() - t0 < timeout do
		task.wait(0.5)
		v = inst:GetAttribute(attr)
	end
	return v
end

local Gardens = workspace:WaitForChild("Gardens")
local plotId = waitForAttribute(player, "PlotId")
local plot = Gardens:WaitForChild("Plot" .. tostring(plotId))
local spawnPos = plot:WaitForChild("SpawnPoint")

local queue = {}
local stealBlacklist = setmetatable({}, { __mode = "k" })
local MAX_STEAL_ATT = 15

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
	if character then
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

local function moveTo(hrp, targetCF)
	return RunService.Heartbeat:Connect(function()
		if hrp and hrp.Parent then
			hrp.CFrame = targetCF
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

local function collect(p, maxAtt)
	local char, _ = getCharacter()
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

	local conn = moveTo(hrp, targetCF)

	local att = 0
	local ok, err = pcall(function()
		while prompt.Parent do
			if maxAtt and att >= maxAtt then break end
			att += 1
			fireproximityprompt(prompt)
			noclipLoop()
			task.wait()
		end
	end)

	conn:Disconnect()
	char:PivotTo(oldPos)
	workspace.Gravity = savedGravity

	if not ok then warn("collect loop error:", err) end
end

local function steal(fruit)
	if stealBlacklist[fruit] then return false end
	if not fruit or not fruit.Parent then return false end

	local ownerUserId = tonumber(fruit:GetAttribute("UserId"))
	local plantId = fruit:GetAttribute("PlantId")
	local fruitId = fruit:GetAttribute("FruitId") or ""

	if not ownerUserId or not plantId then
		warn("steal: fehlende Attribute (UserId/PlantId), blacklist")
		stealBlacklist[fruit] = true
		return false
	end

	local char, _ = getCharacter()
	if not char then return false end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local hp = fruit:FindFirstChild("HarvestPart")
	if not hp then
		warn("steal: kein HarvestPart, blacklist")
		stealBlacklist[fruit] = true
		return false
	end

	local savedGravity = workspace.Gravity
	workspace.Gravity = 0
	local oldPos = char:GetPivot()

	local targetCF = CFrame.new(hp.Position - Vector3.new(0, 4, 0))
	local conn = moveTo(hrp, targetCF)

	local success = false
	local att = 0

	local ok, err = pcall(function()
		while fruit.Parent and att < MAX_STEAL_ATT do
			att += 1
			noclipLoop()
			Networking.Steal.BeginSteal:Fire(ownerUserId, plantId, fruitId)
			task.wait(0.1)
			Networking.Steal.CompleteSteal:Fire()
			task.wait(0.4)

			if not fruit.Parent then
				success = true
				break
			end
		end
	end)

	conn:Disconnect()
	char:PivotTo(oldPos)
	workspace.Gravity = savedGravity

	if not ok then
		warn("steal pcall error:", err)
		stealBlacklist[fruit] = true
		return false
	end

	if not success then
		warn("steal: max Versuche erreicht, blacklist")
		stealBlacklist[fruit] = true
	end

	return success
end

local function goToSpawnAndComplete()
	local char, _ = getCharacter()
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local savedGravity = workspace.Gravity
	workspace.Gravity = 0

	local targetCF
	if spawnPos:IsA("BasePart") then
		targetCF = spawnPos.CFrame
	elseif spawnPos:IsA("Model") then
		targetCF = spawnPos:GetPivot()
	else
		warn("goToSpawnAndComplete: unbekannter spawnPos Typ")
		workspace.Gravity = savedGravity
		return
	end

	local conn = moveTo(hrp, targetCF)
	task.wait(0.5)
	Networking.Steal.CompleteSteal:Fire()
	task.wait(0.5)
	conn:Disconnect()
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
	for _, p in pairs(game.Players:GetPlayers()) do
		if p == player then continue end
		table.insert(pt, p.Name)
	end
	return pt
end

local function getSeedList()
	local st = {}
	for _, data in pairs(SeedData) do
		local name = data.SeedName
		if name and data.RestockShop then
			table.insert(st, name)
		end
	end
	return st
end

local function getGearList()
	local st = {}
	for _, data in pairs(GearData) do
		local name = data.ItemName
		if name then
			table.insert(st, name)
		end
	end
	return st
end

local function getTargetGarden(t)
	local tPlayer = game.Players:FindFirstChild(t)
	if not tPlayer then return end
	local pid = tPlayer:GetAttribute("PlotId")
	if not pid then return end
	return Gardens:FindFirstChild("Plot" .. pid)
end

local function getTargetFruit(t)
	local garden = getTargetGarden(t)
	if not garden then return end

	for _, target in pairs(garden.Plants:GetChildren()) do
		local fruits = target:FindFirstChild("Fruits")
		if not fruits then continue end
		for _, targetFruit in pairs(fruits:GetChildren()) do
			if stealBlacklist[targetFruit] then continue end
			local hp = targetFruit:FindFirstChild("HarvestPart")
			if not hp then continue end
			local pp = FindFirstDescendantOfClass(hp, "ProximityPrompt")
			local age = targetFruit:GetAttribute("Age")
			local maxAge = targetFruit:GetAttribute("MaxAge")
			if pp and pp.Enabled and age and maxAge and age >= maxAge then
				return targetFruit
			end
		end
	end
end

local function maxInventory()
	local maxSize = player:GetAttribute("MaxFruitCapacity")
	local current = player:GetAttribute("FruitCount")
	if not maxSize or not current then return false end
	return current >= maxSize - 1
end

local function isInGarden(t)
	local p = game.Players:FindFirstChild(t)
	if not p then return false end
	return p:GetAttribute("IsInOwnGarden") == true
end

local function canSteal(t)
	if not isInGarden(t) and night.Value then
		return true
	end
	return false
end

task.spawn(function()
	while true do
		if stealTargetToggled and stealTarget and game.Players:FindFirstChild(stealTarget) and canSteal(stealTarget) then
			if maxInventory() then
				local ok, err = pcall(goToSpawnAndComplete)
				if not ok then warn("goToSpawnAndComplete error:", err) end
			else
				local item = getTargetFruit(stealTarget)
				if item and item.Parent then
					local ok, err = pcall(steal, item)
					if not ok then
						warn("steal (main loop) error:", err)
						stealBlacklist[item] = true
					end
				end
			end
			task.wait(0.5)
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
		if noclip then noclipLoop() end

		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then
				hum.WalkSpeed = walkSpeed
				hum.JumpHeight = jumpHeight
			end
		end

		if autoSell then
			local invSize = player:GetAttribute("FruitCount")
			if invSize and invSize >= autoSellInventorySize then
				Networking.NPCS.SellAll:Fire()
			end
		end

		if autoBuy then
			for _, name in pairs(autoBuySelected) do
				Networking.SeedShop.PurchaseSeed:Fire(name)
			end
		end

		if autoBuyGear then
			for _, name in pairs(autoBuySelectedGear) do
				Networking.GearShop.PurchaseGear:Fire(name)
			end
		end
	end
end)

dropped.ChildAdded:Connect(function(p)
	if collectDropped then addQueue(p, 1) end
end)

seeds.ChildAdded:Connect(function(p)
	if collectSeeds then addQueue(p, 2) end
end)

local PlayerTab = Window:CreateTab("Player", 4483362458)
local AutoTab = Window:CreateTab("Auto", 4483362458)
local AutoMainSection = AutoTab:CreateSection("Main")
local StealTab = Window:CreateTab("Steal", 4483362458)
local StealTargetSection = StealTab:CreateSection("Target")
local PetTab = Window:CreateTab("Pets", 4483362458)

PlayerTab:CreateToggle({
	Name = "Noclip",
	CurrentValue = noclip,
	Flag = "noclip",
	Callback = function(Value) noclip = Value end,
})

PlayerTab:CreateSlider({
	Name = "Walk Speed",
	Range = {0, 100},
	Increment = 1,
	CurrentValue = walkSpeed,
	Flag = "walkspeedslider",
	Callback = function(Value) walkSpeed = Value end,
})

PlayerTab:CreateSlider({
	Name = "Jump Height",
	Range = {0, 50},
	Increment = 0.5,
	CurrentValue = jumpHeight,
	Flag = "jumpheightslider",
	Callback = function(Value) jumpHeight = Value end,
})

local StealTargetSelect = StealTab:CreateDropdown({
	Name = "Select Target",
	Options = {},
	CurrentOption = {},
	MultipleOptions = false,
	Flag = nil,
	Callback = function(Options)
		stealTarget = Options[1]
		stealBlacklist = setmetatable({}, { __mode = "k" })
	end,
})

StealTab:CreateToggle({
	Name = "Steal Target",
	CurrentValue = stealTargetToggled,
	Flag = "stealtargettoggled",
	Callback = function(Value)
		stealTargetToggled = Value
		if Value then
			stealBlacklist = setmetatable({}, { __mode = "k" })
		end
	end,
})

AutoTab:CreateToggle({
	Name = "Collect Dropped Items",
	CurrentValue = collectDropped,
	Flag = "autocollectdropped",
	Callback = function(Value)
		collectDropped = Value
		if Value then loopAdd(dropped, 1) else removeTier(1) end
	end,
})

AutoTab:CreateToggle({
	Name = "Collect Seeds",
	CurrentValue = collectSeeds,
	Flag = "autocollectseeds",
	Callback = function(Value)
		collectSeeds = Value
		if Value then loopAdd(seeds, 2) else removeTier(2) end
	end,
})

AutoTab:CreateSection("Selling")

AutoTab:CreateToggle({
	Name = "Auto Sell",
	CurrentValue = autoSell,
	Flag = "autosell",
	Callback = function(Value) autoSell = Value end,
})

AutoTab:CreateSlider({
	Name = "Sell at",
	Range = {0, 100},
	Increment = 1,
	Suffix = "Fruits",
	CurrentValue = autoSellInventorySize,
	Flag = "autosellinventorysize",
	Callback = function(Value) autoSellInventorySize = Value end,
})

AutoTab:CreateSection("Buying")

AutoTab:CreateToggle({
	Name = "Auto Buy Seeds",
	CurrentValue = autoBuy,
	Flag = "autobuyseeds",
	Callback = function(Value) autoBuy = Value end,
})

AutoTab:CreateDropdown({
	Name = "Select Seeds",
	Options = getSeedList(),
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "autobuyselected",
	Callback = function(Options) autoBuySelected = Options end,
})

AutoTab:CreateToggle({
	Name = "Auto Buy Gear",
	CurrentValue = autoBuyGear,
	Flag = "autobuygear",
	Callback = function(Value) autoBuyGear = Value end,
})

AutoTab:CreateDropdown({
	Name = "Select Gear",
	Options = getGearList(),
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "autobuygearselected",
	Callback = function(Options) autoBuySelectedGear = Options end,
})

StealTargetSelect:Refresh(getPlayerList())

game.Players.PlayerAdded:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

game.Players.PlayerRemoving:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

Rayfield:LoadConfiguration()
