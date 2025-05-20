-- Script: CaveGenerator
-- Path: ServerScriptService/CaveGenerator.lua
-- VERSION 6.0.5 - Logging System Integrated

local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
-- Terrain will be checked after Logger is set up

-- Dependencies
local CaveConfig = require(script.Parent.CaveConfig) 
if not CaveConfig then 
	error("CaveGenerator FATAL @ PRE-LOG: CaveConfig module failed to load or returned nil. Script cannot run.") 
	return 
end

-- Load and configure the Logger
local Logger = require(script.Parent.Logger) 
if not Logger then
	error("CaveGenerator FATAL @ PRE-LOG: Logger module failed to load or returned nil. Script cannot run.")
	return
end
Logger:Configure(CaveConfig.Logging)

-- Now you can use the Logger for further setup checks
local Terrain = Workspace:FindFirstChildOfClass("Terrain") 
if not Terrain then
	Logger:Fatal("Init", "Terrain not found in Workspace. Script will not run.")
	return
end
Logger:Info("Init", "Terrain object located successfully.")

Logger:Info("Init", "Attempting to load NoiseGenerator...")
local NoiseGeneratorModule = require(script.Parent.NoiseGenerator)
if not NoiseGeneratorModule then 
	Logger:Fatal("Init", "NoiseGenerator module failed to load or returned nil.") 
	return 
end
Logger:Info("Init", "NoiseGenerator loaded.")

local Perlin = NoiseGeneratorModule.PerlinModule
if not Perlin then 
	Logger:Fatal("Init", "Perlin module (via NoiseGeneratorModule.PerlinModule) is nil.") 
	return 
end
if typeof(Perlin.FBM_Base) ~= "function" then
	Logger:Fatal("Init", "Perlin.FBM_Base is not a function!")
	return
end
if typeof(NoiseGeneratorModule.GetValue) ~= "function" then
	Logger:Fatal("Init", "NoiseGeneratorModule:GetValue is not a function!")
	return
end
Logger:Info("Init", "Perlin module access verified.")
Logger:Info("Init", "CaveConfig check: Main Threshold = %s", tostring(CaveConfig.Threshold))

-- THIS MUST BE DEFINED BEFORE IT'S CALLED IN PHASE 7
local function splitString(inputString, separator)
	if separator == nil then
		separator = "%s" 
	end
	if inputString == nil then return {} end 
	local t = {}
	for strChunk in string.gmatch(inputString, "([^"..separator.."]+)") do
		table.insert(t, strChunk)
	end
	return t
end -- End splitString

-- Script-level state variables
local grid 
local regionSize = CaveConfig.RegionSize
local origin = Vector3.new(-regionSize.X / 2, -regionSize.Y, -regionSize.Z / 2) 
local cellSize = CaveConfig.CellSize

local gridSizeX = math.ceil(regionSize.X / cellSize)
local gridSizeY = math.ceil(regionSize.Y / cellSize)
local gridSizeZ = math.ceil(regionSize.Z / cellSize)
local yieldCounter = 0

math.randomseed(CaveConfig.Seed)
local Rng = Random.new(CaveConfig.Seed) 

local SOLID = 1
local AIR = 0

-- =============================================================================
-- III. GRID3D DEFINITION 
-- =============================================================================
local Grid3D = {}
Grid3D.__index = Grid3D

function Grid3D.new(sX, sY, sZ, defaultVal)
	local newGrid = setmetatable({}, Grid3D)
	newGrid.size = Vector3.new(sX, sY, sZ)
	newGrid.data = table.create(sX * sY * sZ, defaultVal) 
	Logger:Debug("Grid3D", "new: Created grid %dx%dx%d. Data table size: %d", sX, sY, sZ, #newGrid.data) 
	return newGrid
end -- End Grid3D.new

function Grid3D:index(x, y, z)
	if not self:isInBounds(x, y, z) then
		return nil
	end
	return math.floor(z - 1) * self.size.X * self.size.Y + math.floor(y - 1) * self.size.X + math.floor(x)
end -- End Grid3D:index

function Grid3D:get(x, y, z)
	local idx = self:index(x, y, z)
	if not idx then return nil end 
	return self.data[idx]
end -- End Grid3D:get

function Grid3D:set(x, y, z, value)
	local idx = self:index(x, y, z)
	if not idx then 
		Logger:Warn("Grid3D", "set: Attempted set out of bounds for (%s,%s,%s)", tostring(x),tostring(y),tostring(z)) 
		return false 
	end
	self.data[idx] = value
	return true
end -- End Grid3D:set

function Grid3D:isInBounds(x, y, z)
	if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
		Logger:Warn("Grid3D", "isInBounds: Received non-number coords: %s, %s, %s", tostring(x),tostring(y),tostring(z))
		return false
	end
	return x >= 1 and x <= self.size.X and
		y >= 1 and y <= self.size.Y and
		z >= 1 and z <= self.size.Z
end -- End Grid3D:isInBounds

function Grid3D:getNeighborCount(x, y, z, cellType, connectivity)
	connectivity = connectivity or 26 
	local count = 0
	local S = 1 
	for dz = -S, S do
		for dy = -S, S do
			for dx = -S, S do 
				if dx == 0 and dy == 0 and dz == 0 then continue end
				local distSq = dx*dx + dy*dy + dz*dz
				if connectivity == 6 and distSq > 1 then continue end
				if connectivity == 18 and distSq > 2 then continue end
				local val = self:get(x + dx, y + dy, z + dz)
				if val == cellType then count = count + 1 end
			end
		end
	end
	return count
end -- End Grid3D:getNeighborCount

local function TestGridWithFalseValues()
	Logger:Info("Grid3DTest", "--- TestGridWithFalseValues ---")
	local testGridSize = 5
	local testVisited = Grid3D.new(testGridSize, testGridSize, testGridSize, false)

	if not testVisited or not testVisited.data then
		Logger:Error("Grid3DTest", "TEST FAIL: testVisited grid is nil or no data table.")
		return
	end
	Logger:Debug("Grid3DTest", "TestGrid created. Size of data table: %d", #testVisited.data)

	local val_1_1_1 = testVisited:get(1, 1, 1)
	Logger:Debug("Grid3DTest", "TEST: Value at (1,1,1) from fresh 'false' grid: %s (Type: %s)", tostring(val_1_1_1), type(val_1_1_1))

	if val_1_1_1 == false then
		Logger:Debug("Grid3DTest", "TEST PASS: Fresh 'false' grid correctly returns false for get(1,1,1).")
	else
		Logger:Error("Grid3DTest", "TEST FAIL: Fresh 'false' grid DID NOT return false for get(1,1,1)!")
	end

	if not val_1_1_1 then
		Logger:Debug("Grid3DTest", "TEST: 'not val_1_1_1' is TRUE. This is correct if val_1_1_1 is false or nil.")
	else
		Logger:Debug("Grid3DTest", "TEST: 'not val_1_1_1' is FALSE. This is correct if val_1_1_1 is true or a truthy value.")
	end

	testVisited:set(1,1,1, true)
	local val_1_1_1_after_set_true = testVisited:get(1,1,1)
	Logger:Debug("Grid3DTest", "TEST: Value at (1,1,1) after set to true: %s (Type: %s)", tostring(val_1_1_1_after_set_true), type(val_1_1_1_after_set_true))

	if val_1_1_1_after_set_true == true then
		Logger:Debug("Grid3DTest", "TEST PASS: set(true) then get() works.")
	else
		Logger:Error("Grid3DTest", "TEST FAIL: set(true) then get() did not return true.")
	end

	local val_2_2_2_unmodified = testVisited:get(2,2,2) -- Should still be false
	Logger:Debug("Grid3DTest", "TEST: Value at (2,2,2) (unmodified): %s (Type: %s)", tostring(val_2_2_2_unmodified), type(val_2_2_2_unmodified))
	if val_2_2_2_unmodified == false then
		Logger:Debug("Grid3DTest", "TEST PASS: Unmodified cell in 'false' grid returns false.")
	else
		Logger:Error("Grid3DTest", "TEST FAIL: Unmodified cell in 'false' grid did not return false.")
	end
	Logger:Info("Grid3DTest", "--- TestGridWithFalseValues END ---")
end -- End TestGridWithFalseValues
-- =============================================================================
-- IV. UTILITY FUNCTIONS 
-- =============================================================================
local function doYield() 
	yieldCounter = yieldCounter + 1
	if yieldCounter >= CaveConfig.GlobalYieldBatchSize then RunService.Heartbeat:Wait(); yieldCounter = 0 end
end -- End doYield

local function cellToWorld(cellPos, currentOrigin, currentCellSize)
	return Vector3.new(
		currentOrigin.X + (cellPos.X - 1) * currentCellSize,
		currentOrigin.Y + (cellPos.Y - 1) * currentCellSize,
		currentOrigin.Z + (cellPos.Z - 1) * currentCellSize
	)
end -- End cellToWorld

local function CountCellTypesInGrid(targetGrid)
	local airCount = 0
	local solidCount = 0
	if not targetGrid or not targetGrid.data then
		Logger:Warn("Util_CountCells", "Invalid grid provided!")
		return 0, 0
	end
	for z_ct = 1, targetGrid.size.Z do
		for y_ct = 1, targetGrid.size.Y do
			for x_ct = 1, targetGrid.size.X do
				local val = targetGrid:get(x_ct, y_ct, z_ct)
				if val == AIR then
					airCount = airCount + 1
				elseif val == SOLID then
					solidCount = solidCount + 1
				end
			end
		end
	end
	return airCount, solidCount
end -- End CountCellTypesInGrid

local function localFractalNoise(x,y,z,noiseScale,octaves,persistence,lacunarity) 
	return Perlin.FBM_Base(
		x * noiseScale, 
		y * noiseScale, 
		z * noiseScale,
		octaves,
		persistence,
		lacunarity,
		1.0, -- Default frequency for FBM_Base
		1.0  -- Default amplitude for FBM_Base
	)
end -- End localFractalNoise

local function localDistanceToCenterBias(cellX,cellY,cellZ,gSizeX,gSizeY,gSizeZ,maxDBias) 
	local cX,cZ = gSizeX/2, gSizeZ/2
	local dx_bias = (cX-cellX)/cX
	local dz_bias = (cZ-cellZ)/cZ
	local dSq_bias = dx_bias*dx_bias + dz_bias*dz_bias 
	return math.min(math.sqrt(dSq_bias) * maxDBias, maxDBias)
end -- End localDistanceToCenterBias

local function localHeightBias(cellY,gSizeY) 
	local normH = cellY / gSizeY
	if normH <= CaveConfig.P1_HeightBias_BottomZonePercent then 
		return CaveConfig.P1_HeightBias_BottomValue
	elseif normH >= CaveConfig.P1_HeightBias_TopZonePercent then 
		return CaveConfig.P1_HeightBias_TopValue
	else 
		local midTS = CaveConfig.P1_HeightBias_BottomZonePercent
		local midTE = CaveConfig.P1_HeightBias_TopZonePercent
		local midPN = (midTS + midTE) / 2 
		if normH < midPN then 
			local t_hb = (normH - midTS) / (midPN - midTS + 1e-6)
			return CaveConfig.P1_HeightBias_BottomValue + t_hb * (CaveConfig.P1_HeightBias_MidFactor - CaveConfig.P1_HeightBias_BottomValue)
		else 
			local t_hb = (normH - midPN) / (midTE - midPN + 1e-6)
			return CaveConfig.P1_HeightBias_MidFactor + t_hb * (CaveConfig.P1_HeightBias_TopValue - CaveConfig.P1_HeightBias_MidFactor)
		end -- End if normH < midPN
	end -- End if/elseif/else height zones
end -- End localHeightBias

local function localVerticalConnectivityNoise(worldX,worldY,worldZ,noiseScale) 
	local connScale_vcn = noiseScale * CaveConfig.P1_VertConn_NoiseScaleFactor
	return NoiseGeneratorModule:GetValue(worldX * connScale_vcn, worldZ * connScale_vcn, 0) * CaveConfig.P1_VertConn_Strength
end -- End localVerticalConnectivityNoise

local function localRandomFloat(min,max) return min + Rng:NextNumber() * (max - min) end
local function localRandomInt(min,max) return Rng:NextInteger(min, max) end
local function localRandomChance(prob) return Rng:NextNumber() < prob end
local function localShuffleTable(tbl) 
	local n_st = #tbl
	for i_st = n_st, 2, -1 do 
		local j_st = Rng:NextInteger(1, i_st)
		tbl[i_st], tbl[j_st] = tbl[j_st], tbl[i_st]
	end -- End for i_st
end -- End localShuffleTable

-- Queue
local Queue={};Queue.__index=Queue;function Queue.new()return setmetatable({first=0,last=-1,data={}},Queue)end;function Queue:push(v)self.last=self.last+1;self.data[self.last]=v end;function Queue:pop()if self:isEmpty()then return nil end;local v=self.data[self.first];self.data[self.first]=nil;self.first=self.first+1;return v end;function Queue:isEmpty()return self.first>self.last end

local mainCaveCellIndices = {}
-- =============================================================================
-- V. PHASE FUNCTIONS 
-- =============================================================================
local function Phase1_InitialCaveFormation()
	Logger:Info("Phase1", "Starting initial cave structure...")

	-- Hierarchical Noise Configuration Print (Level: DEBUG)
	if CaveConfig.P1_UseHierarchicalNoise then
		Logger:Debug("Phase1Config", "Hierarchical Noise (Broad Structure Pass) is ENABLED.")
		Logger:Debug("Phase1Config", "    Broad Pass Params: ScaleFactor=%.3f, Octaves=%d, Threshold=%.3f",
			CaveConfig.P1_BroadStructure_NoiseScaleFactor,
			CaveConfig.P1_BroadStructure_Octaves,
			CaveConfig.P1_BroadStructure_Threshold)
	else
		Logger:Debug("Phase1Config", "Hierarchical Noise (Broad Structure Pass) is DISABLED.")
	end

	-- Domain Warping Configuration Print (Level: DEBUG)
	if CaveConfig.P1_UseDomainWarp then
		Logger:Debug("Phase1Config", "Domain Warping is ENABLED.")
		Logger:Debug("Phase1Config", "    DW Params: Strength=%.2f, FreqFactor=%.3f, Octaves=%d, Pers=%.2f, Lacu=%.2f",
			CaveConfig.P1_DomainWarp_Strength, CaveConfig.P1_DomainWarp_FrequencyFactor,
			CaveConfig.P1_DomainWarp_Octaves, CaveConfig.P1_DomainWarp_Persistence, CaveConfig.P1_DomainWarp_Lacunarity)
	else
		Logger:Debug("Phase1Config", "Domain Warping is DISABLED.")
	end

	-- Surface Adaptive FBM Configuration Print (Level: DEBUG)
	if CaveConfig.P1_UseSurfaceAdaptiveFBM then
		Logger:Debug("Phase1Config", "Surface Adaptive FBM for Detailed Pass is ENABLED.")
		Logger:Debug("Phase1Config", "    Adaptive Params: TargetThresh=%.3f, NearOct=%d, FarOct=%d, TransRange=%.3f",
			CaveConfig.P1_Adaptive_TargetThreshold,
			CaveConfig.P1_Adaptive_NearSurfaceOctaves,
			CaveConfig.P1_Adaptive_FarSurfaceOctaves,
			CaveConfig.P1_Adaptive_TransitionRange)
		Logger:Debug("Phase1Config", "    (Using P1_Octaves: %d as maxOctaves, P1_NoiseScale: %.4f as frequency for adaptive FBM)",
			CaveConfig.P1_Octaves, CaveConfig.P1_NoiseScale)
	else
		Logger:Debug("Phase1Config", "Surface Adaptive FBM for Detailed Pass is DISABLED (using FBM_Base via localFractalNoise).")
	end

	local startTime = os.clock()
	local airCellsSetInP1 = 0
	local broadPassSetToSolidCount = 0 
	local exampleFinalDensityForSlice 

	for z = 1, gridSizeZ do
		for y = 1, gridSizeY do
			for x = 1, gridSizeX do
				local worldX_orig = origin.X + (x - 0.5) * cellSize
				local worldY_orig = origin.Y + (y - 0.5) * cellSize
				local worldZ_orig = origin.Z + (z - 0.5) * cellSize

				local skipDetailedCalculation = false

				if CaveConfig.P1_UseHierarchicalNoise then
					local broadNoiseEffectiveScale = CaveConfig.P1_NoiseScale * CaveConfig.P1_BroadStructure_NoiseScaleFactor
					local broadNoiseVal = localFractalNoise(worldX_orig, worldY_orig, worldZ_orig,
						broadNoiseEffectiveScale,
						CaveConfig.P1_BroadStructure_Octaves,
						CaveConfig.P1_Persistence, 
						CaveConfig.P1_Lacunarity)  

					if broadNoiseVal > CaveConfig.P1_BroadStructure_Threshold then
						grid:set(x, y, z, SOLID)
						skipDetailedCalculation = true
						broadPassSetToSolidCount = broadPassSetToSolidCount + 1

						if broadPassSetToSolidCount < 15 and broadPassSetToSolidCount % 1 == 0 then 
							Logger:Trace("Phase1", "HIERARCHICAL: Cell(%d,%d,%d) SOLID by Broad Pass. Noise=%.4f (Thresh=%.3f)",
								x,y,z, broadNoiseVal, CaveConfig.P1_BroadStructure_Threshold)
						end
					end
				end

				if not skipDetailedCalculation then
					local worldX_input = worldX_orig
					local worldY_input = worldY_orig
					local worldZ_input = worldZ_orig

					if CaveConfig.P1_UseDomainWarp then
						local warpedX, warpedY, warpedZ = Perlin.DomainWarp(
							worldX_orig, worldY_orig, worldZ_orig,
							CaveConfig.P1_DomainWarp_FrequencyFactor,
							CaveConfig.P1_DomainWarp_Strength,
							nil, 
							CaveConfig.P1_DomainWarp_Octaves,
							CaveConfig.P1_DomainWarp_Persistence,
							CaveConfig.P1_DomainWarp_Lacunarity
						)
						worldX_input = warpedX
						worldY_input = warpedY
						worldZ_input = warpedZ

						if x <= 1 and y <= 1 and z <= 1 then 
							local iterationNum = (z-1)*gridSizeX*gridSizeY + (y-1)*gridSizeX + x
							if iterationNum <= 2 then 
								Logger:Trace("Phase1", "DW_DEBUG: Cell(%d,%d,%d) Orig(%.2f,%.2f,%.2f) -> Warped(%.2f,%.2f,%.2f)",
									x,y,z, worldX_orig, worldY_orig, worldZ_orig, warpedX, warpedY, warpedZ)
							end
						end
					end

					local noiseVal
					if CaveConfig.P1_UseSurfaceAdaptiveFBM then
						noiseVal = Perlin.FBM_SurfaceAdaptive(
							worldX_input, worldY_input, worldZ_input,
							CaveConfig.P1_Octaves, CaveConfig.P1_Persistence, CaveConfig.P1_Lacunarity,
							CaveConfig.P1_NoiseScale, 1.0,
							CaveConfig.P1_Adaptive_TargetThreshold,
							CaveConfig.P1_Adaptive_NearSurfaceOctaves,
							CaveConfig.P1_Adaptive_FarSurfaceOctaves,
							CaveConfig.P1_Adaptive_TransitionRange
						)
					else
						noiseVal = localFractalNoise(
							worldX_input, worldY_input, worldZ_input,
							CaveConfig.P1_NoiseScale, CaveConfig.P1_Octaves,
							CaveConfig.P1_Persistence, CaveConfig.P1_Lacunarity
						)
					end

					local hBias = localHeightBias(y, gridSizeY)
					local dBias = localDistanceToCenterBias(x, y, z, gridSizeX, gridSizeY, gridSizeZ, CaveConfig.P1_DistanceBias_Max)
					local vConnBias = localVerticalConnectivityNoise(worldX_orig, worldY_orig, worldZ_orig, CaveConfig.P1_NoiseScale)
					local finalDensity = noiseVal + hBias + dBias + vConnBias

					if x == math.floor(gridSizeX/2) and y == math.floor(gridSizeY/2) then
						exampleFinalDensityForSlice = finalDensity 
					end

					if finalDensity < CaveConfig.Threshold then
						grid:set(x, y, z, AIR); airCellsSetInP1 = airCellsSetInP1 + 1
						if airCellsSetInP1 < 15 then
							Logger:Trace("Phase1", "DETAILED: Cell(%d,%d,%d) SET TO AIR. finalDensity=%.4f (Noise=%.3f), Thresh=%.4f",x,y,z,finalDensity,noiseVal,CaveConfig.Threshold)
						end
					else
						grid:set(x, y, z, SOLID)
					end
				end
				doYield()
			end 
		end 

		if z % 20 == 0 then
			if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then
				local status_msg_parts = { string.format("Z-slice %d processed.", z) }
				if exampleFinalDensityForSlice then 
					table.insert(status_msg_parts, string.format("Sample DetailedDensity(mid): %.4f (Thresh %.4f)", exampleFinalDensityForSlice, CaveConfig.Threshold))
				end
				if CaveConfig.P1_UseHierarchicalNoise then
					table.insert(status_msg_parts, string.format("BroadSolid: %d.", broadPassSetToSolidCount))
				end
				Logger:Debug("Phase1", table.concat(status_msg_parts, " "))
			end
			exampleFinalDensityForSlice = nil 
		end
	end 

	for z_b = 1, gridSizeZ do
		for x_b = 1, gridSizeX do
			for y_b = 1, gridSizeY do
				if y_b <= CaveConfig.FormationStartHeight_Cells then grid:set(x_b,y_b,z_b,SOLID) end
				if x_b==1 or x_b==gridSizeX or z_b==1 or z_b==gridSizeZ then grid:set(x_b,y_b,z_b,SOLID) end
			end
		end
	end
	Logger:Debug("Phase1", "Borders solidified.")

	Logger:Info("Phase1", "Total cells set to AIR in P1 (detailed pass): %d", airCellsSetInP1)
	if CaveConfig.P1_UseHierarchicalNoise then
		Logger:Info("Phase1", "Total cells set to SOLID by broad pass (skipped detailed): %d", broadPassSetToSolidCount)
	end
	local endTime = os.clock()
	Logger:Info("Phase1", "Finished! Time: %.2fs", endTime - startTime)
end 

local function _createFormation(startX,startY,startZ,type,endYForColumn) 
	local length_cf=localRandomInt(CaveConfig.MinFormationLength_Cells,CaveConfig.MaxFormationLength_Cells)
	local dirY_cf=(type=="stalactite") and -1 or 1
	if type=="column" then 
		if endYForColumn then 
			length_cf=(endYForColumn-startY)+1 
		else 
			Logger:Warn("_createFormation", "Column type provided without endYForColumn parameter for start (%d,%d,%d).", startX,startY,startZ)
			return 
		end
		dirY_cf=1 
	end 
	for i_cf=0,length_cf-1 do 
		local curY_cf=startY+i_cf*dirY_cf
		if not grid:isInBounds(startX,curY_cf,startZ) then break end
		if type~="column" and i_cf>0 and grid:get(startX,curY_cf,startZ)==SOLID then break end
		local radFactor_cf
		if type=="column"then 
			local prog_cf=0
			if length_cf>1 then prog_cf=math.abs((i_cf/(length_cf-1))-.5)*2 end
			radFactor_cf=1-prog_cf*.3 
		else 
			radFactor_cf=(length_cf-i_cf)/length_cf 
		end
		local bRad_cf=CaveConfig.BaseFormationRadius_Factor
		if type=="column" then bRad_cf=bRad_cf*1.2 end
		local rCells_cf=math.max(0,math.floor(bRad_cf*radFactor_cf))
		if type=="column" and length_cf<=2 then rCells_cf=math.max(0,math.floor(bRad_cf*.8))end 
		for r_cf=0,rCells_cf do 
			for dx_cf=-r_cf,r_cf do 
				for dz_cf=-r_cf,r_cf do 
					if math.sqrt(dx_cf*dx_cf+dz_cf*dz_cf)<=r_cf+.5 then 
						local nx_cf,nz_cf=startX+dx_cf,startZ+dz_cf
						if grid:isInBounds(nx_cf,curY_cf,nz_cf) then grid:set(nx_cf,curY_cf,nz_cf,SOLID) end
					end 
				end 
			end 
		end 
		if rCells_cf==0 then grid:set(startX,curY_cf,startZ,SOLID) end
		doYield()
	end 
end 

local function Phase2_RockFormations() 
	Logger:Info("Phase2", "Starting rock formations...")
	local sTime=os.clock()
	local pSpots={}
	local cForms={s=0,m=0,c=0}

	for z_p2=2,gridSizeZ-1 do 
		for x_p2=2,gridSizeX-1 do 
			for y_p2=CaveConfig.FormationStartHeight_Cells+1,gridSizeY-1 do 
				doYield()
				if grid:get(x_p2,y_p2,z_p2)==AIR then 
					local rA=grid:get(x_p2,y_p2+1,z_p2)==SOLID
					local rB=grid:get(x_p2,y_p2-1,z_p2)==SOLID
					local clA,clB=true,true
					for i_cl=1,CaveConfig.FormationClearance_Cells do 
						if not grid:isInBounds(x_p2,y_p2-i_cl,z_p2) or grid:get(x_p2,y_p2-i_cl,z_p2)==SOLID then 
							clA=false; break 
						end 
					end 
					for i_cl=1,CaveConfig.FormationClearance_Cells do 
						if not grid:isInBounds(x_p2,y_p2+i_cl,z_p2) or grid:get(x_p2,y_p2+i_cl,z_p2)==SOLID then 
							clB=false; break 
						end 
					end 
					if rA and clA then table.insert(pSpots,{x=x_p2,y=y_p2,z=z_p2,type="stalactite"}) end
					if rB and clB then table.insert(pSpots,{x=x_p2,y=y_p2,z=z_p2,type="stalagmite"}) end
					if rA and rB then 
						local fY,cY=y_p2,y_p2
						while grid:isInBounds(x_p2,fY-1,z_p2) and grid:get(x_p2,fY-1,z_p2)==AIR do fY=fY-1 end
						while grid:isInBounds(x_p2,cY+1,z_p2) and grid:get(x_p2,cY+1,z_p2)==AIR do cY=cY+1 end
						local actFY,actCY=fY-1,cY+1
						if grid:isInBounds(x_p2,actFY,z_p2) and grid:get(x_p2,actFY,z_p2)==SOLID and 
							grid:isInBounds(x_p2,actCY,z_p2) and grid:get(x_p2,actCY,z_p2)==SOLID then
							local airH=actCY-actFY-1
							if airH>=CaveConfig.MinColumnHeight_Cells then 
								table.insert(pSpots,{x=x_p2,y=(fY+cY)/2,z=z_p2,type="column",floorCellY=fY,ceilCellY=cY})
							end 
						end 
					end 
				end 
			end 
		end 
	end 

	localShuffleTable(pSpots)
	local fAtt=0
	for _,spt in ipairs(pSpots) do 
		fAtt=fAtt+1
		if spt.type=="stalactite" and localRandomChance(CaveConfig.StalactiteChance) then 
			_createFormation(spt.x,spt.y,spt.z,"stalactite",nil);cForms.s=cForms.s+1
		elseif spt.type=="stalagmite" and localRandomChance(CaveConfig.StalagmiteChance) then 
			_createFormation(spt.x,spt.y,spt.z,"stalagmite",nil);cForms.m=cForms.m+1
		elseif spt.type=="column" and localRandomChance(CaveConfig.ColumnChance) then 
			if spt.floorCellY and spt.ceilCellY then 
				_createFormation(spt.x,spt.floorCellY,spt.z,"column",spt.ceilCellY);cForms.c=cForms.c+1 
			else  
				Logger:Debug("Phase2", "Invalid column spot data for attempted creation at (%d,%d,%d)",spt.x,spt.y,spt.z)
			end 
		end 
		doYield()
	end 
	Logger:Debug("Phase2", "Spots processed: %d, Formation creation attempted: %d", #pSpots, fAtt)
	Logger:Info("Phase2", "Created S:%d, M:%d, C:%d.",cForms.s,cForms.m,cForms.c)
	local eTime=os.clock()
	Logger:Info("Phase2", "Finished! Time: %.2fs", eTime-sTime)
end 

local function Phase3_Smoothing()
	Logger:Info("Phase3", "Starting smoothing...")
	local sTime=os.clock()
	for iter=1,CaveConfig.SmoothingIterations do 
		local airPreIter, solidPreIter = CountCellTypesInGrid(grid)
		Logger:Debug("Phase3", "Iter %d PRE-SMOOTH: AIR cells = %d, SOLID cells = %d", iter, airPreIter, solidPreIter)

		local nGridD=table.clone(grid.data) 
		local cellsCh=0
		for z_p3=2,gridSizeZ-1 do 
			for y_p3=2,gridSizeY-1 do 
				for x_p3=2,gridSizeX-1 do 
					local sN=grid:getNeighborCount(x_p3,y_p3,z_p3,SOLID,26) 
					local cV=grid:get(x_p3,y_p3,z_p3) 
					local cI=grid:index(x_p3,y_p3,z_p3) 
					if cI then 
						if cV==SOLID then 
							if (26-sN)>=CaveConfig.SmoothingThreshold_CarveRock then 
								nGridD[cI]=AIR
								if cV == SOLID then cellsCh=cellsCh+1 end
							end 
						else 
							if sN>=CaveConfig.SmoothingThreshold_FillAir then 
								nGridD[cI]=SOLID
								if cV == AIR then cellsCh=cellsCh+1 end 
							end
						end 
					end 
					doYield()
				end 
			end 
		end 
		grid.data=nGridD

		local airPostIter, solidPostIter = CountCellTypesInGrid(grid)
		Logger:Debug("Phase3", "Iteration %d POST-SMOOTH: AIR cells = %d, SOLID cells = %d. Cells changed this iter: %d",iter, airPostIter, solidPostIter, cellsCh)
	end 
	local eTime=os.clock()
	Logger:Info("Phase3", "Finished! Time: %.2fs", eTime-sTime)
end 

local function _floodFillSearch_local_p45(startX, startY, startZ, visitedGrid, invocationContext) 
	local compCells = {}
	local q = Queue.new()
	local isInBoundsFlag = grid:isInBounds(startX,startY,startZ)
	local initialCellVal = isInBoundsFlag and grid:get(startX,startY,startZ) or nil
	local isVisitedFlag = false 

	if not visitedGrid or not visitedGrid.data then
		Logger:Error("_floodFillSearch", "FATAL: 'visitedGrid' parameter is nil or invalid for start (%d,%d,%d). Cannot proceed.", startX, startY, startZ)
		return compCells 
	end

	if visitedGrid:isInBounds(startX, startY, startZ) then
		isVisitedFlag = visitedGrid:get(startX,startY,startZ)
	else
		Logger:Trace("_floodFillSearch", "Start coords (%d,%d,%d) out of bounds for 'visitedGrid'. Assuming not visited.", startX, startY, startZ)
	end

	if invocationContext and invocationContext.floodFillAttempts <= (CaveConfig.FloodFillContext_MaxInitialDebugAttempts or 3) then
		Logger:Trace("_floodFillSearch", "INVOKED #%d with: start (%d,%d,%d)", invocationContext.floodFillAttempts, startX,startY,startZ)
		Logger:Trace("_floodFillSearch", "    Grid InBounds: %s, InitialCellVal: %s, isVisitedInVisitedGrid: %s", 
			tostring(isInBoundsFlag), tostring(initialCellVal), tostring(isVisitedFlag))
	end

	if not isInBoundsFlag or initialCellVal ~= AIR or isVisitedFlag == true then 
		if invocationContext and invocationContext.floodFillAttempts <= (CaveConfig.FloodFillContext_MaxInitialDebugAttempts or 3) then
			Logger:Trace("_floodFillSearch", "DEBUG #%d: Flood PREVENTED. InBounds:%s, IsAir:%s, IsVisited:%s", 
				invocationContext.floodFillAttempts, tostring(isInBoundsFlag), tostring(initialCellVal == AIR), tostring(isVisitedFlag))
		end
		return compCells 
	end

	if invocationContext and invocationContext.floodFillAttempts <= (CaveConfig.FloodFillContext_MaxInitialDebugAttempts or 3) then
		Logger:Trace("_floodFillSearch", "DEBUG #%d: PASSED initial checks. Starting flood from (%d,%d,%d)", invocationContext.floodFillAttempts, startX,startY,startZ)
	end

	q:push({x=startX,y=startY,z=startZ})
	visitedGrid:set(startX,startY,startZ,true)
	local cellsProcessedInFlood = 0
	while not q:isEmpty() do 
		local cell = q:pop()
		if not cell then 
			Logger:Warn("_floodFillSearch", "q:pop() returned nil unexpectedly! Breaking loop.")
			break 
		end
		table.insert(compCells, cell)
		cellsProcessedInFlood = cellsProcessedInFlood + 1 
		doYield() 
		local DIRS = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
		for _,dir in ipairs(DIRS) do 
			local nx,ny,nz = cell.x+dir[1], cell.y+dir[2], cell.z+dir[3]
			local neighborIsAlreadyVisited = true 
			if visitedGrid:isInBounds(nx,ny,nz) then 
				neighborIsAlreadyVisited = visitedGrid:get(nx,ny,nz)
			end
			if grid:isInBounds(nx,ny,nz) and grid:get(nx,ny,nz) == AIR and not neighborIsAlreadyVisited then 
				visitedGrid:set(nx,ny,nz,true)
				q:push({x=nx,y=ny,z=nz})
			end
		end
	end 

	if Logger:IsLevelEnabled(Logger.Levels.TRACE) then
		local compSize = #compCells
		local shouldPrintFinish = false
		if compSize > 0 then
			if invocationContext and invocationContext.componentsFound < (CaveConfig.FloodFillContext_MaxInitialComponentLogs or 3) then
				shouldPrintFinish = true 
			elseif compSize > (CaveConfig.FloodFillContext_LargeComponentThreshold or 1000) then
				shouldPrintFinish = true 
			elseif compSize < (CaveConfig.FloodFillContext_SmallComponentThreshold or 10) and compSize > 0 then 
				shouldPrintFinish = true
			end
		end
		if shouldPrintFinish then
			Logger:Trace("_floodFillSearch", "DEBUG #%d (Comp #%d): Flood from (%d,%d,%d) finished. Size: %d cells. ProcessedInFlood: %d", 
				invocationContext and invocationContext.floodFillAttempts or 0,
				invocationContext and invocationContext.componentsFound + 1 or 0, 
				startX,startY,startZ, compSize, cellsProcessedInFlood)
		end
	end
	return compCells
end

local function _findAirComponents_local_p45() 
	local components={}
	local visited=Grid3D.new(gridSizeX,gridSizeY,gridSizeZ,false) 

	if not visited or not visited.data then
		Logger:Fatal("_findAirComponents", "CRITICAL: Failed to create 'visited' Grid3D instance. Halting component search.")
		return components 
	end

	Logger:Debug("_findAirComponents", "Starting component search...")
	local airCellsFoundByIteration = 0
	local solidCellsFoundByIteration = 0
	local nilCellsFoundByIteration = 0
	local firstAirCellCoords = nil

	local floodFillContext_p45 = { floodFillAttempts = 0, componentsFound = 0 }
	local minComponentSize_p45 = gridSizeX * gridSizeY * gridSizeZ + 1 
	local maxComponentSize_p45 = 0
	local totalCellsInFoundComponents_p45 = 0

	for z_l=1,gridSizeZ do 
		for y_l=1,gridSizeY do 
			for x_l=1,gridSizeX do 
				local currentCellValue = grid:get(x_l,y_l,z_l)
				if currentCellValue == AIR then
					airCellsFoundByIteration = airCellsFoundByIteration + 1
					if not firstAirCellCoords and (CaveConfig.FloodFillLogFirstAirCellFound == nil or CaveConfig.FloodFillLogFirstAirCellFound) then
						firstAirCellCoords = {x=x_l, y=y_l, z=z_l}
						Logger:Debug("_findAirComponents", "FIRST AIR CELL found by iteration at (%d,%d,%d)", x_l,y_l,z_l)
					end
					local isAlreadyVisited = visited:isInBounds(x_l,y_l,z_l) and visited:get(x_l,y_l,z_l) or false
					if not isAlreadyVisited then 
						floodFillContext_p45.floodFillAttempts = floodFillContext_p45.floodFillAttempts + 1
						local nComp = _floodFillSearch_local_p45(x_l,y_l,z_l,visited, floodFillContext_p45) 
						if #nComp>0 then 
							floodFillContext_p45.componentsFound = floodFillContext_p45.componentsFound + 1
							local currentCompSize = #nComp
							totalCellsInFoundComponents_p45 = totalCellsInFoundComponents_p45 + currentCompSize
							if currentCompSize < minComponentSize_p45 then minComponentSize_p45 = currentCompSize end
							if currentCompSize > maxComponentSize_p45 then maxComponentSize_p45 = currentCompSize end
							table.insert(components,nComp)
						end
					end 
				elseif currentCellValue == SOLID then
					solidCellsFoundByIteration = solidCellsFoundByIteration + 1
				else 
					nilCellsFoundByIteration = nilCellsFoundByIteration + 1
					if nilCellsFoundByIteration < (CaveConfig.FloodFillMaxNilCellLogs or 3) then
						Logger:Warn("_findAirComponents", "Found NIL/unexpected cell value '%s' at (%d,%d,%d) during iteration!",tostring(currentCellValue), x_l, y_l, z_l)
					end
				end
				doYield() 
			end 
		end 
		if z_l % math.max(1, math.floor(gridSizeZ / (CaveConfig.FloodFillZSliceLogDivisor or 10))) == 0 then
			Logger:Debug("_findAirComponents", "PROGRESS: Z-slice %d/%d. Air cells by iter: %d. Attempts: %d, Comps Found: %d",
				z_l, gridSizeZ, airCellsFoundByIteration, floodFillContext_p45.floodFillAttempts, floodFillContext_p45.componentsFound)
		end
	end 

	table.sort(components,function(a,b)return #a>#b end) 

	if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then
		Logger:Debug("_findAirComponents", "--- SUMMARY ---")
		Logger:Debug("_findAirComponents", "  Grid Iteration encountered: AIR: %d, SOLID: %d, NIL/Other: %d",
			airCellsFoundByIteration, solidCellsFoundByIteration, nilCellsFoundByIteration)
		if firstAirCellCoords and (CaveConfig.FloodFillLogFirstAirCellFound == nil or CaveConfig.FloodFillLogFirstAirCellFound) then
			Logger:Debug("_findAirComponents", "  First air cell by iteration: (%d,%d,%d)", firstAirCellCoords.x, firstAirCellCoords.y, firstAirCellCoords.z)
		end
		Logger:Debug("_findAirComponents", "  Flood Fill Attempts: %d", floodFillContext_p45.floodFillAttempts)
		Logger:Debug("_findAirComponents", "  Total Air Components Identified: %d", #components)
		if #components > 0 then
			Logger:Debug("_findAirComponents", "  Largest Component Size: %d cells", #components[1])
			local smallestInList = #components[#components] 
			local recordedMin = minComponentSize_p45
			if recordedMin == (gridSizeX * gridSizeY * gridSizeZ + 1) then 
				recordedMin = (#components > 0 and smallestInList or 0)
			end
			Logger:Debug("_findAirComponents", "  Smallest Component in List: %d cells. (Smallest recorded during scan: %d)", smallestInList, recordedMin)
			Logger:Debug("_findAirComponents", "  Max Component Size Recorded: %d cells", maxComponentSize_p45)
			Logger:Debug("_findAirComponents", "  Total Cells in all Found Components: %d", totalCellsInFoundComponents_p45)
			if #components > 0 then
				Logger:Debug("_findAirComponents", "  Average Component Size: %.2f cells", totalCellsInFoundComponents_p45 / #components)
			end
		else
			Logger:Debug("_findAirComponents", "  No actual air components were formed by flood fill.")
		end
		Logger:Debug("_findAirComponents", "--------------------------------------------")
	else
		Logger:Info("_findAirComponents", "Found %d air components. Largest: %d cells.",
			#components, (#components > 0 and #components[1] and #components[1] or 0) )
	end
	return components
end

local function _carveTunnel_local_p46(p1,p2,radiusFactor) 
	local rad=math.max(1,math.floor(CaveConfig.ConnectivityTunnelRadius_Factor*radiusFactor))
	local curP=Vector3.new(p1.x,p1.y,p1.z)
	local tP=Vector3.new(p2.x,p2.y,p2.z)
	local dirV=(tP-curP)
	local dist=dirV.Magnitude
	if dist<1 then return end
	local dirU=dirV.Unit
	local step=0
	Logger:Trace("_carveTunnel", "Carving from(%.1f,%.1f,%.1f) to(%.1f,%.1f,%.1f), dist:%.1f, radius:%d",p1.x,p1.y,p1.z,p2.x,p2.y,p2.z,dist,rad)
	local cellsCT=0
	while step<=dist do 
		local pos=curP+dirU*step
		local cx,cy,cz=math.round(pos.X),math.round(pos.Y),math.round(pos.Z)
		for dx_t=-rad,rad do 
			for dy_t=-rad,rad do 
				for dz_t=-rad,rad do 
					if dx_t*dx_t+dy_t*dy_t+dz_t*dz_t <= rad*rad+.1 then 
						if grid:isInBounds(cx+dx_t,cy+dy_t,cz+dz_t) then 
							if grid:get(cx+dx_t,cy+dy_t,cz+dz_t)==SOLID then cellsCT=cellsCT+1 end
							grid:set(cx+dx_t,cy+dy_t,cz+dz_t,AIR)
						end 
					end 
				end 
			end 
		end 
		step=step+1
		doYield()
	end 
	Logger:Trace("_carveTunnel", "Tunnel done. Approx %d cells carved to AIR.",cellsCT)
end 

local function Phase4_EnsureConnectivity()
	Logger:Info("Phase4", "Starting ensure connectivity...")
	local sTime=os.clock()
	local airCs=_findAirComponents_local_p45() 
	if #airCs==0 then Logger:Info("Phase4", "No air components found. Skipping connectivity.");return end
	if #airCs==1 then 
		Logger:Info("Phase4", "Cave system already connected (1 main component).")
		if airCs[1] then 
			mainCaveCellIndices={}
			for _,c_ac in ipairs(airCs[1]) do 
				if c_ac then 
					local i_ac=grid:index(c_ac.x,c_ac.y,c_ac.z)
					if i_ac then mainCaveCellIndices[i_ac]=true end 
				end 
			end 
		end
		return 
	end

	Logger:Info("Phase4", "Found %d air components. Attempting to connect...", #airCs)
	if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then 
		for i_dc=1,math.min(5,#airCs) do 
			if airCs[i_dc] then Logger:Debug("Phase4", "Comp size %d: %d",i_dc,#airCs[i_dc]) end 
		end 
	end

	local mainC=airCs[1]
	local connsMade=0
	local numToCon=math.min(#airCs-1,CaveConfig.ConnectivityDensity)
	Logger:Info("Phase4", "Will attempt up to %d connections.",numToCon)

	for tCompIdx=2,#airCs do 
		if connsMade>=numToCon then Logger:Debug("Phase4", "Reached ConnectivityDensity limit of %d.", numToCon);break end
		local compB=airCs[tCompIdx]
		if not compB or #compB==0 then Logger:Debug("Phase4", "Target component for connection (index %d) is nil or empty. Skipping.",tCompIdx);continue end

		local cDistSq=math.huge; local cA_b,cB_b
		local sMax=200; local sA,sB={},{}
		if mainC and #mainC>0 then for _=1,math.min(#mainC,sMax) do local c_sm=mainC[localRandomInt(1,#mainC)];if c_sm then table.insert(sA,c_sm)end end end
		if compB and #compB>0 then for _=1,math.min(#compB,sMax) do local c_sm=compB[localRandomInt(1,#compB)];if c_sm then table.insert(sB,c_sm)end end end

		if #sA==0 or #sB==0 then Logger:Warn("Phase4", "Empty sample lists for connecting main component to component index %d. Skipping.",tCompIdx);doYield();continue end

		for _,c1s in ipairs(sA) do 
			for _,c2s in ipairs(sB) do 
				if c1s and c2s then 
					local dSq=(c1s.x-c2s.x)^2+(c1s.y-c2s.y)^2+(c1s.z-c2s.z)^2
					if dSq<cDistSq then cDistSq=dSq;cA_b,cB_b=c1s,c2s end 
				end 
			end 
			doYield()
		end 

		if cA_b and cB_b then 
			_carveTunnel_local_p46(cA_b,cB_b,1.0)
			Logger:Info("Phase4", "Connected component (original index %d) to main. Distance: %.1f",tCompIdx,math.sqrt(cDistSq))
			connsMade=connsMade+1
			if compB and mainC then 
				for _,bC_m in ipairs(compB) do if bC_m then table.insert(mainC,bC_m)end end 
			end 
		else 
			Logger:Warn("Phase4", "Failed to find closest points to connect component index %d.",tCompIdx)
		end 
	end 

	if connsMade > 0 then
		Logger:Info("Phase4", "Connections made. Re-identifying the main cave component.")
		local finalAirCs_P4 = _findAirComponents_local_p45() 
		if #finalAirCs_P4 > 0 and finalAirCs_P4[1] then
			mainCaveCellIndices = {}
			for _, cellData in ipairs(finalAirCs_P4[1]) do
				if cellData then
					local idx = grid:index(cellData.x, cellData.y, cellData.z)
					if idx then mainCaveCellIndices[idx] = true end
				end
			end
			if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then
				local count = 0; for _ in pairs(mainCaveCellIndices) do count = count + 1 end
				Logger:Debug("Phase4", "mainCaveCellIndices repopulated. New main component size: %d cells.", count)
			end
		else
			Logger:Warn("Phase4", "No air components found after connections for mainCaveCellIndices repopulation.")
			mainCaveCellIndices = {} 
		end
	end

	local eTime=os.clock()
	Logger:Info("Phase4", "Finished! Time: %.2fs. Connections made: %d", eTime-sTime, connsMade)
end

local function Phase5_FloodFillCleanup()
	Logger:Info("Phase5", "Starting flood fill cleanup...")
	local sTime=os.clock()
	local airCs_p5=_findAirComponents_local_p45() 
	if #airCs_p5==0 then Logger:Info("Phase5", "No air components. Nothing to clean up.");return end

	Logger:Debug("Phase5", "Found %d components pre-cleanup. Largest: %d cells.", #airCs_p5, (#airCs_p5[1]and #airCs_p5[1]or 0))

	mainCaveCellIndices={}
	if #airCs_p5>0 and airCs_p5[1] then 
		for _,cD_p5 in ipairs(airCs_p5[1]) do 
			if cD_p5 then 
				local idx_p5=grid:index(cD_p5.x,cD_p5.y,cD_p5.z)
				if idx_p5 then mainCaveCellIndices[idx_p5]=true end 
			end 
		end 
	end 
	if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then 
		local mcC_p5=0;for _ in pairs(mainCaveCellIndices)do mcC_p5=mcC_p5+1 end
		Logger:Debug("Phase5", "mainCaveCellIndices populated with %d cells from largest component.", mcC_p5)
	end

	local cellsF_p5=0
	for i_p5f=2,#airCs_p5 do 
		if airCs_p5[i_p5f] then 
			for _,cDF_p5 in ipairs(airCs_p5[i_p5f]) do 
				if cDF_p5 then grid:set(cDF_p5.x,cDF_p5.y,cDF_p5.z,SOLID);cellsF_p5=cellsF_p5+1;doYield()end 
			end 
		end 
	end 
	Logger:Info("Phase5", "Kept largest component. Filled %d cells from %d smaller components.",cellsF_p5,math.max(0,#airCs_p5-1))
	local eTime=os.clock()
	Logger:Info("Phase5", "Finished! Time: %.2fs", eTime-sTime)
end

local function Phase6_SurfaceEntrances()
	Logger:Info("Phase6", "Starting surface entrances...")
	local sTime=os.clock()
	local entrMade_p6=0
	for i_p6e=1,CaveConfig.SurfaceCaveCount do 
		local sx_p6e,sz_p6e,sy_p6e = localRandomInt(3,gridSizeX-2),localRandomInt(3,gridSizeZ-2),gridSizeY-2 
		local cPos_p6e={x=sx_p6e,y=sy_p6e,z=sz_p6e}
		local tY_p6e=CaveConfig.FormationStartHeight_Cells+localRandomInt(3,10)
		local len_p6e,maxL_p6e = 0, localRandomInt(CaveConfig.SurfaceCaveTunnelLength_Cells_MinMax[1],CaveConfig.SurfaceCaveTunnelLength_Cells_MinMax[2])
		local conn_p6e=false

		while cPos_p6e.y>tY_p6e and len_p6e<maxL_p6e and cPos_p6e.y>2 do 
			local ir_p6e=CaveConfig.SurfaceCaveEntranceIrregularity
			local dx_p6e,dz_p6e,dy_p6e = localRandomFloat(-ir_p6e,ir_p6e),localRandomFloat(-ir_p6e,ir_p6e),CaveConfig.SurfaceCaveTunnelSteepness
			local v_p6e=Vector3.new(dx_p6e,dy_p6e,dz_p6e).Unit
			cPos_p6e.x=math.clamp(math.round(cPos_p6e.x+v_p6e.X*1.5),2,gridSizeX-1)
			cPos_p6e.y=math.clamp(math.round(cPos_p6e.y+v_p6e.Y*1.5),2,gridSizeY-1)
			cPos_p6e.z=math.clamp(math.round(cPos_p6e.z+v_p6e.Z*1.5),2,gridSizeZ-1)
			len_p6e=len_p6e+1
			local r_p6e=CaveConfig.SurfaceCaveRadius_Factor
			for drx_p6e=-math.floor(r_p6e),math.floor(r_p6e) do 
				for dry_p6e=-math.floor(r_p6e),math.floor(r_p6e) do 
					for drz_p6e=-math.floor(r_p6e),math.floor(r_p6e) do 
						if drx_p6e*drx_p6e+dry_p6e*dry_p6e+drz_p6e*drz_p6e <= r_p6e*r_p6e+.1 then
							local ncx_p6e,ncy_p6e,ncz_p6e = cPos_p6e.x+drx_p6e,cPos_p6e.y+dry_p6e,cPos_p6e.z+drz_p6e
							if grid:isInBounds(ncx_p6e,ncy_p6e,ncz_p6e) then 
								grid:set(ncx_p6e,ncy_p6e,ncz_p6e,AIR)
								if CaveConfig.FloodFillPhaseEnabled then 
									local ci_p6e=grid:index(ncx_p6e,ncy_p6e,ncz_p6e)
									if ci_p6e then mainCaveCellIndices[ci_p6e]=true end 
								end 
							end 
						end 
					end 
				end 
			end 
			doYield()
			local cTunIdx_p6e=grid:index(cPos_p6e.x,cPos_p6e.y,cPos_p6e.z)
			if cTunIdx_p6e and (not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[cTunIdx_p6e]) then 
				for ox_p6e=-1,1 do for oy_p6e=-1,1 do for oz_p6e=-1,1 do 
							if ox_p6e==0 and oy_p6e==0 and oz_p6e==0 then continue end
							local chkX_p6e,chkY_p6e,chkZ_p6e = cPos_p6e.x+ox_p6e,cPos_p6e.y+oy_p6e,cPos_p6e.z+oz_p6e
							local chkIdx_p6e=grid:index(chkX_p6e,chkY_p6e,chkZ_p6e)
							if chkIdx_p6e and mainCaveCellIndices[chkIdx_p6e] and grid:get(chkX_p6e,chkY_p6e,chkZ_p6e)==AIR then 
								conn_p6e=true; break 
							end 
						end if conn_p6e then break end end if conn_p6e then break end end 
			end 
			if conn_p6e then Logger:Debug("Phase6", "Entrance %d connected to main cave.", i_p6e); break end 
		end 
		if conn_p6e then entrMade_p6=entrMade_p6+1 
		else 
			Logger:Debug("Phase6", "Entrance %d did not connect or reached max length/depth.", i_p6e)
		end 
	end 

	Logger:Info("Phase6", "Created/Attempted %d entrances of %d.",entrMade_p6, CaveConfig.SurfaceCaveCount)
	if entrMade_p6>0 and CaveConfig.FloodFillPhaseEnabled then 
		Logger:Info("Phase6", "Re-evaluating main cave cells after new entrances.")
		local airCs_p6r=_findAirComponents_local_p45()
		if #airCs_p6r>0 and airCs_p6r[1] then 
			mainCaveCellIndices={} 
			for _,cD_p6r in ipairs(airCs_p6r[1]) do 
				if cD_p6r then 
					local idx_p6r=grid:index(cD_p6r.x,cD_p6r.y,cD_p6r.z)
					if idx_p6r then mainCaveCellIndices[idx_p6r]=true end 
				end 
			end 
			if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then 
				local mcC_p6r=0; for _ in pairs(mainCaveCellIndices) do mcC_p6r=mcC_p6r+1 end
				Logger:Debug("Phase6", "Main cave re-identified after entrances: %d cells (Largest component: %d cells)", mcC_p6r, #airCs_p6r[1])
			end 
		else 
			Logger:Debug("Phase6", "No air components found for re-evaluation post-entrances.")
		end 
	end 
	local eTime=os.clock()
	Logger:Info("Phase6", "Finished! Time: %.2fs", eTime-sTime)
end

local function _checkBridgeChamberCriteria_local(cx,cy,cz,length) 
	local minAirAbv=0
	for h=1,CaveConfig.BridgeChamberMinHeight_Cells do 
		local tY=cy+h
		if not grid:isInBounds(cx,tY,cz) then return false end
		local cIdx_bcc=grid:index(cx,tY,cz) 
		if not(grid:get(cx,tY,cz)==AIR and(not CaveConfig.FloodFillPhaseEnabled or(cIdx_bcc and mainCaveCellIndices[cIdx_bcc]))) then return false end
		minAirAbv=minAirAbv+1 
	end 
	if minAirAbv<CaveConfig.BridgeChamberMinHeight_Cells then return false end
	local airCC=0
	local mX,mZ=cx,cz
	local targetX_valid = grid:isInBounds(cx+length,cy,cz)
	local targetZ_valid = grid:isInBounds(cx,cy,cz+length)
	if targetX_valid and grid:get(cx+length,cy,cz)==AIR and grid:get(cx+length,cy-1,cz)==SOLID then mX=cx+length/2 
	elseif targetZ_valid and grid:get(cx,cy,cz+length)==AIR and grid:get(cx,cy-1,cz+length)==SOLID then mZ=cz+length/2 
	end 
	local cRW=math.max(3,math.ceil(CaveConfig.BridgeChamberMinAirCells^(1/3)/2.0))
	local cRC=math.ceil(cRW)
	for dx_bcc_l=-cRC,cRC do for dy_bcc_l=-cRC,cRC do for dz_bcc_l=-cRC,cRC do 
				local curX,curY,curZ=math.floor(mX+dx_bcc_l),cy+dy_bcc_l,math.floor(mZ+dz_bcc_l)
				local ccci_bcc=grid:index(curX,curY,curZ)  
				if ccci_bcc and grid:get(curX,curY,curZ)==AIR and(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[ccci_bcc]) then airCC=airCC+1 end
			end end end 
	return airCC>=CaveConfig.BridgeChamberMinAirCells
end 

local function _buildBridge_local(p1,p2) 
	local thk=localRandomInt(CaveConfig.BridgeThickness_Cells_MinMax[1],CaveConfig.BridgeThickness_Cells_MinMax[2])
	local wid=localRandomInt(CaveConfig.BridgeWidth_Cells_MinMax[1],CaveConfig.BridgeWidth_Cells_MinMax[2]) 
	local isXBr=p1.z==p2.z
	local startAx=isXBr and math.min(p1.x,p2.x) or math.min(p1.z,p2.z)
	local endAx=isXBr and math.max(p1.x,p2.x) or math.max(p1.z,p2.z) 
	local cellsSet=0
	for brY=p1.y-thk,p1.y-1 do  
		if not grid:isInBounds(p1.x,brY,p1.z) then continue end
		for mainAV=startAx+1,endAx-1 do  
			for widOff=-math.floor((wid-1)/2),math.ceil((wid-1)/2) do 
				local cX,cZ 
				if isXBr then cX=mainAV;cZ=p1.z+widOff else cX=p1.x+widOff;cZ=mainAV end 
				if grid:isInBounds(cX,brY,cZ) then 
					if grid:get(cX,brY,cZ)==AIR then cellsSet=cellsSet+1 end
					grid:set(cX,brY,cZ,SOLID) 
				end 
			end 
		end 
		doYield()
	end 
	Logger:Trace("_buildBridge", "Bridge built between (%s,%s,%s) and (%s,%s,%s). Approx %d cells set to SOLID.", p1.x,p1.y,p1.z, p2.x,p2.y,p2.z, cellsSet)
end 

local function Phase7_Bridges() 
	Logger:Info("Phase7", "Starting bridges...")
	local sTime_p7 = os.clock()
	local bridgeCandidates_p7_list = {}
	local x_p7_iter, y_p7_iter, z_p7_iter 
	for y_loop_main_p7 = gridSizeY - CaveConfig.BridgeChamberMinHeight_Cells - 2, CaveConfig.FormationStartHeight_Cells + CaveConfig.BridgeChamberMinHeight_Cells + 1, -1 do
		y_p7_iter = y_loop_main_p7
		for x_loop_main_p7 = 2, gridSizeX - 2 do
			x_p7_iter = x_loop_main_p7 
			for z_loop_main_p7 = 2, gridSizeZ - 2 do
				z_p7_iter = z_loop_main_p7 
				doYield()
				local cellIdx_p7_start = grid:index(x_p7_iter, y_p7_iter, z_p7_iter)
				local isValidStart_p7_check = cellIdx_p7_start and grid:get(x_p7_iter, y_p7_iter, z_p7_iter) == AIR and
					(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[cellIdx_p7_start]) and
					(grid:get(x_p7_iter, y_p7_iter - 1, z_p7_iter) == SOLID)
				if isValidStart_p7_check then
					local current_x_for_scan = x_p7_iter 
					for lenX_p7_scan = 2, 10 do
						local lookX_p7_target = current_x_for_scan + lenX_p7_scan
						if not grid:isInBounds(lookX_p7_target, y_p7_iter, z_p7_iter) then break end
						local endIdxX_p7_target = grid:index(lookX_p7_target, y_p7_iter, z_p7_iter)
						local targetX_is_ledge = endIdxX_p7_target and grid:get(lookX_p7_target, y_p7_iter, z_p7_iter) == AIR and
							(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[endIdxX_p7_target]) and
							(grid:get(lookX_p7_target, y_p7_iter - 1, z_p7_iter) == SOLID)
						if targetX_is_ledge then
							local clearX_gap = true
							for gx_p7_scan = current_x_for_scan + 1, lookX_p7_target - 1 do
								local gXidx_p7_scan = grid:index(gx_p7_scan, y_p7_iter, z_p7_iter)
								local gXflrIdx_p7_scan = grid:index(gx_p7_scan, y_p7_iter - 1, z_p7_iter)
								if not (gXidx_p7_scan and grid:get(gx_p7_scan,y_p7_iter,z_p7_iter)==AIR and(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[gXidx_p7_scan])) or
									not (gXflrIdx_p7_scan and grid:get(gx_p7_scan,y_p7_iter-1,z_p7_iter)==AIR and(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[gXflrIdx_p7_scan])) then
									clearX_gap = false; break
								end 
							end 
							if clearX_gap and _checkBridgeChamberCriteria_local(current_x_for_scan, y_p7_iter, z_p7_iter, lenX_p7_scan) then
								table.insert(bridgeCandidates_p7_list, { p1 = { x = current_x_for_scan, y = y_p7_iter, z = z_p7_iter }, p2 = { x = lookX_p7_target, y = y_p7_iter, z = z_p7_iter } })
								x_loop_main_p7 = lookX_p7_target; break 
							end 
						elseif grid:get(lookX_p7_target,y_p7_iter,z_p7_iter)==SOLID or grid:get(lookX_p7_target,y_p7_iter-1,z_p7_iter)==AIR then break end
					end 
					local current_z_for_scan = z_p7_iter
					for lenZ_p7_scan = 2, 10 do
						local lookZ_p7_target = current_z_for_scan + lenZ_p7_scan
						if not grid:isInBounds(x_p7_iter, y_p7_iter, lookZ_p7_target) then break end 
						local endIdxZ_p7_target = grid:index(x_p7_iter, y_p7_iter, lookZ_p7_target)
						local targetZ_is_ledge = endIdxZ_p7_target and grid:get(x_p7_iter,y_p7_iter,lookZ_p7_target)==AIR and
							(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[endIdxZ_p7_target]) and
							(grid:get(x_p7_iter,y_p7_iter-1,lookZ_p7_target)==SOLID)
						if targetZ_is_ledge then
							local clearZ_gap = true
							for gz_p7_scan = current_z_for_scan + 1, lookZ_p7_target - 1 do
								local gZidx_p7_scan = grid:index(x_p7_iter, y_p7_iter, gz_p7_scan)
								local gZflrIdx_p7_scan = grid:index(x_p7_iter,y_p7_iter-1,gz_p7_scan)
								if not (gZidx_p7_scan and grid:get(x_p7_iter,y_p7_iter,gz_p7_scan)==AIR and(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[gZidx_p7_scan])) or
									not (gZflrIdx_p7_scan and grid:get(x_p7_iter,y_p7_iter-1,gz_p7_scan)==AIR and(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[gZflrIdx_p7_scan])) then
									clearZ_gap = false; break
								end 
							end 
							if clearZ_gap and _checkBridgeChamberCriteria_local(x_p7_iter, y_p7_iter, current_z_for_scan, lenZ_p7_scan) then
								table.insert(bridgeCandidates_p7_list, { p1 = { x = x_p7_iter, y = y_p7_iter, z = current_z_for_scan }, p2 = { x = x_p7_iter, y = y_p7_iter, z = lookZ_p7_target } })
								z_loop_main_p7 = lookZ_p7_target; break 
							end 
						elseif grid:get(x_p7_iter,y_p7_iter,lookZ_p7_target)==SOLID or grid:get(x_p7_iter,y_p7_iter-1,lookZ_p7_target)==AIR then break end
					end 
				end 
			end 
		end 
	end 
	localShuffleTable(bridgeCandidates_p7_list) 
	local builtCoords_p7_val = {}
	local toBuildCount_p7_val = math.min(#bridgeCandidates_p7_list, 30 + math.floor(gridSizeX * gridSizeZ / 5000)) 
	local actualBridgesBuiltThisPhase_p7 = 0
	for i_p7_build_loop = 1, toBuildCount_p7_val do
		local cand_p7_val = bridgeCandidates_p7_list[i_p7_build_loop] 
		if cand_p7_val and cand_p7_val.p1 and cand_p7_val.p2 then
			local midX_p7_val = math.floor((cand_p7_val.p1.x + cand_p7_val.p2.x) / 2)
			local midZ_p7_val = math.floor((cand_p7_val.p1.z + cand_p7_val.p2.z) / 2)
			local key_p7_val = string.format("%d,%d,%d", midX_p7_val, cand_p7_val.p1.y, midZ_p7_val)
			local near_p7_val = false
			for exKey_p7_val in pairs(builtCoords_p7_val) do
				local crds_p7_val = splitString(exKey_p7_val, ",") 
				if #crds_p7_val == 3 then
					local ex_p7_val = tonumber(crds_p7_val[1]); local ey_p7_val = tonumber(crds_p7_val[2]); local ez_p7_val = tonumber(crds_p7_val[3])
					if ex_p7_val and ey_p7_val and ez_p7_val and ey_p7_val == cand_p7_val.p1.y and math.abs(ex_p7_val - midX_p7_val) < 5 and math.abs(ez_p7_val - midZ_p7_val) < 5 then
						near_p7_val = true; break
					end 
				end 
			end 
			if not near_p7_val then
				_buildBridge_local(cand_p7_val.p1, cand_p7_val.p2)
				actualBridgesBuiltThisPhase_p7 = actualBridgesBuiltThisPhase_p7 + 1
				builtCoords_p7_val[key_p7_val] = true
			end 
		end 
	end 
	Logger:Info("Phase7", "Built %d bridges from %d candidates. Time: %.2fs", actualBridgesBuiltThisPhase_p7, #bridgeCandidates_p7_list, os.clock() - sTime_p7) 
end

local function Phase8_BuildWorld()
	Logger:Info("Phase8", "Starting greedy meshing build world...");
	local startTime_p8 = os.clock()
	local airFillBlocks_p8 = 0
	local solidFillBlocks_p8 = 0
	local totalFillBlockCalls_p8 = 0
	local yieldInnerCounter_p8 = 0
	local YIELD_THRESHOLD_INNER_P8 = CaveConfig.GreedyMesherInnerYieldThreshold or 25000 

	local processedGrid = Grid3D.new(gridSizeX, gridSizeY, gridSizeZ, false)
	if not processedGrid or not processedGrid.data then
		Logger:Fatal("Phase8", "CRITICAL: Failed to create 'processedGrid'. Halting Phase 8.")
		return
	end

	local function _getCellFinalMaterial_p8(cx, cy, cz)
		if not grid:isInBounds(cx,cy,cz) then 
			if Logger:IsLevelEnabled(Logger.Levels.TRACE) and math.random(1, 200) == 1 then
				Logger:Trace("GreedyMesherUtil", "Probing OOB for material: (%s,%s,%s).", tostring(cx),tostring(cy),tostring(cz))
			end
			return CaveConfig.RockMaterial 
		end
		local cellValue = grid:get(cx, cy, cz)
		local cellIndex = grid:index(cx, cy, cz) 
		local materialToFill
		if cellValue == nil then 
			Logger:Warn("GreedyMesherUtil", "_getCellFinalMaterial: grid:get returned nil for (%s,%s,%s). Defaulting Rock.", tostring(cx), tostring(cy), tostring(cz))
			return CaveConfig.RockMaterial
		end
		if CaveConfig.FloodFillPhaseEnabled and cellValue == AIR then
			materialToFill = (not (cellIndex and mainCaveCellIndices[cellIndex])) and CaveConfig.RockMaterial or Enum.Material.Air
		elseif cellValue == SOLID then
			materialToFill = CaveConfig.RockMaterial
			if CaveConfig.OreVeins.Enabled then
				local worldX, worldY, worldZ = origin.X + (cx - 0.5) * cellSize, origin.Y + (cy - 0.5) * cellSize, origin.Z + (cz - 0.5) * cellSize
				for _, oreData in ipairs(CaveConfig.OreVeins.OreList) do
					if oreData.Rarity > 0 then
						local oreNoiseVal = localFractalNoise(worldX, worldY, worldZ, oreData.NoiseScale, oreData.Octaves, oreData.Persistence, oreData.Lacunarity)
						local threshold = tonumber(oreData.Threshold) or 1.1 
						local rarity = tonumber(oreData.Rarity) or 0
						if oreNoiseVal > threshold and localRandomChance(rarity) then
							materialToFill = oreData.Material; break
						end
					end
				end
			end
		elseif cellValue == AIR then
			materialToFill = Enum.Material.Air
		else
			Logger:Warn("GreedyMesherUtil", "_getCellFinalMaterial: Unexpected cell value '%s' at (%s,%s,%s). Defaulting Rock.",
				tostring(cellValue), tostring(cx), tostring(cy), tostring(cz))
			materialToFill = CaveConfig.RockMaterial
		end
		if materialToFill == nil then 
			Logger:Error("GreedyMesherUtil", "_getCellFinalMaterial: CRITICAL FALLBACK: Material unresolved for cell (%s,%s,%s), value %s. Defaulting Rock.", tostring(cx), tostring(cy), tostring(cz), tostring(cellValue))
			return CaveConfig.RockMaterial
		end
		return materialToFill
	end

	local function yieldIfNeeded_p8()
		yieldInnerCounter_p8 = yieldInnerCounter_p8 + 1
		if yieldInnerCounter_p8 >= YIELD_THRESHOLD_INNER_P8 then RunService.Heartbeat:Wait(); yieldInnerCounter_p8 = 0 end
	end

	for z_loop = 1, gridSizeZ do 
		for y_loop = 1, gridSizeY do 
			for x_loop = 1, gridSizeX do 
				local isCellProcessed = processedGrid:isInBounds(x_loop, y_loop, z_loop) and processedGrid:get(x_loop, y_loop, z_loop) or false
				if not processedGrid:isInBounds(x_loop, y_loop, z_loop) then
					Logger:Warn("GreedyMesher", "Main loop coords (%d,%d,%d) out of bounds for processedGrid query. This is unexpected.", x_loop, y_loop, z_loop)
				end
				if isCellProcessed == true then continue end
				local startMaterial = _getCellFinalMaterial_p8(x_loop, y_loop, z_loop)
				local meshWidth = 1
				while true do yieldIfNeeded_p8(); local nextX = x_loop + meshWidth
					if not grid:isInBounds(nextX, y_loop, z_loop) then break end
					local nextXProcessed = processedGrid:isInBounds(nextX,y_loop,z_loop) and processedGrid:get(nextX,y_loop,z_loop) or false
					if not processedGrid:isInBounds(nextX,y_loop,z_loop) then Logger:Trace("GreedyMesherDetail", "Width expansion: nextX OOB for processedGrid."); break end
					if nextXProcessed == true then break end
					if _getCellFinalMaterial_p8(nextX, y_loop, z_loop) ~= startMaterial then break end
					meshWidth = meshWidth + 1
				end
				local meshHeight = 1
				while true do local nextY = y_loop + meshHeight; local scanlineOk = true
					for dx = 0, meshWidth - 1 do yieldIfNeeded_p8(); local currentScanX = x_loop + dx
						if not grid:isInBounds(currentScanX, nextY, z_loop) then scanlineOk = false; break end
						local currentScanProcessed = processedGrid:isInBounds(currentScanX,nextY,z_loop) and processedGrid:get(currentScanX,nextY,z_loop) or false
						if not processedGrid:isInBounds(currentScanX,nextY,z_loop) then Logger:Trace("GreedyMesherDetail","Height expansion: currentScanX,nextY OOB for processedGrid."); scanlineOk = false; break end
						if currentScanProcessed == true then scanlineOk = false; break end
						if _getCellFinalMaterial_p8(currentScanX, nextY, z_loop) ~= startMaterial then scanlineOk = false; break end
					end
					if not scanlineOk then break end; meshHeight = meshHeight + 1
				end
				local meshDepth = 1
				while true do local nextZ = z_loop + meshDepth; local sliceOk = true
					for dy = 0, meshHeight - 1 do local currentScanY = y_loop + dy
						for dx = 0, meshWidth - 1 do yieldIfNeeded_p8(); local currentScanX = x_loop + dx
							if not grid:isInBounds(currentScanX, currentScanY, nextZ) then sliceOk = false; break end
							local currentScanProcessed = processedGrid:isInBounds(currentScanX,currentScanY,nextZ) and processedGrid:get(currentScanX,currentScanY,nextZ) or false
							if not processedGrid:isInBounds(currentScanX,currentScanY,nextZ) then Logger:Trace("GreedyMesherDetail","Depth expansion: OOB for processedGrid.");sliceOk = false; break end
							if currentScanProcessed == true then sliceOk = false; break end
							if _getCellFinalMaterial_p8(currentScanX, currentScanY, nextZ) ~= startMaterial then sliceOk = false; break end
						end
						if not sliceOk then break end
					end
					if not sliceOk then break end; meshDepth = meshDepth + 1
				end
				totalFillBlockCalls_p8 = totalFillBlockCalls_p8 + 1
				local cuboidWorldSize = Vector3.new(meshWidth * cellSize, meshHeight * cellSize, meshDepth * cellSize)
				local minCornerWorldPos = cellToWorld(Vector3.new(x_loop, y_loop, z_loop), origin, cellSize)
				local cuboidCenterWorldPos = minCornerWorldPos + cuboidWorldSize / 2
				if Terrain then
					Terrain:FillBlock(CFrame.new(cuboidCenterWorldPos), cuboidWorldSize, startMaterial)
					if startMaterial == Enum.Material.Air then airFillBlocks_p8 = airFillBlocks_p8 + 1 else solidFillBlocks_p8 = solidFillBlocks_p8 + 1 end
				end
				for iz_mark = 0, meshDepth - 1 do for iy_mark = 0, meshHeight - 1 do for ix_mark = 0, meshWidth - 1 do
							yieldIfNeeded_p8()
							if processedGrid:isInBounds(x_loop + ix_mark, y_loop + iy_mark, z_loop + iz_mark) then
								processedGrid:set(x_loop + ix_mark, y_loop + iy_mark, z_loop + iz_mark, true)
							else
								Logger:Warn("GreedyMesher", "Attempt to mark processed OOB for processedGrid at (%d,%d,%d).", x_loop+ix_mark, y_loop+iy_mark, z_loop+iz_mark)
							end
						end end end
				local callCountLogFrequency = CaveConfig.GreedyMesherCallCountLogFrequency or 5000
				if totalFillBlockCalls_p8 % callCountLogFrequency == 0 then 
					Logger:Trace("GreedyMesherDetail", "Cuboid Processed: Call #%d. Start(%d,%d,%d) Dims(%d,%d,%d) Mat:%s",
						totalFillBlockCalls_p8, x_loop,y_loop,z_loop, meshWidth, meshHeight, meshDepth, tostring(startMaterial))
				end
				doYield() 
			end 
		end 
		local logThisZSlice = false
		if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then
			local zSliceDebugLogDivisor = CaveConfig.GreedyMesherZSliceLogDivisor_DebugMode or 1 
			if z_loop % math.max(1, zSliceDebugLogDivisor) == 0 then logThisZSlice = true end
		elseif Logger:IsLevelEnabled(Logger.Levels.INFO) then -- Only show INFO progress if DEBUG is off but INFO is on
			local zSliceReleaseLogDivisor = CaveConfig.GreedyMesherZSliceLogDivisor_ReleaseMode or 10 
			if z_loop == 1 or z_loop == gridSizeZ or z_loop % math.max(1, math.floor(gridSizeZ / zSliceReleaseLogDivisor)) == 0 then
				logThisZSlice = true
			end
		end
		if logThisZSlice then
			local levelToUse = Logger:IsLevelEnabled(Logger.Levels.DEBUG) and Logger.Levels.DEBUG or Logger.Levels.INFO
			Logger:Log(levelToUse, "GreedyMesher", "Z-slice %d/%d. Total FillBlock Calls: %d (AirGroups: %d, SolidGroups: %d)",
				z_loop, gridSizeZ, totalFillBlockCalls_p8, airFillBlocks_p8, solidFillBlocks_p8)
		end
	end 
	Logger:Info("Phase8", "Greedy meshing build complete. Total Terrain:FillBlock calls: %d (Air groups: %d, Solid/Ore groups: %d)", 
		totalFillBlockCalls_p8, airFillBlocks_p8, solidFillBlocks_p8)
	local endTime_p8 = os.clock()
	Logger:Info("Phase8", "Finished! Time: %.2fs", endTime_p8 - startTime_p8)
end

local function selectBestAxialDirection(targetDirection, choices, axialDirsList)
	if not choices or #choices == 0 then return axialDirsList[localRandomInt(1, #axialDirsList)] end 
	local bestDir = choices[1]; local maxDot = -math.huge 
	if targetDirection.Magnitude < 1e-4 then return choices[localRandomInt(1, #choices)] end
	local normalizedTargetDir = targetDirection.Unit 
	for _, choiceDir in ipairs(choices) do
		local dot = normalizedTargetDir:Dot(choiceDir) 
		if dot > maxDot then maxDot = dot; bestDir = choiceDir end
	end
	return bestDir
end

local AXIAL_DIRECTIONS = {Vector3.new(1,0,0), Vector3.new(-1,0,0),Vector3.new(0,1,0), Vector3.new(0,-1,0),Vector3.new(0,0,1), Vector3.new(0,0,-1)}
local AXIAL_DIRECTIONS_MAP = {[Vector3.new(1,0,0)]=true, [Vector3.new(-1,0,0)]=true,[Vector3.new(0,1,0)]=true, [Vector3.new(0,-1,0)]=true,[Vector3.new(0,0,1)]=true, [Vector3.new(0,0,-1)]=true,}

local function rotateVectorAroundAxis(vecToRotate, axis, angleRadians)
	local rotationCFrame = CFrame.fromAxisAngle(axis.Unit, angleRadians)
	return (rotationCFrame * vecToRotate)
end

local function getOrthogonalAxialDirections(dirVec, avoidReverse)
	local orthos = {}
	for _, axialDir in ipairs(AXIAL_DIRECTIONS) do
		if math.abs(axialDir:Dot(dirVec)) < 0.01 then table.insert(orthos, axialDir) end
	end
	if #orthos == 0 then
		Logger:Warn("Util_Axial", "getOrthogonalAxialDirections: Could not find orthos for dir %s. Defaulting.", tostring(dirVec))
		return {AXIAL_DIRECTIONS[3],AXIAL_DIRECTIONS[4],AXIAL_DIRECTIONS[5],AXIAL_DIRECTIONS[6]}
	end
	return orthos
end

local function _carveSphereAgentTunnels(targetGrid, cX, cY, cZ, radiusCells, materialToCarve)
	local R = math.max(0, math.floor(radiusCells)); local cellsChanged = 0
	for dz_s = -R, R do for dy_s = -R, R do for dx_s = -R, R do
				if dx_s*dx_s + dy_s*dy_s + dz_s*dz_s <= R*R + 0.1 then 
					local nx, ny, nz = cX + dx_s, cY + dy_s, cZ + dz_s
					if targetGrid:isInBounds(nx, ny, nz) then
						if targetGrid:get(nx, ny, nz) ~= materialToCarve then cellsChanged = cellsChanged + 1 end
						targetGrid:set(nx, ny, nz, materialToCarve)
					end
				end
			end end end
	return cellsChanged
end

local nextAgentId_global_tracker = 1 -- Renamed from nextAgentId to avoid conflict if nextAgentId is used locally in a phase

local function Phase_AgentTunnels()
	if not CaveConfig.AgentTunnels_Enabled then
		Logger:Info("AgentTunnels", "Skipped as not enabled in CaveConfig.")
		return
	end
	Logger:Info("AgentTunnels", "Starting agent-based tunneling ('Worms')...")
	local startTime = os.clock()
	local activeAgents = {}; local totalAgentMovementSteps = 0; local agentsSpawnedTotal = 0
	local nextAgentId_pat = 1 -- Use a phase-specific nextAgentId to avoid conflict with the global one if it existed.
	-- Your 'nextAgentId' was already local to the function, so this is just to be extra clear.

	local YIELD_AGENT_BATCH_SIZE = 10; local agentProcessingCounter = 0  

	for i = 1, CaveConfig.AgentTunnels_NumInitialAgents do
		local startPosGrid = nil 
		if CaveConfig.AgentTunnels_StartPolicy == "RandomAirInGrid" then
			local attempts = 100; local foundStart = false 
			for _ = 1, attempts do
				local sx_rand,sy_rand,sz_rand = localRandomInt(2,gridSizeX-1),localRandomInt(CaveConfig.FormationStartHeight_Cells+2,gridSizeY-2),localRandomInt(2,gridSizeZ-1)
				if grid:get(sx_rand, sy_rand, sz_rand) == AIR then startPosGrid = {x=sx_rand,y=sy_rand,z=sz_rand}; foundStart=true; break end
			end
			if not foundStart then 
				startPosGrid = {x=localRandomInt(math.floor(gridSizeX*0.25),math.floor(gridSizeX*0.75)),y=localRandomInt(math.floor(gridSizeY*0.25),math.floor(gridSizeY*0.75)),z=localRandomInt(math.floor(gridSizeZ*0.25),math.floor(gridSizeZ*0.75))}
				Logger:Debug("AgentTunnels", "Agent %d (initial) using fallback start point after failing to find AIR cell.", nextAgentId_pat)
			end
		elseif CaveConfig.AgentTunnels_StartPolicy == "MainCaveAir" then
			local mainAirCellsSample = {}
			if mainCaveCellIndices and next(mainCaveCellIndices) ~= nil then
				Logger:Trace("AgentTunnelsInit", "Attempting to use mainCaveCellIndices for MainCaveAir starts.")
				local candidateCells = {}; local collected = 0
				for x_mc=1, gridSizeX do if collected > 20000 then break end for y_mc=1, gridSizeY do if collected > 20000 then break end for z_mc=1, gridSizeZ do
							local idx = grid:index(x_mc, y_mc, z_mc)
							if idx and mainCaveCellIndices[idx] and grid:get(x_mc, y_mc, z_mc) == AIR then
								table.insert(candidateCells, {x=x_mc, y=y_mc, z=z_mc}); collected = collected + 1
								if collected > 20000 then break end 
							end
						end end end
				if #candidateCells > 0 then
					for _=1, math.min(CaveConfig.AgentTunnels_NumInitialAgents*5, #candidateCells) do table.insert(mainAirCellsSample, candidateCells[localRandomInt(1, #candidateCells)]) end
					Logger:Trace("AgentTunnelsInit", "Sampled %d starting points from mainCaveCellIndices.", #mainAirCellsSample)
				else Logger:Warn("AgentTunnelsInit", "mainCaveCellIndices was not empty, but no AIR cells found from it.") end
			end
			if #mainAirCellsSample == 0 then
				Logger:Trace("AgentTunnelsInit", "mainCaveCellIndices empty or yielded no samples. Running _findAirComponents for MainCaveAir start.")
				local tempComponents = _findAirComponents_local_p45() 
				if #tempComponents > 0 and tempComponents[1] and #tempComponents[1] > 0 then
					Logger:Trace("AgentTunnelsInit", "Found %d cells in largest component for MainCaveAir.", #tempComponents[1])
					for k=1, math.min(CaveConfig.AgentTunnels_NumInitialAgents*5, #tempComponents[1]) do table.insert(mainAirCellsSample, tempComponents[1][localRandomInt(1, #tempComponents[1])]) end
				else Logger:Warn("AgentTunnelsInit", "_findAirComponents found no components for MainCaveAir.") end
			end
			if #mainAirCellsSample > 0 then
				startPosGrid = mainAirCellsSample[localRandomInt(1, #mainAirCellsSample)]
				if #mainAirCellsSample > 0 then table.remove(mainAirCellsSample, localRandomInt(1, #mainAirCellsSample)) end -- Avoid error if table becomes empty
			else Logger:Warn("AgentTunnelsInit", "No MainCaveAir cells found. Falling back to random grid point.") end 
		elseif CaveConfig.AgentTunnels_StartPolicy == "SpecificSeeds" and CaveConfig.AgentTunnels_SeedPoints and CaveConfig.AgentTunnels_SeedPoints[i] then
			startPosGrid = CaveConfig.AgentTunnels_SeedPoints[i] 
			if not grid:isInBounds(startPosGrid.x, startPosGrid.y, startPosGrid.z) then
				Logger:Warn("AgentTunnelsInit", "SpecificSeed point OOB: (%s,%s,%s). Falling back.", startPosGrid.x,startPosGrid.y,startPosGrid.z); startPosGrid=nil 
			end
		end
		if not startPosGrid then
			startPosGrid = {x=localRandomInt(math.floor(gridSizeX*0.25),math.floor(gridSizeX*0.75)),y=localRandomInt(math.floor(gridSizeY*0.25),math.floor(gridSizeY*0.75)),z=localRandomInt(math.floor(gridSizeZ*0.25),math.floor(gridSizeZ*0.75))}
			if CaveConfig.AgentTunnels_StartPolicy ~= "RandomAirInGrid" then 
				Logger:Debug("AgentTunnels", "Agent %d (initial) using general fallback start point for policy: %s", nextAgentId_pat, tostring(CaveConfig.AgentTunnels_StartPolicy))
			end
		end
		if startPosGrid then agentsSpawnedTotal = agentsSpawnedTotal + 1
			table.insert(activeAgents, { id=nextAgentId_pat, pos=Vector3.new(startPosGrid.x-0.5,startPosGrid.y-0.5,startPosGrid.z-0.5), dir=AXIAL_DIRECTIONS[localRandomInt(1,#AXIAL_DIRECTIONS)].Unit, lifetime=localRandomInt(CaveConfig.AgentTunnels_AgentLifetime_MinMax.min,CaveConfig.AgentTunnels_AgentLifetime_MinMax.max),stuckCounter=0,radius=localRandomInt(CaveConfig.AgentTunnels_TunnelRadius_MinMax.min,CaveConfig.AgentTunnels_TunnelRadius_MinMax.max)})
			nextAgentId_pat = nextAgentId_pat + 1
		else Logger:Error("AgentTunnels", "Failed to determine startPosGrid for an initial agent.") end
	end
	if #activeAgents == 0 then Logger:Warn("AgentTunnels", "No initial agents could be spawned. Aborting phase."); return end
	Logger:Debug("AgentTunnels", "Initialized %d agents.", #activeAgents)
	local currentLoopIteration = 0
	while #activeAgents > 0 and totalAgentMovementSteps < CaveConfig.AgentTunnels_MaxTotalAgentSteps do
		currentLoopIteration = currentLoopIteration + 1; local nextGenerationAgents = {}; local newBranchedAgentsThisStep = {}
		agentProcessingCounter = 0 
		for i_agent, agent in ipairs(activeAgents) do
			agentProcessingCounter = agentProcessingCounter + 1
			if agentProcessingCounter >= YIELD_AGENT_BATCH_SIZE then doYield(); agentProcessingCounter = 0 end
			local wasAlive = agent.lifetime > 0; agent.lifetime = agent.lifetime - 1
			if agent.lifetime <= 0 then
				if wasAlive and localRandomChance(0.05) then Logger:Trace("AgentTunnelsDetail", "Agent %d DIED OF OLD AGE.", agent.id) end
				continue 
			end
			local gridX,gridY,gridZ = math.round(agent.pos.X),math.round(agent.pos.Y),math.round(agent.pos.Z)
			_carveSphereAgentTunnels(grid, gridX, gridY, gridZ, agent.radius, AIR)
			local newDir = agent.dir 
			if CaveConfig.AgentTunnels_UseNonAxialMovement then 
				if localRandomChance(CaveConfig.AgentTunnels_TurnChance) then
					local turnAxis = Vector3.new(localRandomFloat(-1,1),localRandomFloat(-1,1),localRandomFloat(-1,1))
					if turnAxis.Magnitude < 1e-4 then turnAxis = Vector3.new(0,1,0) end; turnAxis = turnAxis.Unit
					local turnAngleRads = math.rad(localRandomFloat(CaveConfig.AgentTunnels_TurnAngle_MinMax_Degrees.min,CaveConfig.AgentTunnels_TurnAngle_MinMax_Degrees.max))
					if CaveConfig.AgentTunnels_CurlNoise_Enabled and localRandomChance(CaveConfig.AgentTunnels_CurlNoise_Influence) then
						local worldPosForCurl = cellToWorld(Vector3.new(gridX, gridY, gridZ), origin, cellSize)

						-- *** THE FIX IS HERE: Define individual numeric coords for CurlNoise ***
						local inputCurlX = worldPosForCurl.X / CaveConfig.AgentTunnels_CurlNoise_WorldScale
						local inputCurlY = worldPosForCurl.Y / CaveConfig.AgentTunnels_CurlNoise_WorldScale
						local inputCurlZ = worldPosForCurl.Z / CaveConfig.AgentTunnels_CurlNoise_WorldScale

						local freqForCurl = CaveConfig.AgentTunnels_CurlNoise_FrequencyFactor
						local octavesForCurl = CaveConfig.AgentTunnels_CurlNoise_Octaves
						local persForCurl = CaveConfig.AgentTunnels_CurlNoise_Persistence
						local lacForCurl = CaveConfig.AgentTunnels_CurlNoise_Lacunarity

						Logger:Trace("AgentCurlCall", "CurlNoise CALL Params: X=%.2f, Y=%.2f, Z=%.2f, Freq=%.4f, Oct=%d, Pers=%.2f, Lac=%.2f",
							inputCurlX, inputCurlY, inputCurlZ, freqForCurl, octavesForCurl, persForCurl, lacForCurl)

						local curlVec = Perlin.CurlNoise(
							inputCurlX,      -- Use the scalar X
							inputCurlY,      -- Use the scalar Y
							inputCurlZ,      -- Use the scalar Z
							freqForCurl,     -- This is baseFreq for CurlNoise
							nil,             -- Placeholder for unused curlNoiseFunc param in Perlin.CurlNoise
							octavesForCurl,  -- Octaves for CurlNoise internal FBM
							persForCurl,     -- Persistence for CurlNoise internal FBM
							lacForCurl       -- Lacunarity for CurlNoise internal FBM
						)

						if curlVec.Magnitude > 1e-4 then
							local rotationAxis = agent.dir:Cross(curlVec).Unit
							if rotationAxis.Magnitude>1e-4 then newDir = rotateVectorAroundAxis(agent.dir,rotationAxis,math.min(math.acos(math.clamp(agent.dir:Dot(curlVec.Unit),-1,1)),math.rad(CaveConfig.AgentTunnels_CurlNoise_TurnStrength_Degrees)))
							elseif agent.dir:Dot(curlVec.Unit)<-0.5 then newDir = rotateVectorAroundAxis(agent.dir,turnAxis,turnAngleRads*0.5) end
						else newDir = rotateVectorAroundAxis(agent.dir,turnAxis,turnAngleRads) end
					else newDir = rotateVectorAroundAxis(agent.dir,turnAxis,turnAngleRads) end
				end
				if CaveConfig.AgentTunnels_PreferFlattening and newDir.Y~=0 then local horizDir=Vector3.new(newDir.X,0,newDir.Z); if horizDir.Magnitude>1e-4 then newDir=newDir:Lerp(horizDir.Unit,CaveConfig.AgentTunnels_FlatteningStrength) end end
				if newDir.Magnitude > 1e-6 then agent.dir = newDir.Unit end
			else 
				if localRandomChance(CaveConfig.AgentTunnels_TurnChance) then
					local decidedToTurn=false 
					if CaveConfig.AgentTunnels_CurlNoise_Enabled and localRandomChance(CaveConfig.AgentTunnels_CurlNoise_Influence) then
						local worldPos = cellToWorld(Vector3.new(gridX, gridY, gridZ), origin, cellSize) 

						-- *** THE FIX IS HERE (Axial): Define individual numeric coords for CurlNoise ***
						local inputCurlX_ax = worldPos.X / CaveConfig.AgentTunnels_CurlNoise_WorldScale
						local inputCurlY_ax = worldPos.Y / CaveConfig.AgentTunnels_CurlNoise_WorldScale
						local inputCurlZ_ax = worldPos.Z / CaveConfig.AgentTunnels_CurlNoise_WorldScale

						local freqForCurl_ax = CaveConfig.AgentTunnels_CurlNoise_FrequencyFactor
						local octavesForCurl_ax = CaveConfig.AgentTunnels_CurlNoise_Octaves
						local persForCurl_ax = CaveConfig.AgentTunnels_CurlNoise_Persistence
						local lacForCurl_ax = CaveConfig.AgentTunnels_CurlNoise_Lacunarity

						local curlVec=Perlin.CurlNoise(
							inputCurlX_ax,
							inputCurlY_ax,
							inputCurlZ_ax,
							freqForCurl_ax,
							nil,
							octavesForCurl_ax,
							persForCurl_ax,
							lacForCurl_ax
						)

						if curlVec.Magnitude>1e-4 then local choices=getOrthogonalAxialDirections(agent.dir,CaveConfig.AgentTunnels_AvoidImmediateReverse); table.insert(choices,1,agent.dir); local chosenDir=selectBestAxialDirection(curlVec,choices,AXIAL_DIRECTIONS); if chosenDir~=agent.dir then decidedToTurn=true end; newDir=chosenDir
						else local dirs=getOrthogonalAxialDirections(agent.dir,CaveConfig.AgentTunnels_AvoidImmediateReverse); if #dirs>0 then newDir=dirs[localRandomInt(1,#dirs)]; decidedToTurn=true end end
					else local dirs=getOrthogonalAxialDirections(agent.dir,CaveConfig.AgentTunnels_AvoidImmediateReverse); if #dirs>0 then newDir=dirs[localRandomInt(1,#dirs)]; decidedToTurn=true end end
					if decidedToTurn and CaveConfig.AgentTunnels_AvoidImmediateReverse and newDir == -agent.dir then local dirs=getOrthogonalAxialDirections(agent.dir,true); if #dirs>0 then newDir=dirs[localRandomInt(1,#dirs)] end end
				end; agent.dir = newDir 
			end
			if #activeAgents+#newBranchedAgentsThisStep < CaveConfig.AgentTunnels_MaxActiveAgents and localRandomChance(CaveConfig.AgentTunnels_BranchChance) then
				local branchDir=agent.dir; local randAxis=Vector3.new(localRandomFloat(-1,1),localRandomFloat(-1,1),localRandomFloat(-1,1)).Unit; if randAxis.Magnitude<1e-4 then randAxis=Vector3.new(0,0,1) end
				branchDir=rotateVectorAroundAxis(agent.dir,randAxis,math.rad((CaveConfig.AgentTunnels_BranchTurnAngle or 90)+localRandomFloat(-15,15)))
				agentsSpawnedTotal = agentsSpawnedTotal + 1
				table.insert(newBranchedAgentsThisStep, {id=nextAgentId_pat, pos=agent.pos, dir=branchDir.Unit, lifetime=math.floor(agent.lifetime*CaveConfig.AgentTunnels_BranchLifetimeFactor),stuckCounter=0,radius=localRandomInt(CaveConfig.AgentTunnels_TunnelRadius_MinMax.min,CaveConfig.AgentTunnels_TunnelRadius_MinMax.max)})
				nextAgentId_pat = nextAgentId_pat + 1
				Logger:Trace("AgentTunnelsDetail", "Agent %d branched. New agent: %d", agent.id, nextAgentId_pat-1)
			end
			local nextPosFloat = agent.pos + agent.dir * CaveConfig.AgentTunnels_StepLength
			local nGX,nGY,nGZ = math.round(nextPosFloat.X),math.round(nextPosFloat.Y),math.round(nextPosFloat.Z); local margin = 2 
			if nGX>=margin and nGX<=gridSizeX-(margin-1) and nGY>=margin and nGY<=gridSizeY-(margin-1) and nGZ>=margin and nGZ<=gridSizeZ-(margin-1) then 
				agent.pos=nextPosFloat; agent.stuckCounter=0; totalAgentMovementSteps=totalAgentMovementSteps+1; table.insert(nextGenerationAgents, agent)
			else agent.stuckCounter=agent.stuckCounter+1
				if agent.stuckCounter > CaveConfig.AgentTunnels_MaxStuckBeforeDeath then
					if localRandomChance(0.1) then Logger:Trace("AgentTunnelsDetail", "Agent %d died from being stuck/OOB at grid (%d,%d,%d)", agent.id, nGX,nGY,nGZ) end
				else local escAxis=Vector3.new(localRandomFloat(-1,1),localRandomFloat(-1,1),localRandomFloat(-1,1)).Unit; if escAxis.Magnitude<1e-4 then escAxis=Vector3.new(0,1,0) end; agent.dir=rotateVectorAroundAxis(agent.dir,escAxis,math.rad(localRandomFloat(60,120))); if agent.dir.Magnitude>1e-6 then agent.dir=agent.dir.Unit else agent.dir=AXIAL_DIRECTIONS[localRandomInt(1,6)].Unit end; table.insert(nextGenerationAgents, agent) end
			end
		end 
		for _, branchedAgent in ipairs(newBranchedAgentsThisStep) do table.insert(nextGenerationAgents, branchedAgent) end
		activeAgents = nextGenerationAgents
		if currentLoopIteration % 50 == 0 then
			Logger:Debug("AgentTunnels", "Iter %d, Active Agents: %d, Total Steps: %d/%d",
				currentLoopIteration, #activeAgents, totalAgentMovementSteps, CaveConfig.AgentTunnels_MaxTotalAgentSteps)
		end
	end 
	local endTime = os.clock()
	Logger:Info("AgentTunnels", "Finished! %d agents spawned in total. Total movement steps: %d. Time: %.2fs", agentsSpawnedTotal, totalAgentMovementSteps, endTime - startTime)
end

-- =============================================================================
-- VI. MAIN EXECUTION
-- =============================================================================
local function RunCaveGeneration()
	Logger:Info("RunCaveGen", "--- SCRIPT EXECUTION STARTED ---")
	-- Terrain and CaveConfig checks now done at the very top after Logger setup

	Logger:Info("RunCaveGen", "Initializing Grid...")
	Logger:Info("RunCaveGen", "GridSize: %d x %d x %d cells", gridSizeX, gridSizeY, gridSizeZ)

	grid = Grid3D.new(gridSizeX, gridSizeY, gridSizeZ, SOLID)
	if (not grid) or (not grid.data) then 
		Logger:Fatal("RunCaveGen", "Grid3D.new returned nil or grid has no data! Cannot proceed.")
		return 
	end
	Logger:Info("RunCaveGen", "Grid initialized. Total cells: %d", #grid.data)

	if #grid.data ~= (gridSizeX*gridSizeY*gridSizeZ) then 
		Logger:Warn("RunCaveGen", "Grid cell count mismatch! Expected: %d, Actual: %d", (gridSizeX*gridSizeY*gridSizeZ), #grid.data)
	end
	if grid:get(1,1,1) ~= SOLID then 
		Logger:Warn("RunCaveGen", "Grid(1,1,1) is not SOLID after init! Value: %s", tostring(grid:get(1,1,1)))
	else 
		Logger:Debug("RunCaveGen", "Grid(1,1,1) is SOLID as expected after init.")
	end

	mainCaveCellIndices={}
	yieldCounter=0
	local overallStartTime=os.clock()
	local errorInPhase=false

	local phasesToRun={
		{name="Phase1_InitialCaveFormation",func=Phase1_InitialCaveFormation,enabled=true},
		{name="Phase2_RockFormations",func=Phase2_RockFormations,enabled=CaveConfig.FormationPhaseEnabled},
		{name="Phase3_Smoothing",func=Phase3_Smoothing,enabled=CaveConfig.SmoothingPhaseEnabled},
		{name="Phase4_EnsureConnectivity",func=Phase4_EnsureConnectivity,enabled=CaveConfig.ConnectivityPhaseEnabled},
		{name="Phase5_FloodFillCleanup",func=Phase5_FloodFillCleanup,enabled=CaveConfig.FloodFillPhaseEnabled},
		{name="Phase_AgentTunnels", func=Phase_AgentTunnels, enabled=CaveConfig.AgentTunnels_Enabled},
		{name="Phase6_SurfaceEntrances",func=Phase6_SurfaceEntrances,enabled=CaveConfig.SurfaceEntrancesPhaseEnabled},
		{name="Phase7_Bridges",func=Phase7_Bridges,enabled=CaveConfig.BridgePhaseEnabled},
		{name="Phase8_BuildWorld",func=Phase8_BuildWorld,enabled=true}
	}

	for i,phaseInfo in ipairs(phasesToRun) do 
		if phaseInfo.enabled then 
			Logger:Info("RunCaveGen", "--- Starting phase: %s ---", phaseInfo.name)
			local success,errMsgOrResult = pcall(phaseInfo.func) 
			if not success then 
				local errMsg = errMsgOrResult 
				Logger:Error("RunCaveGen", "--- ERROR in %s: %s ---", phaseInfo.name, tostring(errMsg))
				if errMsg and type(errMsg)=="string" then 
					Logger:Error("RunCaveGen", "Stack trace for %s:\n%s", phaseInfo.name, debug.traceback(errMsg,2))
				else 
					Logger:Error("RunCaveGen", "Stack trace for %s (non-string error):\n%s", phaseInfo.name, debug.traceback("Error in pcall, no string message.",2))
				end
				errorInPhase=true; break 
			else 
				Logger:Info("RunCaveGen", "--- Finished phase: %s ---", phaseInfo.name)
				if Logger:IsLevelEnabled(Logger.Levels.DEBUG) then
					if phaseInfo.name == "Phase1_InitialCaveFormation" or 
						phaseInfo.name == "Phase2_RockFormations" or
						phaseInfo.name == "Phase3_Smoothing" or
						phaseInfo.name == "Phase5_FloodFillCleanup" or
						phaseInfo.name == "Phase_AgentTunnels" or 
						phaseInfo.name == "Phase6_SurfaceEntrances" then
						local airCount, solidCount = CountCellTypesInGrid(grid)
						Logger:Debug("RunCaveGen", "POST-%s: AIR cells = %d, SOLID cells = %d", phaseInfo.name, airCount, solidCount)
					end
				end
			end
		else 
			Logger:Info("RunCaveGen", "--- Skipping phase: %s (disabled in CaveConfig) ---", phaseInfo.name)
		end
	end

	local overallEndTime=os.clock()
	Logger:Info("RunCaveGen", "-----------------------------------------------------")
	if errorInPhase then 
		Logger:Error("RunCaveGen", "CAVE GENERATION HALTED DUE TO ERROR IN A PHASE.")
	else 
		Logger:Info("RunCaveGen", "ALL ENABLED PHASES CALLED.")
	end
	Logger:Info("RunCaveGen", "Total script execution time: %.2fs", overallEndTime-overallStartTime)
	Logger:Info("RunCaveGen", "-----------------------------------------------------")
end -- End RunCaveGeneration

task.wait(3)
Logger:Info("MainScript", "--- CaveGenerator Script: Calling RunCaveGeneration ---")
RunCaveGeneration()
Logger:Info("MainScript", "--- CaveGenerator Script: Execution flow ended. ---")