local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local Networking    = require(ReplicatedStorage.SharedModules.Networking)
local SeedData      = require(ReplicatedStorage.SharedModules.SeedData)
local SellValueData = require(ReplicatedStorage.SharedModules.SellValueData)

local WildPetSpawns = workspace.Map.WildPetSpawns

local PetData = {
	Raccoon       = { DisplayName = "Raccoon",        Rarity = "Super",      SpawnChance = 0.24, BasePrice = 5000000  },
	Monkey        = { DisplayName = "Monkey",         Rarity = "Mythic",     SpawnChance = 0.2,  BasePrice = 1000000  },
	Robin         = { DisplayName = "Robin",          Rarity = "Legendary",  SpawnChance = 2.86, BasePrice = 75000    },
	Frog          = { DisplayName = "Frog",           Rarity = "Common",     SpawnChance = 11.9, BasePrice = 10000    },
	Bunny         = { DisplayName = "Bunny",          Rarity = "Common",     SpawnChance = 11.9, BasePrice = 20000    },
	Deer          = { DisplayName = "Deer",           Rarity = "Rare",       SpawnChance = 4.29, BasePrice = 50000    },
	Owl           = { DisplayName = "Owl",            Rarity = "Uncommon",   SpawnChance = 7.14, BasePrice = 25000    },
	Bee           = { DisplayName = "Bee",            Rarity = "Legendary",  SpawnChance = 2.38, BasePrice = 1000000  },
	Unicorn       = { DisplayName = "Unicorn",        Rarity = "Mythic",     SpawnChance = 0.71, BasePrice = 4000000  },
	BlackDragon   = { DisplayName = "Black Dragon",   Rarity = "Super",      SpawnChance = 0,    BasePrice = 1000000  },
	IceSerpent    = { DisplayName = "Ice Serpent",    Rarity = "Super",      SpawnChance = 0,    BasePrice = 20000000 },
	GoldenDragonfly={ DisplayName = "Golden Dragonfly",Rarity = "Mythic",    SpawnChance = 0.6,  BasePrice = 3000000  },
}

-- MutationData
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

-- FruitValueCalc
local FruitValueCalc
do
	local SIZE_EXP_DEFAULT     = 2.65
	local SIZE_EXP_OVERRIDES   = { Mushroom = 1.9, Bamboo = 1.75 }
	local SINGLE_HARVEST_SCALE = 0.15
	local DR_ENABLED = true; local DR_KNEE = 5; local DR_TAIL = 1.5
	local MIN_VALUES = { Carrot = 4 }
	local singleHarvest = {}
	for _, d in pairs(SeedData) do
		if d.SeedName then singleHarvest[d.SeedName] = d.IsSingleHarvest == true end
	end
	FruitValueCalc = function(fruitName, sizeMultiplier, mutation, playerInst, decayAlpha)
		sizeMultiplier = sizeMultiplier or 1
		local exp = SIZE_EXP_OVERRIDES[fruitName] or SIZE_EXP_DEFAULT
		local sz
		if DR_ENABLED and DR_KNEE < sizeMultiplier then
			sz = DR_KNEE ^ exp * (sizeMultiplier / DR_KNEE) ^ math.min(DR_TAIL, exp)
		else
			sz = sizeMultiplier ^ exp
		end
		local mm = 1
		if mutation and mutation ~= "" then
			local rm = MutationData.ReturnPriceMultiplier(mutation)
			if singleHarvest[fruitName] and rm > 1 then mm = 1 + (rm - 1) * SINGLE_HARVEST_SCALE
			else mm = rm end
		end
		local dm = 1
		if type(decayAlpha) == "number" and decayAlpha > 0 then
			dm = 1 - math.clamp(decayAlpha, 0, 1) * 0.8
		end
		local fm  = 1 + (playerInst:GetAttribute("Friends") or 0) * 0.1
		local res = math.floor((SellValueData[fruitName] or 0) * sz * mm * dm * fm)
		local mv  = MIN_VALUES[fruitName]
		return mv and math.max(res, mv) or res
	end
end

local function getFruitSizeMultiplier(fruit)
	for _, attr in ipairs({"SizeMulti","Scale","GrowthScale","FruitScale"}) do
		local v = fruit:GetAttribute(attr)
		if type(v) == "number" and v > 0 then return v end
	end
	if fruit:IsA("Model") then
		local ok, s = pcall(function() return fruit:GetScale() end)
		if ok and type(s) == "number" and s > 0 and math.abs(s - 1) > 0.001 then return s end
		if fruit.PrimaryPart then
			local sz = fruit.PrimaryPart.Size
			return (sz.X + sz.Y + sz.Z) / 3
		end
	end
	return 1
end

local night  = ReplicatedStorage.Night
local player = game.Players.LocalPlayer

local function getCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	return char, char:WaitForChild("HumanoidRootPart")
end

local dropped = workspace.DroppedItems
local seeds   = workspace.Map.SeedPackSpawnServerLocations

-- ============================================================
-- STATE
-- ============================================================
local collectSeeds          = false
local collectDropped        = false
local autoSell              = false
local autoSellInventorySize = 100
local autoBuy               = false
local autoBuySelected       = {}
local autoBuyGear           = false
local autoBuySelectedGear   = {}
local autoBuyPets           = false
local autoBuySelectedPet    = {}
local autoCollect           = false
local collectMutation       = false
local autoCollectMinValue   = 0
local autoCollectMaxValue   = 1000000
local espEnabled            = false
local espMinValue           = 0
local activeESPs            = {}
local activeESPValues       = {}
local noclip                = false
local walkSpeed             = 16
local jumpHeight            = 7.5
local stealTarget           = nil
local stealTargetToggled    = false
local antiSteal             = false
local stealBest             = false
-- Fling
local flingEnabled          = false
local flingTarget           = nil
local flingStrength         = 1      -- 1–10 (1 = originale SkidFling-Stärke)
local flingOnGarden         = false  -- auto-fling wenn Target im Garten
local isFlingling           = false  -- Mutex

-- Nearby-Steal Radius (Studs): wie weit Früchte von der Hauptfrucht entfernt sein dürfen
local STEAL_NEARBY_RADIUS = 15

-- ============================================================
-- ESP FOLDER
-- ============================================================
local espParent
if pcall(function() return CoreGui.Name end) then espParent = CoreGui
else espParent = player:WaitForChild("PlayerGui") end
if espParent:FindFirstChild("G2HFruitESP") then espParent.G2HFruitESP:Destroy() end
local espFolder = Instance.new("Folder")
espFolder.Name = "G2HFruitESP"; espFolder.Parent = espParent

-- ============================================================
-- GARDEN / PLOT INIT
-- ============================================================
local function waitForAttribute(inst, attr, timeout)
	timeout = timeout or 30
	local t0 = tick()
	local v = inst:GetAttribute(attr)
	while v == nil and tick() - t0 < timeout do task.wait(0.5); v = inst:GetAttribute(attr) end
	return v
end

local Gardens  = workspace:WaitForChild("Gardens")
local plotId   = waitForAttribute(player, "PlotId")
local plot     = Gardens:WaitForChild("Plot" .. tostring(plotId))
local spawnPos = plot:WaitForChild("PlotSizeReference")

-- ============================================================
-- CACHE / STATE
-- ============================================================
local queue             = {}
local stealBlacklist    = setmetatable({}, {__mode = "k"})
local stealBlacklistIds = {}
local CACHE_TTL         = 8
local valueCache        = setmetatable({}, {__mode = "k"})
local ppCache           = setmetatable({}, {__mode = "k"})
local bestCache         = nil   -- { plr = Instance } oder nil
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

-- ============================================================
-- NOCLIP
-- ============================================================
local noclipParts = {}
local function rebuildNoclipCache(char)
	noclipParts = {}
	if not char then return end
	for _, d in pairs(char:GetDescendants()) do
		if d:IsA("BasePart") then noclipParts[#noclipParts + 1] = d end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then noclipParts[#noclipParts + 1] = d end
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

-- ============================================================
-- RAYFIELD WINDOW
-- ============================================================
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
		SliderProgress = Color3.fromRGB(130, 130, 130),
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
		PlaceholderColor = Color3.fromRGB(140, 140, 140),
	},
	ToggleUIKeybind = "K",
	ConfigurationSaving = { Enabled = true, FolderName = nil, FileName = "g2h" },
})
Rayfield:Notify({ Title = "Loading...", Content = "Please wait.", Duration = 5, Image = 4483362458 })

-- ============================================================
-- HELPERS
-- ============================================================
local function moveTo(hrp, targetCF)
	return RunService.Heartbeat:Connect(function()
		if hrp and hrp.Parent then
			hrp.CFrame = targetCF
			hrp.AssemblyLinearVelocity  = Vector3.zero
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
	if pp then ppCache[fruit] = { hp = hp, pp = pp } end
	return hp, pp
end

local function getFruitValue(fruit)
	local c = valueCache[fruit]
	if c and os.clock() - c.t < CACHE_TTL then return c.v end
	local name = fruit:GetAttribute("CorePartName") or fruit:GetAttribute("SeedName")
	if not name then return 0 end
	local ok, v = pcall(FruitValueCalc, name, getFruitSizeMultiplier(fruit),
		fruit:GetAttribute("Mutation"), player, fruit:GetAttribute("DecayAlpha"))
	if not ok or type(v) ~= "number" then v = 0 end
	valueCache[fruit] = { v = v, t = os.clock() }
	return v
end

local function isValidFruit(fruit)
	if stealBlacklist[fruit] then return false end
	local fId = fruit:GetAttribute("FruitId")
	if fId and stealBlacklistIds[fId] then return false end
	local hp, pp = getFruitHpPp(fruit)
	if not hp or not pp or not pp.Enabled then return false end
	local age = fruit:GetAttribute("Age"); local maxAge = fruit:GetAttribute("MaxAge")
	return age ~= nil and maxAge ~= nil and age >= maxAge
end

-- ============================================================
-- FLING (angepasster SkidFling — nahtlos, einstellbare Stärke)
-- ============================================================
local function performFling(targetPlayer)
	if isFlingling then return end
	isFlingling = true

	local char, hrp = getCharacter()
	if not char or not hrp then isFlingling = false; return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then isFlingling = false; return end

	local tChar = targetPlayer.Character
	if not tChar then isFlingling = false; return end
	local tHum = tChar:FindFirstChildOfClass("Humanoid")
	local tHrp = tHum and tHum.RootPart
	if not tHrp then isFlingling = false; return end

	local oldPos    = hrp.CFrame
	local savedGrav = workspace.Gravity
	local oldFPDH   = workspace.FallenPartsDestroyHeight

	workspace.Gravity = 0
	workspace.FallenPartsDestroyHeight = 0/0

	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.zero; bv.MaxForce = Vector3.new(9e9, 9e9, 9e9); bv.Parent = hrp

	hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	local BASE = 9e7 * flingStrength
	local ROT  = 9e8 * flingStrength

	local ok, err = pcall(function()
		local t0 = tick(); local angle = 0
		repeat
			if not tHrp or not tHrp.Parent or not hrp.Parent then break end
			angle = angle + 120
			local cfA = CFrame.new(tHrp.Position) * CFrame.new(0,  1.5, 0) * CFrame.Angles(math.rad(angle), 0, 0)
			hrp.CFrame = cfA; hrp.Velocity = Vector3.new(BASE, BASE * 10, BASE); hrp.RotVelocity = Vector3.new(ROT, ROT, ROT)
			task.wait()
			if not tHrp.Parent or not hrp.Parent then break end
			local cfB = CFrame.new(tHrp.Position) * CFrame.new(0, -1.5, 0) * CFrame.Angles(math.rad(angle), 0, 0)
			hrp.CFrame = cfB; hrp.Velocity = Vector3.new(BASE, BASE * 10, BASE); hrp.RotVelocity = Vector3.new(ROT, ROT, ROT)
			task.wait()
		until tick() - t0 > 2.5 or not isFlingling
	end)
	if not ok then warn("performFling:", err) end

	pcall(function() bv:Destroy() end)
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
	workspace.Gravity = savedGrav; workspace.FallenPartsDestroyHeight = oldFPDH

	pcall(function()
		if not hrp or not hrp.Parent then return end
		hrp.CFrame = oldPos * CFrame.new(0, 0.5, 0)
		hrp.Velocity = Vector3.zero; hrp.RotVelocity = Vector3.zero
		for _, p in pairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.Velocity = Vector3.zero; p.RotVelocity = Vector3.zero end
		end
	end)

	isFlingling = false
end

-- ============================================================
-- COLLECT (Queue: Früchte, Seeds, Pets)
-- ============================================================
local function collect(p, maxAtt)
	local char, hrp = getCharacter()
	if not char or not hrp or not char:FindFirstChild("Head") then return end
	if not p or not p.Parent then return end
	local _, prompt = getFruitHpPp(p)
	if not prompt then
		for _, obj in ipairs(p:GetDescendants()) do
			if obj.ClassName == "ProximityPrompt" then prompt = obj; break end
		end
	end
	if not prompt then return end
	maxAtt = maxAtt or 700
	prompt.HoldDuration = 0
	local savedGrav = workspace.Gravity; workspace.Gravity = 0
	local oldPos = char:GetPivot()
	local pos    = p:IsA("Model") and p:GetPivot().Position or p.Position
	local conn   = moveTo(hrp, CFrame.new(pos - Vector3.new(0, 4, 0)))
	local att    = 0
	local ok, err = pcall(function()
		while prompt.Parent and att < maxAtt do
			att = att + 1; fireproximityprompt(prompt); noclipLoop(); task.wait(0.1)
		end
	end)
	conn:Disconnect(); char:PivotTo(oldPos); workspace.Gravity = savedGrav
	if not ok then warn("collect:", err) end
end

-- ============================================================
-- STEAL
-- ============================================================
local function steal(fruit, owner)
	if not isValidFruit(fruit) then return false end
	local ownerUserId = tonumber(fruit:GetAttribute("UserId"))
	local plantId     = fruit:GetAttribute("PlantId")
	local fruitId     = fruit:GetAttribute("FruitId") or ""
	if not ownerUserId or not plantId then
		stealBlacklist[fruit] = true; stealBlacklistIds[fruitId] = true; return false
	end
	local char, hrp = getCharacter()
	if not char or not hrp then return false end
	local hp, pp = getFruitHpPp(fruit)
	if not hp or not pp then
		stealBlacklist[fruit] = true; stealBlacklistIds[fruitId] = true; return false
	end

	local savedGrav = workspace.Gravity; workspace.Gravity = 0
	local oldPos    = char:GetPivot()
	local conn      = moveTo(hrp, CFrame.new(hp.Position - Vector3.new(0, 2, 0)))
	local success   = false

	local ok, err = pcall(function()
		fireproximityprompt(pp, pp.HoldDuration + 0.1)
		task.wait(pp.HoldDuration)
		pp.HoldDuration = 0
		task.wait(0.05)
			
		noclipLoop()

		local att = 0
		repeat
			att = att + 1
			fireproximityprompt(pp)
			if owner then Networking.Steal.BeginSteal:Fire(owner.UserId, plantId, fruitId) end
			noclipLoop()
			task.wait(0.15)
		until att >= 3 or not pp.Parent

		if att >= 3 then
			stealBlacklist[fruit] = true; stealBlacklistIds[fruitId] = true
		end
		success = true
	end)

	conn:Disconnect(); char:PivotTo(oldPos); workspace.Gravity = savedGrav
	valueCache[fruit] = nil; ppCache[fruit] = nil

	if not ok then
		warn("steal:", err); stealBlacklist[fruit] = true; stealBlacklistIds[fruitId] = true
		return false
	end
	return success
end

-- ============================================================
local function goToSpawnAndComplete()
	local char, hrp = getCharacter()
	if not char or not hrp then return end
	local savedGrav = workspace.Gravity; workspace.Gravity = 0
	local targetCF
	if spawnPos:IsA("BasePart") then targetCF = spawnPos.CFrame
	elseif spawnPos:IsA("Model") then targetCF = spawnPos:GetPivot()
	else workspace.Gravity = savedGrav; return end
	local conn = moveTo(hrp, targetCF)
	task.wait(0.02); Networking.Steal.CompleteSteal:Fire(); task.wait(0.06)
	conn:Disconnect(); workspace.Gravity = savedGrav
end

-- ============================================================
-- QUEUE
-- ============================================================
local function sortQueue()
	table.sort(queue, function(a, b) return a.t > b.t end)
end
local function removeTier(tier)
	for i = #queue, 1, -1 do if queue[i].t == tier then table.remove(queue, i) end end
end
local function addQueue(p, tier, mA)
	for _, v in ipairs(queue) do if v.m == p then return end end
	table.insert(queue, { m = p, t = tier, a = mA }); sortQueue()
end
local function loopAdd(f, tier)
	for _, item in pairs(f:GetChildren()) do addQueue(item, tier) end
end
local function findEntry(tbl, model, tier)
	for i, v in ipairs(tbl) do
		if v.m == model and v.t == tier then return i end
	end
	return nil
end

-- ============================================================
-- LISTS
-- ============================================================
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
	local ok, items = pcall(function() return ReplicatedStorage.StockValues.GearShop.Items:GetChildren() end)
	if ok and items then for _, d in pairs(items) do if d.Name then st[#st + 1] = d.Name end end end
	return st
end
local function getPetList()
	local st = {}
	for _, d in pairs(PetData) do if d.DisplayName then st[#st + 1] = d.DisplayName end end
	return st
end

-- ============================================================
-- GARDEN / STEAL HELPERS
-- ============================================================
local function getTargetGarden(t)
	local tp = game.Players:FindFirstChild(t); if not tp then return end
	local pid = tp:GetAttribute("PlotId"); if not pid then return end
	return Gardens:FindFirstChild("Plot" .. pid)
end

local function isInGarden(t)
	local p = typeof(t) == "Instance" and t or game.Players:FindFirstChild(t)
	return p and p:GetAttribute("IsInOwnGarden") == true
end

local function findBestTargetPlayer()
	if bestCache and bestCache.plr and bestCache.plr.Parent
	   and os.clock() - bestCacheT < BEST_TTL then
		return bestCache.plr
	end
	local bPlr, bV = nil, -1
	for _, plr in pairs(game.Players:GetChildren()) do
		if plr == player then continue end
		local garden = getTargetGarden(plr.Name); if not garden then continue end
		for _, target in pairs(garden.Plants:GetChildren()) do
			local fruits = target:FindFirstChild("Fruits")
			local list   = fruits and fruits:GetChildren() or {target}
			for _, tf in ipairs(list) do
				if stealBlacklist[tf] then continue end
				local fId = tf:GetAttribute("FruitId")
				if fId and stealBlacklistIds[fId] then continue end
				local age = tf:GetAttribute("Age"); local maxAge = tf:GetAttribute("MaxAge")
				if not age or not maxAge or age < maxAge then continue end
				local v = getFruitValue(tf)
				if v > bV then bV = v; bPlr = plr end
			end
		end
	end
	bestCache = { plr = bPlr }; bestCacheT = os.clock()
	return bPlr
end

local function getStealableFruit(plr)
	if not plr then return nil end
	local garden = getTargetGarden(plr.Name); if not garden then return nil end
	local bestFruit, bestV = nil, -1
	for _, target in pairs(garden.Plants:GetChildren()) do
		local fruits = target:FindFirstChild("Fruits")
		local list   = fruits and fruits:GetChildren() --or {target}
		for _, tf in ipairs(list) do
			if isValidFruit(tf) then
				if stealBest then
					local v = getFruitValue(tf)
					if v > bestV then bestV = v; bestFruit = tf end
				else
					return tf
				end
			end
		end
	end
	return bestFruit
end

local function maxInventory()
	local maxSize = player:GetAttribute("MaxFruitCapacity")
	local current = player:GetAttribute("FruitCount")
	if not maxSize or not current then return false end
	return current >= maxSize - 1
end

local function stealNearbyFruits(centerPos, ownerPlr)
	if maxInventory() or not centerPos or not ownerPlr then return end

	local ownerAttr = ownerPlr:GetAttribute("IsInOwnGarden")
	if ownerAttr == true then return end

	local garden = getTargetGarden(ownerPlr.Name)
	if not garden then return end

	local candidates = {}
	for _, target in pairs(garden.Plants:GetChildren()) do
		local fruits = target:FindFirstChild("Fruits")
		local list   = fruits and fruits:GetChildren() or {target}
		for _, tf in ipairs(list) do
			if not isValidFruit(tf) then continue end
			local nhp = tf:FindFirstChild("HarvestPart")
			if not nhp then continue end
			local d = (nhp.Position - centerPos).Magnitude
			if d <= STEAL_NEARBY_RADIUS then
				table.insert(candidates, { fruit = tf, dist = d })
			end
		end
	end

	table.sort(candidates, function(a, b) return a.dist < b.dist end)

	for _, entry in ipairs(candidates) do
		if maxInventory() then break end
		if ownerPlr:GetAttribute("IsInOwnGarden") == true then break end

		local tf = entry.fruit
		if not tf or not tf.Parent then continue end
		local tfId = tf:GetAttribute("FruitId")
		if not stealBest or not stealTarget or not stealTargetToggled then return end
		local ok2, res2 = pcall(steal, tf, ownerPlr)
		if not ok2 then
			stealBlacklist[tf] = true
			if tfId then stealBlacklistIds[tfId] = true end
			valueCache[tf] = nil
		end
	end
end

-- ============================================================
-- AUTO SELL / BUY
-- ============================================================
local function sellAll()
	if not autoSell then return end
	local inv = player:GetAttribute("FruitCount")
	if inv and inv >= autoSellInventorySize then Networking.NPCS.SellAll:Fire() end
end
player:GetAttributeChangedSignal("FruitCount"):Connect(sellAll)

local function buySeeds(name, amt)
	if not autoBuy or not table.find(autoBuySelected, name) then return end
	task.spawn(function()
		for _ = 1, amt do Networking.SeedShop.PurchaseSeed:Fire(name); task.wait(0.1) end
	end)
end
local function buyAllSeeds()
	for _, i in pairs(ReplicatedStorage.StockValues.SeedShop.Items:GetChildren()) do
		buySeeds(i.Name, i.Value)
	end
end
local function buyGear(name, amt)
	if not autoBuyGear or not table.find(autoBuySelectedGear, name) then return end
	task.spawn(function()
		for _ = 1, amt do Networking.GearShop.PurchaseGear:Fire(name); task.wait(0.1) end
	end)
end
local function buyAllGear()
	for _, i in pairs(ReplicatedStorage.StockValues.GearShop.Items:GetChildren()) do
		buyGear(i.Name, i.Value)
	end
end

for _, v in pairs(ReplicatedStorage.StockValues.GearShop.Items:GetChildren()) do
	v:GetPropertyChangedSignal("Value"):Connect(function()
		buyGear(v.Name, v.Value)
		task.delay(1, function() buyGear(v.Name, v.Value) end)
	end)
end
for _, v in pairs(ReplicatedStorage.StockValues.SeedShop.Items:GetChildren()) do
	v:GetPropertyChangedSignal("Value"):Connect(function()
		buySeeds(v.Name, v.Value)
		task.delay(1, function() buySeeds(v.Name, v.Value) end)
	end)
end

-- ============================================================
-- PETS
-- ============================================================
local function addPetToQueue(p)
	if not autoBuyPets then return end
	local n = p:GetAttribute("PetName")
	if not n or not table.find(autoBuySelectedPet, n) then return end
	if findEntry(queue, p, 3) then return end
	addQueue(p, 3, 8)  -- maxAtt=8: 8 × 0.1s = 0.8s max pro Pet
end

WildPetSpawns.ChildAdded:Connect(addPetToQueue)

local function addAllPetsToQueue()
	for _, pet in pairs(WildPetSpawns:GetChildren()) do addPetToQueue(pet) end
end

-- ============================================================
-- TASK: STEAL + AUTO-FLING + NEARBY-STEAL LOOP
--
-- Ablauf:
--  1. Steal-Modus aktiv? → Target bestimmen
--  2. Target im Garten + Nacht + flingOnGarden → flingen
--  3. Target draußen + Nacht → Hauptfrucht stehlen
--     → Danach ALLE naheliegenden Früchte im Radius stehlen
--     → Dann erst zu Spawn zurück
--  4. Sonst → warten
-- ============================================================
task.spawn(function()
	while true do
		local stealModeOn = (stealTargetToggled and stealTarget and game.Players:FindFirstChild(stealTarget))
			or stealBest

		if stealModeOn and not isFlingling then
			local targetPlr
			if stealBest then
				targetPlr = findBestTargetPlayer()
			elseif stealTargetToggled and stealTarget then
				targetPlr = game.Players:FindFirstChild(stealTarget)
			end

			if targetPlr then
				if isInGarden(targetPlr) then
					-- Im Garten: kann nicht bestohlen werden
					if flingOnGarden and night.Value and not isFlingling then
						bestCache = nil
						task.spawn(function()
							local ok, err = pcall(performFling, targetPlr)
							if not ok then warn("auto-fling:", err); isFlingling = false end
						end)
						task.wait(3.2)
					else
						task.wait(1.0)
					end

				elseif night.Value then
					-- Draußen bei Nacht → stehlen
					if maxInventory() then
						pcall(goToSpawnAndComplete); task.wait(1)
					else
						local fruit = getStealableFruit(targetPlr)
						if fruit and fruit.Parent then
							local fruitId = fruit:GetAttribute("FruitId")
							local ok, result = pcall(steal, fruit, targetPlr)
							if ok and result then
								bestCache = nil

								-- [NEU] Naheliegende Früchte mitnehmen bevor wir zu Spawn gehen
								local mainHp = fruit:FindFirstChild("HarvestPart")
								if mainHp and not maxInventory() then
									stealNearbyFruits(mainHp.Position, targetPlr)
								end

								pcall(goToSpawnAndComplete)
							elseif not ok then
								warn("steal:", result)
								stealBlacklist[fruit] = true
								if fruitId then stealBlacklistIds[fruitId] = true end
								valueCache[fruit] = nil
							end
						else
							task.wait(0.5)
						end
					end
				else
					task.wait(1.0) -- Tag → warten
				end
			else
				task.wait(0.5)
			end

		-- FIX: War 'not isFlinging' (falsche Variable) → jetzt korrekt 'not isFlingling'
		elseif not isFlingling and #queue > 0 then
			local item = table.remove(queue, 1)
			if item and item.m and item.m.Parent then pcall(collect, item.m, item.a) end
		end
		task.wait()
	end
end)

-- ============================================================
-- TASK: UTILITY (noclip, speed)
-- ============================================================
task.spawn(function()
	while task.wait() do
		if noclip then noclipLoop() end
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then hum.WalkSpeed = walkSpeed; hum.JumpHeight = jumpHeight end
		end
	end
end)

-- ============================================================
-- TASK: AUTO COLLECT (eigene Früchte)
-- ============================================================
task.spawn(function()
	while true do
		task.wait()
		if not autoCollect or not plot or maxInventory() then continue end
		local pPlants = plot:FindFirstChild("Plants"); if not pPlants then continue end
		for _, plant in pairs(pPlants:GetChildren()) do
			if not autoCollect then break end
			local fruits  = plant:FindFirstChild("Fruits")
			local targets = fruits and fruits:GetChildren() or {plant}
			for _, fruit in ipairs(targets) do
				if not autoCollect then break end
				local age = fruit:GetAttribute("Age") or 0
				local maxAge = fruit:GetAttribute("MaxAge") or 1
				local mut  = fruit:GetAttribute("Mutation")
				if age >= maxAge and (not collectMutation or (mut and mut ~= "")) then
					local val = getFruitValue(fruit)
					if val >= autoCollectMinValue and val <= autoCollectMaxValue then
						local fId = fruit:GetAttribute("FruitId")
						local pId = fruit:GetAttribute("PlantId")
						if pId then Networking.Garden.CollectFruit:Fire(pId, fId or ""); task.wait(0.03) end
					end
				end
			end
		end
	end
end)

-- ============================================================
-- TASK: MANUELLER FLING
-- ============================================================
task.spawn(function()
	while true do
		task.wait(0.2)
		if not flingEnabled or not flingTarget or isFlingling then continue end
		local tp = game.Players:FindFirstChild(flingTarget); if not tp then continue end
		local ok, err = pcall(performFling, tp)
		if not ok then warn("manual fling:", err); isFlingling = false end
		task.wait(3.5)
	end
end)

-- ============================================================
-- ESP
-- ============================================================
local function formatNumber(n)
	if not n then return "0" end
	if n >= 1e6 then return string.format("%.2fM", n/1e6):gsub("%.00M", "M")
	elseif n >= 1000 then return string.format("%.2fk", n/1000):gsub("%.00k", "k")
	else return tostring(math.floor(n)) end
end

local function createEsp(fruit)
	local val = getFruitValue(fruit); if val < espMinValue then return end
	if not activeESPs[fruit] then
		local bg = Instance.new("BillboardGui")
		bg.Adornee = fruit:FindFirstChild("HarvestPart") or fruit
		bg.Size = UDim2.new(0, 100, 0, 50); bg.StudsOffset = Vector3.new(0, 2, 0); bg.AlwaysOnTop = true
		local tl = Instance.new("TextLabel")
		tl.Name = "ValueLabel"; tl.Parent = bg; tl.Size = UDim2.new(1, 0, 1, 0)
		tl.BackgroundTransparency = 1; tl.TextColor3 = Color3.new(0.3, 1, 0.3)
		tl.TextStrokeTransparency = 0; tl.Text = "Val: " .. formatNumber(val)
		tl.Font = Enum.Font.GothamBold; tl.TextSize = 14; bg.Parent = espFolder
		activeESPs[fruit] = bg; activeESPValues[fruit] = val
	else
		if activeESPValues[fruit] ~= val then
			activeESPValues[fruit] = val
			local tl = activeESPs[fruit]:FindFirstChild("ValueLabel")
			if tl then tl.Text = "Val: " .. formatNumber(val) end
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
			activeESPs[fruit] = nil; activeESPValues[fruit] = nil
		end
		if not espEnabled then continue end
		for _, garden in pairs(Gardens:GetChildren()) do
			local plants = garden:FindFirstChild("Plants"); if not plants then continue end
			for _, plant in pairs(plants:GetChildren()) do
				local fruits = plant:FindFirstChild("Fruits")
				if fruits then for _, f in pairs(fruits:GetChildren()) do createEsp(f) end
				else createEsp(plant) end
			end
		end
	end
end)

dropped.ChildAdded:Connect(function(p) if collectDropped then addQueue(p, 1) end end)
seeds.ChildAdded:Connect(function(p)   if collectSeeds   then addQueue(p, 2) end end)

-- ============================================================
-- UI TABS
-- ============================================================
local PlayerTab = Window:CreateTab("Player", 4483362458)
local AutoTab   = Window:CreateTab("Auto",   4483362458)
local StealTab  = Window:CreateTab("Steal",  4483362458)
local PetTab    = Window:CreateTab("Pets",   4483362458)
local VisualTab = Window:CreateTab("Visual", 4483362458)

-- ---- Player ----
PlayerTab:CreateToggle({ Name="Noclip", CurrentValue=noclip, Flag="noclip",
	Callback=function(v) noclip=v end })
PlayerTab:CreateSlider({ Name="Walk Speed", Range={0,100}, Increment=1,
	CurrentValue=walkSpeed, Flag="walkspeedslider", Callback=function(v) walkSpeed=v end })
PlayerTab:CreateSlider({ Name="Jump Height", Range={0,50}, Increment=0.5,
	CurrentValue=jumpHeight, Flag="jumpheightslider", Callback=function(v) jumpHeight=v end })

-- ---- Steal ----
StealTab:CreateSection("Steal Best")
StealTab:CreateToggle({ Name="Steal Best", CurrentValue=stealBest, Flag="stealbesttoggled",
	Callback=function(v)
		stealBest = v; valueCache = setmetatable({}, {__mode="k"}); bestCache = nil
	end })

StealTab:CreateSection("Steal Target")
local StealTargetSelect = StealTab:CreateDropdown({
	Name="Pick Target", Options={}, CurrentOption={},
	MultipleOptions=false, Flag=nil,
	Callback=function(opts) stealTarget=opts[1]; resetStealState() end })
StealTab:CreateToggle({ Name="Steal Target", CurrentValue=stealTargetToggled, Flag="stealtargettoggled",
	Callback=function(v) stealTargetToggled=v; if v then resetStealState() end end })

StealTab:CreateSection("Auto-Fling")
StealTab:CreateToggle({ Name="Fling if in garden", CurrentValue=flingOnGarden, Flag="flingongarden",
	Callback=function(v) flingOnGarden=v end })
StealTab:CreateSlider({ Name="Fling Strength", Range={1,10}, Increment=1,
	CurrentValue=flingStrength, Flag="flingstrength",
	Callback=function(v) flingStrength=v end })

StealTab:CreateSection("Manual Fling")
local FlingTargetSelect = StealTab:CreateDropdown({
	Name="Fling Target", Options={}, CurrentOption={},
	MultipleOptions=false, Flag=nil,
	Callback=function(opts) flingTarget=opts[1] end })
StealTab:CreateToggle({ Name="Fling Player", CurrentValue=flingEnabled, Flag="flingplayer",
	Callback=function(v) flingEnabled=v end })

StealTab:CreateSection("Anti")
StealTab:CreateToggle({ Name="Anti Steal (WIP)", CurrentValue=antiSteal, Flag="antistealtoggled",
	Callback=function(v) antiSteal=v end })

-- ---- Auto ----
AutoTab:CreateSection("Main")
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
	MultipleOptions=true, Flag="autobuyselected",
	Callback=function(o) autoBuySelected=o; buyAllSeeds() end })
AutoTab:CreateToggle({ Name="Auto Buy Seeds", CurrentValue=autoBuy, Flag="autobuyseeds",
	Callback=function(v) autoBuy=v; if v then buyAllSeeds() end end })
AutoTab:CreateDropdown({ Name="Select Gear", Options=getGearList(), CurrentOption={},
	MultipleOptions=true, Flag="autobuygearselected",
	Callback=function(o) autoBuySelectedGear=o; buyAllGear() end })
AutoTab:CreateToggle({ Name="Auto Buy Gear", CurrentValue=autoBuyGear, Flag="autobuygear",
	Callback=function(v) autoBuyGear=v; if v then buyAllGear() end end })

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

-- ---- Visual ----
VisualTab:CreateSection("ESP")
VisualTab:CreateToggle({ Name="Enable Fruit ESP", CurrentValue=espEnabled, Flag="fruitesp",
	Callback=function(v) espEnabled=v end })
VisualTab:CreateSlider({ Name="ESP Min Value", Range={0,50000}, Increment=10,
	CurrentValue=espMinValue, Flag="espminvalue", Callback=function(v) espMinValue=v end })
VisualTab:CreateSection("Predictions (TBA)")
VisualTab:CreateToggle({ Name="Predict Events", CurrentValue=false, Flag="predictevents",
	Callback=function() end })
VisualTab:CreateToggle({ Name="Predict Stocks", CurrentValue=false, Flag="predictstocks",
	Callback=function() end })

-- ---- Pets ----
PetTab:CreateSection("Auto Buy")
PetTab:CreateToggle({ Name="Buy Pets", CurrentValue=autoBuyPets, Flag="buypets",
	Callback=function(v) autoBuyPets=v; if v then addAllPetsToQueue() end end })
PetTab:CreateDropdown({ Name="Select Pets", Options=getPetList(), CurrentOption={},
	MultipleOptions=true, Flag="autobuypetsselect",
	Callback=function(o) autoBuySelectedPet=o; addAllPetsToQueue() end })

-- ============================================================
-- PLAYER LIST REFRESH
-- ============================================================
local function refreshPlayerLists()
	local list = getPlayerList()
	StealTargetSelect:Refresh(list)
	FlingTargetSelect:Refresh(list)
end

refreshPlayerLists()
game.Players.PlayerAdded:Connect(refreshPlayerLists)
game.Players.PlayerRemoving:Connect(refreshPlayerLists)

Rayfield:LoadConfiguration()
