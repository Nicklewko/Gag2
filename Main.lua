-- ============================================================
-- ASTRO HUB
-- ============================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local RunService   = game:GetService("RunService")
local RepStore     = game:GetService("ReplicatedStorage")
local CoreGui      = game:GetService("CoreGui")
local Players      = game:GetService("Players")
local V3           = Vector3.new
local V0           = Vector3.zero
local CF           = CFrame.new
local CFA          = CFrame.Angles
local mrad         = math.rad
local mfloor       = math.floor
local mmax         = math.max
local mmin         = math.min
local mclamp       = math.clamp
local mabs         = math.abs
local osclk        = os.clock
local tw           = task.wait
local ts           = task.spawn
local td           = task.delay

local Networking   = require(RepStore.SharedModules.Networking)
local SeedData     = require(RepStore.SharedModules.SeedData)
local SellValueData= require(RepStore.SharedModules.SellValueData)
local WildPetSpawns= workspace.Map.WildPetSpawns

local PetData = {
	Raccoon       = { DisplayName="Raccoon",         Rarity="Super",    SpawnChance=0.24, BasePrice=5000000  },
	Monkey        = { DisplayName="Monkey",          Rarity="Mythic",   SpawnChance=0.2,  BasePrice=1000000  },
	Robin         = { DisplayName="Robin",           Rarity="Legendary",SpawnChance=2.86, BasePrice=75000    },
	Frog          = { DisplayName="Frog",            Rarity="Common",   SpawnChance=11.9, BasePrice=10000    },
	Bunny         = { DisplayName="Bunny",           Rarity="Common",   SpawnChance=11.9, BasePrice=20000    },
	Deer          = { DisplayName="Deer",            Rarity="Rare",     SpawnChance=4.29, BasePrice=50000    },
	Owl           = { DisplayName="Owl",             Rarity="Uncommon", SpawnChance=7.14, BasePrice=25000    },
	Bee           = { DisplayName="Bee",             Rarity="Legendary",SpawnChance=2.38, BasePrice=1000000  },
	Unicorn       = { DisplayName="Unicorn",         Rarity="Mythic",   SpawnChance=0.71, BasePrice=4000000  },
	BlackDragon   = { DisplayName="Black Dragon",    Rarity="Super",    SpawnChance=0,    BasePrice=1000000  },
	IceSerpent    = { DisplayName="Ice Serpent",     Rarity="Super",    SpawnChance=0,    BasePrice=20000000 },
	GoldenDragonfly={DisplayName="Golden Dragonfly", Rarity="Mythic",   SpawnChance=0.6,  BasePrice=3000000  },
	Bear 		  = {DisplayName = "Bear",			 Rarity = "Mythic", SpawnChance = 0.225, BasePrice = 5000000},
	Turtle 		  = {DisplayName = "Turtle",		 Rarity = "Rare", SpawnChance = 3.75, BasePrice = 70000  },
}

-- ============================================================
-- MUTATION DATA
-- ============================================================
local MutationData
do
	local mults = {}
	local MutFolder = RepStore.SharedModules.MutationData
	for _, name in ipairs({"Gold","Rainbow","Electric","Frozen","Bloodlit","Chained","Starstruck"}) do
		local sub = MutFolder:FindFirstChild(name)
		if sub then
			local ok, r = pcall(require, sub)
			mults[name] = (ok and r and r.PriceMultiplier) or 1
		end
	end
	MutationData = { ReturnPriceMultiplier = function(m)
		if not m or m == "" then return 1 end
		return mults[m] or 1
	end }
end

-- ============================================================
-- FRUIT VALUE CALC
-- ============================================================
local FruitValueCalc
do
	local EXP_DEF  = 2.65
	local EXP_OVR  = { Mushroom=1.9, Bamboo=1.75 }
	local SHS      = 0.15
	local DR_ON    = true; local DR_KNEE=5; local DR_TAIL=1.5
	local MIN_VAL  = { Carrot=4 }
	local singleH  = {}
	for _, d in pairs(SeedData) do
		if d.SeedName then singleH[d.SeedName] = d.IsSingleHarvest == true end
	end
	FruitValueCalc = function(name, sz, mut, plr, decay)
		sz = sz or 1
		local exp = EXP_OVR[name] or EXP_DEF
		local s
		if DR_ON and DR_KNEE < sz then
			s = DR_KNEE^exp * (sz/DR_KNEE)^mmin(DR_TAIL,exp)
		else
			s = sz^exp
		end
		local mm = 1
		if mut and mut ~= "" then
			local rm = MutationData.ReturnPriceMultiplier(mut)
			mm = (singleH[name] and rm>1) and (1+(rm-1)*SHS) or rm
		end
		local dm = 1
		if type(decay)=="number" and decay>0 then dm = 1-mclamp(decay,0,1)*0.8 end
		local fm  = 1 + (plr:GetAttribute("Friends") or 0)*0.1
		local res = mfloor((SellValueData[name] or 0)*s*mm*dm*fm)
		local mv  = MIN_VAL[name]
		return mv and mmax(res,mv) or res
	end
end

local function getFruitSzMul(fruit)
	for _, a in ipairs({"SizeMulti","Scale","GrowthScale","FruitScale"}) do
		local v = fruit:GetAttribute(a)
		if type(v)=="number" and v>0 then return v end
	end
	if fruit:IsA("Model") then
		local ok, s = pcall(function() return fruit:GetScale() end)
		if ok and type(s)=="number" and s>0 and mabs(s-1)>0.001 then return s end
		if fruit.PrimaryPart then
			local sz = fruit.PrimaryPart.Size
			return (sz.X+sz.Y+sz.Z)/3
		end
	end
	return 1
end

-- ============================================================
-- PLAYER / WORLD
-- ============================================================
local night  = RepStore.Night
local player = Players.LocalPlayer

local function getChar()
	local c = player.Character or player.CharacterAdded:Wait()
	return c, c:WaitForChild("HumanoidRootPart")
end

local dropped = workspace.DroppedItems
local seeds   = workspace.Map.SeedPackSpawnServerLocations

-- ============================================================
-- STATE
-- ============================================================
local collectSeeds=false; local collectDropped=false
local autoSell=false;     local autoSellSize=100
local autoBuy=false;      local autoBuySel={}
local autoBuyGear=false;  local autoBuyGearSel={}
local autoBuyPets=false;  local autoBuyPetSel={}
local autoCollect=false;  local collectMut=false
local acMin=0;            local acMax=0          -- acMax 0 = no upper limit (ignored)
local acMaxSize=0                                -- max size multiplier; 0 = no limit (ignored)
local espOn=false;        local espMin=0
local activeESPs={};      local activeESPVals={}
local noclip=false;       local walkSpd=16; local jumpH=7.5
local stealTgt=nil;       local stealTgtOn=false
local antiSteal=false;    local stealBest=false
local flingOn=false;      local flingTgt=nil
local flingStr=1;         local flingGarden=false
local isFlinging=false;   local disableParticles=false
local antiAfk=false;      local ignoreSingleHarvest=false
local petFollowSpeed=0;   local espHighlight=false
local hideForeignPlants=false; local hideOwnPlants=false

local NEARBY_R        = 0
local COLLECT_OFFSET  = V3(0,-4,0)
local AC_INTERVAL     = 0.15
local HIDE_PLANT_INTERVAL = 0.01
local HIDE_PLANT_IDLE_INTERVAL = 0.35
local HIDE_PLANT_BUDGET   = 24

-- ============================================================
-- ESP FOLDER
-- ============================================================
local espParent = pcall(function() return CoreGui.Name end) and CoreGui
	or player:WaitForChild("PlayerGui")
if espParent:FindFirstChild("AHFruitESP") then espParent.AHFruitESP:Destroy() end
local espFolder = Instance.new("Folder")
espFolder.Name="AHFruitESP"; espFolder.Parent=espParent

-- ============================================================
-- GARDEN / PLOT
-- ============================================================
local function waitAttr(inst, attr, timeout)
	timeout = timeout or 30
	local t0 = tick()
	local v = inst:GetAttribute(attr)
	while v==nil and tick()-t0<timeout do tw(0.5); v=inst:GetAttribute(attr) end
	return v
end

local Gardens  = workspace:WaitForChild("Gardens")
local plotId   = waitAttr(player,"PlotId")
local plot     = Gardens:WaitForChild("Plot"..tostring(plotId))
local spawnPos = plot:WaitForChild("PlotSizeReference")

-- ============================================================
-- CACHE / BLACKLIST
-- ============================================================
local queue    = {}
local sbList   = setmetatable({},{__mode="k"})
local sbIds    = {}
local CTTL     = 8
local valCache = setmetatable({},{__mode="k"})
local ppCache  = setmetatable({},{__mode="k"})
local bestCache= nil; local bestCacheT=0; local BTTL=1.5

local function resetSteal()
	sbList=setmetatable({},{__mode="k"}); sbIds={}
	valCache=setmetatable({},{__mode="k"}); ppCache=setmetatable({},{__mode="k"})
	bestCache=nil; bestCacheT=0
end

-- ============================================================
-- NOCLIP CACHE
-- ============================================================
local noclipPts={}
local function rebuildNC(char)
	noclipPts={}
	if not char then return end
	for _,d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then noclipPts[#noclipPts+1]=d end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then noclipPts[#noclipPts+1]=d end
	end)
end
player.CharacterAdded:Connect(rebuildNC)
if player.Character then rebuildNC(player.Character) end

local function noclipLoop()
	for i=1,#noclipPts do
		local p=noclipPts[i]
		if p.Parent and p.CanCollide then p.CanCollide=false end
	end
end

-- ============================================================
-- RAYFIELD WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
	Name="Astro Hub", Icon=0,
	LoadingTitle="Astro Hub", LoadingSubtitle="By Someone",
	ShowText="Rayfield",
	Theme={
		TextColor=Color3.fromRGB(255,255,255),
		Background=Color3.fromRGB(10,10,10),
		Topbar=Color3.fromRGB(18,18,18),
		Shadow=Color3.fromRGB(0,0,0),
		NotificationBackground=Color3.fromRGB(15,15,15),
		NotificationActionsBackground=Color3.fromRGB(240,240,240),
		TabBackground=Color3.fromRGB(25,25,25),
		TabStroke=Color3.fromRGB(45,45,45),
		TabBackgroundSelected=Color3.fromRGB(245,245,245),
		TabTextColor=Color3.fromRGB(200,200,200),
		SelectedTabTextColor=Color3.fromRGB(15,15,15),
		ElementBackground=Color3.fromRGB(20,20,20),
		ElementBackgroundHover=Color3.fromRGB(30,30,30),
		SecondaryElementBackground=Color3.fromRGB(14,14,14),
		ElementStroke=Color3.fromRGB(45,45,45),
		SecondaryElementStroke=Color3.fromRGB(35,35,35),
		SliderBackground=Color3.fromRGB(255,255,255),
		SliderProgress=Color3.fromRGB(130,130,130),
		SliderStroke=Color3.fromRGB(180,180,180),
		ToggleBackground=Color3.fromRGB(20,20,20),
		ToggleEnabled=Color3.fromRGB(255,255,255),
		ToggleDisabled=Color3.fromRGB(60,60,60),
		ToggleEnabledStroke=Color3.fromRGB(220,220,220),
		ToggleDisabledStroke=Color3.fromRGB(90,90,90),
		ToggleEnabledOuterStroke=Color3.fromRGB(140,140,140),
		ToggleDisabledOuterStroke=Color3.fromRGB(40,40,40),
		DropdownSelected=Color3.fromRGB(40,40,40),
		DropdownUnselected=Color3.fromRGB(20,20,20),
		InputBackground=Color3.fromRGB(18,18,18),
		InputStroke=Color3.fromRGB(55,55,55),
		PlaceholderColor=Color3.fromRGB(140,140,140),
	},
	ToggleUIKeybind="K",
	ConfigurationSaving={ Enabled=true, FolderName=nil, FileName="g2h" },
})
Rayfield:Notify({ Title="Loading...", Content="Please wait.", Duration=5, Image=4483362458 })

-- ============================================================
-- MOVEMENT HELPERS
-- ============================================================

-- Static target, instant lock-on (used by steal / goToSpawn where the
-- destination doesn't move and full orientation matters).
local function moveTo(hrp, tCF)
	return RunService.Heartbeat:Connect(function()
		if hrp and hrp.Parent then
			hrp.CFrame = tCF
			hrp.AssemblyLinearVelocity  = V0
			hrp.AssemblyAngularVelocity = V0
		end
	end)
end

-- Live position of a part or model, re-read fresh every call (so a moving
-- target, e.g. a wandering pet, is tracked instead of a single snapshot).
local function getLivePos(inst)
	if not inst or not inst.Parent then return nil end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart.Position end
		local ok, piv = pcall(function() return inst:GetPivot() end)
		if ok then return piv.Position end
	end
	return nil
end

-- Internal generic follow utility: recomputes the target position every
-- frame via getPosFn (instead of teleporting to one fixed spot) and either
-- snaps to it instantly (speed <= 0) or walks toward it at `speed` studs/sec.
local function moveToFollow(hrp, getPosFn, opts)
	opts = opts or {}
	local speed  = opts.speed or 0
	local offset = opts.offset or V0
	return RunService.Heartbeat:Connect(function(dt)
		if not hrp or not hrp.Parent then return end
		local pos = getPosFn()
		if not pos then return end
		local target = pos + offset
		if speed <= 0 then
			hrp.CFrame = CF(target)
		else
			local cur  = hrp.Position
			local diff = target - cur
			local dist = diff.Magnitude
			if dist > 0.05 then
				hrp.CFrame = CF(cur + diff.Unit * mmin(dist, speed * dt))
			end
		end
		hrp.AssemblyLinearVelocity  = V0
		hrp.AssemblyAngularVelocity = V0
	end)
end

local function getHpPp(fruit)
	local c = ppCache[fruit]
	if c and c.hp.Parent and c.pp.Parent then return c.hp,c.pp end
	local hp = fruit:FindFirstChild("HarvestPart")
	if not hp then return nil,nil end
	local pp = nil
	for _,obj in ipairs(hp:GetDescendants()) do
		if obj.ClassName=="ProximityPrompt" then pp=obj; break end
	end
	if pp then ppCache[fruit]={hp=hp,pp=pp} end
	return hp,pp
end

local function getFVal(fruit)
	local c = valCache[fruit]
	if c and osclk()-c.t<CTTL then return c.v end
	local name = fruit:GetAttribute("CorePartName") or fruit:GetAttribute("SeedName")
	if not name then return 0 end
	local ok,v = pcall(FruitValueCalc, name, getFruitSzMul(fruit),
		fruit:GetAttribute("Mutation"), player, fruit:GetAttribute("DecayAlpha"))
	if not ok or type(v)~="number" then v=0 end
	valCache[fruit]={v=v,t=osclk()}
	return v
end

local function isValid(fruit)
	if sbList[fruit] then return false end
	local fId = fruit:GetAttribute("FruitId")
	if fId and sbIds[fId] then return false end
	local hp,pp = getHpPp(fruit)
	if not hp or not pp or not pp.Enabled then return false end
	local age=fruit:GetAttribute("Age"); local max=fruit:GetAttribute("MaxAge")
	return age~=nil and max~=nil and age>=max
end

-- ============================================================
-- FLING  (SkidFling-based, seamless return, adjustable strength)
-- ============================================================
local function performFling(tp)
	if isFlinging then return end
	isFlinging = true
	local char,hrp = getChar()
	if not char or not hrp then isFlinging=false; return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then isFlinging=false; return end
	local tc = tp.Character
	if not tc then isFlinging=false; return end
	local thum = tc:FindFirstChildOfClass("Humanoid")
	local thrp = thum and thum.RootPart
	if not thrp then isFlinging=false; return end

	local old   = hrp.CFrame
	local oldG  = workspace.Gravity
	local oldFP = workspace.FallenPartsDestroyHeight
	workspace.Gravity = 0
	workspace.FallenPartsDestroyHeight = 0/0

	local bv = Instance.new("BodyVelocity")
	bv.Velocity=V0; bv.MaxForce=V3(9e9,9e9,9e9); bv.Parent=hrp
	hum:SetStateEnabled(Enum.HumanoidStateType.Seated,false)

	local B = 9e7*flingStr; local R = 9e8*flingStr

	local ok,err = pcall(function()
		local t0=tick(); local ang=0
		repeat
			if not thrp.Parent or not hrp.Parent then break end
			ang = ang+120
			local ra = mrad(ang)
			local cfA = CF(thrp.Position)*CF(0,1.5,0)*CFA(ra,0,0)
			hrp.CFrame=cfA; hrp.Velocity=V3(B,B*10,B); hrp.RotVelocity=V3(R,R,R)
			tw()
			if not thrp.Parent or not hrp.Parent then break end
			local cfB = CF(thrp.Position)*CF(0,-1.5,0)*CFA(ra,0,0)
			hrp.CFrame=cfB; hrp.Velocity=V3(B,B*10,B); hrp.RotVelocity=V3(R,R,R)
			tw()
		until tick()-t0>2.5 or not isFlinging
	end)
	if not ok then warn("fling:",err) end

	pcall(function() bv:Destroy() end)
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Seated,true) end)
	workspace.Gravity=oldG; workspace.FallenPartsDestroyHeight=oldFP

	pcall(function()
		if not hrp or not hrp.Parent then return end
		hrp.CFrame=old*CF(0,0.5,0); hrp.Velocity=V0; hrp.RotVelocity=V0
		for _,p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.Velocity=V0; p.RotVelocity=V0 end
		end
	end)
	isFlinging=false
end

-- ============================================================
-- COLLECT  (queue items: fruits, seeds, pets)
-- ============================================================
local function collect(p, maxAtt, tier)
	local char,hrp = getChar()
	if not char or not hrp or not char:FindFirstChild("Head") then return end
	if not p or not p.Parent then return end
	local _,prompt = getHpPp(p)
	if not prompt then
		for _,obj in ipairs(p:GetDescendants()) do
			if obj.ClassName=="ProximityPrompt" then prompt=obj; break end
		end
	end
	if not prompt then return end
	maxAtt = maxAtt or 700

	local oldG   = workspace.Gravity; workspace.Gravity = 0
	local oldPos = char:GetPivot()

	local speed = (tier == 3) and petFollowSpeed or 0
	local conn  = moveToFollow(hrp, function() return getLivePos(p) end, {
		speed = speed, offset = COLLECT_OFFSET,
	})

	local att = 0
	local ok, err = pcall(function()
		if tier == 3 then
			local t = (hrp.Position - getLivePos(p)).Magnitude / 25
			tw(t)
		end
		prompt.HoldDuration = 0
		while prompt.Parent and att < maxAtt do
			att = att + 1
			fireproximityprompt(prompt)
			noclipLoop()
			tw(0.07)
		end
	end)

	conn:Disconnect(); char:PivotTo(oldPos); workspace.Gravity = oldG
	if not ok then warn("collect:", err) end
end

-- ============================================================
-- STEAL
-- ============================================================
local function steal(fruit, owner)
	if not isValid(fruit) then return false end
	local oUid  = tonumber(fruit:GetAttribute("UserId"))
	local pId   = fruit:GetAttribute("PlantId")
	local fId   = fruit:GetAttribute("FruitId") or ""
	if not oUid or not pId then
		sbList[fruit]=true; sbIds[fId]=true; return false
	end
	local char,hrp = getChar()
	if not char or not hrp then return false end
	local hp,pp = getHpPp(fruit)
	if not hp or not pp then sbList[fruit]=true; sbIds[fId]=true; return false end

	local oldG=workspace.Gravity; workspace.Gravity=0
	local old=char:GetPivot()
	local conn=moveTo(hrp, CF(hp.Position-V3(0,2,0)))
	local ok2=false

	local ok,err=pcall(function()
		fireproximityprompt(pp, pp.HoldDuration+0.1)
		tw(pp.HoldDuration+0.35)
		pp.HoldDuration=0; tw(0.05); noclipLoop()
		local att=0
		repeat
			att=att+1
			fireproximityprompt(pp)
			if owner then Networking.Steal.BeginSteal:Fire(owner.UserId,pId,fId) end
			noclipLoop(); tw(0.2)
		until att>=3 or not pp.Parent
		if att>=3 then sbList[fruit]=true; sbIds[fId]=true end
		ok2=true
	end)

	conn:Disconnect(); char:PivotTo(old); workspace.Gravity=oldG
	valCache[fruit]=nil; ppCache[fruit]=nil

	if not ok then
		warn("steal:",err); sbList[fruit]=true; sbIds[fId]=true; return false
	end
	return ok2
end

local function maxInventory()
	local ms=player:GetAttribute("MaxFruitCapacity")
	local cur=player:GetAttribute("FruitCount")
	if not ms or not cur then return false end
	return cur>=ms-1
end

local function stealNearby(centerPos, ownerPlr)
	if not centerPos or not ownerPlr then return end
	if ownerPlr:GetAttribute("IsInOwnGarden")==true then return end
	local garden
	do
		local tp = Players:FindFirstChild(ownerPlr.Name); if not tp then return end
		local pid = tp:GetAttribute("PlotId"); if not pid then return end
		garden = Gardens:FindFirstChild("Plot"..pid)
	end
	if not garden then return end

	local cands = {}
	local plants = garden:FindFirstChild("Plants")
	if not plants then return end
	for _,tgt in ipairs(plants:GetChildren()) do
		local fr = tgt:FindFirstChild("Fruits")
		if not fr then continue end
		for _,tf in ipairs(fr:GetChildren()) do
			if not isValid(tf) then continue end
			local nhp = tf:FindFirstChild("HarvestPart")
			if not nhp then continue end
			local d = (nhp.Position-centerPos).Magnitude
			if d<=NEARBY_R then cands[#cands+1]={f=tf,d=d} end
		end
	end
	table.sort(cands,function(a,b) return a.d<b.d end)

	for _,e in ipairs(cands) do
		if maxInventory() then break end
		if ownerPlr:GetAttribute("IsInOwnGarden")==true then break end
		local tf=e.f
		if not tf or not tf.Parent or not night.Value then continue end
		local tfId=tf:GetAttribute("FruitId")
		local ok2,r2=pcall(steal,tf,ownerPlr)
		if not ok2 then
			warn("nearbySteal:",r2)
			sbList[tf]=true
			if tfId then sbIds[tfId]=true end
			valCache[tf]=nil
		end
	end
end

local function goToSpawn()
	local char,hrp = getChar()
	if not char or not hrp then return end
	local oldG=workspace.Gravity; workspace.Gravity=0
	local tCF
	if spawnPos:IsA("BasePart") then tCF=spawnPos.CFrame
	elseif spawnPos:IsA("Model") then tCF=spawnPos:GetPivot()
	else workspace.Gravity=oldG; return end
	local conn=moveTo(hrp,tCF)
	tw(0.02); Networking.Steal.CompleteSteal:Fire(); tw(0.06)
	conn:Disconnect(); workspace.Gravity=oldG
end

-- ============================================================
-- QUEUE  (tier 3 = pets, tier 2 = seeds, tier 1 = dropped items —
-- sorting descending by tier means pets are always handled first)
-- ============================================================
local function sortQ()
	table.sort(queue,function(a,b) return a.t>b.t end)
end
local function removeTier(tier)
	for i=#queue,1,-1 do if queue[i].t==tier then table.remove(queue,i) end end
end
local function addQ(p,tier,mA)
	for _,v in ipairs(queue) do if v.m==p then return end end
	queue[#queue+1]={m=p,t=tier,a=mA}; sortQ()
end
local function loopAdd(f,tier)
	for _,item in ipairs(f:GetChildren()) do addQ(item,tier) end
end
local function findEntry(tbl,model,tier)
	for i,v in ipairs(tbl) do
		if v.m==model and v.t==tier then return i end
	end
end

-- ============================================================
-- GARDEN HELPERS
-- ============================================================
local function getGarden(t)
	local tp=Players:FindFirstChild(t); if not tp then return end
	local pid=tp:GetAttribute("PlotId"); if not pid then return end
	return Gardens:FindFirstChild("Plot"..pid)
end

local function inGarden(t)
	local p=typeof(t)=="Instance" and t or Players:FindFirstChild(t)
	return p and p:GetAttribute("IsInOwnGarden")==true
end

-- ============================================================
-- PLANT HIDER (anti-lag)
-- Hides only the non-fruit body parts of multi-harvest plants.
-- Single-harvest plants do not have a Fruits folder here, so they stay visible.
-- ============================================================
local hiddenPlantParts = setmetatable({},{__mode="k"})
local hiddenPlants     = setmetatable({},{__mode="k"})
local hidePlantQueued  = setmetatable({},{__mode="k"})
local watchedPlants    = setmetatable({},{__mode="k"})
local watchedFolders   = setmetatable({},{__mode="k"})
local watchedGardens   = setmetatable({},{__mode="k"})
local hidePlantQueue   = {}
local hidePlantHead    = 1
local hidePlantTail    = 0
local plantHiderReady  = false

local function disconnectAll(list)
	if not list then return end
	for _,conn in ipairs(list) do
		if conn then pcall(function() conn:Disconnect() end) end
	end
end

local function isOwnPlot(garden)
	return garden == plot or (garden and garden.Name == "Plot"..tostring(plotId))
end

local function plantHiderEnabledFor(garden)
	if not garden then return false end
	if isOwnPlot(garden) then return hideOwnPlants end
	return hideForeignPlants
end

local function getPlantHideState(plant)
	local plantsFolder=plant and plant.Parent
	local garden=plantsFolder and plantsFolder.Parent
	local fruits=plant and plant:FindFirstChild("Fruits")
	return fruits, fruits and plantHiderEnabledFor(garden)
end

local function pushPlantVisibility(plant)
	if not plant or not plant.Parent or hidePlantQueued[plant] then return end
	hidePlantQueued[plant]=true
	hidePlantTail += 1
	hidePlantQueue[hidePlantTail]=plant
end

local function popPlantVisibility()
	if hidePlantHead>hidePlantTail then return nil end
	local plant=hidePlantQueue[hidePlantHead]
	hidePlantQueue[hidePlantHead]=nil
	hidePlantHead += 1
	if hidePlantHead>hidePlantTail then
		hidePlantQueue={}; hidePlantHead=1; hidePlantTail=0
	end
	return plant
end

local function clearPlantVisibilityQueue()
	hidePlantQueue={}; hidePlantQueued=setmetatable({},{__mode="k"})
	hidePlantHead=1; hidePlantTail=0
end

local function setPartHidden(part)
	if hiddenPlantParts[part]==nil then
		hiddenPlantParts[part]=part.LocalTransparencyModifier
	end
	if part.LocalTransparencyModifier<1 then
		part.LocalTransparencyModifier=1
	end
end

local function restorePart(part)
	local old=hiddenPlantParts[part]
	if old~=nil then
		if part and part.Parent then
			part.LocalTransparencyModifier=old
		end
		hiddenPlantParts[part]=nil
	end
end

local function restorePlantParts(plant)
	for part in pairs(hiddenPlantParts) do
		if not part or not part.Parent then
			hiddenPlantParts[part]=nil
		elseif not plant or part:IsDescendantOf(plant) then
			restorePart(part)
		end
	end
	if plant then
		hiddenPlants[plant]=nil
	else
		hiddenPlants=setmetatable({},{__mode="k"})
	end
end

local function applyPlantVisibility(plant)
	if not plant or not plant.Parent then
		restorePlantParts(plant)
		return
	end

	local fruits, shouldHide=getPlantHideState(plant)

	if not shouldHide then
		restorePlantParts(plant)
		return
	end

	if hiddenPlants[plant] then return end

	for _,obj in ipairs(plant:GetDescendants()) do
		if obj==fruits or obj:IsDescendantOf(fruits) then continue end
		if obj:IsA("BasePart") then setPartHidden(obj) end
	end
	hiddenPlants[plant]=true
end

local function unwatchPlant(plant)
	disconnectAll(watchedPlants[plant])
	watchedPlants[plant]=nil
	hidePlantQueued[plant]=nil
	hiddenPlants[plant]=nil
	restorePlantParts(plant)
end

local function watchPlant(plant)
	if watchedPlants[plant] then return end
	watchedPlants[plant]={
		plant.DescendantAdded:Connect(function(obj)
			if not (hideForeignPlants or hideOwnPlants) then return end
			if obj.Name=="Fruits" then
				hiddenPlants[plant]=nil
				pushPlantVisibility(plant)
				return
			end
			if obj:IsA("BasePart") then
				local fruits, shouldHide=getPlantHideState(plant)
				if shouldHide and not obj:IsDescendantOf(fruits) then
					setPartHidden(obj)
				elseif hiddenPlantParts[obj]~=nil then
					restorePart(obj)
				end
			end
		end),
		plant.ChildRemoved:Connect(function(obj)
			if obj.Name=="Fruits" then
				hiddenPlants[plant]=nil
				pushPlantVisibility(plant)
			end
		end),
		plant.AncestryChanged:Connect(function()
			if not plant:IsDescendantOf(Gardens) then unwatchPlant(plant) end
		end),
	}
end

local function queueGardenPlants(garden)
	local plants=garden and garden:FindFirstChild("Plants")
	if not plants then return end
	for _,plant in ipairs(plants:GetChildren()) do
		watchPlant(plant)
		pushPlantVisibility(plant)
	end
end

local function watchPlantsFolder(plants)
	if watchedFolders[plants] then return end
	watchedFolders[plants]={
		plants.ChildAdded:Connect(function(plant)
			watchPlant(plant)
			pushPlantVisibility(plant)
		end),
		plants.ChildRemoved:Connect(function(plant)
			unwatchPlant(plant)
		end),
	}
	for _,plant in ipairs(plants:GetChildren()) do watchPlant(plant) end
end

local function watchGarden(garden)
	if watchedGardens[garden] then return end
	watchedGardens[garden]={
		garden.ChildAdded:Connect(function(obj)
			if obj.Name=="Plants" then
				watchPlantsFolder(obj)
				queueGardenPlants(garden)
			end
		end),
	}
	local plants=garden:FindFirstChild("Plants")
	if plants then watchPlantsFolder(plants) end
end

local function queueAllPlantVisibility()
	for _,garden in ipairs(Gardens:GetChildren()) do
		watchGarden(garden)
		queueGardenPlants(garden)
	end
end

local function ensurePlantHider()
	if plantHiderReady then return end
	plantHiderReady=true
	for _,garden in ipairs(Gardens:GetChildren()) do watchGarden(garden) end
	Gardens.ChildAdded:Connect(function(garden)
		watchGarden(garden)
		if hideForeignPlants or hideOwnPlants then queueGardenPlants(garden) end
	end)
end

local function refreshPlantHider()
	ensurePlantHider()
	if hideForeignPlants or hideOwnPlants then
		queueAllPlantVisibility()
	else
		clearPlantVisibilityQueue()
		restorePlantParts()
	end
end

ts(function()
	while true do
		local waitTime=HIDE_PLANT_IDLE_INTERVAL
		if hideForeignPlants or hideOwnPlants then
			ensurePlantHider()

			local done=0
			while done<HIDE_PLANT_BUDGET do
				local plant=popPlantVisibility()
				if not plant then break end
				hidePlantQueued[plant]=nil
				applyPlantVisibility(plant)
				done += 1
			end
			if done>0 then waitTime=HIDE_PLANT_INTERVAL end
		end
		tw(waitTime)
	end
end)

-- ============================================================
-- GLOBAL FRUIT REGISTRY (event-driven; shared by ESP + Steal Best)
--
-- The old approach had BOTH the ESP loop (every 0.5s) and the steal-best
-- search re-walking Gardens → Plants → Fruits from scratch with
-- GetChildren() at every level, every single time. That tree-walk cost
-- scales with total fruit count across every player on the server and was
-- the single biggest perf sink in the script.
--
-- Instead we watch the tree ONCE: ChildAdded on Gardens/Plants/Fruits keeps
-- two flat, weak-keyed sets up to date as the world changes, so both
-- systems below just iterate a flat table instead of walking folders.
--
-- knownFruits     -> every fruit AND single-harvest "fruit-as-plant" model
--                    (mirrors what ESP used to display labels on).
-- stealableFruits -> only true Fruits-folder children (mirrors the
--                    original steal-best scope exactly; single-harvest
--                    plants were never steal targets and still aren't).
-- ============================================================
local knownFruits     = setmetatable({},{__mode="k"})
local stealableFruits = setmetatable({},{__mode="k"})
local frWatchedFruitsFolders = setmetatable({},{__mode="k"})
local frWatchedPlants        = setmetatable({},{__mode="k"})
local frWatchedPlantsFolders = setmetatable({},{__mode="k"})
local frWatchedGardens        = setmetatable({},{__mode="k"})

local function registerFruit(fruit, stealable)
	knownFruits[fruit]=true
	if stealable then stealableFruits[fruit]=true end
end

local function watchFruitsFolder(fr)
	if frWatchedFruitsFolders[fr] then return end
	frWatchedFruitsFolders[fr]=true
	for _,f in ipairs(fr:GetChildren()) do registerFruit(f,true) end
	fr.ChildAdded:Connect(function(f) registerFruit(f,true) end)
end

local function watchFruitPlant(plant)
	if frWatchedPlants[plant] then return end
	frWatchedPlants[plant]=true
	local fr=plant:FindFirstChild("Fruits")
	if fr then
		watchFruitsFolder(fr)
	else
		registerFruit(plant,false) -- single-harvest: plant itself is the "fruit", ESP-only
	end
	plant.ChildAdded:Connect(function(obj)
		if obj.Name=="Fruits" then
			knownFruits[plant]=nil -- it's no longer the fallback "fruit" itself
			watchFruitsFolder(obj)
		end
	end)
end

local function watchFruitPlants(plantsF)
	if frWatchedPlantsFolders[plantsF] then return end
	frWatchedPlantsFolders[plantsF]=true
	for _,plant in ipairs(plantsF:GetChildren()) do watchFruitPlant(plant) end
	plantsF.ChildAdded:Connect(watchFruitPlant)
end

local function watchFruitGarden(garden)
	if frWatchedGardens[garden] then return end
	frWatchedGardens[garden]=true
	local plantsF=garden:FindFirstChild("Plants")
	if plantsF then watchFruitPlants(plantsF) end
	garden.ChildAdded:Connect(function(obj)
		if obj.Name=="Plants" then watchFruitPlants(obj) end
	end)
end

local function fruitRegistryInit()
	for _,g in ipairs(Gardens:GetChildren()) do watchFruitGarden(g) end
	Gardens.ChildAdded:Connect(watchFruitGarden)
end
fruitRegistryInit()

local function findBestTarget()
	if bestCache and bestCache.plr and bestCache.plr.Parent and osclk()-bestCacheT<BTTL then
		return bestCache.plr
	end
	local bPlr,bV=nil,-1
	for fruit in pairs(stealableFruits) do
		if not fruit.Parent then
			stealableFruits[fruit]=nil; knownFruits[fruit]=nil; continue
		end
		if not isValid(fruit) then continue end
		local ownerUid=tonumber(fruit:GetAttribute("UserId"))
		if not ownerUid then continue end
		local plr=Players:GetPlayerByUserId(ownerUid)
		if not plr or plr==player then continue end
		local v=getFVal(fruit)
		if v>bV then bV=v; bPlr=plr end
	end
	bestCache={plr=bPlr}; bestCacheT=osclk()
	return bPlr
end

local function getStealFruit(plr)
	if not plr then return nil end
	local g=getGarden(plr.Name); if not g then return nil end
	local plants=g:FindFirstChild("Plants"); if not plants then return nil end
	local best,bV=nil,-1
	for _,tgt in ipairs(plants:GetChildren()) do
		local fr=tgt:FindFirstChild("Fruits"); if not fr then continue end
		for _,tf in ipairs(fr:GetChildren()) do
			if isValid(tf) then
				if stealBest then
					local v=getFVal(tf); if v>bV then bV=v; best=tf end
				else
					return tf
				end
			end
		end
	end
	return best
end

-- ============================================================
-- LISTS
-- ============================================================
local function getPlrList()
	local t={}
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=player then t[#t+1]=p.Name end
	end
	return t
end
local function getSeedList()
	local t={}
	for _,d in pairs(SeedData) do
		if d.SeedName and d.RestockShop then t[#t+1]=d.SeedName end
	end
	return t
end
local function getGearList()
	local t={}
	local ok,items=pcall(function() return RepStore.StockValues.GearShop.Items:GetChildren() end)
	if ok and items then for _,d in ipairs(items) do if d.Name then t[#t+1]=d.Name end end end
	return t
end
local function getPetList()
	local t={}
	for _,d in pairs(PetData) do if d.DisplayName then t[#t+1]=d.DisplayName end end
	return t
end

-- ============================================================
-- AUTO SELL / BUY
-- ============================================================
local function sellAll()
	if not autoSell then return end
	local inv=player:GetAttribute("FruitCount")
	if inv and inv>=autoSellSize then Networking.NPCS.SellAll:Fire() end
end
player:GetAttributeChangedSignal("FruitCount"):Connect(sellAll)

local function buySeeds(name,amt)
	if not autoBuy or not table.find(autoBuySel,name) then return end
	ts(function() for _=1,amt do Networking.SeedShop.PurchaseSeed:Fire(name) end end)
end
local function buyAllSeeds()
	for _,i in ipairs(RepStore.StockValues.SeedShop.Items:GetChildren()) do buySeeds(i.Name,i.Value) end
end
local function buyGear(name,amt)
	if not autoBuyGear or not table.find(autoBuyGearSel,name) then return end
	ts(function() for _=1,amt do Networking.GearShop.PurchaseGear:Fire(name) end end)
end
local function buyAllGear()
	for _,i in ipairs(RepStore.StockValues.GearShop.Items:GetChildren()) do buyGear(i.Name,i.Value) end
end

for _,v in ipairs(RepStore.StockValues.GearShop.Items:GetChildren()) do
	v:GetPropertyChangedSignal("Value"):Connect(function()
		buyGear(v.Name,v.Value); td(1,function() buyGear(v.Name,v.Value) end)
	end)
end
for _,v in ipairs(RepStore.StockValues.SeedShop.Items:GetChildren()) do
	v:GetPropertyChangedSignal("Value"):Connect(function()
		buySeeds(v.Name,v.Value); td(1,function() buySeeds(v.Name,v.Value) end)
	end)
end

ts(function() while true do tw(90); buyAllGear(); buyAllSeeds() end end)

-- ============================================================
-- PETS
-- ============================================================
local function addPetQ(p)
	if not autoBuyPets then return end
	local n=p:GetAttribute("PetName")
	if not n or not table.find(autoBuyPetSel,n) then return end
	if findEntry(queue,p,3) then return end
	addQ(p,3,8)
end
WildPetSpawns.ChildAdded:Connect(addPetQ)
local function addAllPetsQ()
	for _,pet in ipairs(WildPetSpawns:GetChildren()) do addPetQ(pet) end
end

-- ============================================================
-- TASK: ANTI-AFK
-- ============================================================
ts(function()
	while true do
		tw(840)
		if antiAfk then
			local char=player.Character
			if char then
				local hum=char:FindFirstChild("Humanoid")
				if hum then hum.Jump=true end
			end
		end
	end
end)

-- ============================================================
-- TASK: STEAL + AUTO-FLING + NEARBY-STEAL
-- Flattened with early continues so a branch that already waited (tw(1),
-- tw(0.5), tw(3.2)...) doesn't also pay the trailing per-iteration tw() —
-- the old version waited twice in those paths.
-- ============================================================
ts(function()
	while true do
		local modeOn=(stealTgtOn and stealTgt and Players:FindFirstChild(stealTgt)) or stealBest

		if modeOn and not isFlinging then
			local tPlr
			if stealBest then
				tPlr=findBestTarget()
			elseif stealTgtOn and stealTgt then
				tPlr=Players:FindFirstChild(stealTgt)
			end

			if not tPlr then
				tw(0.5); continue
			end

			if inGarden(tPlr) then
				if flingGarden and night.Value then
					bestCache=nil
					ts(function()
						local ok,err=pcall(performFling,tPlr)
						if not ok then warn("auto-fling:",err); isFlinging=false end
					end)
					tw(3.2)
				else
					tw(1)
				end
				continue
			end

			if not night.Value then
				tw(1); continue
			end

			if maxInventory() then
				pcall(goToSpawn); tw(1); continue
			end

			local fruit=getStealFruit(tPlr)
			if not (fruit and fruit.Parent) then
				tw(0.5); continue
			end

			local fId=fruit:GetAttribute("FruitId")
			local ok,res=pcall(steal,fruit,tPlr)
			if ok and res then
				bestCache=nil
				local mhp=fruit:FindFirstChild("HarvestPart")
				if mhp and not maxInventory() then
					stealNearby(mhp.Position,tPlr)
				end
				pcall(goToSpawn)
			elseif not ok then
				warn("steal:",res)
				sbList[fruit]=true
				if fId then sbIds[fId]=true end
				valCache[fruit]=nil
			end

		elseif not isFlinging and #queue>0 then
			local item=table.remove(queue,1)
			if item and item.m and item.m.Parent then pcall(collect,item.m,item.a,item.t) end
		end
		tw()
	end
end)

-- ============================================================
-- TASK: UTILITY (noclip, speed)
-- perf: throttled to 20Hz (was every single frame) and only writes
-- WalkSpeed/JumpHeight when they actually change.
-- ============================================================
ts(function()
	while tw(0.05) do
		if noclip then noclipLoop() end
		local char=player.Character
		if char then
			local hum=char:FindFirstChild("Humanoid")
			if hum then
				if hum.WalkSpeed  ~= walkSpd then hum.WalkSpeed  = walkSpd end
				if hum.JumpHeight ~= jumpH   then hum.JumpHeight = jumpH   end
			end
		end
	end
end)

-- ============================================================
-- TASK: AUTO COLLECT (own fruits)
-- Filters, in cheapest-first order:
--   1) ripeness (Age >= MaxAge)               — plain attribute read
--   2) mutation requirement                   — plain attribute read
--   3) max size multiplier (0 = unlimited)    — a few attribute reads
--   4) value range (acMax 0 = unlimited)      — cached, can recompute
-- perf: scan interval throttled to AC_INTERVAL instead of every frame.
-- ============================================================
ts(function()
	while true do
		tw(AC_INTERVAL)
		if not autoCollect or not plot or maxInventory() then continue end
		local pPlants=plot:FindFirstChild("Plants"); if not pPlants then continue end

		for _,plant in ipairs(pPlants:GetChildren()) do
			if not autoCollect then break end
			local fr=plant:FindFirstChild("Fruits")
			local tgts=fr and fr:GetChildren() or (not ignoreSingleHarvest and {plant}) or {}

			for _,fruit in ipairs(tgts) do
				if not autoCollect then break end

				local age=fruit:GetAttribute("Age") or 0
				local mx=fruit:GetAttribute("MaxAge") or 1
				if age<mx then continue end -- not ripe yet

				if collectMut then
					local mut=fruit:GetAttribute("Mutation")
					if not mut or mut=="" then continue end
				end

				if acMaxSize>0 and getFruitSzMul(fruit)>acMaxSize then continue end

				local val=getFVal(fruit)
				if val<acMin then continue end
				if acMax>0 and val>acMax then continue end

				local fId=fruit:GetAttribute("FruitId")
				local pId=fruit:GetAttribute("PlantId")
				if pId then Networking.Garden.CollectFruit:Fire(pId,fId or ""); tw(0.03) end
			end
		end
	end
end)

-- ============================================================
-- TASK: MANUAL FLING
-- ============================================================
ts(function()
	while true do
		tw(0.2)
		if not flingOn or not flingTgt or isFlinging then continue end
		local tp=Players:FindFirstChild(flingTgt); if not tp then continue end
		local ok,err=pcall(performFling,tp)
		if not ok then warn("manualFling:",err); isFlinging=false end
		tw(3.5)
	end
end)

-- ============================================================
-- ESP
-- perf: discovery is now event-driven via the global fruit registry
-- above — no more periodic Gardens → Plants → Fruits tree walk every
-- 0.5s. The loop just iterates the flat, already-known fruit set.
-- ============================================================
local function fmtNum(n)
	if not n then return "0" end
	if n>=1e6 then return string.format("%.2fM",n/1e6):gsub("%.00M","M")
	elseif n>=1000 then return string.format("%.2fk",n/1000):gsub("%.00k","k")
	else return tostring(mfloor(n)) end
end

local function createEsp(fruit)
	local val=getFVal(fruit); if val<espMin then return end
	if not activeESPs[fruit] then
		local hl=Instance.new("Highlight")
		hl.Parent=fruit
		hl.Enabled=espHighlight
		local bg=Instance.new("BillboardGui")
		bg.Adornee=fruit:FindFirstChild("HarvestPart") or fruit
		bg.Size=UDim2.new(0,100,0,50); bg.StudsOffset=V3(0,2,0); bg.AlwaysOnTop=true
		local tl=Instance.new("TextLabel")
		tl.Name="VL"; tl.Parent=bg; tl.Size=UDim2.new(1,0,1,0)
		tl.BackgroundTransparency=1; tl.TextColor3=Color3.new(0.3,1,0.3)
		tl.TextStrokeTransparency=0; tl.Text="Val: "..fmtNum(val)
		tl.Font=Enum.Font.GothamBold; tl.TextSize=14; bg.Parent=espFolder
		activeESPs[fruit]={u=bg,h=hl}; activeESPVals[fruit]=val
	else
		if activeESPVals[fruit]~=val then
			activeESPVals[fruit]=val
			local tl=activeESPs[fruit].u:FindFirstChild("VL")
			if tl then tl.Text="Val: "..fmtNum(val) end
		end
		activeESPs[fruit].h.Enabled=espHighlight
	end
end

local function destTable(t)
	for i, inst in pairs(t) do
		inst:Destroy()
	end
end

ts(function()
	while tw(0.5) do
		local rem={}
		for fruit in pairs(activeESPs) do
			if not espOn or not fruit or not fruit.Parent or getFVal(fruit)<espMin then
				rem[#rem+1]=fruit
			end
		end
		for _,fruit in ipairs(rem) do
			if activeESPs[fruit] then destTable(activeESPs[fruit]) end
			activeESPs[fruit]=nil; activeESPVals[fruit]=nil
		end
		if not espOn then continue end

		for fruit in pairs(knownFruits) do
			if not fruit.Parent then knownFruits[fruit]=nil; continue end
			createEsp(fruit)
		end
	end
end)

dropped.ChildAdded:Connect(function(p) if collectDropped then addQ(p,1) end end)
seeds.ChildAdded:Connect(function(p)   if collectSeeds   then addQ(p,2) end end)

-- ============================================================
-- PARTICLES
-- ============================================================
local function disableAllParticles()
	for _, particle in ipairs(workspace:GetDescendants()) do
		if particle:IsA("ParticleEmitter") then
			particle.Enabled = not disableParticles
		end
	end
end

workspace.DescendantAdded:Connect(function(p)
	if p and p:IsA("ParticleEmitter") and disableParticles then
		p.Enabled = false
	end
end)

-- ============================================================
-- UI TABS
-- ============================================================
local InfoTab   = Window:CreateTab("Info",   4483362458)
local PlayerTab = Window:CreateTab("Player", 4483362458)
local AutoTab   = Window:CreateTab("Auto",   4483362458)
local StealTab  = Window:CreateTab("Steal",  4483362458)
local PetTab    = Window:CreateTab("Pets",   4483362458)
local VisualTab = Window:CreateTab("Visual", 4483362458)

local dcInvite = "https://discord.gg/VEGdZccS"

-- ---- Info ----
InfoTab:CreateSection("About")
InfoTab:CreateLabel("Astro Hub — Grow a Garden 2")
InfoTab:CreateParagraph({ Title="Discord:", Content=dcInvite })
InfoTab:CreateButton({
	Name = "Copy to clipboard",
	Callback = function() setclipboard(dcInvite) end,
})
InfoTab:CreateSection("Notes")
InfoTab:CreateParagraph({ Title="NOTE:", Content="Stealing WIP" })
InfoTab:CreateSection("Hotkeys")
InfoTab:CreateLabel("K — Toggle UI")

-- ---- Player ----
PlayerTab:CreateSection("Main")
PlayerTab:CreateToggle({ Name="Noclip", CurrentValue=noclip, Flag="noclip",
	Callback=function(v) noclip=v end })
PlayerTab:CreateSlider({ Name="Walk Speed", Range={0,50}, Increment=1,
	CurrentValue=walkSpd, Flag="walkspd",
	Callback=function(v) walkSpd=v end })
PlayerTab:CreateSlider({ Name="Jump Height", Range={0,30}, Increment=0.5,
	CurrentValue=jumpH, Flag="jumph",
	Callback=function(v) jumpH=v end })

PlayerTab:CreateSection("Misc")
PlayerTab:CreateToggle({ Name="Anti-AFK (WIP)", CurrentValue=antiAfk, Flag="antiafk",
	Callback=function(v) antiAfk=v end })

-- ---- Steal ----
StealTab:CreateSection("Steal Best")
StealTab:CreateToggle({ Name="Steal Best", CurrentValue=stealBest, Flag="stealbesttoggled",
	Callback=function(v)
		stealBest=v; valCache=setmetatable({},{__mode="k"}); bestCache=nil
	end })

StealTab:CreateSection("Steal Target")
local StealTgtDd = StealTab:CreateDropdown({
	Name="Pick Target", Options={}, CurrentOption={},
	MultipleOptions=false, Flag=nil,
	Callback=function(o) stealTgt=o[1]; resetSteal() end })
StealTab:CreateToggle({ Name="Steal Target", CurrentValue=stealTgtOn, Flag="stealtargettoggled",
	Callback=function(v) stealTgtOn=v; if v then resetSteal() end end })

StealTab:CreateSection("Auto-Fling")
StealTab:CreateToggle({ Name="Fling if in Garden", CurrentValue=flingGarden, Flag="flingongarden",
	Callback=function(v) flingGarden=v end })
StealTab:CreateSlider({ Name="Fling Strength", Range={1,10}, Increment=1,
	CurrentValue=flingStr, Flag="flingstrength",
	Callback=function(v) flingStr=v end })

StealTab:CreateSection("Manual Fling")
local FlingTgtDd = StealTab:CreateDropdown({
	Name="Fling Target", Options={}, CurrentOption={},
	MultipleOptions=false, Flag=nil,
	Callback=function(o) flingTgt=o[1] end })
StealTab:CreateToggle({ Name="Fling Player", CurrentValue=flingOn, Flag="flingplayer",
	Callback=function(v) flingOn=v end })

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
	CurrentValue=autoSellSize, Flag="autosellinventorysize",
	Callback=function(v) autoSellSize=v; if autoSell then sellAll() end end })

AutoTab:CreateSection("Buying")
AutoTab:CreateDropdown({ Name="Select Seeds", Options=getSeedList(), CurrentOption={},
	MultipleOptions=true, Flag="autobuyselected",
	Callback=function(o) autoBuySel=o; buyAllSeeds() end })
AutoTab:CreateToggle({ Name="Auto Buy Seeds", CurrentValue=autoBuy, Flag="autobuyseeds",
	Callback=function(v) autoBuy=v; if v then buyAllSeeds() end end })
AutoTab:CreateDropdown({ Name="Select Gear", Options=getGearList(), CurrentOption={},
	MultipleOptions=true, Flag="autobuygearselected",
	Callback=function(o) autoBuyGearSel=o; buyAllGear() end })
AutoTab:CreateToggle({ Name="Auto Buy Gear", CurrentValue=autoBuyGear, Flag="autobuygear",
	Callback=function(v) autoBuyGear=v; if v then buyAllGear() end end })

AutoTab:CreateSection("Own Garden")
AutoTab:CreateToggle({ Name="Auto Collect Own Fruits", CurrentValue=autoCollect, Flag="autocollect",
	Callback=function(v) autoCollect=v end })
AutoTab:CreateToggle({ Name="Requires Mutation", CurrentValue=collectMut, Flag="collectmutation",
	Callback=function(v) collectMut=v end })
AutoTab:CreateToggle({ Name="Ignore Single-Harvest", CurrentValue=ignoreSingleHarvest, Flag="ignoresingleharvest",
	Callback=function(v) ignoreSingleHarvest=v end })
AutoTab:CreateSlider({ Name="Min Value", Range={0,100000}, Increment=10,
	CurrentValue=acMin, Flag="autocollectmin",
	Callback=function(v) acMin=v end })
AutoTab:CreateSlider({ Name="Max Value (0 = any)", Range={0,1000000}, Increment=100,
	CurrentValue=acMax, Flag="autocollectmax",
	Callback=function(v) acMax=v end })
AutoTab:CreateSlider({ Name="Max Size Multi (0 = any)", Range={0,50}, Increment=1,
	CurrentValue=acMaxSize, Flag="autocollectmaxsize",
	Callback=function(v) acMaxSize=v end })

-- ---- Visual ----
VisualTab:CreateSection("ESP")
VisualTab:CreateToggle({ Name="Enable Fruit ESP", CurrentValue=espOn, Flag="fruitesp",
	Callback=function(v) espOn=v end })
VisualTab:CreateToggle({ Name="Highlight Fruits", CurrentValue=espOn, Flag="esphighlight",
	Callback=function(v) espHighlight=v end })
VisualTab:CreateSlider({ Name="ESP Min Value", Range={0,999}, Increment=1, Suffix="k",
	CurrentValue=espMin, Flag="espminvalue",
	Callback=function(v) espMin=v*1000 end })
VisualTab:CreateSection("Performance")
VisualTab:CreateToggle({ Name="No Particles", CurrentValue=disableParticles, Flag="noparticlestoggle",
	Callback=function(v) disableParticles=v; disableAllParticles() end })
VisualTab:CreateToggle({ Name="Hide Foreign Plant Bodies", CurrentValue=hideForeignPlants, Flag="hideforeignplants",
	Callback=function(v) hideForeignPlants=v; refreshPlantHider() end })
VisualTab:CreateToggle({ Name="Hide Own Plant Bodies", CurrentValue=hideOwnPlants, Flag="hideownplants",
	Callback=function(v) hideOwnPlants=v; refreshPlantHider() end })
VisualTab:CreateSection("Predictions (TBA)")
VisualTab:CreateToggle({ Name="Predict Events", CurrentValue=false, Flag="predictevents",
	Callback=function() end })
VisualTab:CreateToggle({ Name="Predict Stocks", CurrentValue=false, Flag="predictstocks",
	Callback=function() end })

-- ---- Pets ----
PetTab:CreateSection("Auto Buy")
PetTab:CreateToggle({ Name="Buy Pets", CurrentValue=autoBuyPets, Flag="buypets",
	Callback=function(v) autoBuyPets=v; if v then addAllPetsQ() end end })
PetTab:CreateDropdown({ Name="Select Pets", Options=getPetList(), CurrentOption={},
	MultipleOptions=true, Flag="autobuypetsselect",
	Callback=function(o) autoBuyPetSel=o; addAllPetsQ() end })

PetTab:CreateSection("Movement")
PetTab:CreateSlider({ Name="Pet Follow Speed", Range={0,60}, Increment=1, Suffix=" studs/s (0 = instant)",
	CurrentValue=petFollowSpeed, Flag="petfollowspeed",
	Callback=function(v) petFollowSpeed=v end })

-- ============================================================
-- PLAYER LIST REFRESH
-- ============================================================
local function refreshPlrLists()
	local list=getPlrList()
	StealTgtDd:Refresh(list)
	FlingTgtDd:Refresh(list)
end
refreshPlrLists()
Players.PlayerAdded:Connect(refreshPlrLists)
Players.PlayerRemoving:Connect(refreshPlrLists)

Rayfield:LoadConfiguration()
