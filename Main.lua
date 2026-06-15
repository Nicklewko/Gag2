local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local Networking = require(ReplicatedStorage.SharedModules.Networking)
local SeedData = require(ReplicatedStorage.SharedModules.SeedData)
local SellValueData = require(ReplicatedStorage.SharedModules.SellValueData)

local MutationData
do
	local mults = {}
	local MutFolder = ReplicatedStorage.SharedModules.MutationData
	for _, name in ipairs({"Gold","Rainbow","Electric","Frozen","Bloodlit","Chained","Starstruck"}) do
		local sub = MutFolder:FindFirstChild(name)
		if sub then
			local ok, r = pcall(require, sub)
			mults[name] = (ok and r and r.PriceMultiplier) or 1
		end
	end
	MutationData = {
		ReturnPriceMultiplier = function(m)
			if not m or m == "" then return 1 end
			return mults[m] or 1
		end
	}
end

local FruitValueCalc
do
	local SIZE_EXP_DEFAULT   = 2.65
	local SIZE_EXP_OVERRIDES = { Mushroom = 1.9, Bamboo = 1.75 }
	local SINGLE_HARVEST_SCALE = 0.15
	local DR_ENABLED  = true
	local DR_KNEE     = 5
	local DR_TAIL     = 1.5
	local MIN_VALUES  = { Carrot = 4 }

	local singleHarvest = {}
	for _, d in pairs(SeedData) do
		if d.SeedName then
			singleHarvest[d.SeedName] = d.IsSingleHarvest == true
		end
	end

	FruitValueCalc = function(fruitName, sizeMultiplier, mutation, playerInst, decayAlpha)
		sizeMultiplier = sizeMultiplier or 1
		local exp = SIZE_EXP_OVERRIDES[fruitName] or SIZE_EXP_DEFAULT

		-- DiminishingReturns
		local sz
		if DR_ENABLED and DR_KNEE < sizeMultiplier then
			sz = DR_KNEE ^ exp * (sizeMultiplier / DR_KNEE) ^ math.min(DR_TAIL, exp)
		else
			sz = sizeMultiplier ^ exp
		end

		-- Mutation
		local mm = 1
		if mutation and mutation ~= "" then
			local rm = MutationData.ReturnPriceMultiplier(mutation)
			if singleHarvest[fruitName] and rm > 1 then
				mm = 1 + (rm - 1) * SINGLE_HARVEST_SCALE
			else
				mm = rm
			end
		end

		-- Decay
		local dm = 1
		if type(decayAlpha) == "number" and decayAlpha > 0 then
			dm = 1 - math.clamp(decayAlpha, 0, 1) * 0.8
		end

		local fm  = 1 + (playerInst:GetAttribute("Friends") or 0) * 0.1
		local res = math.floor((SellValueData[fruitName] or 0) * sz * mm * dm * fm)
		local mv  = MIN_VALUES[fruitName]
		if mv then
			return math.max(res, mv)
		end
		return res
	end
end

local function getFruitSizeMultiplier(fruit)
	local v = fruit:GetAttribute("SizeMulti")
	if v and type(v) == "number" and v > 0 then return v end

	v = fruit:GetAttribute("Scale")
	if v and type(v) == "number" and v > 0 then return v end

	v = fruit:GetAttribute("GrowthScale")
	if v and type(v) == "number" and v > 0 then return v end

	v = fruit:GetAttribute("FruitScale")
	if v and type(v) == "number" and v > 0 then return v end

	if fruit:IsA("Model") then
		local ok, s = pcall(function() return fruit:GetScale() end)
		if ok and type(s) == "number" and s > 0 and math.abs(s - 1) > 0.001 then
			return s
		end
	end

	local pp = fruit:IsA("Model") and fruit.PrimaryPart
	if pp then
		local size = pp.Size
		local avgSize = (size.X + size.Y + size.Z) / 3
		if avgSize > 0.1 then return avgSize end
	end

	return 1
end

local night  = ReplicatedStorage.Night
local player = game.Players.LocalPlayer

local function getCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart")
	return char, root
end

local dropped = workspace.DroppedItems
local seeds   = workspace.Map.SeedPackSpawnServerLocations

local collectSeeds    = false
local collectDropped  = false
local autoSell        = false
local autoSellInventorySize = 100
local autoBuy         = false
local autoBuySelected = {}
local autoBuyGear     = false
local autoBuySelectedGear = {}
local autoBuyPets     = false
local autoBuySelectedPet = {}
local autoCollect     = false
local collectMutation = false
local autoCollectMinValue = 0
local autoCollectMaxValue = 1000000
local espEnabled      = false
local espMinValue     = 0
local activeESPs      = {}
local activeESPValues = {}
local noclip          = false
local walkSpeed       = 16
local jumpHeight      = 7.5
local stealTarget     = nil
local stealTargetToggled = false
local antiSteal       = false
local stealBest       = false

local espParent
local ok_cg = pcall(function() return CoreGui.Name end)
if ok_cg then
	espParent = CoreGui
else
	espParent = player:WaitForChild("PlayerGui")
end
if espParent:FindFirstChild("G2HFruitESP") then espParent.G2HFruitESP:Destroy() end
local espFolder = Instance.new("Folder")
espFolder.Name   = "G2HFruitESP"
espFolder.Parent = espParent

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

local Gardens  = workspace:WaitForChild("Gardens")
local plotId   = waitForAttribute(player, "PlotId")
local plot     = Gardens:WaitForChild("Plot" .. tostring(plotId))
local spawnPos = plot:WaitForChild("SpawnPoint")

local queue             = {}
local stealBlacklist    = setmetatable({}, {__mode = "k"})
local stealBlacklistIds = {}
local CACHE_TTL         = 8
local valueCache        = setmetatable({}, {__mode = "k"})
local ppCache           = setmetatable({}, {__mode = "k"})
local bestCache         = nil
local bestCacheT        = 0
local BEST_TTL          = 1.5

local function resetStealState()
	stealBlacklist    = setmetatable({}, {__mode = "k"})
	stealBlacklistIds = {}
	valueCache        = setmetatable({}, {__mode = "k"})
	ppCache           = setmetatable({}, {__mode = "k"})
	bestCache         = nil
	bestCacheT        = 0
end

-- Noclip cache
local noclipParts = {}

local function rebuildNoclipCache(char)
	noclipParts = {}
	if not char then return end
	for _, d in pairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			noclipParts[#noclipParts + 1] = d
		end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			noclipParts[#noclipParts + 1] = d
		end
	end)
end
player.CharacterAdded:Connect(rebuildNoclipCache)
if player.Character then rebuildNoclipCache(player.Character) end

local function noclipLoop()
	for i = 1, #noclipParts do
		local p = noclipParts[i]
		if p.Parent and p.CanCollide then p.CanCollide = false end
	end
end

local Window = Rayfield:CreateWindow({
	Name = "Astro Hub", Icon = 0,
	LoadingTitle = "Astro Hub", LoadingSubtitle = "By Someone",
	ShowText = "Rayfield",
	Theme = {
	TextColor = Color3.fromRGB(255, 255, 255),

	Background = Color3.fromRGB(10, 10, 10),
	Topbar = Color3.fromRGB(18, 18, 18),
	Shadow = Color3.fromRGB(0, 0, 0),

	NotificationBackground = Color3.fromRGB(15, 15, 15),
	NotificationActionsBackground = Color3.fromRGB(240, 240, 240),

	TabBackground = Color3.fromRGB(25, 25, 25),
	TabStroke = Color3.fromRGB(45, 45, 45),
	TabBackgroundSelected = Color3.fromRGB(245, 245, 245),
	TabTextColor = Color3.fromRGB(200, 200, 200),
	SelectedTabTextColor = Color3.fromRGB(15, 15, 15),

	ElementBackground = Color3.fromRGB(20, 20, 20),
	ElementBackgroundHover = Color3.fromRGB(30, 30, 30),
	SecondaryElementBackground = Color3.fromRGB(14, 14, 14),
	ElementStroke = Color3.fromRGB(45, 45, 45),
	SecondaryElementStroke = Color3.fromRGB(35, 35, 35),

	SliderBackground = Color3.fromRGB(255, 255, 255),
	SliderProgress = Color3.fromRGB(220, 220, 220),
	SliderStroke = Color3.fromRGB(180, 180, 180),

	ToggleBackground = Color3.fromRGB(20, 20, 20),
	ToggleEnabled = Color3.fromRGB(255, 255, 255),
	ToggleDisabled = Color3.fromRGB(60, 60, 60),
	ToggleEnabledStroke = Color3.fromRGB(220, 220, 220),
	ToggleDisabledStroke = Color3.fromRGB(90, 90, 90),
	ToggleEnabledOuterStroke = Color3.fromRGB(140, 140, 140),
	ToggleDisabledOuterStroke = Color3.fromRGB(40, 40, 40),

	DropdownSelected = Color3.fromRGB(40, 40, 40),
	DropdownUnselected = Color3.fromRGB(20, 20, 20),

	InputBackground = Color3.fromRGB(18, 18, 18),
	InputStroke = Color3.fromRGB(55, 55, 55),
	PlaceholderColor = Color3.fromRGB(140, 140, 140)
	}, 
	ToggleUIKeybind = "K",
	ConfigurationSaving = { Enabled = true, FolderName = nil, FileName = "g2h" },
})
Rayfield:Notify({ Title = "Loading...", Content = "Please wait.", Duration = 5, Image = 4483362458 })

local function moveTo(hrp, targetCF)
	return RunService.Heartbeat:Connect(function()
		if hrp and hrp.Parent then
			hrp.CFrame = targetCF
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

local function getFruitHpPp(fruit)
	local c = ppCache[fruit]
	if c and c.hp.Parent and c.pp.Parent then return c.hp, c.pp end
	local hp = fruit:FindFirstChild("HarvestPart")
	if not hp then return nil, nil end
	local pp = nil
	for _, obj in ipairs(hp:GetDescendants()) do
		if obj.ClassName == "ProximityPrompt" then pp = obj; break end
	end
	if pp then ppCache[fruit] = {hp = hp, pp = pp} end
	return hp, pp
end

local function calculateStealDuration(fruit)
	local seedName = fruit:GetAttribute("CorePartName") or fruit:GetAttribute("SeedName") or "Carrot"
	local age      = fruit:GetAttribute("Age") or 1
	local mutation = fruit:GetAttribute("Mutation")
	
	local sellVal  = SellValueData[seedName]
	if not sellVal then return 5 end

	local v = math.floor(sellVal * (age ^ 3))
	
	if mutation and mutation ~= "" then
		local mults = {}
		local MutFolder = ReplicatedStorage.SharedModules.MutationData
		
		local sub = MutFolder:FindFirstChild(mutation)
		if sub then
			local ok, r = pcall(require, sub)
			local priceMultiplier = (ok and r and r.PriceMultiplier) or 1
			v = v * priceMultiplier
		end
	end
	
	return 0, math.sqrt(v) * 0.05
end

local function getFruitValue(fruit)
	local c = valueCache[fruit]
	if c and os.clock() - c.t < CACHE_TTL then return c.v end

	local name = fruit:GetAttribute("CorePartName") or fruit:GetAttribute("SeedName")
	if not name then return 0 end

	local size     = getFruitSizeMultiplier(fruit)
	local mutation = fruit:GetAttribute("Mutation")
	local decay    = fruit:GetAttribute("DecayAlpha")

	local ok, v = pcall(FruitValueCalc, name, size, mutation, player, decay)
	if not ok or type(v) ~= "number" then v = 0 end

	valueCache[fruit] = {v = v, t = os.clock()}
	return v
end

local function isValidFruit(fruit)
	if stealBlacklist[fruit] then return false end
	local fId = fruit:GetAttribute("FruitId")
	if fId and stealBlacklistIds[fId] then return false end
	local hp, pp = getFruitHpPp(fruit)
	if not hp or not pp or not pp.Enabled then return false end
	local age    = fruit:GetAttribute("Age")
	local maxAge = fruit:GetAttribute("MaxAge")
	return age ~= nil and maxAge ~= nil and age >= maxAge
end

local function collect(p, maxAtt)
	local char = getCharacter()
	if not char or not char:FindFirstChild("Head") then return end
	if not p or not p.Parent then return end
	local _, prompt = getFruitHpPp(p)
	if not prompt then
		for _, obj in ipairs(p:GetDescendants()) do
			if obj.ClassName == "ProximityPrompt" then prompt = obj; break end
		end
	end
	if not prompt then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	prompt.HoldDuration = 0
	local savedGravity = workspace.Gravity
	workspace.Gravity  = 0
	local oldPos   = char:GetPivot()
	local pos      = p:IsA("Model") and p:GetPivot().Position or p.Position
	local targetCF = CFrame.new(pos - Vector3.new(0, 4, 0))
	local conn     = moveTo(hrp, targetCF)
	local att      = 0
	local ok, err  = pcall(function()
		while prompt.Parent do
			if maxAtt and att >= maxAtt then break end
			att = att + 1
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
	local ownerUserId = tonumber(fruit:GetAttribute("UserId"))
	local plantId     = fruit:GetAttribute("PlantId")
	local fruitId     = fruit:GetAttribute("FruitId") or ""
	if not ownerUserId or not plantId then
		stealBlacklist[fruit] = true
		stealBlacklistIds[fruitId] = true
		return false
	end
	local char = getCharacter()
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local hp, pp = getFruitHpPp(fruit)
	if not hp or not pp then
		stealBlacklist[fruit] = true
		stealBlacklistIds[fruitId] = true
		return false
	end
	pp.HoldDuration    = 0
	local duration     = calculateStealDuration(fruit) + 0.5
	local savedGravity = workspace.Gravity
	workspace.Gravity  = 0
	local oldPos  = char:GetPivot()
	local conn    = moveTo(hrp, CFrame.new(hp.Position))
	local success = false
	local prevPar = fruit.Parent
	local startT  = os.clock()
	local ok, err = pcall(function()
		while fruit.Parent and fruit.Parent == prevPar do
			if os.clock() - startT >= duration then
				success = true
				break
			end
			noclipLoop()
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
	ppCache[fruit]    = nil
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
	local char = getCharacter()
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local savedGravity = workspace.Gravity
	workspace.Gravity  = 0
	local targetCF
	if spawnPos:IsA("BasePart") then
		targetCF = spawnPos.CFrame
	elseif spawnPos:IsA("Model") then
		targetCF = spawnPos:GetPivot()
	else
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
	table.sort(queue, function(a, b) return a.t < b.t end)
end
local function removeTier(tier)
	for i = #queue, 1, -1 do
		if queue[i].t == tier then table.remove(queue, i) end
	end
end
local function addQueue(p, tier)
	for _, v in ipairs(queue) do
		if v.m == p then return end
	end
	table.insert(queue, {m = p, t = tier})
	sortQueue()
end
local function loopAdd(f, tier)
	for _, item in pairs(f:GetChildren()) do addQueue(item, tier) end
end

local function getPlayerList()
	local pt = {}
	for _, p in pairs(game.Players:GetPlayers()) do
		if p ~= player then pt[#pt + 1] = p.Name end
	end
	return pt
end
local function getSeedList()
	local st = {}
	for _, d in pairs(SeedData) do
		if d.SeedName and d.RestockShop then st[#st + 1] = d.SeedName end
	end
	return st
end
local function getGearList()
	local st = {}
	local ok, items = pcall(function()
		return ReplicatedStorage.StockValues.GearShop.Items:GetChildren()
	end)
	if ok and items then
		for _, d in pairs(items) do
			if d.Name then st[#st + 1] = d.Name end
		end
	end
	return st
end

local function getTargetGarden(t)
	local tp = game.Players:FindFirstChild(t)
	if not tp then return end
	local pid = tp:GetAttribute("PlotId")
	if not pid then return end
	return Gardens:FindFirstChild("Plot" .. pid)
end
local function isInGarden(t)
	local p = game.Players:FindFirstChild(t)
	return p and p:GetAttribute("IsInOwnGarden") == true
end
local function canSteal(t)
	return not isInGarden(t) and night.Value == true
end

local function getTargetFruit(t)
	if stealBest then
		if bestCache and bestCache.Parent and os.clock() - bestCacheT < BEST_TTL and isValidFruit(bestCache) then
			return bestCache
		end
		local best  = nil
		local bestV = -1
		for _, plr in pairs(game.Players:GetChildren()) do
			if plr == player then continue end
			if not canSteal(plr.Name) then continue end
			local garden = getTargetGarden(plr.Name)
			if not garden then continue end
			for _, target in pairs(garden.Plants:GetChildren()) do
				local fruits = target:FindFirstChild("Fruits")
				if fruits then
					for _, tf in pairs(fruits:GetChildren()) do
						if not isValidFruit(tf) then continue end
						local v = getFruitValue(tf)
						if v > bestV then bestV = v; best = tf end
					end
				else
					if isValidFruit(target) then
						if true then continue end -- gotta add later
						local v = getFruitValue(target)
						if v > bestV then bestV = v; best = target end
					end
				end
			end
		end
		bestCache  = best
		bestCacheT = os.clock()
		return best
	else
		local garden = getTargetGarden(t)
		if not garden then return end
		for _, target in pairs(garden.Plants:GetChildren()) do
			local fruits = target:FindFirstChild("Fruits")
			if fruits then
				for _, tf in pairs(fruits:GetChildren()) do
					if isValidFruit(tf) then return tf end
				end
			else
				--if isValidFruit(target) then return target end
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
	local inv = player:GetAttribute("FruitCount")
	if inv and inv >= autoSellInventorySize then Networking.NPCS.SellAll:Fire() end
end
player:GetAttributeChangedSignal("FruitCount"):Connect(sellAll)

local function buySeeds(name, amt)
	if not autoBuy or not table.find(autoBuySelected, name) then return end
	for i = 1, amt do Networking.SeedShop.PurchaseSeed:Fire(name) task.wait(.05) end
end
local function buyGear(name, amt)
	if not autoBuyGear or not table.find(autoBuySelectedGear, name) then return end
	for i = 1, amt do Networking.GearShop.PurchaseGear:Fire(name) task.wait(.05) end
end

for _, v in pairs(ReplicatedStorage.StockValues.GearShop.Items:GetChildren()) do
	v:GetPropertyChangedSignal("Value"):Connect(function() buyGear(v.Name, v.Value) end)
end
for _, v in pairs(ReplicatedStorage.StockValues.SeedShop.Items:GetChildren()) do
	v:GetPropertyChangedSignal("Value"):Connect(function() buySeeds(v.Name, v.Value) end)
end

-- Steal/Queue Loop
task.spawn(function()
	while true do
		local stealTargetActive = stealTargetToggled
			and stealTarget ~= nil
			and game.Players:FindFirstChild(stealTarget) ~= nil
			and canSteal(stealTarget)
		local isStealActive = stealTargetActive or stealBest

		if isStealActive then
			if maxInventory() then
				local ok, err = pcall(goToSpawnAndComplete)
				if not ok then warn("goToSpawnAndComplete error:", err) end
				task.wait(1)
			else
				local item = getTargetFruit(stealTarget)
				if item and item.Parent then
					local fruitId = item:GetAttribute("FruitId")
					local ok, result = pcall(steal, item)
					if ok and result == true then
						local ok2, err2 = pcall(goToSpawnAndComplete)
						if not ok2 then warn("goToSpawnAndComplete error:", err2) end
						bestCache = nil
					elseif not ok then
						warn("steal (main loop) error:", result)
						stealBlacklist[item] = true
						if fruitId then stealBlacklistIds[fruitId] = true end
						valueCache[item] = nil
					end
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
				hum.WalkSpeed  = walkSpeed
				hum.JumpHeight = jumpHeight
			end
		end
	end
end)

-- AutoCollect Loop
task.spawn(function()
	while true do
		task.wait(0.3)
		if not autoCollect or not plot or maxInventory() then continue end
		local pPlants = plot:FindFirstChild("Plants")
		if not pPlants then continue end
		for _, plant in pairs(pPlants:GetChildren()) do
			if not autoCollect then break end
			local fruits = plant:FindFirstChild("Fruits")
			if fruits then
				for _, fruit in pairs(fruits:GetChildren()) do
					if not autoCollect then break end
					local age    = fruit:GetAttribute("Age") or 0
					local maxAge = fruit:GetAttribute("MaxAge") or 1
					local mut    = fruit:GetAttribute("Mutation")
					local hasMut = mut and mut ~= ""
					if age >= maxAge and (not collectMutation or hasMut) then
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
				local fruit  = plant
				local age    = fruit:GetAttribute("Age") or 0
				local maxAge = fruit:GetAttribute("MaxAge") or 1
				local mut    = fruit:GetAttribute("Mutation")
				local hasMut = mut and mut ~= ""
				if age >= maxAge and (not collectMutation or hasMut) then
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
end)

-- ESP
local function createEsp(fruit)
	local val = getFruitValue(fruit)
	if val < espMinValue then return end
	if not activeESPs[fruit] then
		local bg = Instance.new("BillboardGui")
		bg.Adornee     = fruit:FindFirstChild("HarvestPart") or fruit
		bg.Size        = UDim2.new(0, 100, 0, 50)
		bg.StudsOffset = Vector3.new(0, 2, 0)
		bg.AlwaysOnTop = true
		local tl = Instance.new("TextLabel")
		tl.Name               = "ValueLabel"
		tl.Parent             = bg
		tl.Size               = UDim2.new(1, 0, 1, 0)
		tl.BackgroundTransparency = 1
		tl.TextColor3         = Color3.new(0.3, 1, 0.3)
		tl.TextStrokeTransparency = 0
		tl.Text               = "Val: " .. tostring(val)
		tl.Font               = Enum.Font.GothamBold
		tl.TextSize           = 14
		bg.Parent             = espFolder
		activeESPs[fruit]     = bg
		activeESPValues[fruit] = val
	else
		if activeESPValues[fruit] ~= val then
			activeESPValues[fruit] = val
			local tl = activeESPs[fruit]:FindFirstChild("ValueLabel")
			if tl then tl.Text = "Val: " .. tostring(val) end
		end
	end
end

task.spawn(function()
	while task.wait(0.5) do
		local toRemove = {}
		for fruit in pairs(activeESPs) do
			if not espEnabled or not fruit or not fruit.Parent or getFruitValue(fruit) < espMinValue then
				toRemove[#toRemove + 1] = fruit
			end
		end
		for _, fruit in ipairs(toRemove) do
			if activeESPs[fruit] then activeESPs[fruit]:Destroy() end
			activeESPs[fruit]      = nil
			activeESPValues[fruit] = nil
		end
		if not espEnabled then continue end
		for _, garden in pairs(Gardens:GetChildren()) do
			local plants = garden:FindFirstChild("Plants")
			if not plants then continue end
			for _, plant in pairs(plants:GetChildren()) do
				local fruits = plant:FindFirstChild("Fruits")
				if fruits then
					for _, fruit in pairs(fruits:GetChildren()) do createEsp(fruit) end
				else
					createEsp(plant)
				end
			end
		end
	end
end)

dropped.ChildAdded:Connect(function(p) if collectDropped then addQueue(p, 1) end end)
seeds.ChildAdded:Connect(function(p)   if collectSeeds   then addQueue(p, 2) end end)

-- UI
local PlayerTab        = Window:CreateTab("Player",  4483362458)
local AutoTab          = Window:CreateTab("Auto",    4483362458)
local AutoMainSection  = AutoTab:CreateSection("Main")
local StealTab         = Window:CreateTab("Steal",   4483362458)
local StealMainSection = StealTab:CreateSection("Main")
local PetTab           = Window:CreateTab("Pets",    4483362458)
local PetBuySection    = PetTab:CreateSection("Auto Buy")
local VisualTab        = Window:CreateTab("Visual",  4483362458)
local VisualEspSection = VisualTab:CreateSection("ESP")

PlayerTab:CreateToggle({ Name="Noclip", CurrentValue=noclip, Flag="noclip",
	Callback=function(v) noclip=v end })
PlayerTab:CreateSlider({ Name="Walk Speed", Range={0,100}, Increment=1,
	CurrentValue=walkSpeed, Flag="walkspeedslider", Callback=function(v) walkSpeed=v end })
PlayerTab:CreateSlider({ Name="Jump Height", Range={0,50}, Increment=0.5,
	CurrentValue=jumpHeight, Flag="jumpheightslider", Callback=function(v) jumpHeight=v end })

StealTab:CreateToggle({ Name="Steal Best", CurrentValue=stealBest, Flag="stealbesttoggled",
	Callback=function(v)
		stealBest  = v
		valueCache = setmetatable({}, {__mode="k"})
		bestCache  = nil
	end })

local StealTargetSection = StealTab:CreateSection("Target")
local StealTargetSelect  = StealTab:CreateDropdown({
	Name="Select Target", Options={}, CurrentOption={}, MultipleOptions=false, Flag=nil,
	Callback=function(opts) stealTarget=opts[1]; resetStealState() end })
StealTab:CreateToggle({ Name="Steal Target", CurrentValue=stealTargetToggled, Flag="stealtargettoggled",
	Callback=function(v) stealTargetToggled=v; if v then resetStealState() end end })

local StealAntiSection = StealTab:CreateSection("Anti")
StealTab:CreateToggle({ Name="Anti Steal (WIP)", CurrentValue=antiSteal, Flag="antistealtoggled",
	Callback=function(v) antiSteal=v end })

AutoTab:CreateToggle({ Name="Collect Dropped Items", CurrentValue=collectDropped, Flag="autocollectdropped",
	Callback=function(v) collectDropped=v; if v then loopAdd(dropped,1) else removeTier(1) end end })
AutoTab:CreateToggle({ Name="Collect Seeds", CurrentValue=collectSeeds, Flag="autocollectseeds",
	Callback=function(v) collectSeeds=v; if v then loopAdd(seeds,2) else removeTier(2) end end })

AutoTab:CreateSection("Selling")
AutoTab:CreateToggle({ Name="Auto Sell", CurrentValue=autoSell, Flag="autosell",
	Callback=function(v) autoSell=v; if v then sellAll() end end })
AutoTab:CreateSlider({ Name="Sell at", Range={1,100}, Increment=1, Suffix="Fruits",
	CurrentValue=autoSellInventorySize, Flag="autosellinventorysize",
	Callback=function(v) autoSellInventorySize=v; if autoSell then sellAll() end end })

AutoTab:CreateSection("Buying")
AutoTab:CreateDropdown({ Name="Select Seeds", Options=getSeedList(), CurrentOption={},
	MultipleOptions=true, Flag="autobuyselected", Callback=function(o) autoBuySelected=o end })
AutoTab:CreateToggle({ Name="Auto Buy Seeds", CurrentValue=autoBuy, Flag="autobuyseeds",
	Callback=function(v)
		autoBuy = v
		if v then
			for _, i in pairs(ReplicatedStorage.StockValues.SeedShop.Items:GetChildren()) do
				buySeeds(i.Name, i.Value)
			end
		end
	end })
AutoTab:CreateDropdown({ Name="Select Gear", Options=getGearList(), CurrentOption={},
	MultipleOptions=true, Flag="autobuygearselected", Callback=function(o) autoBuySelectedGear=o end })
AutoTab:CreateToggle({ Name="Auto Buy Gear", CurrentValue=autoBuyGear, Flag="autobuygear",
	Callback=function(v)
		autoBuyGear = v
		if v then
			for _, i in pairs(ReplicatedStorage.StockValues.GearShop.Items:GetChildren()) do
				buyGear(i.Name, i.Value)
			end
		end
	end })

AutoTab:CreateSection("Own")
AutoTab:CreateToggle({ Name="Auto Collect Own Fruits", CurrentValue=autoCollect, Flag="autocollect",
	Callback=function(v) autoCollect=v end })
AutoTab:CreateToggle({ Name="Requires Mutation", CurrentValue=collectMutation, Flag="collectmutation",
	Callback=function(v) collectMutation=v end })
AutoTab:CreateSlider({ Name="Min Value", Range={0,100000}, Increment=10,
	CurrentValue=autoCollectMinValue, Flag="autocollectmin",
	Callback=function(v) autoCollectMinValue=v end })
AutoTab:CreateSlider({ Name="Max Value", Range={0,1000000}, Increment=100,
	CurrentValue=autoCollectMaxValue, Flag="autocollectmax",
	Callback=function(v) autoCollectMaxValue=v end })

VisualTab:CreateToggle({ Name="Enable Fruit ESP", CurrentValue=espEnabled, Flag="fruitesp",
	Callback=function(v) espEnabled=v end })
VisualTab:CreateSlider({ Name="ESP Min Value", Range={0,50000}, Increment=10,
	CurrentValue=espMinValue, Flag="espminvalue", Callback=function(v) espMinValue=v end })

local VisualPredSection = VisualTab:CreateSection("Predictions (TBA)")
VisualTab:CreateToggle({ Name="Predict Events", CurrentValue=false, Flag="predictevents",
	Callback=function() end })
VisualTab:CreateToggle({ Name="Predict Stocks", CurrentValue=false, Flag="predictstocks",
	Callback=function() end })

PetTab:CreateToggle({ Name="Buy Pets", CurrentValue=autoBuyPets, Flag="buypets",
	Callback=function(v) autoBuyPets=v end })
PetTab:CreateDropdown({ Name="Select Pets", Options={}, CurrentOption={},
	MultipleOptions=true, Flag="autobuypetsselect", Callback=function(o) autoBuySelectedPet=o end })

StealTargetSelect:Refresh(getPlayerList())
game.Players.PlayerAdded:Connect(function()   StealTargetSelect:Refresh(getPlayerList()) end)
game.Players.PlayerRemoving:Connect(function() StealTargetSelect:Refresh(getPlayerList()) end)

Rayfield:LoadConfiguration()
