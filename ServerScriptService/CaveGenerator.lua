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

local function _ensureNumber(value, defaultValue, fieldNameForWarning)
	if type(value) == "number" then
		return value
	else
		Logger:Warn("ConfigValidation", "Expected number for '%s', got %s. Using default: %s", 
			tostring(fieldNameForWarning), typeof(value), tostring(defaultValue))
		return defaultValue
	end
end

local function cellToWorld(cellPos, currentOrigin, currentCellSize)
	return Vector3.new(
		currentOrigin.X + (cellPos.X - 1) * currentCellSize,
		currentOrigin.Y + (cellPos.Y - 1) * currentCellSize,
		currentOrigin.Z + (cellPos.Z - 1) * currentCellSize
	)
end -- End cellToWorld

local function localRandomFloat(min,max) return min + Rng:NextNumber() * (max - min) end
local function localRandomInt(min,max) return Rng:NextInteger(min, max) end
local function rotateVectorAroundAxis(vecToRotate, axis, angleRadians)
	local rotationCFrame = CFrame.fromAxisAngle(axis.Unit, angleRadians)
	return (rotationCFrame * vecToRotate)
end

local function _getSurfaceCellsInfo(targetGrid, targetMaterial, adjacentMaterial)
	Logger:Debug("Util_Surface", "Starting surface cell identification (Target: %s, Adjacent: %s)", tostring(targetMaterial), tostring(adjacentMaterial))
	local startTime = os.clock()
	local surfaceCells = {}
	local cellsProcessed = 0
	local surfaceCellsFound = 0
	local yieldThreshold_surface = CaveConfig.SurfaceScanYieldBatchSize or 10000 -- Make it configurable, default to 10k

	-- Define neighbors to check for a surface. Dirs point from current cell to neighbor.
	local neighborDirs = {
		{d={0,1,0}, type="Ceiling"},   -- Current cell is SOLID, neighbor ABOVE is AIR -> current cell is part of a CEILING
		{d={0,-1,0}, type="Floor"},    -- Current cell is SOLID, neighbor BELOW is AIR -> current cell is part of a FLOOR
		{d={1,0,0}, type="WallPX"},    -- Current cell is SOLID, neighbor POS_X is AIR -> current cell is part of a WALL (PX face)
		{d={-1,0,0}, type="WallNX"},   -- Current cell is SOLID, neighbor NEG_X is AIR -> current cell is part of a WALL (NX face)
		{d={0,0,1}, type="WallPZ"},    -- Current cell is SOLID, neighbor POS_Z is AIR -> current cell is part of a WALL (PZ face)
		{d={0,0,-1}, type="WallNZ"}    -- Current cell is SOLID, neighbor NEG_Z is AIR -> current cell is part of a WALL (NZ face)
	}

	for z = 1, targetGrid.size.Z do
		for y = 1, targetGrid.size.Y do
			for x = 1, targetGrid.size.X do
				cellsProcessed = cellsProcessed + 1
				if targetGrid:get(x,y,z) == targetMaterial then
					for _, check in ipairs(neighborDirs) do
						local nx, ny, nz = x + check.d[1], y + check.d[2], z + check.d[3]
						if targetGrid:isInBounds(nx,ny,nz) and targetGrid:get(nx,ny,nz) == adjacentMaterial then
							-- This (x,y,z) cell IS a surface cell of targetMaterial,
							-- with its 'check.type' face exposed to adjacentMaterial.
							-- The normal points from (x,y,z) towards (nx,ny,nz).
							table.insert(surfaceCells, {
								pos = Vector3.new(x,y,z),
								normal = Vector3.new(check.d[1], check.d[2], check.d[3]), -- Points from SOLID into AIR
								surfaceType = check.type
							})
							surfaceCellsFound = surfaceCellsFound + 1
							-- A single cell can be part of multiple surfaces (e.g. a corner)
							-- So we don't 'break' here, we add for each exposed face.
						end
					end
				end
				if cellsProcessed % yieldThreshold_surface == 0 then 
					RunService.Heartbeat:Wait() 
					-- If you want to see yields, uncomment this:
					-- Logger:Trace("Util_Surface", "Yielding during surface scan. Cells Processed: %d", cellsProcessed)
				end
			end
		end
		-- Optional: Yield per Z-slice too if grid is very large in XY
		-- RunService.Heartbeat:Wait() 
		-- Logger:Trace("Util_Surface", "Finished Z-slice %d for surface scan.", z)
	end
	Logger:Info("Util_Surface", "Surface cell identification finished. Cells processed: %d. Surface points found: %d. Time: %.2fs",
		cellsProcessed, surfaceCellsFound, os.clock() - startTime)
	return surfaceCells
end

local function _carveSphereGrid(targetGrid, cX, cY, cZ, radiusCells, materialToSet)
	-- Ensure cX, cY, cZ are integers for grid coordinates
	cX = math.round(cX)
	cY = math.round(cY)
	cZ = math.round(cZ)
	radiusCells = math.max(0, math.floor(radiusCells))
	local cellsChanged = 0

	for dz_s = -radiusCells, radiusCells do
		for dy_s = -radiusCells, radiusCells do
			for dx_s = -radiusCells, radiusCells do
				if dx_s*dx_s + dy_s*dy_s + dz_s*dz_s <= radiusCells*radiusCells + 0.1 then -- Small epsilon for edge cases
					local nx, ny, nz = cX + dx_s, cY + dy_s, cZ + dz_s
					if targetGrid:isInBounds(nx, ny, nz) then
						if targetGrid:get(nx, ny, nz) ~= materialToSet then
							cellsChanged = cellsChanged + 1
						end
						targetGrid:set(nx, ny, nz, materialToSet)
					end
				end
			end
		end
	end
	if cellsChanged > 0 or radiusCells > 0 then -- Log even if no cells changed but we tried to carve
		Logger:Trace("CarveUtil_Sphere", "Attempted sphere carve at (%d,%d,%d) r:%d. Cells set to %s: %d", cX,cY,cZ,radiusCells,tostring(materialToSet), cellsChanged)
	end
	return cellsChanged
end

local function _getOrDefault(configTable, fieldName, defaultValue, expectedTypeArg)
	local expectedType = expectedTypeArg or typeof(defaultValue) 
	if configTable and fieldName and configTable[fieldName] ~= nil then
		if typeof(configTable[fieldName]) == expectedType then
			return configTable[fieldName]
		else
			Logger:Warn("ConfigAccess", "Field '%s': Expected type %s, got %s. Using default value: %s", 
				tostring(fieldName), expectedType, typeof(configTable[fieldName]), tostring(defaultValue))
			return defaultValue
		end
	else
		return defaultValue
	end
end

local function _getMinMaxOrDefault(configTable, fieldName, defaultMin, defaultMax)
	local minVal, maxVal = defaultMin, defaultMax
	if configTable and fieldName and typeof(configTable[fieldName]) == "table" then
		local field = configTable[fieldName]
		if typeof(field.min) == "number" then minVal = field.min 
		else Logger:Warn("ConfigAccess", "Field '%s.min' missing/not number. Using default: %s", tostring(fieldName), tostring(defaultMin)) end
		if typeof(field.max) == "number" then maxVal = field.max
		else Logger:Warn("ConfigAccess", "Field '%s.max' missing/not number. Using default: %s", tostring(fieldName), tostring(defaultMax)) end
		if typeof(minVal) == "number" and typeof(maxVal) == "number" and minVal > maxVal then
			Logger:Warn("ConfigAccess", "Field '%s': min (%s) > max (%s). Swapping.",fieldName,tostring(minVal),tostring(maxVal))
			minVal, maxVal = maxVal, minVal 
		end
	else
		if configTable and fieldName and typeof(configTable[fieldName])~="table" then Logger:Warn("ConfigAccess", "Field '%s' not table for MinMax. Using defaults.", fieldName)
		else Logger:Trace("ConfigAccess", "Field '%s' (for MinMax) missing. Using defaults.", fieldName) end
	end
	if typeof(minVal) ~= "number" then minVal = 0 end
	if typeof(maxVal) ~= "number" then maxVal = minVal + 1 end
	return minVal, maxVal
end

local function _generateWindingPath(startPosGrid, initialDirVec3, numSegments, segmentLengthCells, maxTurnAngleDegrees, overallLengthStuds)
	local pathPoints = {startPosGrid}
	local currentPos = Vector3.new(startPosGrid.X, startPosGrid.Y, startPosGrid.Z) 
	local currentDir = initialDirVec3.Unit
	local totalPathLengthCells = 0
	local targetTotalLengthCells = overallLengthStuds / cellSize 

	local upVector = Vector3.new(0, 1, 0)
	if math.abs(currentDir:Dot(upVector)) > 0.9 then 
		upVector = Vector3.new(1, 0, 0) 
	end

	for i = 1, numSegments do
		if totalPathLengthCells >= targetTotalLengthCells then
			break
		end

		local turnAngleRad = math.rad(localRandomFloat(-maxTurnAngleDegrees, maxTurnAngleDegrees))
		local randomRotationAxis = currentDir:Cross(Vector3.new(localRandomFloat(-1,1),localRandomFloat(-1,1),localRandomFloat(-1,1))).Unit
		if randomRotationAxis.Magnitude < 0.1 then 
			randomRotationAxis = currentDir:Cross(upVector).Unit
			if randomRotationAxis.Magnitude < 0.1 then 
				randomRotationAxis = Vector3.new(0,0,1):Cross(currentDir).Unit
				if randomRotationAxis.Magnitude < 0.1 then  randomRotationAxis = Vector3.new(0,1,0) end 
			end
		end

		currentDir = rotateVectorAroundAxis(currentDir, randomRotationAxis, turnAngleRad) -- ASSUMES rotateVectorAroundAxis IS DEFINED AND ACCESSIBLE
		currentDir = currentDir.Unit 

		local nextPos = currentPos + currentDir * segmentLengthCells
		table.insert(pathPoints, nextPos)
		currentPos = nextPos
		totalPathLengthCells = totalPathLengthCells + segmentLengthCells

		doYield() 
	end
	return pathPoints
end

local function _generateWindingPath_Perlin(
	startPosGridVec3, initialDirVec3, 
	numSegmentsToTry, segmentLengthCells, 
	overallTargetLengthStuds, 
	maxTurnAngleDeg, 
	yawNoiseScale, yawStrengthFactor, 
	pitchNoiseScale, pitchStrengthFactor, 
	uniqueNoiseSeedOffset -- A unique number for this specific path
)

	local pathPoints = {Vector3.new(startPosGridVec3.X, startPosGridVec3.Y, startPosGridVec3.Z)}
	local currentPos = pathPoints[1]
	local currentDir = initialDirVec3.Unit
	local targetTotalLengthCells = overallTargetLengthStuds / cellSize -- cellSize needs to be accessible
	local actualPathLengthCells = 0

	local worldUp = Vector3.new(0, 1, 0)
	if math.abs(currentDir:Dot(worldUp)) > 0.98 then
		worldUp = Vector3.new(1, 0, 0) 
	end

	for i = 1, numSegmentsToTry do
		if actualPathLengthCells >= targetTotalLengthCells and overallTargetLengthStuds > 0 then -- Check if overallTargetLengthStuds > 0
			-- Logger:Trace("_generateWindingPath_Perlin", "Path ID %.2f: Target length reached.", uniqueNoiseSeedOffset)
			break
		end

		local localRight = currentDir:Cross(worldUp).Unit
		-- If currentDir and worldUp are parallel (e.g. straight up/down), localRight will be zero.
		if localRight.Magnitude < 0.1 then 
			-- Try a different 'worldUp' for this segment if gimbal lock occurs
			local tempWorldRight = Vector3.new(1,0,0)
			if math.abs(currentDir:Dot(tempWorldRight)) > 0.98 then tempWorldRight = Vector3.new(0,0,1) end
			localRight = currentDir:Cross(tempWorldRight).Unit
		end
		local localUp = localRight:Cross(currentDir).Unit

		local yawNoiseInput = actualPathLengthCells * yawNoiseScale + uniqueNoiseSeedOffset
		local pitchNoiseInput = actualPathLengthCells * pitchNoiseScale + uniqueNoiseSeedOffset + 50.0 -- Offset to decorrelate

		local yawNoiseValue = (Perlin.Noise(yawNoiseInput, uniqueNoiseSeedOffset + 10.1, uniqueNoiseSeedOffset + 20.2) * 2) - 1
		local pitchNoiseValue = (Perlin.Noise(uniqueNoiseSeedOffset + 30.3, pitchNoiseInput, uniqueNoiseSeedOffset + 40.4) * 2) - 1

		local yawTurnAngle = yawNoiseValue * math.rad(maxTurnAngleDeg * yawStrengthFactor)
		local pitchTurnAngle = pitchNoiseValue * math.rad(maxTurnAngleDeg * pitchStrengthFactor)

		local tempDir = currentDir
		tempDir = rotateVectorAroundAxis(tempDir, localUp, yawTurnAngle)
		tempDir = rotateVectorAroundAxis(tempDir, localRight, pitchTurnAngle)

		currentDir = tempDir.Unit

		local nextPos = currentPos + currentDir * segmentLengthCells
		table.insert(pathPoints, nextPos)
		currentPos = nextPos
		actualPathLengthCells = actualPathLengthCells + segmentLengthCells

		doYield() 
	end

	-- Logger:Trace("_generateWindingPath_Perlin", "Path generated. ID %.2f. Points: %d, TargetSegs: %d, ActualLengthCells: %.1f",
	--    uniqueNoiseSeedOffset, #pathPoints, numSegmentsToTry, actualPathLengthCells)

	return pathPoints
end

local function _generateWindingPath_PerlinAdvanced(
	startPosGridVec3, initialDirVec3, 
	numSegmentsToTry, baseSegmentLengthCells, overallTargetLengthStuds, 
	baseMaxTurnDeg, 
	yawNoiseScale, baseYawStrengthFactor, 
	pitchNoiseScale, basePitchStrengthFactor, 
	pathNoiseSeedOffset, 
	pathParamsConfig -- This will be e.g., Config.PathGeneration.Trunk, .Branch, etc.
)

	local pathPointsData = {{pos = Vector3.new(startPosGridVec3.X, startPosGridVec3.Y, startPosGridVec3.Z), radiusCells = 0}} 
	local currentPos = pathPointsData[1].pos
	local currentDir = initialDirVec3.Unit
	local targetTotalLengthCells = overallTargetLengthStuds / cellSize
	local actualPathLengthCells = 0

	local worldUp = Vector3.new(0, 1, 0)
	if math.abs(currentDir:Dot(worldUp)) > 0.98 then
		worldUp = Vector3.new(1, 0, 0) 
	end

	local obstacleCfg = CaveConfig.PathGeneration.ObstacleAvoidance or {} 
	local enableObstacleAvoidance = false -- Keep this true to use the avoidance logic

	-- Helper for more intelligent steering
	local function _getBestSteerDirection(current_Pos_steer, proposed_Dir_steer, originalPerlinProposed_Dir_steer, lookAheadDistInCells_steer, segmentLen_steer, seedOffset_steer, localUp_steer, localRight_steer)
		local steerAngleRad_steer = math.rad(obstacleCfg.SteerAngleDeg or 45) -- Use tuned value

		local probeConfigs = {
			{vector = originalPerlinProposed_Dir_steer, bias = 0.00, debugName = "OriginalPerlin"},
			{vector = rotateVectorAroundAxis(originalPerlinProposed_Dir_steer, localUp_steer, steerAngleRad_steer * 0.5), bias = 0.05, debugName = "GentleYawR"}, -- Softer initial steers
			{vector = rotateVectorAroundAxis(originalPerlinProposed_Dir_steer, localUp_steer, -steerAngleRad_steer * 0.5), bias = 0.05, debugName = "GentleYawL"},
			{vector = rotateVectorAroundAxis(originalPerlinProposed_Dir_steer, localRight_steer, steerAngleRad_steer * 0.3), bias = 0.07, debugName = "GentlePitchU"},
			{vector = rotateVectorAroundAxis(originalPerlinProposed_Dir_steer, localRight_steer, -steerAngleRad_steer * 0.3), bias = 0.07, debugName = "GentlePitchD"},

			{vector = rotateVectorAroundAxis(proposed_Dir_steer, localUp_steer, steerAngleRad_steer), bias = 0.2, debugName = "StdYawR"},
			{vector = rotateVectorAroundAxis(proposed_Dir_steer, localUp_steer, -steerAngleRad_steer), bias = 0.2, debugName = "StdYawL"},
			{vector = rotateVectorAroundAxis(proposed_Dir_steer, localRight_steer, steerAngleRad_steer * 0.7), bias = 0.25, debugName = "StdPitchU"},
			{vector = rotateVectorAroundAxis(proposed_Dir_steer, localRight_steer, -steerAngleRad_steer * 0.7), bias = 0.25, debugName = "StdPitchD"},

			{vector = rotateVectorAroundAxis(proposed_Dir_steer, localUp_steer, steerAngleRad_steer * 2.0), bias = 0.5, debugName = "HardYawR"}, 
			{vector = rotateVectorAroundAxis(proposed_Dir_steer, localUp_steer, -steerAngleRad_steer * 2.0), bias = 0.5, debugName = "HardYawL"},
			{vector = localUp_steer, bias = 0.7, debugName = "TryUpLocalAbs"}, -- More drastic escapes
			{vector = -localUp_steer, bias = 0.7, debugName = "TryDownLocalAbs"},
		}

		local bestDir_steer = nil
		local minScore_steer = math.huge
		local chosenDebugName = "None"

		for _, probeData in ipairs(probeConfigs) do
			local testDir = probeData.vector.Unit
			-- lookAheadDistInCells_steer IS ALREADY the calculated distance in cells
			local lookAheadP = current_Pos_steer + testDir * lookAheadDistInCells_steer 
			local lX, lY, lZ = math.round(lookAheadP.X), math.round(lookAheadP.Y), math.round(lookAheadP.Z)

			local score = 0
			if not grid:isInBounds(lX, lY, lZ) then
				score = 100 
			elseif grid:get(lX, lY, lZ) == SOLID then
				score = 10  
			end

			score = score + probeData.bias 
			score = score + Rng:NextNumber() * 0.01 

			if score < minScore_steer then
				minScore_steer = score
				bestDir_steer = testDir
				chosenDebugName = probeData.debugName
			end
		end

		if bestDir_steer and minScore_steer < 9.9 then -- Found a direction that isn't definitely SOLID or heavily OOB (allow slightly into solid for tie-breaking)
			Logger:Trace("_generatePathAdv_SteerChoice", "Path ID %.1f: Chose steer dir %s (type: %s, score %.2f)", seedOffset_steer, tostring(bestDir_steer), chosenDebugName, minScore_steer)
			return bestDir_steer
		else
			Logger:Warn("_generatePathAdv_SteerChoice", "Path ID %.1f: No sufficiently clear steer direction found (best score %.2f was for %s). Original Perlin-proposed: %s", seedOffset_steer, minScore_steer, chosenDebugName, tostring(originalPerlinProposed_Dir_steer))
			return nil 
		end
	end

	local wasInitialClearanceCarved = (pathParamsConfig and pathParamsConfig.CarveInitialClearanceAtStart and (pathParamsConfig.InitialClearanceRadiusCells or 0) > 0)
	local initialClearanceRadiusValue = (pathParamsConfig and pathParamsConfig.InitialClearanceRadiusCells or 0)

	for i = 1, numSegmentsToTry do
		if actualPathLengthCells >= targetTotalLengthCells and overallTargetLengthStuds > 0 then
			break
		end

		local localRight = currentDir:Cross(worldUp).Unit
		if localRight.Magnitude < 0.1 then 
			local altWorldUp = Vector3.new(1,0,0)
			if math.abs(currentDir:Dot(altWorldUp)) > 0.98 then altWorldUp = Vector3.new(0,0,1) end
			localRight = currentDir:Cross(altWorldUp).Unit
			if localRight.Magnitude < 0.1 then 
				localRight = Vector3.new(-currentDir.Y, currentDir.X, 0).Unit -- Another failsafe if Z is dominant
				if localRight.Magnitude < 0.1 then localRight = Vector3.new(0, -currentDir.Z, currentDir.Y).Unit end
				if localRight.Magnitude < 0.1 then localRight = Vector3.new(1,0,0) end -- Absolute fallback
			end
		end
		local localUp = localRight:Cross(currentDir).Unit

		local modulationInput = actualPathLengthCells * (pathParamsConfig.TurnTendencyNoiseScale or 0.05) + pathNoiseSeedOffset
		local turnTendencyNoise = (Perlin.Noise(modulationInput, pathNoiseSeedOffset + 100, pathNoiseSeedOffset + 110) * 2) - 1
		local currentMaxTurnDeg = baseMaxTurnDeg * (1 + turnTendencyNoise * (pathParamsConfig.TurnTendencyVariance or 0.3))
		currentMaxTurnDeg = math.max(5, currentMaxTurnDeg) 

		local currentYawStrength = baseYawStrengthFactor 
		local currentPitchStrength = basePitchStrengthFactor 

		local yawNoiseInput = actualPathLengthCells * yawNoiseScale + pathNoiseSeedOffset
		local pitchNoiseInput = actualPathLengthCells * pitchNoiseScale + pathNoiseSeedOffset + 50.0
		local yawNoiseValue = (Perlin.Noise(yawNoiseInput, pathNoiseSeedOffset + 10.1, pathNoiseSeedOffset + 20.2) * 2) - 1
		local pitchNoiseValue = (Perlin.Noise(pathNoiseSeedOffset + 30.3, pitchNoiseInput, pathNoiseSeedOffset + 40.4) * 2) - 1
		local yawTurnAngle = yawNoiseValue * math.rad(currentMaxTurnDeg * currentYawStrength)
		local pitchTurnAngle = pitchNoiseValue * math.rad(currentMaxTurnDeg * currentPitchStrength)

		local perlinProposedDir = currentDir
		perlinProposedDir = rotateVectorAroundAxis(perlinProposedDir, localUp, yawTurnAngle)
		perlinProposedDir = rotateVectorAroundAxis(perlinProposedDir, localRight, pitchTurnAngle)
		perlinProposedDir = perlinProposedDir.Unit

		local finalDirForSegment = perlinProposedDir

		if enableObstacleAvoidance then
			local lookAheadDistInCells = (obstacleCfg.LookAheadDistanceCells or 1) * baseSegmentLengthCells
			lookAheadDistInCells = math.max(1, lookAheadDistInCells) 

			for attempt = 0, (obstacleCfg.MaxSteerAttempts or 3) do 
				local dirToTest = (attempt == 0) and perlinProposedDir or finalDirForSegment 

				local lookAheadPos = currentPos + dirToTest * lookAheadDistInCells
				local lX, lY, lZ = math.round(lookAheadPos.X), math.round(lookAheadPos.Y), math.round(lookAheadPos.Z)

				local isObstructed = false
				if not grid:isInBounds(lX, lY, lZ) then
					isObstructed = true
					if attempt == 0 then Logger:Trace("_generatePathAdv_Obstacle", "Path ID %.1f (Seg %d): Perlin dir %s leads OOB at %s", pathNoiseSeedOffset, i, tostring(dirToTest),tostring(Vector3.new(lX,lY,lZ))) end
				elseif grid:get(lX, lY, lZ) == SOLID then
					local N_FORGIVING_SEGMENTS_TRUNK = 3 -- How many segments get this special treatment FOR TRUNK-LIKE (those with clearance)
					local FORGIVING_RADIUS_EXPANSION_TRUNK = baseSegmentLengthCells 
					local isWithinForgivingPocket = false

					if wasInitialClearanceCarved and initialClearanceRadiusValue > 0 and i <= N_FORGIVING_SEGMENTS_TRUNK then
						if (Vector3.new(lX,lY,lZ) - startPosGridVec3).Magnitude <= (initialClearanceRadiusValue + FORGIVING_RADIUS_EXPANSION_TRUNK) then
							isWithinForgivingPocket = true
						end
					end

					if not isWithinForgivingPocket then
						isObstructed = true
						local reason = "SOLID"
						if wasInitialClearanceCarved and i <=N_FORGIVING_SEGMENTS_TRUNK then reason = "SOLID (outside forgiving pocket)" end
						if attempt == 0 then  Logger:Trace("_generatePathAdv_Obstacle", "Path ID %.1f (Seg %d): Perlin dir %s hits %s at %s", pathNoiseSeedOffset, i, tostring(dirToTest), reason,tostring(Vector3.new(lX,lY,lZ))) end
					else
						Logger:Trace("_generatePathAdv_Obstacle", "Path ID %.1f (Seg %d): Perlin dir %s hits SOLID at %s but within forgiving pocket. Allowed.", pathNoiseSeedOffset, i, tostring(dirToTest),tostring(Vector3.new(lX,lY,lZ)))
					end
				end

				if not isObstructed then
					finalDirForSegment = dirToTest 
					if attempt > 0 then Logger:Debug("_generatePathAdv_Obstacle", "Path ID %.1f (Seg %d): Steer attempt %d successful with dir %s.", pathNoiseSeedOffset,i, attempt, tostring(finalDirForSegment)) end
					break 
				end

				if attempt < (obstacleCfg.MaxSteerAttempts or 3) then
					Logger:Debug("_generatePathAdv_Obstacle", "Path ID %.1f (Seg %d): Obstacle for dir %s. Advanced steer attempt #%d.", pathNoiseSeedOffset, i, tostring(dirToTest), attempt + 1)
					local steeredDir = _getBestSteerDirection(currentPos, dirToTest, perlinProposedDir, lookAheadDistInCells, baseSegmentLengthCells, pathNoiseSeedOffset, localUp, localRight)
					if steeredDir then
						finalDirForSegment = steeredDir
					else
						Logger:Warn("_generatePathAdv", "Path ID %.1f (Seg %d): Advanced steer could not find any clear alternative. Terminating path.", pathNoiseSeedOffset, i)
						finalDirForSegment = nil 
						break 
					end
				else
					Logger:Warn("_generatePathAdv", "Path ID %.1f (Seg %d): Max steer attempts (%d) reached. Terminating path.", pathNoiseSeedOffset, i, (obstacleCfg.MaxSteerAttempts or 3))
					finalDirForSegment = nil 
					break 
				end
			end 

			if not finalDirForSegment then 
				if #pathPointsData > 1 then table.remove(pathPointsData) end 
				Logger:Warn("_generatePathAdv", "Path ID %.1f terminated after %d segments due to obstacle avoidance failure.", pathNoiseSeedOffset, i-1)
				return pathPointsData 
			end
		end 

		currentDir = finalDirForSegment.Unit

		local nextPos = currentPos + currentDir * baseSegmentLengthCells

		table.insert(pathPointsData, {pos = nextPos, radiusCells = 0}) 
		currentPos = nextPos
		actualPathLengthCells = actualPathLengthCells + baseSegmentLengthCells

		doYield() 
	end

	Logger:Info("_generatePathAdv", "Advanced path generated. ID: %.1f. Points: %d / TargetSegs: %d. ActualLengthCells: %.1f / Target: %.1f",
		pathNoiseSeedOffset, #pathPointsData, numSegmentsToTry, actualPathLengthCells, targetTotalLengthCells)

	local justPositions = {}
	for _, data_item in ipairs(pathPointsData) do 
		table.insert(justPositions, data_item.pos)
	end
	return justPositions
end

-- Add this lerp function if not already present and accessible in your utilities
local function lerp(a,b,t) return a+t*(b-a) end

local function _carveCylinderGrid(targetGrid, p1, p2, radiusCells, materialToSet)
	-- p1, p2 are Vector3 of grid coordinates {x,y,z}
	radiusCells = math.max(0, math.floor(radiusCells))
	local cellsChangedTotal = 0

	local direction = (p2 - p1)
	local length = direction.Magnitude
	if length < 0.5 then -- If very short, just carve a sphere at p1
		-- Logger:Trace("CarveUtil", "Cylinder too short, carving sphere at p1 for (%s) r:%d", tostring(p1), radiusCells)
		return _carveSphereGrid(targetGrid, p1.X, p1.Y, p1.Z, radiusCells, materialToSet)
	end

	local unitDirection = direction.Unit
	local R_sq = radiusCells * radiusCells

	-- Iterate along the line segment from p1 to p2
	-- We can do this by stepping along the main axis of the direction vector
	-- or by iterating a bounding box and checking distance to the line segment.
	-- For simplicity and to match "overlapping strokes" let's use spheres along the line.
	-- Step size should be small enough to ensure good overlap, e.g., radiusCells / 2 or 1.
	local stepSize = math.max(1, radiusCells / 2) -- Or even just 1 for dense fill
	local numSteps = math.ceil(length / stepSize)

	Logger:Trace("CarveUtil_Cylinder", "Cylinder p1(%s) p2(%s) r:%d. Length:%.2f, UnitDir:%s, StepSize:%.1f, NumSteps:%d",
		tostring(p1), tostring(p2), radiusCells, length, tostring(unitDirection), stepSize, numSteps)

	for i = 0, numSteps do
		local t = i / math.max(1, numSteps) -- Normalized distance along segment
		local currentCenterPoint = p1 + unitDirection * (t * length)
		Logger:Trace("CarveUtil_Cylinder", "Segment %d/%d at (%.1f,%.1f,%.1f) with radius %d",
			i, numSteps, currentCenterPoint.X, currentCenterPoint.Y, currentCenterPoint.Z, radiusCells)
		cellsChangedTotal = cellsChangedTotal + _carveSphereGrid(targetGrid,
			math.round(currentCenterPoint.X),
			math.round(currentCenterPoint.Y),
			math.round(currentCenterPoint.Z),
			radiusCells,
			materialToSet
		)
		doYield() -- Yield within long carving operations
	end
	Logger:Info("CarveUtil_Cylinder", "Finished cylinder. Approx spheres: %d. Total cells changed (sum of sphere changes): %d", numSteps + 1, cellsChangedTotal)
	return cellsChangedTotal
end

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

local function Phase_CarveSkeleton()
	Logger:Info("Phase_CarveSkeleton", "Starting Skeleton Generation (Trunk, Branches, Spurs)...")
	local startTime = os.clock()

	local skeletonData = { trunkPath = {}, branchPaths = {}, spurPaths = {} } 
	local collectedBranchPaths, collectedSpurPaths = {}, {}
	local validBranchStartIndex, validBranchEndIndex
	local primaryBranchStartIndices_USED = {}
	local branchesMade, spursMade = 0, 0
	local initialTrunkDirection = Vector3.new(1,0,0) 

	-- ==== TRUNK GENERATION ====
	Logger:Debug("Phase_CarveSkeleton", "Setting up TRUNK parameters...")
	local pathGenCfg_Trunk_raw = (CaveConfig.PathGeneration and CaveConfig.PathGeneration.Trunk) or {} -- USED _raw
	local skelCfg_Trunk_raw = CaveConfig.Skeleton_Trunk or {} -- USED _raw

	local TP = { -- TP for Trunk Parameters - DEFINE DEFAULTS
		StartRadiusStuds = 10, EndRadiusStuds = 14, RadiusVarianceFactor = 0.15, TargetLengthStuds = 200,
		StartX_Range = {0.15, 0.25}, StartY_Range = {0.45, 0.55}, StartZ_Range = {0.15, 0.25},
		Count_MinMax = {min = 4, max = 6},
		SegmentBaseLengthStuds = 12, PathPerlin_MaxTurnDeg = 20, PathPerlin_YawNoiseScale = 0.015,
		PathPerlin_YawStrengthFactor = 0.9, PathPerlin_PitchNoiseScale = 0.02, PathPerlin_PitchStrengthFactor = 0.3,
		RadiusVarianceNoiseScale = 0.03, TurnTendencyNoiseScale = 0.02, TurnTendencyVariance = 0.2,
		CarveInitialClearanceAtStart = true, InitialClearanceRadiusCells = 5
	}
	-- Overwrite TP with values from skelCfg_Trunk_raw if they exist and are valid
	TP.StartRadiusStuds = _ensureNumber(skelCfg_Trunk_raw.StartRadiusStuds, TP.StartRadiusStuds, "skelCfg_Trunk_raw.StartRadiusStuds")
	TP.EndRadiusStuds = _ensureNumber(skelCfg_Trunk_raw.EndRadiusStuds, TP.EndRadiusStuds, "skelCfg_Trunk_raw.EndRadiusStuds")
	TP.RadiusVarianceFactor = _ensureNumber(skelCfg_Trunk_raw.RadiusVarianceFactor, TP.RadiusVarianceFactor, "skelCfg_Trunk_raw.RadiusVarianceFactor")
	TP.TargetLengthStuds = _ensureNumber(skelCfg_Trunk_raw.TargetLengthStuds, TP.TargetLengthStuds, "skelCfg_Trunk_raw.TargetLengthStuds")
	if typeof(skelCfg_Trunk_raw.StartX_Range) == "table" and #skelCfg_Trunk_raw.StartX_Range == 2 and typeof(skelCfg_Trunk_raw.StartX_Range[1])=="number" and typeof(skelCfg_Trunk_raw.StartX_Range[2])=="number" then TP.StartX_Range = skelCfg_Trunk_raw.StartX_Range else Logger:Warn("CFG: Trunk.StartX_Range invalid, using defaults.") end
	if typeof(skelCfg_Trunk_raw.StartY_Range) == "table" and #skelCfg_Trunk_raw.StartY_Range == 2 and typeof(skelCfg_Trunk_raw.StartY_Range[1])=="number" and typeof(skelCfg_Trunk_raw.StartY_Range[2])=="number" then TP.StartY_Range = skelCfg_Trunk_raw.StartY_Range else Logger:Warn("CFG: Trunk.StartY_Range invalid, using defaults.") end
	if typeof(skelCfg_Trunk_raw.StartZ_Range) == "table" and #skelCfg_Trunk_raw.StartZ_Range == 2 and typeof(skelCfg_Trunk_raw.StartZ_Range[1])=="number" and typeof(skelCfg_Trunk_raw.StartZ_Range[2])=="number" then TP.StartZ_Range = skelCfg_Trunk_raw.StartZ_Range else Logger:Warn("CFG: Trunk.StartZ_Range invalid, using defaults.") end
	TP.Count_MinMax.min, TP.Count_MinMax.max = _getMinMaxOrDefault(skelCfg_Trunk_raw, "Count_MinMax", TP.Count_MinMax.min, TP.Count_MinMax.max)

	TP.SegmentBaseLengthStuds = _ensureNumber(pathGenCfg_Trunk_raw.SegmentBaseLengthStuds, TP.SegmentBaseLengthStuds, "PathGen.Trunk.SegmentBaseLengthStuds")
	TP.PathPerlin_MaxTurnDeg = _ensureNumber(pathGenCfg_Trunk_raw.PathPerlin_MaxTurnDeg, TP.PathPerlin_MaxTurnDeg, "PathGen.Trunk.PathPerlin_MaxTurnDeg")
	TP.PathPerlin_YawNoiseScale = _ensureNumber(pathGenCfg_Trunk_raw.PathPerlin_YawNoiseScale, TP.PathPerlin_YawNoiseScale, "PathGen.Trunk.PathPerlin_YawNoiseScale")
	TP.PathPerlin_YawStrengthFactor = _ensureNumber(pathGenCfg_Trunk_raw.PathPerlin_YawStrengthFactor, TP.PathPerlin_YawStrengthFactor, "PathGen.Trunk.PathPerlin_YawStrengthFactor")
	TP.PathPerlin_PitchNoiseScale = _ensureNumber(pathGenCfg_Trunk_raw.PathPerlin_PitchNoiseScale, TP.PathPerlin_PitchNoiseScale, "PathGen.Trunk.PathPerlin_PitchNoiseScale")
	TP.PathPerlin_PitchStrengthFactor = _ensureNumber(pathGenCfg_Trunk_raw.PathPerlin_PitchStrengthFactor, TP.PathPerlin_PitchStrengthFactor, "PathGen.Trunk.PathPerlin_PitchStrengthFactor")
	TP.RadiusVarianceNoiseScale = _ensureNumber(pathGenCfg_Trunk_raw.RadiusVarianceNoiseScale, TP.RadiusVarianceNoiseScale, "PathGen.Trunk.RadiusVarianceNoiseScale")
	TP.RadiusVarianceFactor = _ensureNumber(pathGenCfg_Trunk_raw.RadiusVarianceFactor, TP.RadiusVarianceFactor, "PathGen.Trunk.RadiusVarianceFactor")
	TP.TurnTendencyNoiseScale = _ensureNumber(pathGenCfg_Trunk_raw.TurnTendencyNoiseScale, TP.TurnTendencyNoiseScale, "PathGen.Trunk.TurnTendencyNoiseScale")
	TP.TurnTendencyVariance = _ensureNumber(pathGenCfg_Trunk_raw.TurnTendencyVariance, TP.TurnTendencyVariance, "PathGen.Trunk.TurnTendencyVariance")
	TP.CarveInitialClearanceAtStart = _getOrDefault(pathGenCfg_Trunk_raw, "CarveInitialClearanceAtStart", TP.CarveInitialClearanceAtStart, "boolean")
	TP.InitialClearanceRadiusCells = _ensureNumber(pathGenCfg_Trunk_raw.InitialClearanceRadiusCells, TP.InitialClearanceRadiusCells, "PathGen.Trunk.InitialClearanceRadiusCells")

	local trunkStartRadiusCells = TP.StartRadiusStuds / cellSize
	local trunkEndRadiusCells = TP.EndRadiusStuds / cellSize
	local trunkSegmentLengthCells = TP.SegmentBaseLengthStuds / cellSize
	local trunkNumSegments = math.max(1, math.ceil(TP.TargetLengthStuds / TP.SegmentBaseLengthStuds))

	local startX = localRandomInt(math.floor(gridSizeX * TP.StartX_Range[1]), math.floor(gridSizeX * TP.StartX_Range[2]))
	local startY = localRandomInt(math.floor(gridSizeY * TP.StartY_Range[1]), math.floor(gridSizeY * TP.StartY_Range[2]))
	local startZ = localRandomInt(math.floor(gridSizeZ * TP.StartZ_Range[1]), math.floor(gridSizeZ * TP.StartZ_Range[2]))
	local trunkStartPos = Vector3.new(startX, startY, startZ)

	if TP.CarveInitialClearanceAtStart and TP.InitialClearanceRadiusCells > 0 then
		Logger:Debug("Phase_CarveSkeleton", "Carving initial TRUNK clearance: %s, R:%d cells", tostring(trunkStartPos), TP.InitialClearanceRadiusCells)
		_carveSphereGrid(grid, trunkStartPos.X, trunkStartPos.Y, trunkStartPos.Z, TP.InitialClearanceRadiusCells, AIR)
	end

	local initialTrunkTargetPos = Vector3.new(gridSizeX / 2, gridSizeY / 2, gridSizeZ / 2)
	local globalTargetInfluence = _getOrDefault(CaveConfig.PathGeneration, "GlobalTargetInfluence", 0.3, "number")
	local globalTargetNoiseScale = _getOrDefault(CaveConfig.PathGeneration, "GlobalTargetNoiseScale", 0.002, "number")
	if globalTargetInfluence > 0 then
		local noisyOffsetMag = gridSizeX * 0.4 
		local nX = (Perlin.Noise(origin.X*globalTargetNoiseScale+12.3,origin.Y*globalTargetNoiseScale+45.6,origin.Z*globalTargetNoiseScale+78.9) * 2-1) * noisyOffsetMag
		local nY = (Perlin.Noise(origin.X*globalTargetNoiseScale-12.3,origin.Y*globalTargetNoiseScale-45.6,origin.Z*globalTargetNoiseScale-78.9) * 2-1) * (gridSizeY*0.15) 
		local nZ = (Perlin.Noise(origin.X*globalTargetNoiseScale+55.5,origin.Y*globalTargetNoiseScale-22.2,origin.Z*globalTargetNoiseScale+88.8) * 2-1) * noisyOffsetMag
		initialTrunkTargetPos = Vector3.new(gridSizeX/2+nX, gridSizeY/2+nY, gridSizeZ/2+nZ)
		initialTrunkTargetPos = Vector3.new(gridSizeX/2,gridSizeY/2,gridSizeZ/2):Lerp(initialTrunkTargetPos, globalTargetInfluence)
	end
	initialTrunkDirection = (initialTrunkTargetPos - trunkStartPos).Unit
	if initialTrunkDirection.Magnitude < 0.1 then initialTrunkDirection = Vector3.new(1,0,0) end

	Logger:Debug("Phase_CarveSkeleton", "Generating TRUNK: Start:%s, Dir:%s, Len:%.0f studs, Segs:%d, SegLenC:%.1f",
		tostring(trunkStartPos),tostring(initialTrunkDirection),TP.TargetLengthStuds,trunkNumSegments,trunkSegmentLengthCells)

	local trunkPathPoints = _generateWindingPath_PerlinAdvanced( -- Calling with TP fields
		trunkStartPos, initialTrunkDirection, trunkNumSegments, trunkSegmentLengthCells, TP.TargetLengthStuds,
		TP.PathPerlin_MaxTurnDeg, TP.PathPerlin_YawNoiseScale, TP.PathPerlin_YawStrengthFactor, 
		TP.PathPerlin_PitchNoiseScale, TP.PathPerlin_PitchStrengthFactor, 
		Rng:NextNumber()*1e4+100, pathGenCfg_Trunk_raw -- IMPORTANT: Pass pathGenCfg_Trunk_raw (the original config table) for the last argument
	)
	skeletonData.trunkPath = trunkPathPoints

	if #trunkPathPoints < 2 then
		Logger:Warn("Phase_CarveSkeleton", "TRUNK path gen failed (<2 points). Skipping carving.")
	else
		Logger:Info("Phase_CarveSkeleton", "TRUNK path %d points. Carving...", #trunkPathPoints)
		for i=1, #trunkPathPoints-1 do
			local p1 = trunkPathPoints[i]; local p2 = trunkPathPoints[i+1]; if not p1 or not p2 then Logger:Warn("Phase_CarveSkeleton", "Nil point in TRUNK path at index " .. i); break end
			local prog= (i-1)/math.max(1,#trunkPathPoints-2)
			local baseRC = lerp(trunkStartRadiusCells, trunkEndRadiusCells, prog)
			local variedRC = baseRC * (1+localRandomFloat(-TP.RadiusVarianceFactor, TP.RadiusVarianceFactor))
			-- Use TP for radius variance noise parameters
			if TP.RadiusVarianceNoiseScale > 0 and TP.RadiusVarianceFactor > 0 then
				local lenSoFar_t = prog*trunkNumSegments*trunkSegmentLengthCells 
				local rNoiseIn_t = lenSoFar_t*TP.RadiusVarianceNoiseScale + (Rng:NextNumber()*100 + 300)
				local rNoiseVal_t = (Perlin.Noise(rNoiseIn_t,Rng:NextNumber()*10,Rng:NextNumber()*10)*2)-1
				variedRC = variedRC * (1+rNoiseVal_t*TP.RadiusVarianceFactor)
			end
			_carveCylinderGrid(grid, p1, p2, math.max(1, math.floor(variedRC)), AIR)
			if i%10==0 then doYield() end
		end
	end
	Logger:Info("Phase_CarveSkeleton", "Main Trunk carving finished.")

	validBranchStartIndex = math.max(2, math.floor(#trunkPathPoints * 0.1))
	validBranchEndIndex = math.min(#trunkPathPoints - 1, math.floor(#trunkPathPoints * 0.9)) 

	-- ==== PRIMARY BRANCH GENERATION ====
	Logger:Info("Phase_CarveSkeleton", "Starting Primary Branch Generation...")
	local pathGenCfg_Branch_raw = (CaveConfig.PathGeneration and CaveConfig.PathGeneration.Branch) or {} -- Used _raw
	local skelCfg_Branch_raw = CaveConfig.Skeleton_Branch or {} -- Used _raw

	if not CaveConfig.PathGeneration or not CaveConfig.PathGeneration.Branch or not CaveConfig.Skeleton_Branch then
		Logger:Error("Phase_CarveSkeleton_Branch", "CRITICAL: Branch PathGeneration or Skeleton config table missing. Skipping all branches.")
	else
		local numBranches_min_cfg, numBranches_max_cfg = _getMinMaxOrDefault(skelCfg_Trunk_raw, "Count_MinMax", 4, 6) -- Using skelCfg_Trunk_raw for consistency
		local numBranches = localRandomInt(numBranches_min_cfg, numBranches_max_cfg)
		local trunkPathIndicesForBranches = {}

		if #trunkPathPoints >= 2 and validBranchEndIndex >= validBranchStartIndex then
			for i_bidx = validBranchStartIndex, validBranchEndIndex do table.insert(trunkPathIndicesForBranches, i_bidx) end
			localShuffleTable(trunkPathIndicesForBranches)
		else Logger:Warn("Phase_CarveSkeleton_Branch", "Trunk path too short or invalid range for branches (%d points). No branches from trunk.", #trunkPathPoints) end

		for iter = 1, #trunkPathIndicesForBranches do
			local trunkPointIndex_branch = trunkPathIndicesForBranches[iter]
			if branchesMade >= numBranches then break end

			local proceedWithThisBranch = true 
			if not (trunkPathPoints and trunkPathPoints[trunkPointIndex_branch]) then
				Logger:Warn("Phase_CarveSkeleton_Branch", "Invalid trunkPointIndex %s for branch attempt %d. Skipping.", tostring(trunkPointIndex_branch), branchesMade+1)
				proceedWithThisBranch = false
			end

			if proceedWithThisBranch then
				local branchStartPoint = trunkPathPoints[trunkPointIndex_branch]
				local currentTrunkTangentDir 
				if trunkPointIndex_branch < #trunkPathPoints and trunkPathPoints[trunkPointIndex_branch + 1] then
					currentTrunkTangentDir = (trunkPathPoints[trunkPointIndex_branch + 1] - branchStartPoint).Unit
				elseif trunkPointIndex_branch > 1 and trunkPathPoints[trunkPointIndex_branch - 1] then
					currentTrunkTangentDir = (branchStartPoint - trunkPathPoints[trunkPointIndex_branch - 1]).Unit
				else
					currentTrunkTangentDir = initialTrunkDirection 
				end
				if currentTrunkTangentDir.Magnitude < 0.1 then currentTrunkTangentDir = Vector3.new(Rng:NextNumber()*2-1,Rng:NextNumber()*2-1,Rng:NextNumber()*2-1).Unit end
				if currentTrunkTangentDir.Magnitude < 0.1 then currentTrunkTangentDir = Vector3.new(1,0,0) end

				local randomPerpAxis = currentTrunkTangentDir:Cross(Vector3.new(localRandomFloat(-1,1), localRandomFloat(-1,1), localRandomFloat(-1,1))).Unit
				if randomPerpAxis.Magnitude < 0.1 then 
					local upVec = Vector3.new(0,1,0); if math.abs(currentTrunkTangentDir:Dot(upVec)) > 0.95 then upVec = Vector3.new(1,0,0) end
					randomPerpAxis = currentTrunkTangentDir:Cross(upVec).Unit
					if randomPerpAxis.Magnitude < 0.1 then randomPerpAxis = Vector3.new(0,0,1) end 
				end
				local rotationAroundTangent = math.rad(localRandomFloat(0, 360))
				local branchOutwardBaseDir = rotateVectorAroundAxis(randomPerpAxis, currentTrunkTangentDir, rotationAroundTangent)

				local BP = { -- BRANCH PARAMETERS WITH DEFAULTS
					SegmentBaseLengthStuds = 9, PathPerlin_MaxTurnDeg = 30, PathPerlin_YawNoiseScale = 0.035,
					PathPerlin_YawStrengthFactor = 0.95, PathPerlin_PitchNoiseScale = 0.04, PathPerlin_PitchStrengthFactor = 0.5,
					RadiusVarianceNoiseScale = 0.06, RadiusVarianceFactor = 0.20, TurnTendencyNoiseScale = 0.05, TurnTendencyVariance = 0.35,
					BranchOutwardMin = 0.4, BranchOutwardMax = 0.8, BranchTangentInfluenceMin = -0.1, BranchTangentInfluenceMax = 0.3,
					RadiusStudsMin = 4, RadiusStudsMax = 7, LengthStudsMin = 30, LengthStudsMax = 70,
					CarveInitialClearanceAtStart = false, InitialClearanceRadiusCells = 0
				}
				BP.SegmentBaseLengthStuds = _ensureNumber(pathGenCfg_Branch_raw.SegmentBaseLengthStuds, BP.SegmentBaseLengthStuds, "PathGen.Branch.SegLen")
				BP.PathPerlin_MaxTurnDeg = _ensureNumber(pathGenCfg_Branch_raw.PathPerlin_MaxTurnDeg, BP.PathPerlin_MaxTurnDeg, "PathGen.Branch.MaxTurn")
				BP.PathPerlin_YawNoiseScale = _ensureNumber(pathGenCfg_Branch_raw.PathPerlin_YawNoiseScale, BP.PathPerlin_YawNoiseScale, "PathGen.Branch.YawScale")
				BP.PathPerlin_YawStrengthFactor = _ensureNumber(pathGenCfg_Branch_raw.PathPerlin_YawStrengthFactor, BP.PathPerlin_YawStrengthFactor, "PathGen.Branch.YawStr")
				BP.PathPerlin_PitchNoiseScale = _ensureNumber(pathGenCfg_Branch_raw.PathPerlin_PitchNoiseScale, BP.PathPerlin_PitchNoiseScale, "PathGen.Branch.PitchScale")
				BP.PathPerlin_PitchStrengthFactor = _ensureNumber(pathGenCfg_Branch_raw.PathPerlin_PitchStrengthFactor, BP.PathPerlin_PitchStrengthFactor, "PathGen.Branch.PitchStr")
				BP.RadiusVarianceNoiseScale = _ensureNumber(pathGenCfg_Branch_raw.RadiusVarianceNoiseScale, BP.RadiusVarianceNoiseScale, "PathGen.Branch.RadVarScale")
				BP.RadiusVarianceFactor = _ensureNumber(pathGenCfg_Branch_raw.RadiusVarianceFactor, BP.RadiusVarianceFactor, "PathGen.Branch.RadVarFactor")
				BP.TurnTendencyNoiseScale = _ensureNumber(pathGenCfg_Branch_raw.TurnTendencyNoiseScale, BP.TurnTendencyNoiseScale, "PathGen.Branch.TurnTendScale")
				BP.TurnTendencyVariance = _ensureNumber(pathGenCfg_Branch_raw.TurnTendencyVariance, BP.TurnTendencyVariance, "PathGen.Branch.TurnTendVar")
				BP.BranchOutwardMin, BP.BranchOutwardMax = _getMinMaxOrDefault(pathGenCfg_Branch_raw, "BranchOutwardMinMax", BP.BranchOutwardMin, BP.BranchOutwardMax)
				BP.BranchTangentInfluenceMin, BP.BranchTangentInfluenceMax = _getMinMaxOrDefault(pathGenCfg_Branch_raw, "BranchTangentInfluenceMinMax", BP.BranchTangentInfluenceMin, BP.BranchTangentInfluenceMax)
				BP.RadiusStudsMin, BP.RadiusStudsMax = _getMinMaxOrDefault(skelCfg_Branch_raw, "RadiusStuds_MinMax", BP.RadiusStudsMin, BP.RadiusStudsMax)
				BP.LengthStudsMin, BP.LengthStudsMax = _getMinMaxOrDefault(skelCfg_Branch_raw, "LengthStuds_MinMax", BP.LengthStudsMin, BP.LengthStudsMax)
				BP.CarveInitialClearanceAtStart = _getOrDefault(pathGenCfg_Branch_raw, "CarveInitialClearanceAtStart", BP.CarveInitialClearanceAtStart, "boolean")
				BP.InitialClearanceRadiusCells = _ensureNumber(pathGenCfg_Branch_raw.InitialClearanceRadiusCells, BP.InitialClearanceRadiusCells, "PathGen.Branch.InitialClearance")

				local outwardStrength = localRandomFloat(BP.BranchOutwardMin, BP.BranchOutwardMax) 
				local tangentInfluence = localRandomFloat(BP.BranchTangentInfluenceMin, BP.BranchTangentInfluenceMax)
				local branchInitialDir = (branchOutwardBaseDir * outwardStrength + currentTrunkTangentDir * tangentInfluence).Unit 
				if branchInitialDir.Magnitude < 0.1 then branchInitialDir = branchOutwardBaseDir.Unit end
				if branchInitialDir.Magnitude < 0.1 then branchInitialDir = randomPerpAxis.Unit end

				local branchRadiusStuds = localRandomFloat(BP.RadiusStudsMin, BP.RadiusStudsMax)
				local branchLengthStuds = localRandomFloat(BP.LengthStudsMin, BP.LengthStudsMax)
				local branchSegLenCells = BP.SegmentBaseLengthStuds / cellSize
				local branchNumSegments = math.max(1, math.ceil(branchLengthStuds / BP.SegmentBaseLengthStuds))

				Logger:Debug("Phase_CarveSkeleton_Branch", "Attempt Branch %d (TrunkPt %d): Dir %s, R%.1f, L%.1f, Segs %d",
					branchesMade+1,trunkPointIndex_branch,tostring(branchInitialDir),branchRadiusStuds,branchLengthStuds,branchNumSegments)

				local branchPathPoints = _generateWindingPath_PerlinAdvanced(
					branchStartPoint, branchInitialDir, branchNumSegments, branchSegLenCells, branchLengthStuds,
					BP.PathPerlin_MaxTurnDeg, BP.PathPerlin_YawNoiseScale, BP.PathPerlin_YawStrengthFactor,
					BP.PathPerlin_PitchNoiseScale, BP.PathPerlin_PitchStrengthFactor, 
					Rng:NextNumber()*1e4+200+trunkPointIndex_branch, pathGenCfg_Branch_raw 
				)

				if #branchPathPoints >= 2 then
					local branchRadiusCells = math.max(1, math.floor(branchRadiusStuds/cellSize))
					for k=1,#branchPathPoints-1 do
						local p1b,p2b = branchPathPoints[k], branchPathPoints[k+1]; if not p1b or not p2b then Logger:Warn("Phase_CarveSkeleton_Branch", "Nil point in branch path for branch %d. Skipping segment.", branchesMade+1); break end
						local currentBranchRC = branchRadiusCells
						if BP.RadiusVarianceNoiseScale > 0 and BP.RadiusVarianceFactor > 0 then
							local prog_br=(k-1)/math.max(1,#branchPathPoints-2)
							local lenSoFar_br = prog_br*branchNumSegments*branchSegLenCells
							local rNoiseIn_br = lenSoFar_br*BP.RadiusVarianceNoiseScale+(Rng:NextNumber()*100+400+k)
							local rNoiseVal_br = (Perlin.Noise(rNoiseIn_br,Rng:NextNumber()*10,Rng:NextNumber()*10)*2)-1
							currentBranchRC = currentBranchRC*(1+rNoiseVal_br*BP.RadiusVarianceFactor)
							currentBranchRC = math.max(1,math.floor(currentBranchRC))
						end
						_carveCylinderGrid(grid,p1b,p2b,currentBranchRC,AIR)
						if k%5==0 then doYield() end
					end
					table.insert(primaryBranchStartIndices_USED, trunkPointIndex_branch)
					table.insert(collectedBranchPaths, branchPathPoints)
					branchesMade=branchesMade+1
					Logger:Info("Phase_CarveSkeleton_Branch", "Branch %d carved.", branchesMade)
				else 
					Logger:Warn("Phase_CarveSkeleton_Branch","Branch path gen failed at TrunkPt %d (<2 pts). Branch %d not created.", trunkPointIndex_branch, branchesMade+1) 
				end
			end 
			doYield()
		end
	end 
	skeletonData.branchPaths = collectedBranchPaths
	Logger:Info("Phase_CarveSkeleton", "%d Primary Branches Made.", branchesMade)

	-- ==== SECONDARY SPUR GENERATION ====
	Logger:Info("Phase_CarveSkeleton", "Starting Secondary Spur Generation...")
	local pathCfgSpur = (CaveConfig.PathGeneration and CaveConfig.PathGeneration.Spur) or {}
	local skelCfgSpur = CaveConfig.Skeleton_Spur or {}

	if not CaveConfig.PathGeneration or not CaveConfig.PathGeneration.Spur or not CaveConfig.Skeleton_Spur then
		Logger:Error("Phase_CarveSkeleton_Spur", "CRITICAL: Spur PathGeneration or Skeleton config table missing. Skipping spurs.")
	else
		local numSpurs_min_cfg, numSpurs_max_cfg = _getMinMaxOrDefault(skelCfgSpur, "Count_MinMax_PerTrunk", 3, 7)
		local numSpurs = localRandomInt(numSpurs_min_cfg, numSpurs_max_cfg)
		local availableTrunkPointsIndicesForSpurs = {}

		if #trunkPathPoints >=2 and validBranchEndIndex >= validBranchStartIndex then
			for i_spidx = validBranchStartIndex, validBranchEndIndex do table.insert(availableTrunkPointsIndicesForSpurs, i_spidx) end
			localShuffleTable(availableTrunkPointsIndicesForSpurs)
		else Logger:Warn("Phase_CarveSkeleton_Spur", "Trunk path too short for spurs (%d points). No spurs from trunk.", #trunkPathPoints) end

		local SPUR_MIN_DIST = _getOrDefault(skelCfgSpur, "MinDistFromBranchSegments", 2)

		for iterSpur = 1, #availableTrunkPointsIndicesForSpurs do
			local candidateTrunkPointIndex_spur = availableTrunkPointsIndicesForSpurs[iterSpur]
			if spursMade >= numSpurs then break end
			local proceedWithThisSpur = true
			if not (trunkPathPoints and trunkPathPoints[candidateTrunkPointIndex_spur]) then
				Logger:Warn("Phase_CarveSkeleton_Spur", "Invalid trunk point for spur %d. Skipping.", spursMade+1)
				proceedWithThisSpur = false
			end

			if proceedWithThisSpur then
				local isTooClose = false
				for _, usedIdx in ipairs(primaryBranchStartIndices_USED) do if math.abs(candidateTrunkPointIndex_spur - usedIdx) < SPUR_MIN_DIST then isTooClose=true; break end end
				if isTooClose then proceedWithThisSpur = false end
			end

			if proceedWithThisSpur then
				local spurStartPoint = trunkPathPoints[candidateTrunkPointIndex_spur]
				local currentTrunkTangentDir_s 
				if candidateTrunkPointIndex_spur < #trunkPathPoints and trunkPathPoints[candidateTrunkPointIndex_spur+1] then currentTrunkTangentDir_s = (trunkPathPoints[candidateTrunkPointIndex_spur+1] - spurStartPoint).Unit
				elseif candidateTrunkPointIndex_spur > 1 and trunkPathPoints[candidateTrunkPointIndex_spur-1] then currentTrunkTangentDir_s = (spurStartPoint - trunkPathPoints[candidateTrunkPointIndex_spur-1]).Unit
				else currentTrunkTangentDir_s = initialTrunkDirection end 
				if currentTrunkTangentDir_s.Magnitude < 0.1 then currentTrunkTangentDir_s = Vector3.new(1,0,0) end

				local randomPerpAxis_s = currentTrunkTangentDir_s:Cross(Vector3.new(localRandomFloat(-1,1),localRandomFloat(-1,1),localRandomFloat(-1,1))).Unit
				if randomPerpAxis_s.Magnitude < 0.1 then local up =Vector3.new(0,1,0); if math.abs(currentTrunkTangentDir_s:Dot(up)) > 0.95 then up=Vector3.new(1,0,0) end; randomPerpAxis_s = currentTrunkTangentDir_s:Cross(up).Unit end
				if randomPerpAxis_s.Magnitude < 0.1 then randomPerpAxis_s = Vector3.new(0,0,1) end
				local spurOutwardBaseDir = rotateVectorAroundAxis(randomPerpAxis_s, currentTrunkTangentDir_s, math.rad(localRandomFloat(0,360)))
				local spurInitialDir = (spurOutwardBaseDir + currentTrunkTangentDir_s * localRandomFloat(0.0,0.2) * (Rng:NextNumber()<0.5 and 1 or -1)).Unit
				if spurInitialDir.Magnitude < 0.1 then spurInitialDir = spurOutwardBaseDir.Unit end
				if spurInitialDir.Magnitude < 0.1 then spurInitialDir = randomPerpAxis_s.Unit end

				local SP = { -- SP for Spur Parameters
					SegmentBaseLengthStuds = 7, PathPerlin_MaxTurnDeg = 40, PathPerlin_YawNoiseScale = 0.045,
					PathPerlin_YawStrengthFactor = 1.0, PathPerlin_PitchNoiseScale = 0.05, PathPerlin_PitchStrengthFactor = 0.6,
					RadiusVarianceNoiseScale = 0.07, RadiusVarianceFactor = 0.25, TurnTendencyNoiseScale = 0.06, TurnTendencyVariance = 0.4,
					RadiusStudsMin = 2, RadiusStudsMax = 4, LengthStudsMin = 15, LengthStudsMax = 35,
					CarveInitialClearanceAtStart = false, InitialClearanceRadiusCells = 0
				}
				SP.SegmentBaseLengthStuds = _ensureNumber(pathCfgSpur.SegmentBaseLengthStuds, SP.SegmentBaseLengthStuds, "PathGen.Spur.SegLen")
				SP.PathPerlin_MaxTurnDeg = _ensureNumber(pathCfgSpur.PathPerlin_MaxTurnDeg, SP.PathPerlin_MaxTurnDeg, "PathGen.Spur.MaxTurn")
				SP.PathPerlin_YawNoiseScale = _ensureNumber(pathCfgSpur.PathPerlin_YawNoiseScale, SP.PathPerlin_YawNoiseScale, "PathGen.Spur.YawScale")
				SP.PathPerlin_YawStrengthFactor = _ensureNumber(pathCfgSpur.PathPerlin_YawStrengthFactor, SP.PathPerlin_YawStrengthFactor, "PathGen.Spur.YawStr")
				SP.PathPerlin_PitchNoiseScale = _ensureNumber(pathCfgSpur.PathPerlin_PitchNoiseScale, SP.PathPerlin_PitchNoiseScale, "PathGen.Spur.PitchScale")
				SP.PathPerlin_PitchStrengthFactor = _ensureNumber(pathCfgSpur.PathPerlin_PitchStrengthFactor, SP.PathPerlin_PitchStrengthFactor, "PathGen.Spur.PitchStr")
				SP.RadiusVarianceNoiseScale = _ensureNumber(pathCfgSpur.RadiusVarianceNoiseScale, SP.RadiusVarianceNoiseScale, "PathGen.Spur.RadVarScale")
				SP.RadiusVarianceFactor = _ensureNumber(pathCfgSpur.RadiusVarianceFactor, SP.RadiusVarianceFactor, "PathGen.Spur.RadVarFactor")
				SP.TurnTendencyNoiseScale = _ensureNumber(pathCfgSpur.TurnTendencyNoiseScale, SP.TurnTendencyNoiseScale, "PathGen.Spur.TurnTendScale")
				SP.TurnTendencyVariance = _ensureNumber(pathCfgSpur.TurnTendencyVariance, SP.TurnTendencyVariance, "PathGen.Spur.TurnTendVar")
				SP.RadiusStudsMin, SP.RadiusStudsMax = _getMinMaxOrDefault(skelCfgSpur, "RadiusStuds_MinMax", SP.RadiusStudsMin, SP.RadiusStudsMax)
				SP.LengthStudsMin, SP.LengthStudsMax = _getMinMaxOrDefault(skelCfgSpur, "LengthStuds_MinMax", SP.LengthStudsMin, SP.LengthStudsMax)
				SP.CarveInitialClearanceAtStart = _getOrDefault(pathCfgSpur, "CarveInitialClearanceAtStart", SP.CarveInitialClearanceAtStart, "boolean")
				SP.InitialClearanceRadiusCells = _ensureNumber(pathCfgSpur.InitialClearanceRadiusCells, SP.InitialClearanceRadiusCells, "PathGen.Spur.InitialClearance")

				local spurRadiusStuds = localRandomFloat(SP.RadiusStudsMin, SP.RadiusStudsMax)
				local spurLengthStuds = localRandomFloat(SP.LengthStudsMin, SP.LengthStudsMax)
				local spurSegLenCells = SP.SegmentBaseLengthStuds / cellSize
				local spurNumSegments = math.max(1, math.ceil(spurLengthStuds / SP.SegmentBaseLengthStuds))

				Logger:Debug("Phase_CarveSkeleton_Spur", "Attempt Spur %d (TrunkPt %d): Dir %s, R%.1f, L%.1f, Segs %d",
					spursMade+1,candidateTrunkPointIndex_spur,tostring(spurInitialDir),spurRadiusStuds,spurLengthStuds,spurNumSegments)

				local spurPathPoints = _generateWindingPath_PerlinAdvanced(
					spurStartPoint, spurInitialDir, spurNumSegments, spurSegLenCells, spurLengthStuds,
					SP.PathPerlin_MaxTurnDeg, SP.PathPerlin_YawNoiseScale, SP.PathPerlin_YawStrengthFactor,
					SP.PathPerlin_PitchNoiseScale, SP.PathPerlin_PitchStrengthFactor, 
					Rng:NextNumber()*1e4+300+candidateTrunkPointIndex_spur, pathCfgSpur
				)
				if #spurPathPoints >= 2 then
					local spurRadiusCells = math.max(1, math.floor(spurRadiusStuds / cellSize))
					for k_s=1, #spurPathPoints-1 do
						local p1s,p2s = spurPathPoints[k_s],spurPathPoints[k_s+1]; if not p1s or not p2s then Logger:Warn("Phase_CarveSkeleton_Spur", "Nil point in spur path. Skipping segment."); break end
						local currentSpurRC = spurRadiusCells
						if SP.RadiusVarianceNoiseScale > 0 and SP.RadiusVarianceFactor > 0 then
							local prog_sp = (k_s-1)/math.max(1,#spurPathPoints-2)
							local lenSoFar_sp = prog_sp*spurNumSegments*spurSegLenCells
							local rNoiseIn_sp = lenSoFar_sp*SP.RadiusVarianceNoiseScale+(Rng:NextNumber()*100+500+k_s)
							local rNoiseVal_sp = (Perlin.Noise(rNoiseIn_sp,Rng:NextNumber()*10,Rng:NextNumber()*10)*2)-1
							currentSpurRC = currentSpurRC*(1+rNoiseVal_sp*SP.RadiusVarianceFactor); currentSpurRC = math.max(1,math.floor(currentSpurRC))
						end
						_carveCylinderGrid(grid,p1s,p2s,currentSpurRC,AIR)
						if k_s%5==0 then doYield() end
					end
					table.insert(collectedSpurPaths, spurPathPoints)
					spursMade=spursMade+1
					Logger:Info("Phase_CarveSkeleton_Spur", "Spur %d carved.", spursMade)
				else Logger:Warn("Phase_CarveSkeleton_Spur", "Spur path gen failed at TrunkPt %d (<2 pts).",candidateTrunkPointIndex_spur) end
			end
			doYield()
		end
	end 
	skeletonData.spurPaths = collectedSpurPaths
	Logger:Info("Phase_CarveSkeleton", "%d Secondary Spurs Made (off trunk).", spursMade)

	Logger:Debug("Phase_CarveSkeleton_Return", "Returning skeletonData. Trunk points: %d, Branch path sets: %d, Spur path sets: %d",
		(skeletonData.trunkPath and #skeletonData.trunkPath or 0),
		(skeletonData.branchPaths and #skeletonData.branchPaths or 0),
		(skeletonData.spurPaths and #skeletonData.spurPaths or 0)
	)
	Logger:Info("Phase_CarveSkeleton", "Phase (Skeleton Carve) Finished! Total Time: %.2fs", os.clock() - startTime)
	return skeletonData
end

local function Phase_ConnectLoops(skeletonDataReceived)
	Logger:Info("Phase_ConnectLoops", "Starting Full Loop Generation...")
	local startTime = os.clock()

	if not skeletonDataReceived or not skeletonDataReceived.branchPaths or #skeletonDataReceived.branchPaths < 2 then
		Logger:Warn("Phase_ConnectLoops", "Not enough branch paths in skeletonData to attempt loops. Need at least 2. Skipping.")
		Logger:Info("Phase_ConnectLoops", "Finished (skipped due to insufficient branch paths). Time: %.2fs", os.clock() - startTime)
		return 
	end

	local allPrimaryBranchPaths = skeletonDataReceived.branchPaths
	-- Correctly get the LoopConnector specific part of PathGeneration config
	local pathGenCfgLoop_raw = (CaveConfig.PathGeneration and CaveConfig.PathGeneration.LoopConnector) or {}

	local numLoopsToAttempt = localRandomInt(1, _getOrDefault(pathGenCfgLoop_raw, "NumLoopsToAttempt", 2, "number")) 
	local loopsMade = 0

	local defaultLoopRadiusMin = 3
	local defaultLoopRadiusMax = 6
	local loopRadiusMin, loopRadiusMax = _getMinMaxOrDefault(pathGenCfgLoop_raw, "RadiusStuds_MinMax", defaultLoopRadiusMin, defaultLoopRadiusMax)

	local maxDistStuds = _getOrDefault(pathGenCfgLoop_raw, "MaxDistanceStuds", 80, "number")
	local minSegLenStudsLoop = _getOrDefault(pathGenCfgLoop_raw, "SegmentBaseLengthStuds", 10, "number")


	local availableBranchIndices = {}
	for i = 1, #allPrimaryBranchPaths do table.insert(availableBranchIndices, i) end

	for attempt = 1, numLoopsToAttempt * 5 do 
		if loopsMade >= numLoopsToAttempt then break end
		if #availableBranchIndices < 2 then 
			Logger:Debug("Phase_ConnectLoops", "Not enough unique branches left to form more loops.")
			break 
		end

		local proceedWithThisSpecificLoopAttempt = true 
		localShuffleTable(availableBranchIndices)
		local branchIndex1 = availableBranchIndices[1]
		local branchIndex2 = availableBranchIndices[2]
		local path1, path2, endPoint1, endPoint2

		if not (allPrimaryBranchPaths[branchIndex1] and #allPrimaryBranchPaths[branchIndex1] > 0) then
			Logger:Warn("Phase_ConnectLoops", "Branch path at index %d invalid/empty for loop attempt %d. Removing.", branchIndex1, attempt)
			if #availableBranchIndices >=1 then table.remove(availableBranchIndices, 1) end 
			proceedWithThisSpecificLoopAttempt = false
		end

		if proceedWithThisSpecificLoopAttempt then
			if not (allPrimaryBranchPaths[branchIndex2] and #allPrimaryBranchPaths[branchIndex2] > 0) then
				Logger:Warn("Phase_ConnectLoops", "Branch path at index %d invalid/empty for loop attempt %d. Removing.", branchIndex2, attempt)
				local actualIndexForB2 = -1; for k,v in ipairs(availableBranchIndices) do if v==branchIndex2 then actualIndexForB2=k; break; end end
				if actualIndexForB2 > 0 then table.remove(availableBranchIndices, actualIndexForB2) end
				proceedWithThisSpecificLoopAttempt = false
			end
		end

		if proceedWithThisSpecificLoopAttempt then
			path1 = allPrimaryBranchPaths[branchIndex1]
			path2 = allPrimaryBranchPaths[branchIndex2]
			endPoint1 = path1[#path1] 
			endPoint2 = path2[#path2] 
			local distanceStuds = (endPoint1 - endPoint2).Magnitude * cellSize

			Logger:Trace("Phase_ConnectLoops", "Considering loop (Attempt %d) B%d to B%d. Dist: %.1f studs",
				attempt, branchIndex1, branchIndex2, distanceStuds)

			if distanceStuds < (minSegLenStudsLoop * 1.5) or distanceStuds > maxDistStuds then
				Logger:Trace("Phase_ConnectLoops", "Loop Attempt %d: Dist %.1f not suitable (MinReq: %.1f, MaxAllow: %.1f). Skip.", 
					attempt, distanceStuds, minSegLenStudsLoop * 1.5, maxDistStuds)
				proceedWithThisSpecificLoopAttempt = false
			end
		end

		if proceedWithThisSpecificLoopAttempt then
			local loopInitialDir = (endPoint2 - endPoint1).Unit
			if loopInitialDir.Magnitude < 0.1 then loopInitialDir = Vector3.new(localRandomFloat(-1,1),0,localRandomFloat(-1,1)).Unit end
			if loopInitialDir.Magnitude < 0.1 then loopInitialDir = Vector3.new(1,0,0) end

			local loopRadiusStuds = localRandomFloat(loopRadiusMin, loopRadiusMax)
			local loopRadiusCells = math.max(1, math.floor(loopRadiusStuds / cellSize))

			local LP = { -- LP for Loop Parameters - Defaults, these are overwritten by _getOrDefault using pathGenCfgLoop_raw
				SegmentBaseLengthStuds = 10, PathPerlin_MaxTurnDeg = 28, PathPerlin_YawNoiseScale = 0.03,
				PathPerlin_YawStrengthFactor = 0.9, PathPerlin_PitchNoiseScale = 0.035, PathPerlin_PitchStrengthFactor = 0.45,
				RadiusVarianceNoiseScale = 0.055, RadiusVarianceFactor = 0.15,
				TurnTendencyNoiseScale = 0.045, TurnTendencyVariance = 0.25,
				CarveInitialClearanceAtStart = false, InitialClearanceRadiusCells = 0 
			}
			LP.SegmentBaseLengthStuds = _getOrDefault(pathGenCfgLoop_raw, "SegmentBaseLengthStuds", LP.SegmentBaseLengthStuds, "number")
			LP.PathPerlin_MaxTurnDeg = _getOrDefault(pathGenCfgLoop_raw, "PathPerlin_MaxTurnDeg", LP.PathPerlin_MaxTurnDeg, "number")
			LP.PathPerlin_YawNoiseScale = _getOrDefault(pathGenCfgLoop_raw, "PathPerlin_YawNoiseScale", LP.PathPerlin_YawNoiseScale, "number")
			LP.PathPerlin_YawStrengthFactor = _getOrDefault(pathGenCfgLoop_raw, "PathPerlin_YawStrengthFactor", LP.PathPerlin_YawStrengthFactor, "number")
			LP.PathPerlin_PitchNoiseScale = _getOrDefault(pathGenCfgLoop_raw, "PathPerlin_PitchNoiseScale", LP.PathPerlin_PitchNoiseScale, "number")
			LP.PathPerlin_PitchStrengthFactor = _getOrDefault(pathGenCfgLoop_raw, "PathPerlin_PitchStrengthFactor", LP.PathPerlin_PitchStrengthFactor, "number")
			LP.RadiusVarianceNoiseScale = _getOrDefault(pathGenCfgLoop_raw, "RadiusVarianceNoiseScale", LP.RadiusVarianceNoiseScale, "number")
			LP.RadiusVarianceFactor = _getOrDefault(pathGenCfgLoop_raw, "RadiusVarianceFactor", LP.RadiusVarianceFactor, "number")
			LP.TurnTendencyNoiseScale = _getOrDefault(pathGenCfgLoop_raw, "TurnTendencyNoiseScale", LP.TurnTendencyNoiseScale, "number")
			LP.TurnTendencyVariance = _getOrDefault(pathGenCfgLoop_raw, "TurnTendencyVariance", LP.TurnTendencyVariance, "number")
			LP.CarveInitialClearanceAtStart = _getOrDefault(pathGenCfgLoop_raw, "CarveInitialClearanceAtStart", LP.CarveInitialClearanceAtStart, "boolean")
			LP.InitialClearanceRadiusCells = _getOrDefault(pathGenCfgLoop_raw, "InitialClearanceRadiusCells", LP.InitialClearanceRadiusCells, "number")

			local loopSegLenCells = LP.SegmentBaseLengthStuds / cellSize
			local loopLengthStuds = (endPoint1 - endPoint2).Magnitude * cellSize 
			local loopNumSegments = math.max(3, math.ceil(loopLengthStuds / LP.SegmentBaseLengthStuds)) 

			Logger:Debug("Phase_ConnectLoops", "Attempting Loop Path (Loop #%d, Overall Attempt %d): Connect B%d to B%d. R_studs: %.1f, L_studs: %.1f, NumSeg: %d",
				loopsMade + 1, attempt, branchIndex1, branchIndex2, loopRadiusStuds, loopLengthStuds, loopNumSegments)

			local loopPathPoints = _generateWindingPath_PerlinAdvanced(
				endPoint1, loopInitialDir, loopNumSegments, loopSegLenCells, loopLengthStuds,
				LP.PathPerlin_MaxTurnDeg, LP.PathPerlin_YawNoiseScale, LP.PathPerlin_YawStrengthFactor,
				LP.PathPerlin_PitchNoiseScale, LP.PathPerlin_PitchStrengthFactor,
				Rng:NextNumber() * 10000 + 400.0 + attempt, 
				pathGenCfgLoop_raw 
			)

			if #loopPathPoints >= 2 then 
				loopPathPoints[#loopPathPoints] = endPoint2 
				for k = 1, #loopPathPoints - 1 do
					local p1_lp, p2_lp = loopPathPoints[k], loopPathPoints[k+1]
					if not p1_lp or not p2_lp then Logger:Warn("ConnectLoops: Nil point in loop path. Skipping segment."); break end
					_carveCylinderGrid(grid, p1_lp, p2_lp, loopRadiusCells, AIR)
					if k % 3 == 0 then doYield() end
				end
				loopsMade = loopsMade + 1
				Logger:Info("Phase_ConnectLoops", "Loop #%d successfully carved connecting branch %d and %d.", loopsMade, branchIndex1, branchIndex2)

				local idx1ToRemove = -1; for l,val in ipairs(availableBranchIndices) do if val == branchIndex1 then idx1ToRemove = l; break; end end
				if idx1ToRemove > 0 then table.remove(availableBranchIndices, idx1ToRemove) end

				local idx2ToRemove = -1; for l,val in ipairs(availableBranchIndices) do if val == branchIndex2 then idx2ToRemove = l; break; end end
				if idx2ToRemove > 0 then table.remove(availableBranchIndices, idx2ToRemove) end
			else
				Logger:Warn("Phase_ConnectLoops", "Loop connector path gen failed (<2 pts) for attempt %d.", attempt)
			end
		end 
		doYield()
	end 
	Logger:Info("Phase_ConnectLoops", "%d Full Loops Made. Finished! Time: %.2fs", loopsMade, os.clock() - startTime)
end

local function Phase_GenerateMultiLevels(skeletonDataReceived)
	Logger:Info("Phase0B_MultiLevel", "Starting Multi-Level Trunk & Shaft Generation...")
	local startTime = os.clock()

	if not skeletonDataReceived or not skeletonDataReceived.trunkPath or #skeletonDataReceived.trunkPath == 0 then
		Logger:Warn("Phase0B_MultiLevel", "Main trunk path not available in skeletonData. Skipping multi-level generation.")
		Logger:Info("Phase0B_MultiLevel", "Finished (skipped). Time: %.2fs", os.clock() - startTime)
		return skeletonDataReceived -- Return original data if skipping
	end

	local originalTrunkPath = skeletonDataReceived.trunkPath

	-- Multi-Level Parameters (Move to CaveConfig later)
	local createUpperLevel = true -- Toggle for upper level
	local upperLevelYOffsetStuds = localRandomFloat(8, 10)
	local upperLevelRadiusStuds_MinMax = {min = 5, max = 9} -- Can be different from main trunk

	local createLowerLevel = true -- Toggle for lower level
	local lowerLevelYOffsetStuds = localRandomFloat(6, 8)
	local lowerLevelRadiusStuds_MinMax = {min = 4, max = 7} -- Can be tighter

	local numConnectingShaftsPerLevel = localRandomInt(2, 4)
	local shaftRadiusStuds_MinMax = {min = 2, max = 4}
	local shaftBlendRadiusFactor = 1.5 -- e.g., shaft radius * 1.5 for blending sphere

	local newLevelPaths = {} -- To store newly created level paths, might add to skeletonData

	-- Function to generate and carve a parallel trunk
	local function createAndCarveParallelTrunk(basePath, yOffsetStuds, radiusStuds_MinMax, levelName)
		Logger:Info("Phase0B_MultiLevel", "Creating %s level.", levelName)
		local yOffsetCells = math.round(yOffsetStuds / cellSize)
		if yOffsetCells == 0 then
			Logger:Warn("Phase0B_MultiLevel", "%s Y-offset in cells is 0. Skipping level.", levelName)
			return nil
		end

		local newPath = {}
		for _, p_orig in ipairs(basePath) do
			table.insert(newPath, Vector3.new(p_orig.X, p_orig.Y + yOffsetCells, p_orig.Z))
		end

		if #newPath < 2 then
			Logger:Warn("Phase0B_MultiLevel", "%s path has less than 2 points. Skipping carving.", levelName)
			return nil
		end

		local startRadiusStuds = radiusStuds_MinMax.min
		local endRadiusStuds = radiusStuds_MinMax.max
		local startRadiusCells = math.max(1, math.floor(startRadiusStuds / cellSize))
		local endRadiusCells = math.max(1, math.floor(endRadiusStuds / cellSize))
		local radiusVariance = 0.1 -- Less variance for these parallel trunks for simplicity

		Logger:Debug("Phase0B_MultiLevel", "%s: %d points, Y Offset: %d cells. RadiusStuds Range: %.1f-%.1f", levelName, #newPath, yOffsetCells, radiusStuds_MinMax.min, radiusStuds_MinMax.max)

		for i = 1, #newPath - 1 do
			local p1 = newPath[i]
			local p2 = newPath[i+1]
			local progress = (i-1) / math.max(1, #newPath - 2)
			local baseRCells = lerp(startRadiusCells, endRadiusCells, progress)
			local variedRCells = math.max(1, math.floor(baseRCells * (1 + localRandomFloat(-radiusVariance, radiusVariance))))

			_carveCylinderGrid(grid, p1, p2, variedRCells, AIR)
			if i % 10 == 0 then doYield() end
		end
		Logger:Info("Phase0B_MultiLevel", "%s level carving finished.", levelName)
		return newPath
	end

	-- Create Upper Level
	if createUpperLevel then
		local upperPath = createAndCarveParallelTrunk(originalTrunkPath, upperLevelYOffsetStuds, upperLevelRadiusStuds_MinMax, "Upper")
		if upperPath then table.insert(newLevelPaths, {name = "Upper", path = upperPath}) end
	end

	-- Create Lower Level
	if createLowerLevel then
		local lowerPath = createAndCarveParallelTrunk(originalTrunkPath, -lowerLevelYOffsetStuds, lowerLevelRadiusStuds_MinMax, "Lower") -- Negative offset
		if lowerPath then table.insert(newLevelPaths, {name = "Lower", path = lowerPath}) end
	end

	-- Connecting Shafts
	if #newLevelPaths > 0 and #originalTrunkPath > 2 then
		Logger:Info("Phase0B_MultiLevel", "Creating Connecting Shafts...")
		for _, levelData in ipairs(newLevelPaths) do
			local levelPath = levelData.path
			if not levelPath or #levelPath < 2 then continue end

			local shaftsToThisLevelMade = 0
			local shaftAnchorIndicesOnTrunk = {}
			for i = math.floor(#originalTrunkPath * 0.1), math.floor(#originalTrunkPath * 0.9) do -- Mid 80% of trunk
				table.insert(shaftAnchorIndicesOnTrunk, i)
			end
			localShuffleTable(shaftAnchorIndicesOnTrunk)

			for i = 1, math.min(numConnectingShaftsPerLevel, #shaftAnchorIndicesOnTrunk) do
				local trunkAnchorIndex = shaftAnchorIndicesOnTrunk[i]
				if not originalTrunkPath[trunkAnchorIndex] then continue end
				local trunkPoint = originalTrunkPath[trunkAnchorIndex]

				-- Find closest point on the current levelPath to this trunkPoint (in XZ plane)
				local closestLevelPoint = levelPath[1]
				local minDistSqXZ = math.huge
				if not closestLevelPoint then continue end

				for _, lp in ipairs(levelPath) do
					local distSq = (lp.X - trunkPoint.X)^2 + (lp.Z - trunkPoint.Z)^2
					if distSq < minDistSqXZ then
						minDistSqXZ = distSq
						closestLevelPoint = lp
					end
				end

				local shaftRadiusStuds = localRandomFloat(shaftRadiusStuds_MinMax.min, shaftRadiusStuds_MinMax.max)
				local shaftRadiusCells = math.max(2, math.floor(shaftRadiusStuds / cellSize))

				-- Shaft Point 1 (on main trunk, or slightly offset if needed)
				local shaftP1 = trunkPoint
				-- Shaft Point 2 (on new level trunk, adjusted Y from closestLevelPoint if needed)
				local shaftP2 = Vector3.new(closestLevelPoint.X, closestLevelPoint.Y, closestLevelPoint.Z)
				-- Ensure P1 is lower than P2 if shafting up, or vice-versa, just for consistent carving logic if it mattered.
				-- Here, _carveCylinderGrid handles arbitrary p1,p2.

				Logger:Debug("Phase0B_MultiLevel", "Shaft %d for %s: TrunkPt(%s) to LevelPt(%s), R_studs:%.1f",
					shaftsToThisLevelMade + 1, levelData.name, tostring(shaftP1), tostring(shaftP2), shaftRadiusStuds)

				_carveCylinderGrid(grid, shaftP1, shaftP2, shaftRadiusCells, AIR)

				-- Blending "lips"
				local blendRadiusCells = math.max(shaftRadiusCells, math.floor(shaftRadiusCells * shaftBlendRadiusFactor))
				_carveSphereGrid(grid, shaftP1.X, shaftP1.Y, shaftP1.Z, blendRadiusCells, AIR)
				_carveSphereGrid(grid, shaftP2.X, shaftP2.Y, shaftP2.Z, blendRadiusCells, AIR)

				shaftsToThisLevelMade = shaftsToThisLevelMade + 1
				doYield()
			end
			Logger:Info("Phase0B_MultiLevel", "%d shafts made to %s level.", shaftsToThisLevelMade, levelData.name)
		end
	end

	-- Optionally, add newLevelPaths to skeletonData if other phases might use them
	-- For now, they are just carved.
	if not skeletonDataReceived.extraLevelPaths then skeletonDataReceived.extraLevelPaths = {} end
	for _, levelData in ipairs(newLevelPaths) do
		table.insert(skeletonDataReceived.extraLevelPaths, levelData)
	end

	Logger:Info("Phase0B_MultiLevel", "Multi-Level Generation Finished! Time: %.2fs", os.clock() - startTime)
	return skeletonDataReceived -- Return the (potentially modified) skeletonData
end

local function Phase_VaryPassageWidths(skeletonDataReceived)
	Logger:Info("Phase_VaryPassageWidths", "Starting Passage Variation (Pinch-Points)...")
	local startTime = os.clock()

	if not skeletonDataReceived then
		Logger:Warn("Phase_VaryPassageWidths", "Skeleton data is NIL. Skipping.")
		return skeletonDataReceived
	end

	-- Parameters (Move to CaveConfig later)
	local pinchChancePerTunnel = 0.3 -- Chance each major tunnel part gets a pinch
	local numPinchesPerSelectedTunnel = localRandomInt(1, 2)
	local pinchLengthStuds_MinMax = {min = 10, max = 20} -- Length of the pinched segment
	-- How much smaller the radius becomes (in cells). 1 means radius shrinks by 1 cell.
	local pinchRadiusReductionCells_MinMax = {min = 1, max = 1} -- For main tunnels. Can be {1,2} for more aggressive.
	-- Ensure originalRadius - reduction >= 1
	local pinchBlendRadiusFactor = 1.2 -- Blend sphere is pinchRadius * this factor

	local allPathsToProcess = {}
	if skeletonDataReceived.trunkPath and #skeletonDataReceived.trunkPath > 0 then
		table.insert(allPathsToProcess, {path = skeletonDataReceived.trunkPath, type = "Trunk"})
	end
	if skeletonDataReceived.branchPaths then
		for i, p in ipairs(skeletonDataReceived.branchPaths) do
			if p and #p > 0 then table.insert(allPathsToProcess, {path = p, type = "Branch"..i}) end
		end
	end
	if skeletonDataReceived.extraLevelPaths then -- From multi-level
		for i, levelData in ipairs(skeletonDataReceived.extraLevelPaths) do
			if levelData and levelData.path and #levelData.path > 0 then
				table.insert(allPathsToProcess, {path = levelData.path, type = levelData.name.."_LevelTrunk"})
			end
		end
	end
	if skeletonDataReceived.loopConnectorPaths then -- (If we add this to skeletonData from Phase0A)
		for i, p in ipairs(skeletonDataReceived.loopConnectorPaths) do
			if p and #p > 0 then table.insert(allPathsToProcess, {path = p, type = "LoopConnector"..i}) end
		end
	end
	-- Not doing spurs for now, they are already thin.

	local pinchesMadeTotal = 0

	for _, pathData in ipairs(allPathsToProcess) do
		local currentPath = pathData.path
		local pathType = pathData.type
		if #currentPath < 5 then continue end -- Path too short for meaningful pinch

		if localRandomChance(pinchChancePerTunnel) then
			for pinchAttempt = 1, numPinchesPerSelectedTunnel do
				-- Select a random segment (sequence of points) along this path for the pinch
				local pinchLengthStuds = localRandomFloat(pinchLengthStuds_MinMax.min, pinchLengthStuds_MinMax.max)
				local pinchLengthCells = pinchLengthStuds / cellSize

				-- Determine approximate number of path segments for this pinch length
				-- Assumes path segments are somewhat uniform in length (e.g. ~3.75 cells from _generateWindingPath)
				local avgSegLenCells = 3.75 -- Estimate, or calculate from path
				local numSegmentsForPinch = math.max(2, math.ceil(pinchLengthCells / avgSegLenCells))

				if #currentPath < numSegmentsForPinch + 2 then continue end -- Not enough segments in path

				local pinchStartIndex = localRandomInt(2, #currentPath - numSegmentsForPinch - 1)
				local pinchEndIndex = pinchStartIndex + numSegmentsForPinch

				if not currentPath[pinchStartIndex] or not currentPath[pinchEndIndex] then
					Logger:Warn("Phase_VaryPassageWidths", "Invalid indices for pinch on %s.", pathType)
					continue
				end

				local p_start_pinch = currentPath[pinchStartIndex]
				local p_end_pinch = currentPath[pinchEndIndex]

				-- Estimate original radius. This is tricky as it varied.
				-- For now, let's assume a typical original radius for that path type.
				-- Trunk/Levels: 2-3 cells. Branches: 2 cells. Loops: 1-2 cells.
				-- This needs better passing of original radius data OR re-estimation based on nearby cells.
				-- Let's just use a default for now and make the pinch absolute.
				local assumedOriginalRadiusCells = 2
				if string.find(pathType, "Trunk") then assumedOriginalRadiusCells = 3 end

				local radiusReduction = localRandomInt(pinchRadiusReductionCells_MinMax.min, pinchRadiusReductionCells_MinMax.max)
				local pinchFinalRadiusCells = math.max(1, assumedOriginalRadiusCells - radiusReduction)

				-- Step 1: Fill the segment SOLID to create the constriction "walls"
				-- The fill radius should be based on assumedOriginalRadiusCells
				Logger:Debug("Phase_VaryPassageWidths", "Pinching %s: Seg %d-%d. OrigR_est:%d, PinchR:%d",
					pathType, pinchStartIndex, pinchEndIndex, assumedOriginalRadiusCells, pinchFinalRadiusCells)

				for i = pinchStartIndex, pinchEndIndex -1 do
					if not currentPath[i] or not currentPath[i+1] then break end
					-- Fill slightly wider than original to ensure it connects to existing walls
					_carveCylinderGrid(grid, currentPath[i], currentPath[i+1], assumedOriginalRadiusCells + 1, SOLID)
				end
				doYield()

				-- Step 2: Re-carve the narrower AIR passage through the SOLID block
				for i = pinchStartIndex, pinchEndIndex -1 do
					if not currentPath[i] or not currentPath[i+1] then break end
					_carveCylinderGrid(grid, currentPath[i], currentPath[i+1], pinchFinalRadiusCells, AIR)
				end
				pinchesMadeTotal = pinchesMadeTotal + 1
				doYield()

				-- Blending: Carve spheres at the start and end of the pinched segment
				local blendRadiusCells = math.max(pinchFinalRadiusCells + 1, math.floor(pinchFinalRadiusCells * pinchBlendRadiusFactor))
				if currentPath[pinchStartIndex-1] then -- Blend with previous segment if exists
					_carveSphereGrid(grid, p_start_pinch.X, p_start_pinch.Y, p_start_pinch.Z, blendRadiusCells, AIR)
				end
				if currentPath[pinchEndIndex+1] then -- Blend with next segment if exists
					_carveSphereGrid(grid, p_end_pinch.X, p_end_pinch.Y, p_end_pinch.Z, blendRadiusCells, AIR)
				end
			end
		end
	end

	Logger:Info("Phase_VaryPassageWidths", "%d Pinch-Points created. Finished! Time: %.2fs", pinchesMadeTotal, os.clock() - startTime)
	return skeletonDataReceived -- Return skeletonData, possibly unchanged in structure but grid is modified
end

local function Phase_CarveChambers(skeletonDataReceived)
	Logger:Info("Phase_CarveChambers", "Starting Chamber and Dome Generation...")
	local startTime = os.clock()

	if not skeletonDataReceived then
		Logger:Warn("Phase_CarveChambers", "Skeleton data is NIL. Skipping chamber generation.")
		Logger:Info("Phase_CarveChambers", "Finished (skipped due to NIL data)! Time: %.2fs", os.clock() - startTime)
		return
	end
	if not skeletonDataReceived.trunkPath or (#skeletonDataReceived.trunkPath == 0 and (#skeletonDataReceived.branchPaths == 0 or not skeletonDataReceived.branchPaths)) then
		Logger:Warn("Phase_CarveChambers", "Skeleton data missing trunkPath (or it's empty) AND no branchPaths. Skipping chamber generation.")
		Logger:Info("Phase_CarveChambers", "Finished (skipped due to insufficient path data)! Time: %.2fs", os.clock() - startTime)
		return
	end
	if not skeletonDataReceived.branchPaths then
		Logger:Warn("Phase_CarveChambers", "Skeleton data branchPaths is NIL. Some chamber logic might rely on it.")
		-- We can proceed but primary hall anchor choices will be limited.
	end

	local numPrimaryHalls = localRandomInt(2, 3)
	local primaryHallRadiusStuds_MinMax = {min = 15, max = 20}
	local numSecondaryChambersPerBranch = localRandomInt(0, 2) 
	local secondaryChamberRadiusStuds_MinMax = {min = 8, max = 12}

	local mainTrunkPath = skeletonDataReceived.trunkPath or {} -- Use empty table if nil, though above check should catch it
	local allPrimaryBranchPaths = skeletonDataReceived.branchPaths or {} -- Use empty table if nil

	Logger:Debug("Phase_CarveChambers", "Received skeleton data. Trunk points: %d, Branch path sets: %d",
		#mainTrunkPath, #allPrimaryBranchPaths)
	if #allPrimaryBranchPaths > 0 then
		if allPrimaryBranchPaths[1] and #allPrimaryBranchPaths[1] > 0 then
			Logger:Debug("Phase_CarveChambers", "First branch path received in Phase1 has %d points.", #allPrimaryBranchPaths[1])
		else
			Logger:Debug("Phase_CarveChambers", "First branch path in list received in Phase1 is empty or nil.")
		end
	else
		Logger:Debug("Phase_CarveChambers", "No branch paths collected/received or branchPaths table is empty.")
	end

	-- Logic for Primary Halls
	Logger:Debug("Phase_CarveChambers", "Attempting to create %d primary halls.", numPrimaryHalls)
	local potentialHallAnchors = {}

	if #allPrimaryBranchPaths > 0 then
		for _, branchPath_table in ipairs(allPrimaryBranchPaths) do
			if branchPath_table and #branchPath_table > 0 then
				table.insert(potentialHallAnchors, branchPath_table[1]) 
			end
		end
		Logger:Debug("Phase_CarveChambers", "Collected %d branch starting points as potential hall anchors.", #potentialHallAnchors)
	end

	if #potentialHallAnchors == 0 and #mainTrunkPath > 2 then
		Logger:Debug("Phase_CarveChambers", "No/few branch start points from branchPaths, using trunk mid-points as fallback for halls.")
		local firstTrunkAnchor = math.max(1, math.floor(#mainTrunkPath * 0.2))
		local lastTrunkAnchor = math.min(#mainTrunkPath, math.floor(#mainTrunkPath * 0.8))
		if lastTrunkAnchor >= firstTrunkAnchor then
			for i = firstTrunkAnchor, lastTrunkAnchor do
				if mainTrunkPath[i] then
					table.insert(potentialHallAnchors, mainTrunkPath[i])
				end
			end
		end
		Logger:Debug("Phase_CarveChambers", "Collected %d fallback trunk points as potential hall anchors.", #potentialHallAnchors)
	end

	if #potentialHallAnchors > 0 then
		localShuffleTable(potentialHallAnchors)
		local hallsCreated = 0
		for i = 1, math.min(numPrimaryHalls, #potentialHallAnchors) do
			local hallCenterPoint = potentialHallAnchors[i]
			if not hallCenterPoint then 
				Logger:Warn("Phase_CarveChambers", "Hall center point is nil for primary hall attempt %d. Index was %d.", hallsCreated + 1, i)
				continue
			end

			local hallRadiusStuds = localRandomFloat(primaryHallRadiusStuds_MinMax.min, primaryHallRadiusStuds_MinMax.max)
			local hallRadiusCells = math.max(1, math.floor(hallRadiusStuds / cellSize))

			Logger:Debug("Phase_CarveChambers", "Creating Primary Hall %d at (%s) R_studs: %.1f (R_cells: %d)",
				hallsCreated + 1, tostring(hallCenterPoint), hallRadiusStuds, hallRadiusCells)

			_carveSphereGrid(grid, hallCenterPoint.X, hallCenterPoint.Y, hallCenterPoint.Z, hallRadiusCells, AIR)
			hallsCreated = hallsCreated + 1
			doYield()
		end
		Logger:Info("Phase_CarveChambers", "%d Primary Halls created.", hallsCreated)
	else
		Logger:Warn("Phase_CarveChambers", "No potential anchor points found for primary halls.")
	end

	-- Logic for Secondary Chambers
	Logger:Debug("Phase_CarveChambers", "Attempting secondary chambers on %d primary branches.", #allPrimaryBranchPaths)
	if #allPrimaryBranchPaths > 0 then
		local secChambersMade = 0
		for branchIdx, branchPath_table in ipairs(allPrimaryBranchPaths) do 
			if numSecondaryChambersPerBranch > 0 and branchPath_table and #branchPath_table > 3 then
				for _ = 1, numSecondaryChambersPerBranch do
					local pointIndexOnBranch = localRandomInt(math.max(2, math.floor(#branchPath_table * 0.2)), math.min(#branchPath_table - 1, math.floor(#branchPath_table * 0.8)))
					if pointIndexOnBranch > 0 and pointIndexOnBranch <= #branchPath_table and branchPath_table[pointIndexOnBranch] then
						local chamberCenterPoint = branchPath_table[pointIndexOnBranch]
						local chamberRadiusStuds = localRandomFloat(secondaryChamberRadiusStuds_MinMax.min, secondaryChamberRadiusStuds_MinMax.max)
						local chamberRadiusCells = math.max(1, math.floor(chamberRadiusStuds / cellSize))

						Logger:Debug("Phase_CarveChambers", "Creating Secondary Chamber on branch %d (path index %d) at (%s) R_studs: %.1f (R_cells: %d)",
							branchIdx, pointIndexOnBranch, tostring(chamberCenterPoint), chamberRadiusStuds, chamberRadiusCells)

						_carveSphereGrid(grid, chamberCenterPoint.X, chamberCenterPoint.Y, chamberCenterPoint.Z, chamberRadiusCells, AIR)
						secChambersMade = secChambersMade + 1
						doYield()
					else
						Logger:Warn("Phase_CarveChambers", "Invalid pointIndexOnBranch or point for sec chamber on branch path %d.", branchIdx)
					end
				end
			end
		end
		Logger:Info("Phase_CarveChambers", "%d Secondary Chambers created.", secChambersMade)
	end

	Logger:Info("Phase_CarveChambers", "Chamber and Dome Generation Finished! Total Time: %.2fs", os.clock() - startTime)
end

local function Phase_MesoDetailing(skeletonDataReceived) -- May or may not need skeletonData
	Logger:Info("Phase_MesoDetailing", "Starting Meso Detailing (Scallops & Pockets)...")
	local startTime = os.clock()

	-- Parameters (Move to CaveConfig later)
	local scallopChance = 0.05 -- Chance per valid surface cell to attempt a scallop
	local scallopRadiusStuds_MinMax = {min = 1, max = 2}
	local scallopDepthFactor = 0.5 -- How deep into the wall the scallop center is (0.5 = halfway in)

	-- Get all SOLID cells that form CEILINGS or upper WALLS
	-- Ceilings: SOLID cell with AIR above it. surfaceType = "Ceiling"
	-- Walls: SOLID cell with AIR to its X/Z side. surfaceType = "WallPX", "WallNX", "WallPZ", "WallNZ"

	-- This will get ALL solid surface cells. We will filter them.
	local allSolidSurfaceCells = _getSurfaceCellsInfo(grid, SOLID, AIR)
	Logger:Debug("Phase_MesoDetailing", "Found %d raw solid surface cell faces.", #allSolidSurfaceCells)

	local scallopCandidateSurfaces = {}
	for _, surfInfo in ipairs(allSolidSurfaceCells) do
		-- We want ceilings (SOLID is below AIR, normal points UP)
		-- and upper walls. For upper walls, we need a height check.
		-- For now, let's include all walls and ceilings.
		-- 'Ceiling' type means the SOLID cell at surfInfo.pos is *forming* the ceiling.
		-- 'WallPX' etc. means the SOLID cell at surfInfo.pos is *forming* a wall.
		if surfInfo.surfaceType == "Ceiling" or 
			string.sub(surfInfo.surfaceType, 1, 4) == "Wall" then
			-- Optional: Add height check for walls to only do "upper walls"
			-- local worldY = origin.Y + (surfInfo.pos.Y - 0.5) * cellSize
			-- if worldY is in the upper half of a passage, etc.
			table.insert(scallopCandidateSurfaces, surfInfo)
		end
	end
	Logger:Debug("Phase_MesoDetailing", "Filtered to %d ceiling/wall surface cell faces for scallops.", #scallopCandidateSurfaces)

	local scallopsCarved = 0
	if #scallopCandidateSurfaces > 0 then
		for _, surfInfo in ipairs(scallopCandidateSurfaces) do
			if localRandomChance(scallopChance) then
				local scallopRadiusStuds = localRandomFloat(scallopRadiusStuds_MinMax.min, scallopRadiusStuds_MinMax.max)
				local scallopRadiusCells = math.max(1, math.ceil(scallopRadiusStuds / cellSize)) -- Use ceil for slightly larger impact

				-- Center of the scallop sphere should be INSIDE the solid wall/ceiling
				-- surfInfo.pos is the SOLID surface cell. surfInfo.normal points into AIR.
				-- We want to carve from surfInfo.pos IN THE OPPOSITE DIRECTION of surfInfo.normal (into the solid).
				local carveCenter = surfInfo.pos - surfInfo.normal * (scallopRadiusCells * scallopDepthFactor)

				Logger:Trace("Phase_MesoDetailing", "Scallop at SOLID %s (normal %s, type %s). Carve R:%d at %s",
					tostring(surfInfo.pos), tostring(surfInfo.normal), surfInfo.surfaceType,
					scallopRadiusCells, tostring(carveCenter))

				_carveSphereGrid(grid, math.round(carveCenter.X), math.round(carveCenter.Y), math.round(carveCenter.Z),
					scallopRadiusCells, AIR)
				scallopsCarved = scallopsCarved + 1
				if scallopsCarved % 100 == 0 then doYield() end
			end
		end
	end

	Logger:Info("Phase_MesoDetailing", "Starting Overhang Ledge Generation...")

	-- Parameters for Ledges (Move to CaveConfig later)
	local ledgeChancePerWallSurface = 0.02 -- Lower chance than scallops
	local ledgeRadiusStuds_MinMax = {min = 2, max = 4}
	local ledgeProtrusionFactor = 0.75 -- Center of sphere is this * radius out from wall
	-- For filtering "high on walls"
	local minLedgeHeightAboveFloorGuessCells = 3 -- Ledge must be at least this many cells above a guessed floor

	local ledgesMade = 0
	-- We iterate through scallopCandidateSurfaces which already contains walls and ceilings.
	-- We only want walls for ledges.

	for _, surfInfo in ipairs(scallopCandidateSurfaces) do -- Uses the same filtered list as scallops
		if string.sub(surfInfo.surfaceType, 1, 4) == "Wall" then -- Only consider wall surfaces
			if localRandomChance(ledgeChancePerWallSurface) then

				-- Basic height check: is this wall cell "high enough"?
				-- This is a rough guess. A better way would be to find the actual floor below.
				local isHighEnough = true 
				-- Check Y coord relative to some passage baseline, or if there's enough AIR below it
				local airBelowCount = 0
				for y_check = 1, minLedgeHeightAboveFloorGuessCells do
					if grid:get(surfInfo.pos.X, surfInfo.pos.Y - y_check, surfInfo.pos.Z) == AIR then
						airBelowCount = airBelowCount + 1
					else
						break -- Hit solid floor
					end
				end
				if airBelowCount < minLedgeHeightAboveFloorGuessCells then
					isHighEnough = false
				end

				if not isHighEnough then
					-- Logger:Trace("Phase_MesoDetailing_Ledge", "Skipping ledge at %s, not high enough.", tostring(surfInfo.pos))
					continue
				end

				local ledgeRadiusStuds = localRandomFloat(ledgeRadiusStuds_MinMax.min, ledgeRadiusStuds_MinMax.max)
				local ledgeRadiusCells = math.max(1, math.ceil(ledgeRadiusStuds / cellSize))

				-- Ledge sphere center: start at the SOLID wall cell, move OUTWARDS into AIR
				-- surfInfo.normal points from SOLID into AIR.
				local ledgeCenter = surfInfo.pos + surfInfo.normal * (ledgeRadiusCells * ledgeProtrusionFactor)

				Logger:Debug("Phase_MesoDetailing_Ledge", "Attempting Ledge at SOLID wall %s (normal %s). LedgeCenter %s, R_cells:%d",
					tostring(surfInfo.pos), tostring(surfInfo.normal), tostring(ledgeCenter), ledgeRadiusCells)

				-- Add a SOLID sphere to form the ledge
				_carveSphereGrid(grid, math.round(ledgeCenter.X), math.round(ledgeCenter.Y), math.round(ledgeCenter.Z),
					ledgeRadiusCells, SOLID) 
				ledgesMade = ledgesMade + 1

				-- Blending the underside is more complex; skip for first pass.
				-- It would involve finding the bottom surface cells of this new ledge and carving AIR.

				if ledgesMade % 20 == 0 then doYield() end
			end
		end
	end
	Logger:Info("Phase_MesoDetailing", "%d Overhang Ledges created.", ledgesMade)


	Logger:Info("Phase_MesoDetailing", "Meso Detailing Finished! Scallops: %d, Ledges: %d. Time: %.2fs", scallopsCarved, ledgesMade, os.clock() - startTime)
	return skeletonDataReceived 
end

local function Phase_InitialNoiseCarve()
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
	Logger:Debug("_createFormation_Enter", "Start (%d,%d,%d), Type: %s", startX,startY,startZ,type) -- Keep Enter

	local length_cf=localRandomInt(CaveConfig.MinFormationLength_Cells,CaveConfig.MaxFormationLength_Cells)
	-- Ensure no temporary hardcodes are left for length_cf or rCells_cf unless specifically testing them
	Logger:Debug("_createFormation_Params", "Length_cf: %d, Type: %s", length_cf, type) -- Keep Params

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

	local totalCellsSetForThisFormation = 0 -- Track total for this one formation

	for i_cf=0,length_cf-1 do 
		local curY_cf=startY+i_cf*dirY_cf
		-- Logger:Debug("_createFormation_Loop", "i_cf: %d, curY: %d", i_cf, curY_cf) -- Maybe remove this or make TRACE

		if not grid:isInBounds(startX,curY_cf,startZ) then 
			-- Logger:Debug("_createFormation_Loop", "Centerline out of bounds. Breaking.")
			break 
		end
		if type~="column" and i_cf>0 and grid:get(startX,curY_cf,startZ)==SOLID then 
			-- Logger:Debug("_createFormation_Loop", "Hit existing SOLID on centerline. Breaking.")
			break 
		end

		local radFactor_cf
		if type=="column"then 
			local prog_cf=0
			if length_cf>1 then prog_cf=math.abs((i_cf/(length_cf-1))-.5)*2 end
			radFactor_cf=1-prog_cf*.3 
		else 
			radFactor_cf=(length_cf-i_cf)/length_cf 
		end
		local bRad_cf=CaveConfig.BaseFormationRadius_Factor
		-- Logger:Debug("_createFormation_RadiusCalc", "bRad_cf: %.2f, radFactor_cf: %.2f", bRad_cf, radFactor_cf) -- Maybe remove

		if type=="column" then bRad_cf=bRad_cf*1.2 end
		local rCells_cf=math.max(0,math.floor(bRad_cf*radFactor_cf))
		-- Logger:Debug("_createFormation_RadiusCalc", "Final rCells_cf: %d", rCells_cf) -- Maybe remove

		if type=="column" and length_cf<=2 then rCells_cf=math.max(0,math.floor(bRad_cf*.8))end 

		local cellsSetThisYLevel = 0
		for r_cf=0,rCells_cf do 
			for dx_cf=-r_cf,r_cf do 
				for dz_cf=-r_cf,r_cf do 
					if math.sqrt(dx_cf*dx_cf+dz_cf*dz_cf)<=r_cf+.5 then 
						local nx_cf,nz_cf=startX+dx_cf,startZ+dz_cf
						if grid:isInBounds(nx_cf,curY_cf,nz_cf) then 
							if grid:get(nx_cf,curY_cf,nz_cf) == AIR then
								grid:set(nx_cf,curY_cf,nz_cf,SOLID) 
								cellsSetThisYLevel = cellsSetThisYLevel + 1
								-- Logger:Trace("_createFormation_Set", ...) -- REMOVE THIS TRACE
							end
						end
					end 
				end 
			end 
		end 

		if rCells_cf==0 then 
			if grid:isInBounds(startX,curY_cf,startZ) then
				local currentValue = grid:get(startX,curY_cf,startZ)
				-- Logger:Trace("_createFormation_CenterCheck", "Cell (%d,%d,%d) value BEFORE set for centerline (rCells_cf=0) is: %s", startX,curY_cf,startZ, tostring(currentValue)) -- REMOVE OR MAKE TRACE
				if currentValue == AIR then
					grid:set(startX,curY_cf,startZ,SOLID) 
					cellsSetThisYLevel = cellsSetThisYLevel + 1
					-- Logger:Trace("_createFormation_SetCenter", ...) -- REMOVE THIS TRACE
				end
			end
		end
		totalCellsSetForThisFormation = totalCellsSetForThisFormation + cellsSetThisYLevel
		-- Logger:Debug("_createFormation_LoopEnd", "Y-level %d. Cells set this Y-level: %d", curY_cf, cellsSetThisYLevel) -- Maybe remove or make TRACE
		doYield()
	end 
	Logger:Debug("_createFormation_Exit", "EXITED: Start (%d,%d,%d), Type: %s. Total cells set for this one: %d", startX,startY,startZ,type, totalCellsSetForThisFormation) -- Keep Exit, add total count
end

local function Phase_GrowRockFormations(skeletonDataReceived) 
	Logger:Info("Phase_GrowRockFormations", "Starting rock formations...") 
	-- Optional: Add the ConfigSnapshot log here if you want to verify config values at runtime
	-- Logger:Info("Phase_GrowRockFormations_ConfigSnapshot", "BaseRadiusFactor: %.3f, ... MinDistTunnel: %d",
	--    CaveConfig.BaseFormationRadius_Factor, ..., CaveConfig.FormationMinDistanceFromTunnel_Cells)

	local sTime=os.clock()
	local pSpots={}
	local cForms={s=0,m=0,c=0}

	local MIN_HORIZONTAL_AIR_NEIGHBORS = CaveConfig.FormationHorizontalMinAirNeighbors or 4
	local MIN_DISTANCE_FROM_SKELETON_CELLS = CaveConfig.FormationMinDistanceFromTunnel_Cells or 0 

	local function isTooCloseToSkeleton(checkPosVec3, skeletonData, minDistanceCells)
		if not skeletonData or minDistanceCells <= 0 then return false end
		local minDistanceSq = minDistanceCells * minDistanceCells
		local pathsToConsider = {}
		if skeletonData.trunkPath and #skeletonData.trunkPath > 0 then table.insert(pathsToConsider, skeletonData.trunkPath) end
		if skeletonData.branchPaths then
			for _, p in ipairs(skeletonData.branchPaths) do if p and #p > 0 then table.insert(pathsToConsider, p) end end
		end
		if skeletonData.spurPaths then 
			for _, p in ipairs(skeletonData.spurPaths) do if p and #p > 0 then table.insert(pathsToConsider, p) end end
		end
		if skeletonData.extraLevelPaths then 
			for _, levelData in ipairs(skeletonData.extraLevelPaths) do
				if levelData and levelData.path and #levelData.path > 0 then table.insert(pathsToConsider, levelData.path) end
			end
		end
		if #pathsToConsider == 0 then return false end 
		for _, path in ipairs(pathsToConsider) do
			for _, pointOnPath in ipairs(path) do
				local differenceVector = pointOnPath - checkPosVec3
				local distSq = differenceVector.X^2 + differenceVector.Y^2 + differenceVector.Z^2 
				-- Or alternatively: local distSq = differenceVector:Dot(differenceVector)
				if distSq < minDistanceSq then
					return true 
				end
			end
		end
		return false 
	end

	for z_p2=2,gridSizeZ-1 do 
		for x_p2=2,gridSizeX-1 do 
			for y_p2=CaveConfig.FormationStartHeight_Cells+1,gridSizeY-1 do 
				doYield()

				local canProceedWithSpot = false -- Flag to control flow instead of goto
				if grid:get(x_p2,y_p2,z_p2)==AIR then 
					local currentSpotPos = Vector3.new(x_p2, y_p2, z_p2) 

					if not isTooCloseToSkeleton(currentSpotPos, skeletonDataReceived, MIN_DISTANCE_FROM_SKELETON_CELLS) then
						canProceedWithSpot = true
						-- else
						-- Logger:Trace("Phase_GrowRockFormations_PathSkip", "Skipped spot (%d,%d,%d) - too close to a skeleton path.",x_p2,y_p2,z_p2)
					end
				end

				if canProceedWithSpot then
					local rA_isSolidAnchor = grid:get(x_p2,y_p2+1,z_p2)==SOLID 
					local rB_isSolidAnchor = grid:get(x_p2,y_p2-1,z_p2)==SOLID 

					local clA_hasVerticalClearance, clB_hasVerticalClearance = true,true
					for i_cl=1,CaveConfig.FormationClearance_Cells do 
						if not grid:isInBounds(x_p2,y_p2-i_cl,z_p2) or grid:get(x_p2,y_p2-i_cl,z_p2)==SOLID then 
							clA_hasVerticalClearance=false; break 
						end 
					end 
					for i_cl=1,CaveConfig.FormationClearance_Cells do 
						if not grid:isInBounds(x_p2,y_p2+i_cl,z_p2) or grid:get(x_p2,y_p2+i_cl,z_p2)==SOLID then 
							clB_hasVerticalClearance=false; break 
						end 
					end

					local function hasSufficientHorizontalClearance(x, y, z, minAirNeighbors)
						local airNeighborCount = 0
						local horizontalNeighbors = {
							{1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1},
							{1,0,1}, {-1,0,1}, {1,0,-1}, {-1,0,-1} 
						}
						for _, d in ipairs(horizontalNeighbors) do
							if grid:isInBounds(x+d[1], y, z+d[3]) and grid:get(x+d[1], y, z+d[3]) == AIR then 
								airNeighborCount = airNeighborCount + 1
							end
						end
						return airNeighborCount >= minAirNeighbors
					end

					if rA_isSolidAnchor and clA_hasVerticalClearance then
						if hasSufficientHorizontalClearance(x_p2, y_p2, z_p2, MIN_HORIZONTAL_AIR_NEIGHBORS) then
							table.insert(pSpots,{x=x_p2,y=y_p2,z=z_p2,type="stalactite"}) 
						end
					end

					if rB_isSolidAnchor and clB_hasVerticalClearance then
						if hasSufficientHorizontalClearance(x_p2, y_p2, z_p2, MIN_HORIZONTAL_AIR_NEIGHBORS) then
							table.insert(pSpots,{x=x_p2,y=y_p2,z=z_p2,type="stalagmite"}) 
						end
					end

					if rA_isSolidAnchor and rB_isSolidAnchor then 
						local fY,cY=y_p2,y_p2
						while grid:isInBounds(x_p2,fY-1,z_p2) and grid:get(x_p2,fY-1,z_p2)==AIR do fY=fY-1 end
						while grid:isInBounds(x_p2,cY+1,z_p2) and grid:get(x_p2,cY+1,z_p2)==AIR do cY=cY+1 end
						local actFY,actCY=fY-1,cY+1
						if grid:isInBounds(x_p2,actFY,z_p2) and grid:get(x_p2,actFY,z_p2)==SOLID and 
							grid:isInBounds(x_p2,actCY,z_p2) and grid:get(x_p2,actCY,z_p2)==SOLID then
							local airH=actCY-actFY-1
							if airH>=CaveConfig.MinColumnHeight_Cells then 
								if hasSufficientHorizontalClearance(x_p2, y_p2, z_p2, MIN_HORIZONTAL_AIR_NEIGHBORS) then
									local columnMidPointForCheck = Vector3.new(x_p2, math.floor((fY+cY)/2), z_p2)
									if not isTooCloseToSkeleton(columnMidPointForCheck, skeletonDataReceived, MIN_DISTANCE_FROM_SKELETON_CELLS) then
										table.insert(pSpots,{x=x_p2,y=columnMidPointForCheck.Y,z=z_p2,type="column",floorCellY=fY,ceilCellY=cY})
										-- else
										-- Logger:Trace("Phase_GrowRockFormations_PathSkip", "Skipped COLUMN spot (%d,%f,%d) - too close to skeleton.", x_p2, columnMidPointForCheck.Y, z_p2)
									end
								end
							end 
						end 
					end 
				end -- End of if canProceedWithSpot
			end 
		end 
	end 
	Logger:Info("Phase_GrowRockFormations_Debug", "Found %d potential formation spots (after horizontal and skeleton proximity clearance).", #pSpots)
	localShuffleTable(pSpots)

	local fAtt=0
	local formationsToCreateLimit = math.max(1, math.min(10, math.floor(#pSpots * 0.25)))
	Logger:Debug("Phase_GrowRockFormations_LimitSet", "Formation create limit set to: %d (based on %d spots * 0.05)", formationsToCreateLimit, #pSpots)
	local actualFormationsMadeThisRun = 0

	for _,spt in ipairs(pSpots) do 
		if actualFormationsMadeThisRun >= formationsToCreateLimit then 
			Logger:Debug("Phase_GrowRockFormations_Debug", "Reached formationsToCreateLimit of %d. Stopping.", formationsToCreateLimit)
			break 
		end

		fAtt=fAtt+1
		Logger:Debug("Phase_GrowRockFormations_SPOT_DETAILS", "Processing Spot #%d: Type=%s, Coords=(%d,%d,%d). StalacChance=%.2f, StalagChance=%.2f, ColChance=%.2f", 
			fAtt, spt.type, spt.x, spt.y, spt.z, CaveConfig.StalactiteChance, CaveConfig.StalagmiteChance, CaveConfig.ColumnChance)
		if spt.type=="stalactite" and localRandomChance(CaveConfig.StalactiteChance) then 
			Logger:Debug("Phase_GrowRockFormations_Debug", "Attempting ONE stalactite at %d,%d,%d", spt.x,spt.y,spt.z)
			_createFormation(spt.x,spt.y,spt.z,"stalactite",nil);cForms.s=cForms.s+1
			actualFormationsMadeThisRun = actualFormationsMadeThisRun + 1 
		elseif spt.type=="stalagmite" and localRandomChance(CaveConfig.StalagmiteChance) then 
			Logger:Debug("Phase_GrowRockFormations_Debug", "Attempting ONE stalagmite at %d,%d,%d", spt.x,spt.y,spt.z)
			_createFormation(spt.x,spt.y,spt.z,"stalagmite",nil);cForms.m=cForms.m+1
			actualFormationsMadeThisRun = actualFormationsMadeThisRun + 1
		elseif spt.type=="column" and localRandomChance(CaveConfig.ColumnChance) then 
			if spt.floorCellY and spt.ceilCellY then 
				Logger:Debug("Phase_GrowRockFormations_Debug", "Attempting ONE column at %d,%d,%d", spt.x,spt.y,spt.z) 
				_createFormation(spt.x,spt.floorCellY,spt.z,"column",spt.ceilCellY);cForms.c=cForms.c+1 
				actualFormationsMadeThisRun = actualFormationsMadeThisRun + 1
			else  
				Logger:Warn("Phase_GrowRockFormations_Debug", "Invalid column spot data for attempted creation at (%d,%d,%d), FloorY: %s, CeilY: %s",
					spt.x,spt.y,spt.z, tostring(spt.floorCellY), tostring(spt.ceilCellY))
			end 
		end 
	end 
	Logger:Debug("Phase_GrowRockFormations", "Spots processed up to limit: %d. Actual Formations Created: %d", fAtt, actualFormationsMadeThisRun)
	Logger:Info("Phase_GrowRockFormations", "Created (attempted under limit) S:%d, M:%d, C:%d.",cForms.s,cForms.m,cForms.c)
	local eTime=os.clock()
	Logger:Info("Phase_GrowRockFormations", "Finished! Time: %.2fs", eTime-sTime)
end

local function Phase_ApplySmoothing()
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

local function Phase_EnsureMainConnectivity()
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

local function Phase_CleanupIsolatedAir()
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

local function Phase_CreateSurfaceEntrances()
	Logger:Info("Phase6", "Starting surface entrances...")
	local sTime=os.clock()
	local entrMade_p6=0
	for i_p6e=1,CaveConfig.SurfaceCaveCount do 
		local sx_p6e,sz_p6e,sy_p6e = localRandomInt(3,gridSizeX-2),localRandomInt(3,gridSizeZ-2),gridSizeY-2 
		local cPos_p6e={x=sx_p6e,y=sy_p6e,z=sz_p6e}
		local tY_p6e=CaveConfig.FormationStartHeight_Cells+localRandomInt(3,10)
		local minTunnelLen = CaveConfig.SurfaceCaveTunnelLength_Cells_MinMax.min
		local maxTunnelLen = CaveConfig.SurfaceCaveTunnelLength_Cells_MinMax.max

		if type(minTunnelLen) ~= "number" or type(maxTunnelLen) ~= "number" then
			Logger:Error("Phase6_ConfigErr", "SurfaceCaveTunnelLength_Cells_MinMax.min or .max is nil or not a number! Using defaults. Min: %s, Max: %s", tostring(minTunnelLen), tostring(maxTunnelLen))
			minTunnelLen = 20 -- Default fallback
			maxTunnelLen = 45 -- Default fallback
		end
		local maxL_p6e = localRandomInt(minTunnelLen, maxTunnelLen)
		local len_p6e = 0
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

local function Phase_BuildBridges() 
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

	local YIELD_AGENT_BATCH_SIZE = 2; local agentProcessingCounter = 0 -- More frequent yields 

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
	Logger:Info("RunCaveGen_ENTRY", "RunCaveGeneration function has been entered.")
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

	local skeletonOutputFromPhase0 = nil -- To store data from Phase0

	local phasesToRun={
		{name="Phase_CarveSkeleton",func=Phase_CarveSkeleton,enabled=true},
		{name="Phase_ConnectLoops",func=Phase_ConnectLoops,enabled=true},
		{name="Phase_GenerateMultiLevels",func=Phase_GenerateMultiLevels,enabled=true},
		{name="Phase_VaryPassageWidths",func=Phase_VaryPassageWidths,enabled=true},
		{name="Phase_CarveChambers",func=Phase_CarveChambers,enabled=true},   
		{name="Phase_MesoDetailing",func=Phase_MesoDetailing,enabled=true},
		{name="Phase_GrowRockFormations",func=Phase_GrowRockFormations,enabled=true}, 
		{name="Phase_InitialNoiseCarve",func=Phase_InitialNoiseCarve,enabled=false}, -- Likely keep disabled
		{name="Phase_ApplySmoothing",func=Phase_ApplySmoothing,enabled=true},        
		{name="Phase_EnsureMainConnectivity",func=Phase_EnsureMainConnectivity,enabled=true},
		{name="Phase_CleanupIsolatedAir",func=Phase_CleanupIsolatedAir,enabled=true}, 
		{name="Phase_AgentTunnels", func=Phase_AgentTunnels, enabled=true},   
		{name="Phase_CreateSurfaceEntrances",func=Phase_CreateSurfaceEntrances,enabled=true},
		{name="Phase_BuildBridges",func=Phase_BuildBridges,enabled=true},             
		{name="Phase8_BuildWorld",func=Phase8_BuildWorld,enabled=true}
	}

	for i,phaseInfo in ipairs(phasesToRun) do 
		if phaseInfo.enabled then 
			Logger:Info("RunCaveGen", "--- Starting phase: %s ---", phaseInfo.name)
			local success, resultOrError

			-- Special handling for PRE/POST logging and passing skeleton data
			local preAir, preSolid = -1, -1
			local shouldLogCounts = Logger:IsLevelEnabled(Logger.Levels.DEBUG) and 
					(phaseInfo.name == "Phase_CarveSkeleton" or -- Keep for first major carving
					-- phaseInfo.name == "Phase_CarveChambers" or -- Maybe remove for now
					phaseInfo.name == "Phase_CleanupIsolatedAir" or -- Useful after cleanup
					phaseInfo.name == "Phase_GrowRockFormations") -- Useful for formation deltas

			if shouldLogCounts then
				preAir, preSolid = CountCellTypesInGrid(grid)
				Logger:Debug("RunCaveGen_COUNTS", "PRE-%s: AIR cells = %d, SOLID cells = %d", phaseInfo.name, preAir, preSolid)
			end

			-- Call the phase function
			if phaseInfo.name == "Phase_CarveSkeleton" then
				success, resultOrError = pcall(phaseInfo.func)
				if success then skeletonOutputFromPhase0 = resultOrError 
				else skeletonOutputFromPhase0 = nil end
			elseif phaseInfo.name == "Phase_ConnectLoops" or 
				   phaseInfo.name == "Phase_GenerateMultiLevels" or 
				   phaseInfo.name == "Phase_VaryPassageWidths" or 
				   phaseInfo.name == "Phase_CarveChambers" or
				   phaseInfo.name == "Phase_MesoDetailing" or
				   phaseInfo.name == "Phase_GrowRockFormations" then -- Added GrowRockFormations here
				
				if not skeletonOutputFromPhase0 then 
					Logger:Warn("RunCaveGen", "Skeleton data for %s is nil. Passing nil.", phaseInfo.name)
				end
				success, resultOrError = pcall(phaseInfo.func, skeletonOutputFromPhase0)
				if success and phaseInfo.name == "Phase_GenerateMultiLevels" and resultOrError then
					skeletonOutputFromPhase0 = resultOrError -- Capture potentially modified skeletonData
					Logger:Debug("RunCaveGen", "Phase_GenerateMultiLevels output captured. Extra Level Paths: %d", 
						(skeletonOutputFromPhase0 and skeletonOutputFromPhase0.extraLevelPaths and #skeletonOutputFromPhase0.extraLevelPaths) or 0)
				end
			else 
				success, resultOrError = pcall(phaseInfo.func)
			end

			-- Post-call processing
			if not success then 
				local errMsg = resultOrError 
				Logger:Error("RunCaveGen", "--- ERROR in %s: %s ---", phaseInfo.name, tostring(errMsg))
				if errMsg and type(errMsg)=="string" then 
					Logger:Error("RunCaveGen", "Stack trace for %s:\n%s", phaseInfo.name, debug.traceback(errMsg,2))
				else 
					Logger:Error("RunCaveGen", "Stack trace for %s (non-string error):\n%s", phaseInfo.name, debug.traceback("Error in pcall, no string message.",2))
				end
				errorInPhase=true; break 
			else 
				Logger:Info("RunCaveGen", "--- Finished phase: %s ---", phaseInfo.name)
				if shouldLogCounts then
					local postAir, postSolid = CountCellTypesInGrid(grid)
					local deltaAir = postAir - preAir
					local deltaSolid = postSolid - preSolid
					Logger:Debug("RunCaveGen_COUNTS", "POST-%s: AIR cells = %d, SOLID cells = %d. DELTA_AIR: %d, DELTA_SOLID: %d", 
						phaseInfo.name, postAir, postSolid, deltaAir, deltaSolid)
					
					-- Specific check for Phase_GrowRockFormations delta based on ONE formation
					if phaseInfo.name == "Phase_GrowRockFormations" then
						if deltaSolid < 0 then -- Only warn if it somehow *removes* solid
							Logger:Warn("RunCaveGen_COUNTS", "POST-%s: UNEXPECTED NEGATIVE DELTA_SOLID of %d!", phaseInfo.name, deltaSolid)
						end
						if deltaAir ~= -deltaSolid then
							Logger:Warn("RunCaveGen_COUNTS", "POST-%s: UNEXPECTED DELTA_AIR! Delta Air (%d) is not the negative of Delta Solid (%d). Check logic.", 
								phaseInfo.name, deltaAir, deltaSolid)
						end
					end
				end
			end
		else 
			Logger:Info("RunCaveGen", "--- Skipping phase: %s (not enabled or config missing) ---", phaseInfo.name)
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