local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local Networking = require(ReplicatedStorage.SharedModules.Networking)
local SeedData = require(ReplicatedStorage.SharedModules.SeedData)
local SellValueData = require(ReplicatedStorage.SharedModules.SellValueData)
-- FastFlags + Asserts sind gecacht → kein Crash
local FastFlags = require(ReplicatedStorage.UserGenerated.FastFlags)
local Asserts = require(ReplicatedStorage.UserGenerated.Lang.Asserts)

-- MutationData: Sub-Module direkt requiren (kein FastFlags-Crash)
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
				warn("MutationData:", name, "fehlgeschlagen, Fallback 1x")
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

-- FruitValueCalc: originale Logik inline, MutationData durch lokale Version ersetzt
local FruitValueCalc
do
	local fv1 = FastFlags.Replicated("Game.Selling.SizeMultiplier", Asserts.FinitePositive, 1)
	local fv2 = FastFlags.Replicated("Game.Selling.MutationMultiplier", Asserts.FinitePositive, 1)
	local fv3 = FastFlags.Replicated("Game.Selling.SizeExponent", Asserts.FinitePositive, 2.65)
	local fv4 = FastFlags.Replicated("Game.Selling.SizeExponentOverrides", Asserts.Map(Asserts.String, Asserts.FinitePositive), {
		Mushroom = 1.9,
		Bamboo = 1.75
	})
	local fv5 = FastFlags.Replicated("Game.Selling.SingleHarvestMutationBonusScale", Asserts.FiniteNonNegative, 0.15)
	local fv6 = FastFlags.Replicated("Game.Selling.SizeDiminishingReturns.Enabled", Asserts.Boolean, true)
	local fv7 = FastFlags.Replicated("Game.Selling.SizeDiminishingReturns.Knee", Asserts.FinitePositive, 5)
	local fv8 = FastFlags.Replicated("Game.Selling.SizeDiminishingReturns.TailExponent", Asserts.FinitePositive, 1.5)

	local singleHarvest = {}
	local kneeMultipliers = {}
	local tailExponentMultipliers = {}
	local minValues = { Carrot = 4 }

	for _, data in SeedData do
		if data.SeedName then
			singleHarvest[data.SeedName] = data.IsSingleHarvest == true
			kneeMultipliers[data.SeedName] = 1
			tailExponentMultipliers[data.SeedName] = 1
		end
	end

	local fv12 = FastFlags.Replicated("Game.Selling.SizeDiminishingReturns.KneeMultipliers", Asserts.Map(Asserts.String, Asserts.FinitePositive), kneeMultipliers)
	local fv13 = FastFlags.Replicated("Game.Selling.SizeDiminishingReturns.TailExponentMultipliers", Asserts.Map(Asserts.String, Asserts.FinitePositive), tailExponentMultipliers)

	-- Identisch zum Original, nur MutationData → lokale Version
	FruitValueCalc = function(p1, p2, p3, p4, p5)
		local v22 = fv4:Get()[p1] or fv3:Get()
		local v32 = p2 ^ v22
		if fv6:Get() then
			local v42 = fv7:Get() * (fv12:Get()[p1] or 1)
			if v42 < p2 then
				v32 = v42 ^ v22 * (p2 / v42) ^ math.min(fv8:Get() * (fv13:Get()[p1] or 1), v22)
			end
		end
		local v72 = fv1:Get()
		local v82
		if p3 then
			local v9 = MutationData.ReturnPriceMultiplier(p3)  -- lokale Version
			local v10 = if singleHarvest[p1] and v9 > 1 then 1 + (v9 - 1) * fv5:Get() else v9
			v82 = v10 * fv2:Get()
		else
			v82 = 1
		end
		local v11 = if typeof(p5) == "number" and p5 > 0 then 1 - math.clamp(p5, 0, 1) * 0.8 else 1
		local v122 = 1 + (p4:GetAttribute("Friends") or 0) * 0.1
		local v132 = minValues[p1]
		local v142 = math.floor((SellValueData[p1] or 0) * v32 * v72 * v82 * v11 * v122)
		return if v132 then if v142 < v132 then v132 else v142 else v142
	end
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
local autoBuyPets = false
local autoBuySelectedPet = {}

local autoCollect = false
local collectMutation = false
local autoCollectMinValue = 0
local autoCollectMaxValue = 1000000

local espEnabled = false
local espMinValue = 0
local activeESPs = {}
local espParent = pcall(function() return CoreGui.Name end) and CoreGui or player:WaitForChild("PlayerGui")

if espParent:FindFirstChild("G2HFruitESP") then
	espParent.G2HFruitESP:Destroy()
end
local espFolder = Instance.new("Folder")
espFolder.Name = "G2HFruitESP"
espFolder.Parent = espParent

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
local stealBlacklistIds = {}

local CACHE_TTL = 8
local valueCache = setmetatable({}, { __mode = "k" })

local function resetStealState()
	stealBlacklist = setmetatable({}, { __mode = "k" })
	stealBlacklistIds = {}
	valueCache = setmetatable({}, { __mode = "k" })
end

local Window = Rayfield:CreateWindow({
	Name = "Gag2 Hub",
	Icon = 0,
	LoadingTitle = "Gag2 Hub",
	LoadingSubtitle = "By Someone",
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
	if true then return 0.6 end

	local seedName = fruit:GetAttribute("CorePartName") or "Carrot"
	local age = fruit:GetAttribute("Age") or 1
	local mutation = fruit:GetAttribute("Mutation")
	local sellValue = SellValueData[seedName]
	if not sellValue then return 5 end

	local v2 = math.floor(sellValue * age)
	if mutation and mutation ~= "" then
		v2 = v2 * MutationData.ReturnPriceMultiplier(mutation)
	end
	return math.clamp(math.sqrt(v2) * 0.05, 0.5, 5)
end

local function getFruitValue(fruit)
	local cached = valueCache[fruit]
	if cached and os.clock() - cached.t < CACHE_TTL then
		return cached.v
	end

	local name = fruit:GetAttribute("CorePartName") or fruit:GetAttribute("SeedName")
	if not name then return 0 end

	local size = fruit:GetAttribute("SizeMultiplier") or fruit:GetAttribute("Scale") or 1
	local mutation = fruit:GetAttribute("Mutation")
	local decay = fruit:GetAttribute("DecayAlpha")

	local ok, v = pcall(FruitValueCalc, name, size, mutation, player, decay)
	v = (ok and type(v) == "number") and v or 0

	valueCache[fruit] = { v = v, t = os.clock() }
	return v
end

local function isValidFruit(fruit)
	if stealBlacklist[fruit] then return false end
	local fId = fruit:GetAttribute("FruitId")
	if fId and stealBlacklistIds[fId] then return false end
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
	if not isValidFruit(fruit) then return false end
	if not fruit or not fruit.Parent then return false end

	local ownerUserId = tonumber(fruit:GetAttribute("UserId"))
	local plantId = fruit:GetAttribute("PlantId")
	local fruitId = fruit:GetAttribute("FruitId") or ""

	if not ownerUserId or not plantId then
		warn("steal: fehlende Attribute, blacklist")
		stealBlacklist[fruit] = true
		stealBlacklistIds[fruitId] = true
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
		stealBlacklistIds[fruitId] = true
		return false
	end

	local pp = FindFirstDescendantOfClass(hp, "ProximityPrompt")
	if not pp then
		warn("steal: kein ProximityPrompt, blacklist")
		stealBlacklist[fruit] = true
		stealBlacklistIds[fruitId] = true
		return false
	end

	pp.HoldDuration = 0

	local duration = calculateStealDuration(fruit) + 0.5
	local savedGravity = workspace.Gravity
	workspace.Gravity = 0
	local oldPos = char:GetPivot()
	local targetCF = CFrame.new(hp.Position)
	local conn = moveTo(hrp, targetCF)

	local success = false
	local prevPar = fruit.Parent
	local startTime = os.clock()

	local ok, err = pcall(function()
		while fruit.Parent and fruit.Parent == prevPar do
			if os.clock() - startTime >= duration then
				success = true
				break
			end
			noclipLoop()
			Networking.Steal.BeginSteal:Fire(ownerUserId, plantId, fruitId)
			fireproximityprompt(pp)
			task.wait()
			if not fruit.Parent or fruit.Parent ~= prevPar then
				success = true
				break
			end
		end
	end)

	conn:Disconnect()
	char:PivotTo(oldPos)
	workspace.Gravity = savedGravity
	valueCache[fruit] = nil

	if not ok then
		warn("steal pcall error:", err)
		stealBlacklist[fruit] = true
		stealBlacklistIds[fruitId] = true
		return false
	end

	if not success then
		warn("steal: fehlgeschlagen, blacklist")
		stealBlacklist[fruit] = true
		stealBlacklistIds[fruitId] = true
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
	local ok, items = pcall(function()
		return ReplicatedStorage.StockValues.GearShop.Items:GetChildren()
	end)
	if ok and items then
		for _, data in pairs(items) do
			if data.Name then table.insert(st, data.Name) end
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

local function isInGarden(t)
	local p = game.Players:FindFirstChild(t)
	if not p then return false end
	return p:GetAttribute("IsInOwnGarden") == true
end

local function canSteal(t)
	if not isInGarden(t) and night.Value then return true end
	return false
end

local function getTargetFruit(t)
	if stealBest then
		local best = nil
		local bestValue = -1

		for _, plr in pairs(game.Players:GetChildren()) do
			if plr == player then continue end
			if not canSteal(plr.Name) then continue end
			local garden = getTargetGarden(plr.Name)
			if not garden then continue end

			for _, target in pairs(garden.Plants:GetChildren()) do
				local fruits = target:FindFirstChild("Fruits")
				if fruits then
					for _, targetFruit in pairs(fruits:GetChildren()) do
						if not isValidFruit(targetFruit) then continue end
						local value = getFruitValue(targetFruit)
						if value > bestValue then
							bestValue = value
							best = targetFruit
						end
					end
				else
					if not isValidFruit(target) then continue end
					local value = getFruitValue(target)
					if value > bestValue then
						bestValue = value
						best = target
					end
				end
			end
		end

		return best
	else
		local garden = getTargetGarden(t)
		if not garden then return end

		for _, target in pairs(garden.Plants:GetChildren()) do
			local fruits = target:FindFirstChild("Fruits")
			if fruits then
				for _, targetFruit in pairs(fruits:GetChildren()) do
					if isValidFruit(targetFruit) then return targetFruit end
				end
			else
				if isValidFruit(target) then return target end
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

local function sellAll()
	if not autoSell then return end
	local invSize = player:GetAttribute("FruitCount")
	if invSize and invSize >= autoSellInventorySize then
		Networking.NPCS.SellAll:Fire()
	end
end
player:GetAttributeChangedSignal("FruitCount"):Connect(sellAll)

local function buySeeds(name, amt)
	if autoBuy and table.find(autoBuySelected, name) then
		for i = 1, amt do
			Networking.SeedShop.PurchaseSeed:Fire(name)
		end
	end
end

local function buyGear(name, amt)
	if autoBuyGear and table.find(autoBuySelectedGear, name) then
		for i = 1, amt do
			Networking.GearShop.PurchaseGear:Fire(name)
		end
	end
end

-- Fix: v.:GetAttributeChangedSignal → v:GetAttributeChangedSignal
for _, v in pairs(ReplicatedStorage.StockValues.GearShop.Items:GetChildren()) do
	v:GetAttributeChangedSignal("Value"):Connect(function()
		buyGear(v.Name, v:GetAttribute("Value") or 0)
	end)
end

for _, v in pairs(ReplicatedStorage.StockValues.SeedShop.Items:GetChildren()) do
	v:GetAttributeChangedSignal("Value"):Connect(function()
		buySeeds(v.Name, v:GetAttribute("Value") or 0)
	end)
end

-- Steal/Queue Loop
task.spawn(function()
	while true do
		local isStealActive = (stealTargetToggled and stealTarget and game.Players:FindFirstChild(stealTarget) and canSteal(stealTarget)) or stealBest

		if isStealActive then
			if maxInventory() then
				local ok, err = pcall(goToSpawnAndComplete)
				if not ok then warn("goToSpawnAndComplete error:", err) end
				task.wait(1)
			else
				local item = getTargetFruit(stealTarget)
				if item and item.Parent then
					local fruitId = item:GetAttribute("FruitId")
					local ok, err = pcall(steal, item)
					if not ok then
						warn("steal (main loop) error:", err)
						stealBlacklist[item] = true
						if fruitId then stealBlacklistIds[fruitId] = true end
						valueCache[item] = nil
					end
					local ok2, err2 = pcall(goToSpawnAndComplete)
					if not ok2 then warn("goToSpawnAndComplete error:", err2) end
				else
					task.wait(0.5)
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

-- Utility Loop
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

		if autoCollect and plot then
			local pPlants = plot:FindFirstChild("Plants")
			if pPlants and not maxInventory() then
				for _, plant in pairs(pPlants:GetChildren()) do
					if not autoCollect then break end
					local fruits = plant:FindFirstChild("Fruits")
					if fruits then
						for _, fruit in pairs(fruits:GetChildren()) do
							if not autoCollect then break end
							local age = fruit:GetAttribute("Age") or 0
							local maxAge = fruit:GetAttribute("MaxAge") or 1
							local mutation = fruit:GetAttribute("Mutation")
							local hasMutation = mutation and mutation ~= ""
							if age >= maxAge and (not collectMutation or hasMutation) then
								local val = getFruitValue(fruit)
								if val >= autoCollectMinValue and val <= autoCollectMaxValue then
									local fId = fruit:GetAttribute("FruitId")
									local pId = fruit:GetAttribute("PlantId")
									if fId and pId then
										Networking.Garden.CollectFruit:Fire(pId, fId)
										task.wait(0.05)
									end
								end
							end
						end
					else
						local fruit = plant
						local age = fruit:GetAttribute("Age") or 0
						local maxAge = fruit:GetAttribute("MaxAge") or 1
						local mutation = fruit:GetAttribute("Mutation")
						local hasMutation = mutation and mutation ~= ""
						if age >= maxAge and (not collectMutation or hasMutation) then
							local val = getFruitValue(fruit)
							if val >= autoCollectMinValue and val <= autoCollectMaxValue then
								local pId = fruit:GetAttribute("PlantId")
								if pId then
									Networking.Garden.CollectFruit:Fire(pId, "")
									task.wait(0.05)
								end
							end
						end
					end
				end
			end
		end
	end
end)

-- ESP
local function createEsp(fruit)
	local val = getFruitValue(fruit)
	if val >= espMinValue then
		if not activeESPs[fruit] then
			local bg = Instance.new("BillboardGui")
			bg.Adornee = fruit:FindFirstChild("HarvestPart") or fruit
			bg.Size = UDim2.new(0, 100, 0, 50)
			bg.StudsOffset = Vector3.new(0, 2, 0)
			bg.AlwaysOnTop = true

			local tl = Instance.new("TextLabel")
			tl.Name = "ValueLabel"
			tl.Parent = bg
			tl.Size = UDim2.new(1, 0, 1, 0)
			tl.BackgroundTransparency = 1
			tl.TextColor3 = Color3.new(0.3, 1, 0.3)
			tl.TextStrokeTransparency = 0
			tl.Text = "Val: " .. tostring(val)
			tl.Font = Enum.Font.GothamBold
			tl.TextSize = 14

			bg.Parent = espFolder
			activeESPs[fruit] = bg
		else
			local tl = activeESPs[fruit]:FindFirstChild("ValueLabel")
			if tl then tl.Text = "Val: " .. tostring(val) end
		end
	end
end

task.spawn(function()
	while task.wait(0.5) do
		local toRemove = {}
		for fruit, gui in pairs(activeESPs) do
			if not espEnabled or not fruit or not fruit.Parent or getFruitValue(fruit) < espMinValue then
				table.insert(toRemove, fruit)
			end
		end
		for _, fruit in ipairs(toRemove) do
			if activeESPs[fruit] then
				activeESPs[fruit]:Destroy()
				activeESPs[fruit] = nil
			end
		end

		if espEnabled then
			for _, garden in pairs(Gardens:GetChildren()) do
				local plants = garden:FindFirstChild("Plants")
				if plants then
					for _, plant in pairs(plants:GetChildren()) do
						local fruits = plant:FindFirstChild("Fruits")
						if fruits then
							for _, fruit in pairs(fruits:GetChildren()) do
								createEsp(fruit)
							end
						else
							createEsp(plant)
						end
					end
				end
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

-- UI
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
	Callback = function(Value)
		autoSell = Value
		if autoSell then sellAll() end
	end,
})

AutoTab:CreateSlider({
	Name = "Sell at",
	Range = {1, 100},
	Increment = 1,
	Suffix = "Fruits",
	CurrentValue = autoSellInventorySize,
	Flag = "autosellinventorysize",
	Callback = function(Value)
		autoSellInventorySize = Value
		if autoSell then sellAll() end
	end,
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
	Name = "Auto Collect Own Fruits",
	CurrentValue = autoCollect,
	Flag = "autocollect",
	Callback = function(Value) autoCollect = Value end,
})

AutoTab:CreateToggle({
	Name = "Requires Mutation",
	CurrentValue = collectMutation,
	Flag = "collectmutation",
	Callback = function(Value) collectMutation = Value end,
})

AutoTab:CreateSlider({
	Name = "Min Value",
	Range = {0, 100000},
	Increment = 10,
	CurrentValue = autoCollectMinValue,
	Flag = "autocollectmin",
	Callback = function(Value) autoCollectMinValue = Value end,
})

AutoTab:CreateSlider({
	Name = "Max Value",
	Range = {0, 1000000},
	Increment = 100,
	CurrentValue = autoCollectMaxValue,
	Flag = "autocollectmax",
	Callback = function(Value) autoCollectMaxValue = Value end,
})

VisualTab:CreateToggle({
	Name = "Enable Fruit ESP",
	CurrentValue = espEnabled,
	Flag = "fruitesp",
	Callback = function(Value) espEnabled = Value end,
})

VisualTab:CreateSlider({
	Name = "ESP Min Value",
	Range = {0, 50000},
	Increment = 10,
	CurrentValue = espMinValue,
	Flag = "espminvalue",
	Callback = function(Value) espMinValue = Value end,
})

local VisualPredictionSection = VisualTab:CreateSection("Predictions (TBA)")

VisualTab:CreateToggle({
	Name = "Predict Events",
	CurrentValue = false,
	Flag = "predictevents",
	Callback = function(Value) end,
})

VisualTab:CreateToggle({
	Name = "Predict Stocks",
	CurrentValue = false,
	Flag = "predictstocks",
	Callback = function(Value) end,
})

PetTab:CreateToggle({
	Name = "Buy Pets",
	CurrentValue = autoBuyPets,
	Flag = "buypets",
	Callback = function(Value) autoBuyPets = Value end,
})

PetTab:CreateDropdown({
	Name = "Select Pets",
	Options = {},
	CurrentOption = {},
	MultipleOptions = true,
	Flag = "autobuypetsselect",
	Callback = function(Options) autoBuySelectedPet = Options end,
})

StealTargetSelect:Refresh(getPlayerList())

game.Players.PlayerAdded:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

game.Players.PlayerRemoving:Connect(function()
	StealTargetSelect:Refresh(getPlayerList())
end)

Rayfield:LoadConfiguration()
