local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.SharedModules.Networking)
local SeedData = require(ReplicatedStorage.SharedModules.SeedData)
local SellValueData = require(ReplicatedStorage.SharedModules.SellValueData)

local MutationData
do
	local mutationMultipliers = {}
	local mutationNames = {"Gold", "Rainbow", "Electric", "Frozen", "Bloodlit", "Chained", "Starstruck"}
	local MutationDataFolder = ReplicatedStorage.SharedModules.MutationData

	for _, name in ipairs(mutationNames) do
		local subModule = MutationDataFolder:FindFirstChild(name)
		if subModule then
			local ok, result = pcall(require, subModule)
			if ok and result and result.PriceMultiplier then
				mutationMultipliers[name] = result.PriceMultiplier
			else
				warn("MutationData: Sub-Modul", name, "fehlgeschlagen, Fallback 1x")
				mutationMultipliers[name] = 1
			end
		end
	end

	MutationData = {
		ReturnPriceMultiplier = function(mutation)
			if not mutation or mutation == "" then return 1 end
			return mutationMultipliers[mutation] or 1
		end
	}
end

local singleHarvestPlants = {}
for _, data in SeedData do
	if data.SeedName then
		singleHarvestPlants[data.SeedName] = data.IsSingleHarvest == true
	end
end

local SIZE_EXPONENT_OVERRIDES = { Mushroom = 1.9, Bamboo = 1.75 }
local MIN_VALUES = { Carrot = 4 }

local function calcFruitValue(fruitName, sizeMultiplier, mutation, playerInst, decayAlpha)
	local exponent = SIZE_EXPONENT_OVERRIDES[fruitName] or 2.65
	local sizeScore = (sizeMultiplier or 1) ^ exponent

	local mutMult = 1
	if mutation and mutation ~= "" then
		local rawMult = MutationData.ReturnPriceMultiplier(mutation)
		if singleHarvestPlants[fruitName] and rawMult > 1 then
			mutMult = 1 + (rawMult - 1) * 0.25
		else
			mutMult = rawMult
		end
	end

	local decayMult = 1
	if typeof(decayAlpha) == "number" and decayAlpha > 0 then
		decayMult = 1 - math.clamp(decayAlpha, 0, 1) * 0.8
	end

	local friendsMult = 1 + (playerInst:GetAttribute("Friends") or 0) * 0.1
	local base = SellValueData[fruitName] or 0
	local result = math.floor(base * sizeScore * mutMult * decayMult * friendsMult)

	local minVal = MIN_VALUES[fruitName]
	return minVal and math.max(result, minVal) or result
end

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
local autoCollect = false
local noclip = false
local walkSpeed = 16
local jumpHeight = 7.5
local stealTarget = nil
local stealTargetToggled = false
local antiSteal = false
local stealBest = false

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

local CACHE_TTL = 8
local valueCache = setmetatable({}, { __mode = "k" })

local function resetStealState()
	stealBlacklist = setmetatable({}, { __mode = "k" })
	valueCache = setmetatable({}, { __mode = "k" })
end

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

local function calculateStealDuration(fruit)
	local seedName = fruit:GetAttribute("CorePartName") or "Carrot"
	local age = fruit:GetAttribute("Age") or 1
	local mutation = fruit:GetAttribute("Mutation")

	if true then return 0 end

	local sellValue = SellValueData[seedName]
	if not sellValue then
		warn("calculateStealDuration: kein SellValue für", seedName, "→ fallback 5s")
		return 5
	end

	local v2 = math.floor(sellValue * age ^ 3)
	if mutation and mutation ~= "" then
		v2 = v2 * MutationData.ReturnPriceMultiplier(mutation)
	end

	return math.sqrt(v2)
end

local function getFruitValue(fruit)
	local cached = valueCache[fruit]
	if cached and os.clock() - cached.t < CACHE_TTL then
		return cached.v
	end

	local name = fruit:GetAttribute("CorePartName")
	if not name then return 0 end

	local size = fruit:GetAttribute("SizeMultiplier") or 1
	local mutation = fruit:GetAttribute("Mutation")
	local decay = fruit:GetAttribute("DecayAlpha")

	local v = calcFruitValue(name, size, mutation, player, decay)

	valueCache[fruit] = { v = v, t = os.clock() }
	return v
end

local function isValidFruit(fruit)
	if stealBlacklist[fruit] then return false end
	local hp = fruit:FindFirstChild("HarvestPart")
	if not hp then return false end
	local pp = FindFirstDescendantOfClass(hp, "ProximityPrompt")
	local age = fruit:GetAttribute("Age")
	local maxAge = fruit:GetAttribute("MaxAge")
	return pp ~= nil and pp.Enabled and age ~= nil and maxAge ~= nil and age >= maxAge
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
		warn("steal: fehlende Attribute, blacklist")
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

	local duration = calculateStealDuration(fruit) + 0.1

	local savedGravity = workspace.Gravity
	workspace.Gravity = 0
	local oldPos = char:GetPivot()

	local targetCF = CFrame.new(hp.Position)
	local conn = moveTo(hrp, targetCF)
	local pp = FindFirstDescendantOfClass(hp, "ProximityPrompt")

	local success = false
	local prevPar = fruit.Parent
	local startTime = os.clock()
	print(duration)

	local ok, err = pcall(function()
		while fruit.Parent and fruit.Parent == prevPar do
			if os.clock() - startTime >= duration then
				success = true
				break
			end

			noclipLoop()
			fireproximityprompt(pp)
			Networking.Steal.BeginSteal:Fire(ownerUserId, plantId, fruitId)
			task.wait()

			if not fruit.Parent or fruit.Parent ~= prevPar then
				success = true
				break
			end
		end
	end)

	warn("Finished")

	conn:Disconnect()
	char:PivotTo(oldPos)
	workspace.Gravity = savedGravity
	valueCache[fruit] = nil

	if not ok then
		warn("steal pcall error:", err)
		stealBlacklist[fruit] = true
		return false
	end

	if not success then
		warn("steal: fehlgeschlagen, blacklist")
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
	task.wait()
	Networking.Steal.CompleteSteal:Fire()
	task.wait()
	conn:Disconnect()
	workspace.Gravity = savedGravity
end

local function sortQueue()
	table.sort(queue, function(a, b)
		return a.t < b.t
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
	for _, data in pairs(ReplicatedStorage.StockValues.GearShop.Items:GetChildren()) do
		local name = data.Name
		if name then table.insert(st, name) end
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

	if stealBest then
		local best = nil
		local bestValue = -1

		for _, target in pairs(garden.Plants:GetChildren()) do
			local fruits = target:FindFirstChild("Fruits")
			if not fruits then continue end
			for _, targetFruit in pairs(fruits:GetChildren()) do
				if not isValidFruit(targetFruit) then continue end
				local value = getFruitValue(targetFruit)
				if value > bestValue then
					bestValue = value
					best = targetFruit
				end
			end
		end

		return best
	else
		for _, target in pairs(garden.Plants:GetChildren()) do
			local fruits = target:FindFirstChild("Fruits")
			if not fruits then continue end
			for _, targetFruit in pairs(fruits:GetChildren()) do
				if isValidFruit(targetFruit) then
					return targetFruit
				end
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
	if not isInGarden(t) and night.Value then return true end
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
						valueCache[item] = nil
					end
					local ok2, err2 = pcall(goToSpawnAndComplete)
					if not ok2 then warn("goToSpawnAndComplete error:", err2) end
				end
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
local StealMainSection = StealTab:CreateSection("Main")
local PetTab = Window:CreateTab("Pets", 4483362458)
local PetBuySection = PetTab:CreateSection("Auto Buy")
local VisualTab = Window:CreateTab("Visual", 4483362458)
local VisualEspSection = VisualTab:CreateSection("ESP")

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

StealTab:CreateToggle({
	Name = "Steal Best",
	CurrentValue = stealBest,
	Flag = "stealbesttoggled",
	Callback = function(Value)
		stealBest = Value
		valueCache = setmetatable({}, { __mode = "k" })
	end,
})

local StealTargetSection = StealTab:CreateSection("Target")

local StealTargetSelect = StealTab:CreateDropdown({
	Name = "Select Target",
	Options = {},
	CurrentOption = {},
	MultipleOptions = false,
	Flag = nil,
	Callback = function(Options)
		stealTarget = Options[1]
		resetStealState()
	end,
})

StealTab:CreateToggle({
	Name = "Steal Target",
	CurrentValue = stealTargetToggled,
	Flag = "stealtargettoggled",
	Callback = function(Value)
		stealTargetToggled = Value
		if Value then resetStealState() end
	end,
})

local StealAntiSection = StealTab:CreateSection("Anti")

StealTab:CreateToggle({
	Name = "Anti Steal (WIP)",
	CurrentValue = antiSteal,
	Flag = "antistealtoggled",
	Callback = function(Value) antiSteal = Value end,
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

AutoTab:CreateSection("Own")

AutoTab:CreateToggle({
	Name = "Auto Collect Fruits",
	CurrentValue = autoCollect,
	Flag = "autocollect",
	Callback = function(Value) autoCollect = Value end,
})

StealTargetSelect:Refresh(getPlayerList())

game.Players.PlayerAdded:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

game.Players.PlayerRemoving:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

Rayfield:LoadConfiguration()
