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
	local startTime = os.clock()
	local airCellsSetInP1 = 0
	local exampleFinalDensityForSlice 
	for z = 1, gridSizeZ do
		for y = 1, gridSizeY do
			for x = 1, gridSizeX do
				local worldX = origin.X + (x - 0.5) * cellSize
				local worldY = origin.Y + (y - 0.5) * cellSize
				local worldZ = origin.Z + (z - 0.5) * cellSize

				local noiseVal = localFractalNoise(worldX, worldY, worldZ, 
					CaveConfig.P1_NoiseScale, 
					CaveConfig.P1_Octaves, 
					CaveConfig.P1_Persistence, 
					CaveConfig.P1_Lacunarity)
				local hBias = localHeightBias(y, gridSizeY)
				local dBias = localDistanceToCenterBias(x, y, z, 
					gridSizeX, gridSizeY, gridSizeZ, CaveConfig.P1_DistanceBias_Max)
				local vConnBias = localVerticalConnectivityNoise(worldX, worldY, worldZ, 
					CaveConfig.P1_NoiseScale)

				local finalDensity = noiseVal + 
					hBias + 
					dBias + 
					vConnBias -- MultiLineStatement: Ensured reasonable indent

				if x == math.floor(gridSizeX/2) and y == math.floor(gridSizeY/2) then 
					exampleFinalDensityForSlice = finalDensity 
				end

				if finalDensity < CaveConfig.Threshold then
					grid:set(x, y, z, AIR); airCellsSetInP1 = airCellsSetInP1 + 1
					if airCellsSetInP1 < 15 and CaveConfig.DebugMode then 
						print(string.format("P1 DEBUG: Cell(%d,%d,%d) SET TO AIR. finalDensity=%.4f, Thresh=%.4f",x,y,z,finalDensity,CaveConfig.Threshold)) 
					end
				else 
					grid:set(x, y, z, SOLID) 
				end -- End if finalDensity
				doYield()
			end -- End for x
		end -- End for y
		if CaveConfig.DebugMode and z % 20 == 0 then 
			if exampleFinalDensityForSlice then 
				print(string.format("P1 DEBUG: Z-slice %d. Sample Density (mid): %.4f for Thresh %.4f",z,exampleFinalDensityForSlice,CaveConfig.Threshold))
			else 
				print(string.format("P1 DEBUG: Z-slice %d done.", z)) 
			end
		end -- End if DebugMode print
	end -- End for z
	for z_b = 1, gridSizeZ do 
		for x_b = 1, gridSizeX do 
			for y_b = 1, gridSizeY do
				if y_b <= CaveConfig.FormationStartHeight_Cells then grid:set(x_b,y_b,z_b,SOLID) end
				if x_b==1 or x_b==gridSizeX or z_b==1 or z_b==gridSizeZ then grid:set(x_b,y_b,z_b,SOLID) end
			end -- End for y_b
		end -- End for x_b
	end -- End for z_b
	if CaveConfig.DebugMode then print("P1 DEBUG: Borders solidified.") end
	print("P1 INFO: Total cells set to AIR in P1: " .. airCellsSetInP1)
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

local function _floodFillSearch_local_p45(startX,startY,startZ,visitedGrid) 
	local compCells={};local q=Queue.new()

	-- More detailed checks at the start of the flood fill
	local isInBoundsFlag = grid:isInBounds(startX,startY,startZ)
	local initialCellVal = nil
	if isInBoundsFlag then initialCellVal = grid:get(startX,startY,startZ) end
	local isVisitedFlag = visitedGrid:get(startX,startY,startZ) -- This is specifically on the 'visitedGrid' passed in

	if CaveConfig.DebugMode then
		print(string.format("_floodFillSearch INVOKED with: start (%d,%d,%d)", startX,startY,startZ))
		print(string.format("    InBoundsCheck: %s", tostring(isInBoundsFlag)))
		if isInBoundsFlag then print(string.format("    InitialCellValueCheck: %s (expected AIR i.e. 0)", tostring(initialCellVal))) end
		print(string.format("    VisitedCheck: %s (expected false)", tostring(isVisitedFlag)))
	end

	if (not isInBoundsFlag) or (initialCellVal ~= AIR) or (isVisitedFlag == true) then 
		-- One of these conditions must be met to "Not Start"
		if CaveConfig.DebugMode then
			print(string.format("_floodFillSearch DEBUG: Condition MET - Not starting. InBounds:%s, IsAir:%s, IsVisited:%s", 
				tostring(isInBoundsFlag), 
				tostring(initialCellVal == AIR), -- Correctly check if it IS AIR
				tostring(isVisitedFlag)))
		end
		return compCells 
	end

	-- If we reach here, the above 'if' was FALSE, so flood fill SHOULD proceed
	if CaveConfig.DebugMode then print(string.format("_floodFillSearch DEBUG: PASSED initial checks. Starting flood from (%d,%d,%d)", startX,startY,startZ)) end

	q:push({x=startX,y=startY,z=startZ})
	visitedGrid:set(startX,startY,startZ,true) -- Mark the STARTING cell as visited for THIS flood instance

	local cellsProcessedInFlood = 0
	while not q:isEmpty() do 
		local cell=q:pop()
		if cell then 
			table.insert(compCells,cell)
			cellsProcessedInFlood = cellsProcessedInFlood + 1 
		end
		doYield()
		local DIRS={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
		if cell then 
			for _,dir in ipairs(DIRS) do 
				local nx,ny,nz=cell.x+dir[1],cell.y+dir[2],cell.z+dir[3]
				if grid:isInBounds(nx,ny,nz) and grid:get(nx,ny,nz)==AIR and not visitedGrid:get(nx,ny,nz) then 
					visitedGrid:set(nx,ny,nz,true)
					q:push({x=nx,y=ny,z=nz})
				end
			end
		end
	end -- End while

	if CaveConfig.DebugMode then 
		print(string.format("_floodFillSearch DEBUG: Flood from (%d,%d,%d) finished. Component size: %d. Cells processed in this flood: %d", 
			startX,startY,startZ, #compCells, cellsProcessedInFlood)) 
	end
	return compCells
end -- End _floodFillSearch_local_p45 (DETAILED DEBUG)

local function _findAirComponents_local_p45() 
	local components={};
	local visited=Grid3D.new(gridSizeX,gridSizeY,gridSizeZ,false) 

	print("_findAirComponents_local_p45 DEBUG: Starting search...")
	local airCellsFoundByIteration = 0
	local solidCellsFoundByIteration = 0
	local nilCellsFoundByIteration = 0
	local firstAirCellCoords = nil

	for z_l=1,gridSizeZ do 
		for y_l=1,gridSizeY do 
			for x_l=1,gridSizeX do 
				-- DIRECTLY CHECK THE GRID VALUE HERE
				local currentCellValue = grid:get(x_l,y_l,z_l)

				if currentCellValue == AIR then
					airCellsFoundByIteration = airCellsFoundByIteration + 1
					if not firstAirCellCoords then -- Store coordinates of the VERY FIRST air cell found by this loop
						firstAirCellCoords = {x=x_l, y=y_l, z=z_l}
						if CaveConfig.DebugMode then
							print(string.format("FAC_p45 DEBUG: FIRST AIR CELL found by iteration at (%d,%d,%d)", x_l,y_l,z_l))
						end
					end

					-- Now, only if it's air AND not visited, try to flood fill
					if not visited:get(x_l,y_l,z_l) then 
						local nComp=_floodFillSearch_local_p45(x_l,y_l,z_l,visited) -- _floodFillSearch_local_p45 also uses grid:get
						if #nComp>0 then 
							table.insert(components,nComp)
							if CaveConfig.DebugMode and #components < 5 then 
								print(string.format("FAC_p45 DEBUG: Actual Component %d (size %d) started from (%d,%d,%d)",#components,#nComp,x_l,y_l,z_l))
							end 
						end
					end -- End if not visited
				elseif currentCellValue == SOLID then
					solidCellsFoundByIteration = solidCellsFoundByIteration + 1
				else
					nilCellsFoundByIteration = nilCellsFoundByIteration + 1
					if CaveConfig.DebugMode and nilCellsFoundByIteration < 5 then
						print(string.format("FAC_p45 DEBUG: Found NIL cell at (%d,%d,%d) during iteration!", x_l, y_l, z_l))
					end
				end -- End if currentCellValue check
			end -- End for x_l
		end -- End for y_l
		if CaveConfig.DebugMode and z_l % 20 == 0 then
			print(string.format("FAC_p45 DEBUG: Iterated up to z_l = %d. Current airCellsFoundByIteration = %d", z_l, airCellsFoundByIteration))
		end
	end -- End for z_l

	table.sort(components,function(a,b)return #a>#b end) 

	print(string.format("FAC_p45 DEBUG: Iteration finished. Total AIR cells encountered by loop: %d", airCellsFoundByIteration))
	print(string.format("FAC_p45 DEBUG: Iteration finished. Total SOLID cells encountered by loop: %d", solidCellsFoundByIteration))
	print(string.format("FAC_p45 DEBUG: Iteration finished. Total NIL cells encountered by loop: %d", nilCellsFoundByIteration))
	if firstAirCellCoords then
		print(string.format("FAC_p45 DEBUG: Coordinates of FIRST air cell found by iteration: (%d,%d,%d)", firstAirCellCoords.x, firstAirCellCoords.y, firstAirCellCoords.z))
	else
		print("FAC_p45 DEBUG: NO air cells were found by the iteration loop directly from 'grid:get'.")
	end
	print(string.format("FAC_p45 DEBUG: Found %d components total.", #components))

	return components
end -- End _findAirComponents_local_p45 (EXTREME DEBUG)

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
				end -- End if c1s and c2s
			end -- End for c2s
			doYield()
		end -- End for c1s

		if cA_b and cB_b then 
			_carveTunnel_local_p46(cA_b,cB_b,1.0)
			print(string.format("P4 INFO: Connected comp (orig idx %d). Dist: %.1f",tCompIdx,math.sqrt(cDistSq)))
			connsMade=connsMade+1
			if compB and mainC then 
				for _,bC_m in ipairs(compB) do if bC_m then table.insert(mainC,bC_m)end end 
			end -- End if compB and mainC (merge)
		else 
			print("P4 WARN: Failed to connect comp idx",tCompIdx)
		end -- End if cA_b and cB_b (carve)
	end -- End for tCompIdx
	if connsMade>0 then mainCaveCellIndices={} end 
	local eTime=os.clock()
	print("P4 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s. Connections: "..connsMade)
end -- End Phase4_EnsureConnectivity

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
			end -- End if cD_p5 valid
		end -- End for cD_p5
	end -- End if airCs_p5[1] exists

	if CaveConfig.DebugMode then local mcC_p5=0;for _ in pairs(mainCaveCellIndices)do mcC_p5=mcC_p5+1 end;print("P5 DEBUG: mainCaveCellIndices populated w/ "..mcC_p5.." cells.")end

	local cellsF_p5=0
	for i_p5f=2,#airCs_p5 do 
		if airCs_p5[i_p5f] then 
			for _,cDF_p5 in ipairs(airCs_p5[i_p5f]) do 
				if cDF_p5 then grid:set(cDF_p5.x,cDF_p5.y,cDF_p5.z,SOLID);cellsF_p5=cellsF_p5+1;doYield()end 
			end -- End for cDF_p5
		end -- End if airCs_p5[i_p5f] exists
	end -- End for i_p5f
	print(string.format("P5 INFO: Kept largest. Filled %d from %d smaller.",cellsF_p5,math.max(0,#airCs_p5-1)))
	local eTime=os.clock()
	print("P5 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s")
end -- End Phase5_FloodFillCleanup

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
								end -- End if FloodFillEnabled
							end -- End if isInBounds
						end -- End if in sphere
					end -- End for drz_p6e
				end -- End for dry_p6e
			end -- End for drx_p6e
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
							end -- End if connected
						end -- End for oz_p6e
						if conn_p6e then break end 
					end -- End for oy_p6e
					if conn_p6e then break end 
				end -- End for ox_p6e
			end -- End if current tunnel pos is main cave
			if conn_p6e then if CaveConfig.DebugMode then print("P6 DEBUG: Entrance",i_p6e,"connected.")end;break end 
		end -- End while tunnel
		if conn_p6e then entrMade_p6=entrMade_p6+1 
		elseif CaveConfig.DebugMode then print("P6 DEBUG: Entrance",i_p6e,"did not connect or reached max length/depth.")
		end -- End if conn_p6e for counting
	end -- End for i_p6e (each entrance)

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
				end -- End if cD_p6r valid
			end -- End for cD_p6r
			if CaveConfig.DebugMode then 
				local mcC_p6r=0; for _ in pairs(mainCaveCellIndices) do mcC_p6r=mcC_p6r+1 end
				print("P6 DEBUG: Main cave re-identified:",mcC_p6r,"(Largest comp:",#airCs_p6r[1],")")
			end -- End if DebugMode print
		elseif CaveConfig.DebugMode then print("P6 DEBUG: No air comps for re-eval post-entrances.")
		end -- End if/elseif airCs_p6r
	end -- End if entrances made and flood fill enabled
	local eTime=os.clock()
	print("P6 INFO: Finished! Time: "..string.format("%.2f",eTime-sTime).."s")
end -- End Phase6_SurfaceEntrances

local function _checkBridgeChamberCriteria_local(cx,cy,cz,length) 
	local minAirAbv=0
	for h=1,CaveConfig.BridgeChamberMinHeight_Cells do 
		local tY=cy+h
		if not grid:isInBounds(cx,tY,cz) then return false end
		local cIdx_bcc=grid:index(cx,tY,cz) 
		if not(grid:get(cx,tY,cz)==AIR and(not CaveConfig.FloodFillPhaseEnabled or(cIdx_bcc and mainCaveCellIndices[cIdx_bcc]))) then return false end
		minAirAbv=minAirAbv+1 
	end -- End for h
	if minAirAbv<CaveConfig.BridgeChamberMinHeight_Cells then return false end

	local airCC=0
	local mX,mZ=cx,cz
	local targetX_valid = grid:isInBounds(cx+length,cy,cz)
	local targetZ_valid = grid:isInBounds(cx,cy,cz+length)

	if targetX_valid and grid:get(cx+length,cy,cz)==AIR and grid:get(cx+length,cy-1,cz)==SOLID then mX=cx+length/2 
	elseif targetZ_valid and grid:get(cx,cy,cz+length)==AIR and grid:get(cx,cy-1,cz+length)==SOLID then mZ=cz+length/2 
	end -- End if/elseif target check

	local cRW=math.max(3,math.ceil(CaveConfig.BridgeChamberMinAirCells^(1/3)/2.0))
	local cRC=math.ceil(cRW)
	for dx_bcc_l=-cRC,cRC do 
		for dy_bcc_l=-cRC,cRC do 
			for dz_bcc_l=-cRC,cRC do 
				local curX,curY,curZ=math.floor(mX+dx_bcc_l),cy+dy_bcc_l,math.floor(mZ+dz_bcc_l)
				local ccci_bcc=grid:index(curX,curY,curZ)  
				if ccci_bcc and grid:get(curX,curY,curZ)==AIR and(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[ccci_bcc]) then airCC=airCC+1 end
			end -- End for dz_bcc_l
		end -- End for dy_bcc_l
	end -- End for dx_bcc_l
	return airCC>=CaveConfig.BridgeChamberMinAirCells
end -- End _checkBridgeChamberCriteria_local

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
				end -- End if isInBounds
			end -- End for widOff
		end -- End for mainAV
		doYield()
	end -- End for brY
	if CaveConfig.DebugMode then print("_buildBridge_local DEBUG: Bridge done. Approx cells SOLID:",cellsSet)end
end -- End _buildBridge_local

local function Phase7_Bridges() -- This is the function starting around line 571 (in previous full version errors)
	print("P7 INFO: Starting bridges...")
	local sTime_p7 = os.clock()
	local brBuilt_p7 = 0
	local bridgeCandidates_p7_list = {}
	local x_p7_iter, y_p7_iter, z_p7_iter -- Current iteration point

	for y_loop_main_p7 = gridSizeY - CaveConfig.BridgeChamberMinHeight_Cells - 2, CaveConfig.FormationStartHeight_Cells + CaveConfig.BridgeChamberMinHeight_Cells + 1, -1 do
		y_p7_iter = y_loop_main_p7
		for x_loop_main_p7 = 2, gridSizeX - 2 do
			x_p7_iter = x_loop_main_p7 -- Initialize for the start of Z loop
			for z_loop_main_p7 = 2, gridSizeZ - 2 do
				z_p7_iter = z_loop_main_p7 -- Initialize for this specific (x,z) attempt
				doYield()

				local cellIdx_p7_start = grid:index(x_p7_iter, y_p7_iter, z_p7_iter)
				local isValidStart_p7_check = cellIdx_p7_start and grid:get(x_p7_iter, y_p7_iter, z_p7_iter) == AIR and
					(not CaveConfig.FloodFillPhaseEnabled or mainCaveCellIndices[cellIdx_p7_start]) and
					(grid:get(x_p7_iter, y_p7_iter - 1, z_p7_iter) == SOLID)

				if isValidStart_p7_check then
					local current_x_for_scan = x_p7_iter -- Use this for X-scan, so original x_p7_iter for Z-scan is preserved

					-- Try X-direction bridges
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
								end -- End if gap not clear for X
							end -- End for gx_p7_scan
							if clearX_gap and _checkBridgeChamberCriteria_local(current_x_for_scan, y_p7_iter, z_p7_iter, lenX_p7_scan) then
								table.insert(bridgeCandidates_p7_list, { p1 = { x = current_x_for_scan, y = y_p7_iter, z = z_p7_iter }, p2 = { x = lookX_p7_target, y = y_p7_iter, z = z_p7_iter } })
								x_loop_main_p7 = lookX_p7_target -- CRITICAL: Advance the OUTER x loop iterator to skip
								break -- Found X-bridge, break from lenX_p7_scan loop, will also skip rest of z_loop for THIS OLD x_loop_main_p7
							end -- End if clearX_gap and criteria
						elseif grid:get(lookX_p7_target,y_p7_iter,z_p7_iter)==SOLID or grid:get(lookX_p7_target,y_p7_iter-1,z_p7_iter)==AIR then break end
					end -- End for lenX_p7_scan

					-- Try Z-direction bridges (uses original x_p7_iter from outer loop)
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
								end -- End if gap not clear for Z
							end -- End for gz_p7_scan
							if clearZ_gap and _checkBridgeChamberCriteria_local(x_p7_iter, y_p7_iter, current_z_for_scan, lenZ_p7_scan) then
								table.insert(bridgeCandidates_p7_list, { p1 = { x = x_p7_iter, y = y_p7_iter, z = current_z_for_scan }, p2 = { x = x_p7_iter, y = y_p7_iter, z = lookZ_p7_target } })
								z_loop_main_p7 = lookZ_p7_target -- CRITICAL: Advance the OUTER z loop iterator
								break -- Found Z-bridge
							end -- End if clearZ_p7 and criteria
						elseif grid:get(x_p7_iter,y_p7_iter,lookZ_p7_target)==SOLID or grid:get(x_p7_iter,y_p7_iter-1,lookZ_p7_target)==AIR then break end
					end -- End for lenZ_p7_scan
				end -- End if isValidStart_p7_check
			end -- End for z_loop_main_p7 
		end -- End for x_loop_main_p7
	end -- End for y_loop_main_p7

	localShuffleTable(bridgeCandidates_p7_list) -- Correct variable name
	local builtCoords_p7_val = {}
	local toBuildCount_p7_val = math.min(#bridgeCandidates_p7_list, 30 + math.floor(gridSizeX * gridSizeZ / 5000)) -- Correct
	local actualBridgesBuiltThisPhase_p7 = 0

	for i_p7_build_loop = 1, toBuildCount_p7_val do
		local cand_p7_val = bridgeCandidates_p7_list[i_p7_build_loop] -- Correct
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
	print(string.format("P7 INFO: Built %d bridges from %d candidates. Time: %.2fs", actualBridgesBuiltThisPhase_p7, #bridgeCandidates_p7_list, os.clock() - sTime_p7)) -- Correct variable for count
end -- End Phase7_Bridges

local function Phase8_BuildWorld()
	print("P8 INFO: Starting build world...");local sTime_p8=os.clock();local bSize_p8=Vector3.new(cellSize,cellSize,cellSize);local airBlks_p8,rockBlks_p8=0,0
	for z_p8=1,gridSizeZ do 
		for y_p8=1,gridSizeY do 
			for x_p8=1,gridSizeX do 
				local cellV_p8=grid:get(x_p8,y_p8,z_p8)
				local idx_p8=grid:index(x_p8,y_p8,z_p8)
				local mat_p8
				if CaveConfig.FloodFillPhaseEnabled and cellV_p8==AIR and not(idx_p8 and mainCaveCellIndices[idx_p8]) then 
					mat_p8=CaveConfig.RockMaterial
				elseif cellV_p8==SOLID then 
					mat_p8=CaveConfig.RockMaterial
					if CaveConfig.OreVeins.Enabled then 
						local wx_p8,wy_p8,wz_p8 = origin.X+(x_p8-.5)*cellSize,origin.Y+(y_p8-.5)*cellSize,origin.Z+(z_p8-.5)*cellSize
						for _,oreD_p8 in ipairs(CaveConfig.OreVeins.OreList) do 
							if oreD_p8.Rarity>0 then 
								local oreN_p8=localFractalNoise(wx_p8,wy_p8,wz_p8,oreD_p8.NoiseScale,oreD_p8.Octaves,oreD_p8.Persistence,oreD_p8.Lacunarity)
								if oreN_p8 > oreD_p8.Threshold and localRandomChance(oreD_p8.Rarity) then 
									mat_p8=oreD_p8.Material; break 
								end -- End if oreN_p8
							end -- End if Rarity > 0
						end -- End for oreD_p8
					end -- End if OreVeins.Enabled
				else 
					mat_p8=Enum.Material.Air 
				end -- End if/elseif/else material

				local cellMC_p8=cellToWorld(Vector3.new(x_p8,y_p8,z_p8),origin,cellSize)
				local blkCtr_p8=cellMC_p8+bSize_p8/2
				if CaveConfig.DebugMode and (x_p8==1 and y_p8==math.floor(gridSizeY/2) and z_p8%10==0) then 
					print(string.format("P8 DEBUG: Cell(%d,%d,%d),GridVal:%s,Fill:%s@%s",x_p8,y_p8,z_p8,tostring(cellV_p8),tostring(mat_p8),tostring(blkCtr_p8)))
				end -- End if DebugMode print
				Terrain:FillBlock(CFrame.new(blkCtr_p8),bSize_p8,mat_p8)
				if mat_p8==Enum.Material.Air then airBlks_p8=airBlks_p8+1 else rockBlks_p8=rockBlks_p8+1 end
				doYield()
			end -- End for x_p8
		end -- End for y_p8
		if CaveConfig.DebugMode or z_p8%math.max(1,math.floor(gridSizeZ/20))==0 then 
			print(string.format("P8 INFO: Fill %.1f%%(Z %d/%d)",(z_p8/gridSizeZ)*100,z_p8,gridSizeZ))
		end -- End if DebugMode print
	end -- End for z_p8
	print("P8 INFO: AirBlocks:"..airBlks_p8..", RockBlocks:"..rockBlks_p8)
	local eTime_p8=os.clock()
	print("P8 INFO: Finished! Time: "..string.format("%.2f",eTime_p8-sTime_p8).."s")
end -- End Phase8_BuildWorld

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
	end -- End if/else grid(1,1,1) check

	Phase1_InitialCaveFormation()
	if CaveConfig.DebugMode then
		local airP1, solidP1 = CountCellTypesInGrid(grid)
		print(string.format("--- DEBUG POST-P1: AIR cells = %d, SOLID cells = %d ---", airP1, solidP1))
	end

	if CaveConfig.FormationPhaseEnabled then Phase2_RockFormations() end
	if CaveConfig.DebugMode and CaveConfig.FormationPhaseEnabled then
		local airP2, solidP2 = CountCellTypesInGrid(grid)
		print(string.format("--- DEBUG POST-P2: AIR cells = %d, SOLID cells = %d ---", airP2, solidP2))
	end

	if CaveConfig.SmoothingPhaseEnabled then Phase3_Smoothing() end

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
				end -- End if errMsg is string
				errorInPhase=true; break 
			else 
				print("--- RunCaveGeneration: Finished "..phaseInfo.name.." ---")
			end -- End if not success
		else 
			print("--- RunCaveGeneration: Skipping "..phaseInfo.name.." ---")
		end -- End if phaseInfo.enabled
	end -- End for phasesToRun

	local overallEndTime=os.clock()
	print("-----------------------------------------------------")
	if errorInPhase then print("CAVE GEN HALTED DUE TO ERROR.")else print("ALL ENABLED PHASES CALLED.")end
	print("Total script exec time: "..string.format("%.2f",overallEndTime-overallStartTime).."s");print("-----------------------------------------------------")
end -- End RunCaveGeneration

task.wait(3); print("--- CaveGenerator Script: Calling RunCaveGeneration ---")
RunCaveGeneration(); print("--- CaveGenerator Script: Execution flow ended. ---")