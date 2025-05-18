-- Script: CaveGenerator
-- Path: ServerScriptService/CaveGenerator.lua
-- VERSION 6.0.5 - Correcting all reported errors (Syntax, Comparison, MultiLine, UnknownGlobal)

local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

if not Terrain then
	error("CaveGenerator FATAL @ TOP: Terrain not found in Workspace. Script will not run.")
	return 
end
print("CaveGenerator INFO @ TOP: Terrain object located successfully.")

-- Dependencies
print("CaveGenerator INFO @ TOP: Attempting to load CaveConfig...")
local CaveConfig = require(script.Parent.CaveConfig)
if not CaveConfig then error("CaveGenerator FATAL @ TOP: CaveConfig module failed to load or returned nil.") return end
print("CaveGenerator INFO @ TOP: CaveConfig loaded. Threshold = " .. tostring(CaveConfig.Threshold))

print("CaveGenerator INFO @ TOP: Attempting to load NoiseGenerator...")
local NoiseGeneratorModule = require(script.Parent.NoiseGenerator)
if not NoiseGeneratorModule then error("CaveGenerator FATAL @ TOP: NoiseGenerator module failed to load or returned nil.") return end
print("CaveGenerator INFO @ TOP: NoiseGenerator loaded.")

local Perlin = NoiseGeneratorModule.PerlinModule
if not Perlin then error("CaveGenerator FATAL @ TOP: Perlin module (via NoiseGeneratorModule.PerlinModule) is nil.") return end
if typeof(Perlin.FBM_Base) ~= "function" then 
	error("CaveGenerator FATAL @ TOP: Perlin.FBM_Base is not a function!") 
	return 
end
if typeof(NoiseGeneratorModule.GetValue) ~= "function" then 
	error("CaveGenerator FATAL @ TOP: NoiseGeneratorModule:GetValue is not a function!") 
	return 
end
print("CaveGenerator INFO @ TOP: Perlin module access verified.")

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
	if CaveConfig.DebugMode then 
		print(string.format("Grid3D.new: Created grid %dx%dx%d. Data table size: %d", sX, sY, sZ, #newGrid.data)) 
	end
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
		if CaveConfig.DebugMode then 
			print(string.format("Grid3D:set WARNING - Attempted set out of bounds for (%s,%s,%s)", tostring(x),tostring(y),tostring(z))) 
		end
		return false 
	end
	self.data[idx] = value
	return true
end -- End Grid3D:set

function Grid3D:isInBounds(x, y, z)
	if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
		if CaveConfig.DebugMode then warn("Grid3D:isInBounds WARN: Received non-number coords: ", x,y,z) end
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
	print("--- TestGridWithFalseValues ---")
	local testGridSize = 5
	local testVisited = Grid3D.new(testGridSize, testGridSize, testGridSize, false)

	if not testVisited or not testVisited.data then
		print("TEST FAIL: testVisited grid is nil or no data table.")
		return
	end
	print("TestGrid created. Size of data table:", #testVisited.data)

	local val_1_1_1 = testVisited:get(1, 1, 1)
	print(string.format("TEST: Value at (1,1,1) from fresh 'false' grid: %s (Type: %s)", tostring(val_1_1_1), type(val_1_1_1)))

	if val_1_1_1 == false then
		print("TEST PASS: Fresh 'false' grid correctly returns false for get(1,1,1).")
	else
		print("TEST FAIL: Fresh 'false' grid DID NOT return false for get(1,1,1)!")
	end

	if not val_1_1_1 then
		print("TEST: 'not val_1_1_1' is TRUE. This is correct if val_1_1_1 is false or nil.")
	else
		print("TEST: 'not val_1_1_1' is FALSE. This is correct if val_1_1_1 is true or a truthy value.")
	end

	testVisited:set(1,1,1, true)
	local val_1_1_1_after_set_true = testVisited:get(1,1,1)
	print(string.format("TEST: Value at (1,1,1) after set to true: %s (Type: %s)", tostring(val_1_1_1_after_set_true), type(val_1_1_1_after_set_true)))

	if val_1_1_1_after_set_true == true then
		print("TEST PASS: set(true) then get() works.")
	else
		print("TEST FAIL: set(true) then get() did not return true.")
	end

	local val_2_2_2_unmodified = testVisited:get(2,2,2) -- Should still be false
	print(string.format("TEST: Value at (2,2,2) (unmodified): %s (Type: %s)", tostring(val_2_2_2_unmodified), type(val_2_2_2_unmodified)))
	if val_2_2_2_unmodified == false then
		print("TEST PASS: Unmodified cell in 'false' grid returns false.")
	else
		print("TEST FAIL: Unmodified cell in 'false' grid did not return false.")
	end
	print("--- TestGridWithFalseValues END ---")
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
		warn("CountCellTypesInGrid: Invalid grid provided!")
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
	print("Phase 1 INFO: Starting initial cave structure...")

	-- Hierarchical Noise Configuration Print
	if CaveConfig.P1_UseHierarchicalNoise then
		print("Phase 1 INFO: Hierarchical Noise (Broad Structure Pass) is ENABLED.")
		print(string.format("    Broad Pass Params: ScaleFactor=%.3f, Octaves=%d, Threshold=%.3f",
			CaveConfig.P1_BroadStructure_NoiseScaleFactor,
			CaveConfig.P1_BroadStructure_Octaves,
			CaveConfig.P1_BroadStructure_Threshold))
	else
		print("Phase 1 INFO: Hierarchical Noise (Broad Structure Pass) is DISABLED.")
	end

	-- Domain Warping Configuration Print
	if CaveConfig.P1_UseDomainWarp then
		print("Phase 1 INFO: Domain Warping is ENABLED.")
		print(string.format("    DW Params: Strength=%.2f, FreqFactor=%.3f, Octaves=%d, Pers=%.2f, Lacu=%.2f",
			CaveConfig.P1_DomainWarp_Strength, CaveConfig.P1_DomainWarp_FrequencyFactor,
			CaveConfig.P1_DomainWarp_Octaves, CaveConfig.P1_DomainWarp_Persistence, CaveConfig.P1_DomainWarp_Lacunarity))
	else
		print("Phase 1 INFO: Domain Warping is DISABLED.")
	end

	local startTime = os.clock()
	local airCellsSetInP1 = 0
	local broadPassSetToSolidCount = 0 -- Counter for cells set by broad pass
	local exampleFinalDensityForSlice -- Remains for detailed pass sampling

	for z = 1, gridSizeZ do
		for y = 1, gridSizeY do
			for x = 1, gridSizeX do
				local worldX_orig = origin.X + (x - 0.5) * cellSize
				local worldY_orig = origin.Y + (y - 0.5) * cellSize
				local worldZ_orig = origin.Z + (z - 0.5) * cellSize

				local skipDetailedCalculation = false

				-- Hierarchical Noise Pass (Broad Structure)
				if CaveConfig.P1_UseHierarchicalNoise then
					local broadNoiseEffectiveScale = CaveConfig.P1_NoiseScale * CaveConfig.P1_BroadStructure_NoiseScaleFactor

					local broadNoiseVal = localFractalNoise(worldX_orig, worldY_orig, worldZ_orig,
						broadNoiseEffectiveScale,
						CaveConfig.P1_BroadStructure_Octaves,
						CaveConfig.P1_Persistence, -- Using main persistence
						CaveConfig.P1_Lacunarity)  -- Using main lacunarity

					-- If broad noise suggests a solid area, mark as SOLID and skip detailed calculation
					if broadNoiseVal > CaveConfig.P1_BroadStructure_Threshold then
						grid:set(x, y, z, SOLID)
						skipDetailedCalculation = true
						broadPassSetToSolidCount = broadPassSetToSolidCount + 1

						if CaveConfig.DebugMode and broadPassSetToSolidCount < 15 and broadPassSetToSolidCount % 1 == 0 then -- Log a few initial ones
							print(string.format("P1 HIERARCHICAL: Cell(%d,%d,%d) SOLID by Broad Pass. Noise=%.4f (Thresh=%.3f)",
								x,y,z, broadNoiseVal, CaveConfig.P1_BroadStructure_Threshold))
						end
					end
				end

				-- Detailed Noise Pass (Domain Warped or Regular)
				if not skipDetailedCalculation then
					local worldX_input = worldX_orig
					local worldY_input = worldY_orig
					local worldZ_input = worldZ_orig

					if CaveConfig.P1_UseDomainWarp then
						local warpedX, warpedY, warpedZ = Perlin.DomainWarp(
							worldX_orig, worldY_orig, worldZ_orig,
							CaveConfig.P1_DomainWarp_FrequencyFactor,
							CaveConfig.P1_DomainWarp_Strength,
							nil, -- Use default Perlin.Noise_Raw
							CaveConfig.P1_DomainWarp_Octaves,
							CaveConfig.P1_DomainWarp_Persistence,
							CaveConfig.P1_DomainWarp_Lacunarity
						)
						worldX_input = warpedX
						worldY_input = warpedY
						worldZ_input = warpedZ

						if CaveConfig.DebugMode and x <= 1 and y <= 1 and z <= 1 then -- Existing DW debug
							local iterationNum = (z-1)*gridSizeX*gridSizeY + (y-1)*gridSizeX + x
							if iterationNum <= 2 then 
								print(string.format("P1 DW DEBUG: Cell(%d,%d,%d) Orig(%0.2f,%0.2f,%0.2f) -> Warped(%0.2f,%0.2f,%0.2f)",
									x,y,z, worldX_orig, worldY_orig, worldZ_orig, warpedX, warpedY, warpedZ))
							end
						end
					end

					local noiseVal = localFractalNoise(worldX_input, worldY_input, worldZ_input,
						CaveConfig.P1_NoiseScale,
						CaveConfig.P1_Octaves,
						CaveConfig.P1_Persistence,
						CaveConfig.P1_Lacunarity)

					local hBias = localHeightBias(y, gridSizeY)
					local dBias = localDistanceToCenterBias(x, y, z, gridSizeX, gridSizeY, gridSizeZ, CaveConfig.P1_DistanceBias_Max)
					local vConnBias = localVerticalConnectivityNoise(worldX_orig, worldY_orig, worldZ_orig, CaveConfig.P1_NoiseScale)

					local finalDensity = noiseVal + hBias + dBias + vConnBias

					if x == math.floor(gridSizeX/2) and y == math.floor(gridSizeY/2) then
						exampleFinalDensityForSlice = finalDensity -- Keep for detailed pass sample
					end

					if finalDensity < CaveConfig.Threshold then
						grid:set(x, y, z, AIR); airCellsSetInP1 = airCellsSetInP1 + 1
						if airCellsSetInP1 < 15 and CaveConfig.DebugMode then
							print(string.format("P1 DETAILED: Cell(%d,%d,%d) SET TO AIR. finalDensity=%.4f (Noise=%.3f), Thresh=%.4f",x,y,z,finalDensity,noiseVal,CaveConfig.Threshold))
						end
					else
						grid:set(x, y, z, SOLID)
					end
				end
				doYield()
			end -- End for x
		end -- End for y

		-- Existing Z-slice debug print
		if CaveConfig.DebugMode and z % 20 == 0 then
			local status_msg = string.format("P1 DEBUG: Z-slice %d done.", z)
			if exampleFinalDensityForSlice then -- Will only be set if at least one cell in the slice went through detailed pass
				status_msg = string.format("P1 DEBUG: Z-slice %d. Sample DetailedDensity(mid): %.4f (Thresh %.4f)", z, exampleFinalDensityForSlice, CaveConfig.Threshold)
			end
			if CaveConfig.P1_UseHierarchicalNoise then
				status_msg = status_msg .. string.format(" BroadSolid: %d.", broadPassSetToSolidCount)
			end
			print(status_msg)
			exampleFinalDensityForSlice = nil -- Reset for next sampled slice
		end
	end -- End for z

	-- Solidify borders (existing logic)
	for z_b = 1, gridSizeZ do
		for x_b = 1, gridSizeX do
			for y_b = 1, gridSizeY do
				if y_b <= CaveConfig.FormationStartHeight_Cells then grid:set(x_b,y_b,z_b,SOLID) end
				if x_b==1 or x_b==gridSizeX or z_b==1 or z_b==gridSizeZ then grid:set(x_b,y_b,z_b,SOLID) end
			end
		end
	end
	if CaveConfig.DebugMode then print("P1 DEBUG: Borders solidified.") end

	-- Final P1 summary prints
	print("P1 INFO: Total cells set to AIR in P1 (detailed pass): " .. airCellsSetInP1)
	if CaveConfig.P1_UseHierarchicalNoise then
		print("P1 INFO: Total cells set to SOLID by broad pass (skipped detailed): " .. broadPassSetToSolidCount)
	end
	local endTime = os.clock(); print("P1 INFO: Finished! Time: " .. string.format("%.2f", endTime - startTime) .. "s")
end -- End Phase1_InitialCaveFormation

local function _createFormation(startX,startY,startZ,type,endYForColumn) 
	local length_cf=localRandomInt(CaveConfig.MinFormationLength_Cells,CaveConfig.MaxFormationLength_Cells)
	local dirY_cf=(type=="stalactite") and -1 or 1
	if type=="column" then 
		if endYForColumn then 
			length_cf=(endYForColumn-startY)+1 
		else 
			warn("_createFormation WARN: Column type provided without endYForColumn parameter.")
			return 
		end
		dirY_cf=1 
	end -- End if type column
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
		end -- End if type column for radius factor

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
					end -- End if inside circle
				end -- End for dz_cf
			end -- End for dx_cf
		end -- End for r_cf
		if rCells_cf==0 then grid:set(startX,curY_cf,startZ,SOLID) end
		doYield()
	end -- End for i_cf (length)
end -- End _createFormation

local function Phase2_RockFormations() -- This is approx your line 318
	print("P2 INFO: Starting rock formations...")
	local sTime=os.clock()
	local pSpots={}
	local cForms={s=0,m=0,c=0} -- s for stalactites, m for stalagmites, c for columns

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
					end -- End for i_cl (stalactite clearance)
					for i_cl=1,CaveConfig.FormationClearance_Cells do 
						if not grid:isInBounds(x_p2,y_p2+i_cl,z_p2) or grid:get(x_p2,y_p2+i_cl,z_p2)==SOLID then 
							clB=false; break 
						end 
					end -- End for i_cl (stalagmite clearance)

					if rA and clA then table.insert(pSpots,{x=x_p2,y=y_p2,z=z_p2,type="stalactite"}) end
					if rB and clB then table.insert(pSpots,{x=x_p2,y=y_p2,z=z_p2,type="stalagmite"}) end

					if rA and rB then -- Potential column middle
						local fY,cY=y_p2,y_p2
						while grid:isInBounds(x_p2,fY-1,z_p2) and grid:get(x_p2,fY-1,z_p2)==AIR do fY=fY-1 end
						while grid:isInBounds(x_p2,cY+1,z_p2) and grid:get(x_p2,cY+1,z_p2)==AIR do cY=cY+1 end
						local actFY,actCY=fY-1,cY+1
						if grid:isInBounds(x_p2,actFY,z_p2) and grid:get(x_p2,actFY,z_p2)==SOLID and 
							grid:isInBounds(x_p2,actCY,z_p2) and grid:get(x_p2,actCY,z_p2)==SOLID then
							local airH=actCY-actFY-1
							if airH>=CaveConfig.MinColumnHeight_Cells then 
								table.insert(pSpots,{x=x_p2,y=(fY+cY)/2,z=z_p2,type="column",floorCellY=fY,ceilCellY=cY})
							end -- End if airH
						end -- End if solid floor/ceiling for column
					end -- End if rA and rB
				end -- End if grid cell is AIR
			end -- End for y_p2
		end -- End for x_p2
	end -- End for z_p2

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
			elseif CaveConfig.DebugMode then 
				print("P2 DEBUG: Invalid col spot data",spt.x,spt.y,spt.z)
			end -- End if valid column spot data
		end -- End if/elseif type
		doYield()
	end -- End for _,spt
	if CaveConfig.DebugMode then print("P2 DEBUG: Spots processed: ".. #pSpots..", Formation creation attempted: "..fAtt)end
	print(string.format("P2 INFO: Created S:%d, M:%d, C:%d.",cForms.s,cForms.m,cForms.c))
	local eTime=os.clock()
	print("P2 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s")
end -- End Phase2_RockFormations

local function Phase3_Smoothing()
	print("P3 INFO: Starting smoothing...")
	local sTime=os.clock()
	for iter=1,CaveConfig.SmoothingIterations do 
		local airPreIter, solidPreIter = CountCellTypesInGrid(grid)
		if CaveConfig.DebugMode then 
			print(string.format("P3 DEBUG: Iter %d PRE-SMOOTH: AIR cells = %d, SOLID cells = %d", iter, airPreIter, solidPreIter))
		end

		local nGridD=table.clone(grid.data) -- Operate on a clone for this iteration
		local cellsCh=0
		for z_p3=2,gridSizeZ-1 do 
			for y_p3=2,gridSizeY-1 do 
				for x_p3=2,gridSizeX-1 do 
					local sN=grid:getNeighborCount(x_p3,y_p3,z_p3,SOLID,26) -- Read from original grid
					local cV=grid:get(x_p3,y_p3,z_p3) -- Read from original grid
					local cI=grid:index(x_p3,y_p3,z_p3) 
					if cI then 
						local currentTargetVal = cV -- What nGridD[cI] will be if no change
						if cV==SOLID then 
							if (26-sN)>=CaveConfig.SmoothingThreshold_CarveRock then 
								nGridD[cI]=AIR
								if cV == SOLID then cellsCh=cellsCh+1 end
							end 
						else -- cV == AIR
							if sN>=CaveConfig.SmoothingThreshold_FillAir then 
								nGridD[cI]=SOLID
								if cV == AIR then cellsCh=cellsCh+1 end 
								-- else: no change, it stays AIR from original grid.
								-- if it wasn't modified in newGridData, it would take cV
								-- but since we clone grid.data, if we don't set it, it's cV from previous iter
							end
						end 
					end 
					doYield()
				end 
			end 
		end 
		grid.data=nGridD -- Apply changes from this iteration

		local airPostIter, solidPostIter = CountCellTypesInGrid(grid)
		if CaveConfig.DebugMode then 
			print(string.format("P3 DEBUG: Iteration %d POST-SMOOTH: AIR cells = %d, SOLID cells = %d. Cells changed this iter: %d",iter, airPostIter, solidPostIter, cellsCh))
		end
	end 
	local eTime=os.clock()
	print("P3 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s")
end -- End Phase3_Smoothing

-- Script-level state for _floodFillSearch to avoid UnknownGlobal if not passed.
-- These are effectively parameters to the function if declared in its signature.

local function _floodFillSearch_local_p45(startX, startY, startZ, visitedGrid, invocationContext) 
	local compCells = {}
	local q = Queue.new()

	-- Validate inputs and initial state
	local isInBoundsFlag = grid:isInBounds(startX,startY,startZ)
	local initialCellVal = nil
	if isInBoundsFlag then 
		initialCellVal = grid:get(startX,startY,startZ) 
	end

	local isVisitedFlag = false 
	if not visitedGrid or not visitedGrid.data then
		if CaveConfig.DebugMode then 
			warn(string.format("_floodFillSearch_local_p45 FATAL: 'visitedGrid' parameter is nil or invalid for start (%d,%d,%d). Cannot proceed.", startX, startY, startZ))
		end
		return compCells 
	end
	if visitedGrid:isInBounds(startX, startY, startZ) then
		isVisitedFlag = visitedGrid:get(startX,startY,startZ)
	elseif CaveConfig.DebugMode then 
		-- warn(string.format("_floodFillSearch_local_p45: Start coords (%d,%d,%d) out of bounds for 'visitedGrid'. Assuming not visited.", startX, startY, startZ))
	end

	-- CONDITIONAL initial prints (only for first few attempts in a _findAirComponents_local_p45 call)
	if CaveConfig.DebugMode and invocationContext and invocationContext.floodFillAttempts <= (CaveConfig.FloodFillContext_MaxInitialDebugAttempts or 3) then
		print(string.format("_floodFillSearch INVOKED #%d with: start (%d,%d,%d)", invocationContext.floodFillAttempts, startX,startY,startZ))
		print(string.format("    Grid InBounds: %s, InitialCellVal: %s, isVisitedInVisitedGrid: %s", 
			tostring(isInBoundsFlag), tostring(initialCellVal), tostring(isVisitedFlag)))
	end

	-- Check conditions to start flood fill
	if not isInBoundsFlag or initialCellVal ~= AIR or isVisitedFlag == true then 
		if CaveConfig.DebugMode and invocationContext and invocationContext.floodFillAttempts <= (CaveConfig.FloodFillContext_MaxInitialDebugAttempts or 3) then
			print(string.format("_floodFillSearch DEBUG #%d: Flood PREVENTED. InBounds:%s, IsAir:%s, IsVisited:%s", 
				invocationContext.floodFillAttempts, tostring(isInBoundsFlag), tostring(initialCellVal == AIR), tostring(isVisitedFlag)))
		end
		return compCells 
	end

	if CaveConfig.DebugMode and invocationContext and invocationContext.floodFillAttempts <= (CaveConfig.FloodFillContext_MaxInitialDebugAttempts or 3) then
		print(string.format("_floodFillSearch DEBUG #%d: PASSED initial checks. Starting flood from (%d,%d,%d)", invocationContext.floodFillAttempts, startX,startY,startZ))
	end

	q:push({x=startX,y=startY,z=startZ})
	visitedGrid:set(startX,startY,startZ,true)

	local cellsProcessedInFlood = 0
	while not q:isEmpty() do 
		local cell = q:pop()
		if not cell then 
			if CaveConfig.DebugMode then warn("_floodFillSearch: q:pop() returned nil unexpectedly! Breaking loop.") end
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

	-- CONDITIONAL "finished" print
	if CaveConfig.DebugMode then
		local compSize = #compCells
		local shouldPrintFinish = false
		if compSize > 0 then
			if invocationContext and invocationContext.componentsFound < (CaveConfig.FloodFillContext_MaxInitialComponentLogs or 3) then
				shouldPrintFinish = true -- Log first few components found
			elseif compSize > (CaveConfig.FloodFillContext_LargeComponentThreshold or 1000) then
				shouldPrintFinish = true -- Log very large components
			elseif compSize < (CaveConfig.FloodFillContext_SmallComponentThreshold or 10) and compSize > 0 then -- Avoid printing for 0-size that didn't flood
				shouldPrintFinish = true -- Log very small (but non-zero) components
			end
		end

		if shouldPrintFinish then
			print(string.format("_floodFillSearch DEBUG #%d (Comp #%d): Flood from (%d,%d,%d) finished. Size: %d cells. ProcessedInFlood: %d", 
				invocationContext and invocationContext.floodFillAttempts or 0,
				invocationContext and invocationContext.componentsFound + 1 or 0, -- +1 because component is about to be "found"
				startX,startY,startZ, compSize, cellsProcessedInFlood))
		end
	end
	return compCells
end

local function _findAirComponents_local_p45() 
	local components={}
	local visited=Grid3D.new(gridSizeX,gridSizeY,gridSizeZ,false) 

	if not visited or not visited.data then
		error("FAC_p45 CRITICAL: Failed to create 'visited' Grid3D instance. Halting component search.")
		return components 
	end

	if CaveConfig.DebugMode then print("_findAirComponents_local_p45: Starting component search...") end
	local airCellsFoundByIteration = 0
	local solidCellsFoundByIteration = 0
	local nilCellsFoundByIteration = 0
	local firstAirCellCoords = nil -- For debug

	-- Context for _floodFillSearch_local_p45 debugging & local stats
	local floodFillContext_p45 = {
		floodFillAttempts = 0, -- How many times we try to start a flood
		componentsFound = 0    -- How many actual components were identified
	}
	local minComponentSize_p45 = gridSizeX * gridSizeY * gridSizeZ + 1 -- Init to impossibly large
	local maxComponentSize_p45 = 0
	local totalCellsInFoundComponents_p45 = 0

	for z_l=1,gridSizeZ do 
		for y_l=1,gridSizeY do 
			for x_l=1,gridSizeX do 
				local currentCellValue = grid:get(x_l,y_l,z_l)

				if currentCellValue == AIR then
					airCellsFoundByIteration = airCellsFoundByIteration + 1
					if not firstAirCellCoords and CaveConfig.DebugMode and (CaveConfig.FloodFillLogFirstAirCellFound == nil or CaveConfig.FloodFillLogFirstAirCellFound) then
						firstAirCellCoords = {x=x_l, y=y_l, z=z_l}
						print(string.format("FAC_p45 DEBUG: FIRST AIR CELL found by iteration at (%d,%d,%d)", x_l,y_l,z_l))
					end

					local isAlreadyVisited = false
					if visited:isInBounds(x_l,y_l,z_l) then
						isAlreadyVisited = visited:get(x_l,y_l,z_l)
					end

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
							-- Individual component log is now handled conditionally inside _floodFillSearch_local_p45
						end
					end 
				elseif currentCellValue == SOLID then
					solidCellsFoundByIteration = solidCellsFoundByIteration + 1
				else 
					nilCellsFoundByIteration = nilCellsFoundByIteration + 1
					if CaveConfig.DebugMode and nilCellsFoundByIteration < (CaveConfig.FloodFillMaxNilCellLogs or 3) then
						print(string.format("FAC_p45 DEBUG: Found NIL/unexpected cell value '%s' at (%d,%d,%d) during iteration!",tostring(currentCellValue), x_l, y_l, z_l))
					end
				end
				doYield() 
			end 
		end 
		if CaveConfig.DebugMode and z_l % math.max(1, math.floor(gridSizeZ / (CaveConfig.FloodFillZSliceLogDivisor or 10))) == 0 then
			print(string.format("FAC_p45 PROGRESS: Z-slice %d/%d. Air cells by iter: %d. Attempts: %d, Comps Found: %d",
				z_l, gridSizeZ, airCellsFoundByIteration, floodFillContext_p45.floodFillAttempts, floodFillContext_p45.componentsFound))
		end
	end 

	table.sort(components,function(a,b)return #a>#b end) 

	-- Enhanced summary print, always shows if DebugMode is true
	if CaveConfig.DebugMode then
		print("--- FAC_p45 (_findAirComponents) SUMMARY ---")
		print(string.format("  Grid Iteration encountered: AIR: %d, SOLID: %d, NIL/Other: %d",
			airCellsFoundByIteration, solidCellsFoundByIteration, nilCellsFoundByIteration))
		if firstAirCellCoords and (CaveConfig.FloodFillLogFirstAirCellFound == nil or CaveConfig.FloodFillLogFirstAirCellFound) then
			print(string.format("  First air cell by iteration: (%d,%d,%d)", firstAirCellCoords.x, firstAirCellCoords.y, firstAirCellCoords.z))
		end
		print(string.format("  Flood Fill Attempts: %d", floodFillContext_p45.floodFillAttempts))
		print(string.format("  Total Air Components Identified: %d", #components))
		if #components > 0 then
			print(string.format("  Largest Component Size: %d cells", #components[1]))
			local smallestInList = #components[#components] 
			local recordedMin = minComponentSize_p45
			if recordedMin == (gridSizeX * gridSizeY * gridSizeZ + 1) then 
				recordedMin = (#components > 0 and smallestInList or 0)
			end
			print(string.format("  Smallest Component in List: %d cells. (Smallest recorded during scan: %d)", smallestInList, recordedMin))
			print(string.format("  Max Component Size Recorded: %d cells", maxComponentSize_p45))
			print(string.format("  Total Cells in all Found Components: %d", totalCellsInFoundComponents_p45))
			if #components > 0 then
				print(string.format("  Average Component Size: %.2f cells", totalCellsInFoundComponents_p45 / #components))
			end
		else
			print("  No actual air components were formed by flood fill.")
		end
		print("--------------------------------------------")
	else
		-- Non-debug mode still gets a very concise summary (useful for P4/P5)
		print(string.format("FAC_p45 INFO: Found %d air components. Largest: %d cells.",
			#components, (#components > 0 and #components[1] or 0) ))
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
	if CaveConfig.DebugMode then print(string.format("_carveTunnel_local_p46 DEBUG: Carving from(%.1f,%.1f,%.1f) to(%.1f,%.1f,%.1f),d%.1f,r%d",p1.x,p1.y,p1.z,p2.x,p2.y,p2.z,dist,rad))end
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
						end -- End if isInBounds
					end -- End if in sphere
				end -- End for dz_t
			end -- End for dy_t
		end -- End for dx_t
		step=step+1
		doYield()
	end -- End while step
	if CaveConfig.DebugMode then print("_carveTunnel_local_p46 DEBUG: Tunnel done. Approx cells to AIR:",cellsCT)end
end -- End _carveTunnel_local_p46

local function Phase4_EnsureConnectivity()
	print("P4 INFO: Starting ensure connectivity...")
	local sTime=os.clock()
	local airCs=_findAirComponents_local_p45() 
	if #airCs==0 then print("P4 INFO: No air components.");return end
	if #airCs==1 then print("P4 INFO: Already connected."); if airCs[1] then mainCaveCellIndices={}; for _,c_ac in ipairs(airCs[1]) do if c_ac then local i_ac=grid:index(c_ac.x,c_ac.y,c_ac.z); if i_ac then mainCaveCellIndices[i_ac]=true end end end end; return end

	print("P4 INFO: Found "..#airCs.." comps. Connecting...")
	if CaveConfig.DebugMode then for i_dc=1,math.min(5,#airCs) do if airCs[i_dc] then print("P4 DEBUG: Comp size",i_dc,":",#airCs[i_dc]) end end end

	local mainC=airCs[1]
	local connsMade=0
	local numToCon=math.min(#airCs-1,CaveConfig.ConnectivityDensity)
	print("P4 INFO: Will attempt up to "..numToCon.." connections.")

	for tCompIdx=2,#airCs do 
		if connsMade>=numToCon then if CaveConfig.DebugMode then print("P4 DEBUG: Reached ConnectivityDensity limit")end;break end
		local compB=airCs[tCompIdx]
		if not compB or #compB==0 then if CaveConfig.DebugMode then print("P4 DEBUG: CompB idx",tCompIdx,"nil/empty.")end;continue end

		local cDistSq=math.huge
		local cA_b,cB_b
		local sMax=200
		local sA,sB={},{}
		if mainC and #mainC>0 then for _=1,math.min(#mainC,sMax) do local c_sm=mainC[localRandomInt(1,#mainC)];if c_sm then table.insert(sA,c_sm)end end end
		if compB and #compB>0 then for _=1,math.min(#compB,sMax) do local c_sm=compB[localRandomInt(1,#compB)];if c_sm then table.insert(sB,c_sm)end end end

		if #sA==0 or #sB==0 then print("P4 WARN: Empty sample for connecting idx",tCompIdx);doYield();continue end

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
			print(string.format("P4 INFO: Connected comp (orig idx %d). Dist: %.1f",tCompIdx,math.sqrt(cDistSq)))
			connsMade=connsMade+1
			if compB and mainC then 
				for _,bC_m in ipairs(compB) do if bC_m then table.insert(mainC,bC_m)end end 
			end 
		else 
			print("P4 WARN: Failed to connect comp idx",tCompIdx)
		end 
	end 
	if connsMade>0 then mainCaveCellIndices={} end -- If connections made, re-evaluate mainCaveCellIndices.
	-- More robustly, after connections, the largest component might have changed, or existing mainC absorbed others.
	-- So, it might be better to call _findAirComponents again if P5 relies on the *absolute* largest.
	-- For now, if P5 calls _findAirComponents_local_p45 again, this reset might be okay.
	-- To be safe and ensure mainCaveCellIndices accurately reflects the current largest connected component post-P4:
	if connsMade > 0 then
		print("P4 INFO: Connections made. Re-identifying the main cave component.")
		local finalAirCs_P4 = _findAirComponents_local_p45() -- This will run with the (now less spammy) flood fill debug
		if #finalAirCs_P4 > 0 and finalAirCs_P4[1] then
			mainCaveCellIndices = {}
			for _, cellData in ipairs(finalAirCs_P4[1]) do
				if cellData then
					local idx = grid:index(cellData.x, cellData.y, cellData.z)
					if idx then mainCaveCellIndices[idx] = true end
				end
			end
			if CaveConfig.DebugMode then
				local count = 0; for _ in pairs(mainCaveCellIndices) do count = count + 1 end
				print("P4 DEBUG: mainCaveCellIndices repopulated. New main component size: " .. count)
			end
		else
			if CaveConfig.DebugMode then print("P4 DEBUG: No air components found after connections for mainCaveCellIndices repopulation.") end
			mainCaveCellIndices = {} -- Ensure it's empty if no components
		end
	end

	local eTime=os.clock()
	print("P4 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s. Connections: "..connsMade)
end

local function Phase5_FloodFillCleanup()
	print("P5 INFO: Starting flood fill cleanup...")
	local sTime=os.clock()
	local airCs_p5=_findAirComponents_local_p45() 
	if #airCs_p5==0 then print("P5 INFO: No air components.");return end
	if CaveConfig.DebugMode then print("P5 DEBUG: Found "..#airCs_p5.." comps pre-cleanup. Largest: "..(#airCs_p5[1]and #airCs_p5[1]or 0))end

	mainCaveCellIndices={}
	if #airCs_p5>0 and airCs_p5[1] then 
		for _,cD_p5 in ipairs(airCs_p5[1]) do 
			if cD_p5 then 
				local idx_p5=grid:index(cD_p5.x,cD_p5.y,cD_p5.z)
				if idx_p5 then mainCaveCellIndices[idx_p5]=true end 
			end 
		end 
	end 

	if CaveConfig.DebugMode then local mcC_p5=0;for _ in pairs(mainCaveCellIndices)do mcC_p5=mcC_p5+1 end;print("P5 DEBUG: mainCaveCellIndices populated w/ "..mcC_p5.." cells.")end

	local cellsF_p5=0
	for i_p5f=2,#airCs_p5 do 
		if airCs_p5[i_p5f] then 
			for _,cDF_p5 in ipairs(airCs_p5[i_p5f]) do 
				if cDF_p5 then grid:set(cDF_p5.x,cDF_p5.y,cDF_p5.z,SOLID);cellsF_p5=cellsF_p5+1;doYield()end 
			end 
		end 
	end 
	print(string.format("P5 INFO: Kept largest. Filled %d from %d smaller.",cellsF_p5,math.max(0,#airCs_p5-1)))
	local eTime=os.clock()
	print("P5 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s")
end

local function Phase6_SurfaceEntrances()
	print("P6 INFO: Starting surface entrances...")
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
				for ox_p6e=-1,1 do 
					for oy_p6e=-1,1 do 
						for oz_p6e=-1,1 do 
							if ox_p6e==0 and oy_p6e==0 and oz_p6e==0 then continue end
							local chkX_p6e,chkY_p6e,chkZ_p6e = cPos_p6e.x+ox_p6e,cPos_p6e.y+oy_p6e,cPos_p6e.z+oz_p6e
							local chkIdx_p6e=grid:index(chkX_p6e,chkY_p6e,chkZ_p6e)
							if chkIdx_p6e and mainCaveCellIndices[chkIdx_p6e] and grid:get(chkX_p6e,chkY_p6e,chkZ_p6e)==AIR then 
								conn_p6e=true; break 
							end 
						end 
						if conn_p6e then break end 
					end 
					if conn_p6e then break end 
				end 
			end 
			if conn_p6e then if CaveConfig.DebugMode then print("P6 DEBUG: Entrance",i_p6e,"connected.")end;break end 
		end 
		if conn_p6e then entrMade_p6=entrMade_p6+1 
		elseif CaveConfig.DebugMode then print("P6 DEBUG: Entrance",i_p6e,"did not connect or reached max length/depth.")
		end 
	end 

	print("P6 INFO: Created/attempted",entrMade_p6,"entrances of",CaveConfig.SurfaceCaveCount)
	if entrMade_p6>0 and CaveConfig.FloodFillPhaseEnabled then 
		print("P6 INFO: Re-evaluating main cave cells after entrances.")
		local airCs_p6r=_findAirComponents_local_p45()
		if #airCs_p6r>0 and airCs_p6r[1] then 
			mainCaveCellIndices={} 
			for _,cD_p6r in ipairs(airCs_p6r[1]) do 
				if cD_p6r then 
					local idx_p6r=grid:index(cD_p6r.x,cD_p6r.y,cD_p6r.z)
					if idx_p6r then mainCaveCellIndices[idx_p6r]=true end 
				end 
			end 
			if CaveConfig.DebugMode then 
				local mcC_p6r=0; for _ in pairs(mainCaveCellIndices) do mcC_p6r=mcC_p6r+1 end
				print("P6 DEBUG: Main cave re-identified:",mcC_p6r,"(Largest comp:",#airCs_p6r[1],")")
			end 
		elseif CaveConfig.DebugMode then print("P6 DEBUG: No air comps for re-eval post-entrances.")
		end 
	end 
	local eTime=os.clock()
	print("P6 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s")
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
	for dx_bcc_l=-cRC,cRC do 
		for dy_bcc_l=-cRC,cRC do 
			for dz_bcc_l=-cRC,cRC do 
				local curX,curY,curZ=math.floor(mX+dx_bcc_l),cy+dy_bcc_l,math.floor(mZ+dz_bcc_l)
				local ccci_bcc=grid:index(curX,curY,curZ)  
				if ccci_bcc and grid:get(curX,curY,curZ)==AIR and(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[ccci_bcc]) then airCC=airCC+1 end
			end 
		end 
	end 
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
	if CaveConfig.DebugMode then print("_buildBridge_local DEBUG: Bridge done. Approx cells SOLID:",cellsSet)end
end 

local function Phase7_Bridges() 
	print("P7 INFO: Starting bridges...")
	local sTime_p7 = os.clock()
	local brBuilt_p7 = 0
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
								x_loop_main_p7 = lookX_p7_target 
								break 
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
								z_loop_main_p7 = lookZ_p7_target 
								break 
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
					local ex_p7_val = tonumber(crds_p7_val[1])
					local ey_p7_val = tonumber(crds_p7_val[2])
					local ez_p7_val = tonumber(crds_p7_val[3])
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
	print(string.format("P7 INFO: Built %d bridges from %d candidates. Time: %.2fs", actualBridgesBuiltThisPhase_p7, #bridgeCandidates_p7_list, os.clock() - sTime_p7)) 
end

local function Phase8_BuildWorld()
	print("P8 INFO: Starting greedy meshing build world...");
	local startTime_p8 = os.clock()
	local airFillBlocks_p8 = 0
	local solidFillBlocks_p8 = 0
	local totalFillBlockCalls_p8 = 0
	local yieldInnerCounter_p8 = 0
	local YIELD_THRESHOLD_INNER_P8 = CaveConfig.GreedyMesherInnerYieldThreshold or 25000 

	local processedGrid = Grid3D.new(gridSizeX, gridSizeY, gridSizeZ, false)
	if not processedGrid or not processedGrid.data then
		error("P8 CRITICAL: Failed to create 'processedGrid'. Halting Phase 8.")
		return
	end

	local function _getCellFinalMaterial_p8(cx, cy, cz)
		if not grid:isInBounds(cx,cy,cz) then 
			if CaveConfig.DebugMode then 
				if math.random(1, 200) == 1 then -- Heavily reduce spam for this trace
					-- print("P8 Greedy _getCellFinalMaterial_p8 TRACE: Probing OOB: ("..tostring(cx)..","..tostring(cy)..","..tostring(cz)..").")
				end
			end
			return CaveConfig.RockMaterial 
		end

		local cellValue = grid:get(cx, cy, cz)
		local cellIndex = grid:index(cx, cy, cz) 
		local materialToFill

		if cellValue == nil then 
			if CaveConfig.DebugMode then warn(string.format("P8 Greedy _getCellFinalMaterial_p8 WARN: grid:get returned nil for (%s,%s,%s). Defaulting Rock.", tostring(cx), tostring(cy), tostring(cz))) end
			return CaveConfig.RockMaterial
		end

		if CaveConfig.FloodFillPhaseEnabled and cellValue == AIR then
			if not (cellIndex and mainCaveCellIndices[cellIndex]) then
				materialToFill = CaveConfig.RockMaterial
			else
				materialToFill = Enum.Material.Air
			end
		elseif cellValue == SOLID then
			materialToFill = CaveConfig.RockMaterial
			if CaveConfig.OreVeins.Enabled then
				local worldX, worldY, worldZ = origin.X + (cx - 0.5) * cellSize, origin.Y + (cy - 0.5) * cellSize, origin.Z + (cz - 0.5) * cellSize
				for _, oreData in ipairs(CaveConfig.OreVeins.OreList) do
					if oreData.Rarity > 0 then
						local oreNoiseVal = localFractalNoise(worldX, worldY, worldZ,
							oreData.NoiseScale, oreData.Octaves, oreData.Persistence, oreData.Lacunarity)
						local threshold = tonumber(oreData.Threshold) or 1.1 
						local rarity = tonumber(oreData.Rarity) or 0
						if oreNoiseVal > threshold and localRandomChance(rarity) then
							materialToFill = oreData.Material
							break
						end
					end
				end
			end
		elseif cellValue == AIR then
			materialToFill = Enum.Material.Air
		else
			if CaveConfig.DebugMode then
				warn(string.format("P8 Greedy _getCellFinalMaterial_p8 WARNING: Unexpected cell value '%s' at (%s,%s,%s). Defaulting Rock.",
					tostring(cellValue), tostring(cx), tostring(cy), tostring(cz)))
			end
			materialToFill = CaveConfig.RockMaterial
		end

		if materialToFill == nil then 
			if CaveConfig.DebugMode then warn(string.format("P8 Greedy _getCellFinalMaterial_p8 CRITICAL FALLBACK: Material unresolved for cell (%s,%s,%s), value %s. Defaulting Rock.", tostring(cx), tostring(cy), tostring(cz), tostring(cellValue))) end
			return CaveConfig.RockMaterial
		end
		return materialToFill
	end

	local function yieldIfNeeded_p8()
		yieldInnerCounter_p8 = yieldInnerCounter_p8 + 1
		if yieldInnerCounter_p8 >= YIELD_THRESHOLD_INNER_P8 then
			RunService.Heartbeat:Wait()
			yieldInnerCounter_p8 = 0
		end
	end

	for z_loop = 1, gridSizeZ do 
		for y_loop = 1, gridSizeY do 
			for x_loop = 1, gridSizeX do 
				local isCellProcessed = false
				if processedGrid:isInBounds(x_loop, y_loop, z_loop) then
					isCellProcessed = processedGrid:get(x_loop, y_loop, z_loop)
				else 
					-- This case should ideally not be hit if x_loop,y_loop,z_loop are from 1 to gridSize
					if CaveConfig.DebugMode then warn("P8 WARNING: Main loop x,y,z out of bounds for processedGrid query. This is unexpected.") end
				end

				if isCellProcessed == true then
					continue
				end

				local startMaterial = _getCellFinalMaterial_p8(x_loop, y_loop, z_loop)

				local meshWidth = 1
				while true do
					yieldIfNeeded_p8()
					local nextX = x_loop + meshWidth
					if not grid:isInBounds(nextX, y_loop, z_loop) then break end
					local nextXProcessed = false
					if processedGrid:isInBounds(nextX,y_loop,z_loop) then 
						nextXProcessed = processedGrid:get(nextX,y_loop,z_loop) 
					else 
						if CaveConfig.DebugMode then warn ("P8 Warning: nextX OOB for processedGrid in width expansion.") end
						break -- Treat OOB for processedGrid as a hard boundary for safety
					end
					if nextXProcessed == true then break end
					if _getCellFinalMaterial_p8(nextX, y_loop, z_loop) ~= startMaterial then break end
					meshWidth = meshWidth + 1
				end

				local meshHeight = 1
				while true do
					local nextY = y_loop + meshHeight
					local scanlineOk = true
					for dx = 0, meshWidth - 1 do
						yieldIfNeeded_p8()
						local currentScanX = x_loop + dx
						if not grid:isInBounds(currentScanX, nextY, z_loop) then scanlineOk = false; break end
						local currentScanProcessed = false
						if processedGrid:isInBounds(currentScanX,nextY,z_loop) then 
							currentScanProcessed = processedGrid:get(currentScanX,nextY,z_loop) 
						else
							if CaveConfig.DebugMode then warn ("P8 Warning: currentScanX,nextY OOB for processedGrid in height expansion.") end
							scanlineOk = false; break
						end
						if currentScanProcessed == true then scanlineOk = false; break end
						if _getCellFinalMaterial_p8(currentScanX, nextY, z_loop) ~= startMaterial then scanlineOk = false; break end
					end
					if not scanlineOk then break end
					meshHeight = meshHeight + 1
				end

				local meshDepth = 1
				while true do
					local nextZ = z_loop + meshDepth
					local sliceOk = true
					for dy = 0, meshHeight - 1 do
						local currentScanY = y_loop + dy
						for dx = 0, meshWidth - 1 do
							yieldIfNeeded_p8()
							local currentScanX = x_loop + dx
							if not grid:isInBounds(currentScanX, currentScanY, nextZ) then sliceOk = false; break end
							local currentScanProcessed = false
							if processedGrid:isInBounds(currentScanX,currentScanY,nextZ) then 
								currentScanProcessed = processedGrid:get(currentScanX,currentScanY,nextZ) 
							else
								if CaveConfig.DebugMode then warn ("P8 Warning: currentScanX,currentScanY,nextZ OOB for processedGrid in depth expansion.") end
								sliceOk = false; break
							end
							if currentScanProcessed == true then sliceOk = false; break end
							if _getCellFinalMaterial_p8(currentScanX, currentScanY, nextZ) ~= startMaterial then sliceOk = false; break end
						end
						if not sliceOk then break end
					end
					if not sliceOk then break end
					meshDepth = meshDepth + 1
				end

				totalFillBlockCalls_p8 = totalFillBlockCalls_p8 + 1

				local cuboidWorldSize = Vector3.new(
					meshWidth * cellSize,
					meshHeight * cellSize,
					meshDepth * cellSize
				)
				local minCornerWorldPos = cellToWorld(Vector3.new(x_loop, y_loop, z_loop), origin, cellSize)
				local cuboidCenterWorldPos = minCornerWorldPos + cuboidWorldSize / 2

				if Terrain then
					Terrain:FillBlock(CFrame.new(cuboidCenterWorldPos), cuboidWorldSize, startMaterial)
					if startMaterial == Enum.Material.Air then
						airFillBlocks_p8 = airFillBlocks_p8 + 1
					else
						solidFillBlocks_p8 = solidFillBlocks_p8 + 1
					end
				end

				for iz_mark = 0, meshDepth - 1 do
					for iy_mark = 0, meshHeight - 1 do
						for ix_mark = 0, meshWidth - 1 do
							yieldIfNeeded_p8()
							if processedGrid:isInBounds(x_loop + ix_mark, y_loop + iy_mark, z_loop + iz_mark) then
								processedGrid:set(x_loop + ix_mark, y_loop + iy_mark, z_loop + iz_mark, true)
							else
								if CaveConfig.DebugMode then warn ("P8 Warning: Attempt to mark processed OOB for processedGrid.") end
							end
						end
					end
				end

				local callCountLogFrequency = CaveConfig.GreedyMesherCallCountLogFrequency or 5000 -- Default: log every 5000th cuboid
				if CaveConfig.DebugMode and totalFillBlockCalls_p8 % callCountLogFrequency == 0 then 
					print(string.format("P8 Greedy DEBUG (Cuboid Processed): Call #%d. Start(%d,%d,%d) Dims(%d,%d,%d) Mat:%s",
						totalFillBlockCalls_p8, x_loop,y_loop,z_loop, meshWidth, meshHeight, meshDepth, tostring(startMaterial)))
				end

				doYield() -- Original script-level yield counter
			end -- End x_loop 
		end -- End y_loop

		-- V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V
		-- CORRECTED AND SINGLE Z-SLICE PROGRESS INFO PRINT LOGIC:
		-- V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V V
		local logThisZSlice = false
		if CaveConfig.DebugMode then
			-- Behavior when DebugMode is ON:
			-- Use GreedyMesherZSliceLogDivisor_DebugMode from config, default to 1 (print every Z-slice if DebugMode is true)
			local zSliceDebugLogDivisor = CaveConfig.GreedyMesherZSliceLogDivisor_DebugMode or 1 
			if z_loop % math.max(1, zSliceDebugLogDivisor) == 0 then -- Note: using direct modulo, not floor(gridSizeZ/divisor) for this mode
				logThisZSlice = true
			end
		else
			-- Behavior when DebugMode is OFF:
			-- Use GreedyMesherZSliceLogDivisor_ReleaseMode from config, default to aiming for ~10 prints
			local zSliceReleaseLogDivisor = CaveConfig.GreedyMesherZSliceLogDivisor_ReleaseMode or 10 
			-- Print for first, last, and periodically based on the divisor's intent to give N total prints
			if z_loop == 1 or z_loop == gridSizeZ or z_loop % math.max(1, math.floor(gridSizeZ / zSliceReleaseLogDivisor)) == 0 then
				logThisZSlice = true
			end
		end

		if logThisZSlice then
			print(string.format("P8 Greedy INFO: Z-slice %d/%d. Total Calls: %d (AirGroups: %d, SolidGroups: %d)",
				z_loop, gridSizeZ, totalFillBlockCalls_p8, airFillBlocks_p8, solidFillBlocks_p8))
		end
		-- ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ 
		-- END OF CORRECTED Z-SLICE PROGRESS INFO PRINT LOGIC
		-- ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ 

	end -- End z_loop

	-- Final summary print for Phase 8 (basic version, no detailed cuboid stats for now)
	print(string.format("P8 INFO: Greedy meshing build complete. Total Terrain:FillBlock calls: %d (Air groups: %d, Solid/Ore groups: %d)", 
		totalFillBlockCalls_p8, airFillBlocks_p8, solidFillBlocks_p8))
	local endTime_p8 = os.clock()
	print("P8 INFO: Finished! Time: " .. string.format("%.2f", endTime_p8 - startTime_p8) .. "s")
end

-- =============================================================================
-- VI. MAIN EXECUTION
-- =============================================================================
local function RunCaveGeneration()
	print("--- RunCaveGeneration: SCRIPT EXECUTION STARTED ---")
	if (not Terrain) then error("RunCaveGeneration FATAL: Terrain nil!") return end; print("RunCaveGeneration INFO: Terrain confirmed.")
	if (not CaveConfig) then error("RunCaveGeneration FATAL: CaveConfig nil!") return end; print("RunCaveGeneration INFO: CaveConfig loaded. Threshold="..tostring(CaveConfig.Threshold)..", Debug="..tostring(CaveConfig.DebugMode))
	print("RunCaveGeneration INFO: Initializing Grid..."); print(string.format("RunCaveGeneration INFO: gridSize: %d,%d,%d",gridSizeX,gridSizeY,gridSizeZ))

	grid = Grid3D.new(gridSizeX, gridSizeY, gridSizeZ, SOLID)
	if (not grid) or (not grid.data) then error("RunCaveGeneration FATAL: Grid3D.new fail!")return end
	print("RunCaveGeneration INFO: Grid init. Total cells: "..tostring(#grid.data))
	if #grid.data ~= (gridSizeX*gridSizeY*gridSizeZ) then warn("RunCaveGeneration WARN: Grid size mismatch!")end
	if grid:get(1,1,1) ~= SOLID then 
		warn("RunCaveGeneration WARN: Grid(1,1,1) not SOLID! Val: "..tostring(grid:get(1,1,1)))
	else 
		print("RunCaveGeneration INFO: Grid(1,1,1) SOLID.")
	end

	-- mainCaveCellIndices initialization MOVED INSIDE and BEFORE phases that might use it extensively.
	-- However, P5 always re-populates it based on the largest component found then.
	-- P4 also re-populates it if connections are made.
	-- P6 re-populates it if entrances are made and FloodFillPhaseEnabled.
	-- So, simply declaring it should be fine:
	mainCaveCellIndices={}
	yieldCounter=0
	local overallStartTime=os.clock()
	local errorInPhase=false

	local phasesToRun={
		{name="Phase1_InitialCaveFormation",func=Phase1_InitialCaveFormation,enabled=true}, -- THIS IS THE ONLY P1 CALL NOW
		{name="Phase2_RockFormations",func=Phase2_RockFormations,enabled=CaveConfig.FormationPhaseEnabled},
		{name="Phase3_Smoothing",func=Phase3_Smoothing,enabled=CaveConfig.SmoothingPhaseEnabled},
		{name="Phase4_EnsureConnectivity",func=Phase4_EnsureConnectivity,enabled=CaveConfig.ConnectivityPhaseEnabled},
		{name="Phase5_FloodFillCleanup",func=Phase5_FloodFillCleanup,enabled=CaveConfig.FloodFillPhaseEnabled},
		{name="Phase6_SurfaceEntrances",func=Phase6_SurfaceEntrances,enabled=CaveConfig.SurfaceEntrancesPhaseEnabled},
		{name="Phase7_Bridges",func=Phase7_Bridges,enabled=CaveConfig.BridgePhaseEnabled},
		{name="Phase8_BuildWorld",func=Phase8_BuildWorld,enabled=true}
	}

	for i,phaseInfo in ipairs(phasesToRun) do 
		if phaseInfo.enabled then 
			print("--- RunCaveGeneration: Starting "..phaseInfo.name.." ---")
			local success,errMsg=pcall(phaseInfo.func)
			if not success then 
				warn("--- RunCaveGeneration: ERROR in "..phaseInfo.name..": "..tostring(errMsg).." ---")
				if errMsg and type(errMsg)=="string" then 
					warn(debug.traceback(errMsg,2))
				else 
					warn(debug.traceback("Err in pcall,no str msg.",2))
				end
				errorInPhase=true; break 
			else 
				print("--- RunCaveGeneration: Finished "..phaseInfo.name.." ---")
				-- Add debug cell counts after key phases IF DebugMode is on
				if CaveConfig.DebugMode then
					if phaseInfo.name == "Phase1_InitialCaveFormation" or 
						phaseInfo.name == "Phase2_RockFormations" or
						phaseInfo.name == "Phase3_Smoothing" or -- Can be useful after smoothing too
						phaseInfo.name == "Phase5_FloodFillCleanup" or
						phaseInfo.name == "Phase6_SurfaceEntrances" then
						local airCount, solidCount = CountCellTypesInGrid(grid)
						print(string.format("--- DEBUG POST-%s: AIR cells = %d, SOLID cells = %d ---", phaseInfo.name, airCount, solidCount))
					end
				end
			end
		else 
			print("--- RunCaveGeneration: Skipping "..phaseInfo.name.." ---")
		end
	end

	local overallEndTime=os.clock()
	print("-----------------------------------------------------")
	if errorInPhase then print("CAVE GEN HALTED DUE TO ERROR.")else print("ALL ENABLED PHASES CALLED.")end
	print("Total script exec time: "..string.format("%.2f",overallEndTime-overallStartTime).."s");print("-----------------------------------------------------")
end -- End RunCaveGeneration

task.wait(3); print("--- CaveGenerator Script: Calling RunCaveGeneration ---")
RunCaveGeneration(); print("--- CaveGenerator Script: Execution flow ended. ---")