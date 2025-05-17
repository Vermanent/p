-- ServerScript: CaveBuilder
-- Path: ServerScriptService/CaveBuilder.lua
-- VERSION 5.2 - Complete implementation of procedural cave generation
-- Integrates with NoiseGenerator and uses CaveConfig settings

local CaveBuilder = {}
CaveBuilder.__index = CaveBuilder

-- Services
local RunService = game:GetService("RunService")

-- Dependencies
local CaveConfig = require(script.Parent.CaveConfig)
local NoiseGenerator = require(script.Parent.NoiseGenerator)

-- Constants and Variables
local Grid3D = {}
Grid3D.__index = Grid3D

local SOLID = 1
local AIR = 0

-- Voxel data structure (3D Grid)
function Grid3D.new(sizeX, sizeY, sizeZ, defaultValue)
	local self = setmetatable({}, Grid3D)
	self.size = Vector3.new(sizeX, sizeY, sizeZ)
	self.data = table.create(sizeX * sizeY * sizeZ, defaultValue or 0)
	return self
end

function Grid3D:index(x, y, z)
	-- Convert 3D coordinates to 1D array index
	if not self:isInBounds(x, y, z) then
		return nil
	end
	return (z - 1) * self.size.X * self.size.Y + (y - 1) * self.size.X + x
end

function Grid3D:get(x, y, z)
	local idx = self:index(x, y, z)
	if not idx then return nil end
	return self.data[idx]
end

function Grid3D:set(x, y, z, value)
	local idx = self:index(x, y, z)
	if not idx then return false end
	self.data[idx] = value
	return true
end

function Grid3D:isInBounds(x, y, z)
	return x >= 1 and x <= self.size.X and
		y >= 1 and y <= self.size.Y and
		z >= 1 and z <= self.size.Z
end

function Grid3D:forEachCell(func)
	-- Iterate through all cells and call func(x, y, z, value)
	for z = 1, self.size.Z do
		for y = 1, self.size.Y do
			for x = 1, self.size.X do
				local idx = self:index(x, y, z)
				func(x, y, z, self.data[idx])
			end
		end
	end
end

function Grid3D:getNeighborCount(x, y, z, cellType)
	local count = 0
	for nx = x-1, x+1 do
		for ny = y-1, y+1 do
			for nz = z-1, z+1 do
				if not (nx == x and ny == y and nz == z) then
					local val = self:get(nx, ny, nz)
					if val == cellType then
						count = count + 1
					end
				end
			end
		end
	end
	return count
end

-- Utility Functions
local function worldToCell(worldPos, origin, cellSize)
	return Vector3.new(
		math.floor((worldPos.X - origin.X) / cellSize) + 1,
		math.floor((worldPos.Y - origin.Y) / cellSize) + 1,
		math.floor((worldPos.Z - origin.Z) / cellSize) + 1
	)
end

local function cellToWorld(cellPos, origin, cellSize)
	return Vector3.new(
		origin.X + (cellPos.X - 1) * cellSize,
		origin.Y + (cellPos.Y - 1) * cellSize,
		origin.Z + (cellPos.Z - 1) * cellSize
	)
end

local function yield()
	if CaveBuilder.yieldCounter >= CaveConfig.GlobalYieldBatchSize then
		RunService.Heartbeat:Wait()
		CaveBuilder.yieldCounter = 0
	else
		CaveBuilder.yieldCounter = CaveBuilder.yieldCounter + 1
	end
end

local function fractalNoise(x, y, z, noiseScale, octaves, persistence, lacunarity)
	-- fractalNoise implementation (FBM)
	return NoiseGenerator.PerlinModule.FBM_Base(
		x * noiseScale, 
		y * noiseScale, 
		z * noiseScale, 
		octaves, 
		persistence, 
		lacunarity, 
		1.0, 
		1.0
	)
end

local function distanceToCenterBias(cellX, cellY, cellZ, gridSizeX, gridSizeZ)
	-- Calculate distance from center as a bias factor
	local centerX, centerZ = gridSizeX / 2, gridSizeZ / 2
	local dx = (centerX - cellX) / centerX
	local dz = (centerZ - cellZ) / centerZ
	local distSqr = dx * dx + dz * dz
	return math.min(math.sqrt(distSqr) * CaveConfig.P1_DistanceBias_Max, CaveConfig.P1_DistanceBias_Max)
end

local function heightBias(cellY, gridSizeY)
	-- Calculate height bias based on cell's Y position
	local normalizedHeight = cellY / gridSizeY

	if normalizedHeight <= CaveConfig.P1_HeightBias_BottomZonePercent then
		return CaveConfig.P1_HeightBias_BottomValue
	elseif normalizedHeight >= CaveConfig.P1_HeightBias_TopZonePercent then
		return CaveConfig.P1_HeightBias_TopValue
	else
		-- Interpolate between bottom and mid zones
		local t = (normalizedHeight - CaveConfig.P1_HeightBias_BottomZonePercent) / 
			(CaveConfig.P1_HeightBias_TopZonePercent - CaveConfig.P1_HeightBias_BottomZonePercent)
		return CaveConfig.P1_HeightBias_BottomValue + 
			t * (CaveConfig.P1_HeightBias_MidFactor - CaveConfig.P1_HeightBias_BottomValue)
	end
end

local function verticalConnectivityNoise(x, y, z, noiseScale)
	-- Vertical connectivity noise to create vertical shafts/connections
	local connScale = noiseScale * CaveConfig.P1_VertConn_NoiseScaleFactor
	return NoiseGenerator:GetValue(x * connScale, z * connScale, 0) * CaveConfig.P1_VertConn_Strength
end

-- Random Utilities
local random = Random.new(CaveConfig.Seed or os.time())
local function randomFloat(min, max)
	return min + random:NextNumber() * (max - min)
end

local function randomInt(min, max)
	return random:NextInteger(min, max)
end

local function randomChance(probability)
	return random:NextNumber() < probability
end

-- Queue data structure for flood fill
local Queue = {}
Queue.__index = Queue
function Queue.new()
	return setmetatable({first = 0, last = -1, data = {}}, Queue)
end

function Queue:push(value)
	self.last = self.last + 1
	self.data[self.last] = value
end

function Queue:pop()
	if self:isEmpty() then return nil end
	local value = self.data[self.first]
	self.data[self.first] = nil
	self.first = self.first + 1
	return value
end

function Queue:isEmpty()
	return self.first > self.last
end

-- Initialize CaveBuilder
function CaveBuilder.new(region, origin)
	local self = setmetatable({}, CaveBuilder)

	self.region = region or CaveConfig.RegionSize
	self.origin = origin or Vector3.new(0, 0, 0)
	self.cellSize = CaveConfig.CellSize

	-- Calculate grid dimensions
	self.gridSizeX = math.ceil(self.region.X / self.cellSize)
	self.gridSizeY = math.ceil(self.region.Y / self.cellSize)
	self.gridSizeZ = math.ceil(self.region.Z / self.cellSize)

	print("CaveBuilder initialized with grid size:", self.gridSizeX, self.gridSizeY, self.gridSizeZ)

	-- Create voxel grid - initially all solid rock
	self.grid = Grid3D.new(self.gridSizeX, self.gridSizeY, self.gridSizeZ, SOLID)

	return self
end

-- Master build function - coordinates all phases
function CaveBuilder:Build()
	CaveBuilder.yieldCounter = 0

	print("Starting cave generation...")
	local startTime = os.clock()

	-- Phase 1: Initial cave formation using noise
	if true then -- Always run this phase
		self:Phase1_InitialCaveFormation()
	end

	-- Phase 2: Generate rock formations (stalactites, stalagmites, columns)
	if CaveConfig.FormationPhaseEnabled then
		self:Phase2_RockFormations()
	end

	-- Phase 3: Smoothing pass
	if CaveConfig.SmoothingPhaseEnabled then
		self:Phase3_Smoothing()
	end

	-- Phase 4: Ensure connectivity
	if CaveConfig.ConnectivityPhaseEnabled then
		self:Phase4_EnsureConnectivity()
	end

	-- Phase 5: Flood fill to remove isolated chambers
	if CaveConfig.FloodFillPhaseEnabled then
		self:Phase5_FloodFill()
	end

	-- Phase 6: Create surface entrances
	if CaveConfig.SurfaceEntrancesPhaseEnabled then
		self:Phase6_SurfaceEntrances()
	end

	-- Phase 7: Add bridges between chambers
	if CaveConfig.BridgePhaseEnabled then
		self:Phase7_Bridges()
	end

	-- Phase 8: Convert grid to actual parts
	self:Phase8_BuildWorld()

	local endTime = os.clock()
	print("Cave generation complete! Time taken: " .. string.format("%.2f", endTime - startTime) .. " seconds")

	return self.grid
end

-- Phase 1: Create the basic cave structure using 3D noise
function CaveBuilder:Phase1_InitialCaveFormation()
	print("Phase 1: Generating initial cave structure...")
	local startTime = os.clock()

	for z = 1, self.gridSizeZ do
		for y = 1, self.gridSizeY do
			for x = 1, self.gridSizeX do
				-- Convert grid position to world position for noise sampling
				local worldX = self.origin.X + (x - 1) * self.cellSize
				local worldY = self.origin.Y + (y - 1) * self.cellSize
				local worldZ = self.origin.Z + (z - 1) * self.cellSize

				-- Get base noise value
				local noiseValue = fractalNoise(
					worldX, worldY, worldZ,
					CaveConfig.P1_NoiseScale,
					CaveConfig.P1_Octaves,
					CaveConfig.P1_Persistence,
					CaveConfig.P1_Lacunarity
				)

				-- Apply biases
				local heightBiasValue = heightBias(y, self.gridSizeY)
				local distanceBiasValue = distanceToCenterBias(x, y, z, self.gridSizeX, self.gridSizeZ)
				local vertConnValue = verticalConnectivityNoise(worldX, worldY, worldZ, CaveConfig.P1_NoiseScale)

				-- Combine all factors
				local finalValue = noiseValue + heightBiasValue + distanceBiasValue + vertConnValue

				-- Carve air where the value is below threshold
				if finalValue < CaveConfig.Threshold then
					self.grid:set(x, y, z, AIR)
				else
					self.grid:set(x, y, z, SOLID)
				end

				yield()
			end
		end
	end

	-- Ensure the floor and edges remain solid
	for z = 1, self.gridSizeZ do
		for x = 1, self.gridSizeX do
			-- Floor
			for y = 1, CaveConfig.FormationStartHeight_Cells do
				self.grid:set(x, y, z, SOLID)
			end

			-- Edges
			if x == 1 or x == self.gridSizeX or z == 1 or z == self.gridSizeZ then
				for y = 1, self.gridSizeY do
					self.grid:set(x, y, z, SOLID)
				end
			end
		end
	end

	local endTime = os.clock()
	print("Phase 1 complete! Time taken: " .. string.format("%.2f", endTime - startTime) .. " seconds")
end

-- Phase 2: Add stalactites, stalagmites, and columns
function CaveBuilder:Phase2_RockFormations()
	print("Phase 2: Generating rock formations...")
	local startTime = os.clock()

	-- Find suitable locations for formations
	local potentialFormationSpots = {}

	for z = 2, self.gridSizeZ - 1 do
		for x = 2, self.gridSizeX - 1 do
			-- Look for air cells with solid rock above (stalactites) or below (stalagmites)
			for y = CaveConfig.FormationStartHeight_Cells + CaveConfig.FormationClearance_Cells, self.gridSizeY - CaveConfig.FormationClearance_Cells do
				if self.grid:get(x, y, z) == AIR then
					local airAbove = self.grid:get(x, y+1, z) == AIR
					local airBelow = self.grid:get(x, y-1, z) == AIR
					local rockAbove = self.grid:get(x, y+1, z) == SOLID
					local rockBelow = self.grid:get(x, y-1, z) == SOLID

					-- Stalactite spot
					if airBelow and rockAbove then
						table.insert(potentialFormationSpots, {x=x, y=y, z=z, type="stalactite"})
					end

					-- Stalagmite spot
					if airAbove and rockBelow then
						table.insert(potentialFormationSpots, {x=x, y=y, z=z, type="stalagmite"})
					end

					-- Column spot - need enough vertical space
					if airAbove and airBelow then
						-- Find ceiling and floor
						local ceilingY = y
						while ceilingY < self.gridSizeY and self.grid:get(x, ceilingY, z) == AIR do
							ceilingY = ceilingY + 1
						end

						local floorY = y - 1
						while floorY > 1 and self.grid:get(x, floorY, z) == AIR do
							floorY = floorY - 1
						end

						local chamberHeight = ceilingY - floorY - 1
						if chamberHeight >= CaveConfig.MinColumnHeight_Cells then
							table.insert(potentialFormationSpots, {
								x=x, y=y, z=z, 
								type="column", 
								floorY=floorY+1, 
								ceilingY=ceilingY-1, 
								height=chamberHeight
							})
						end
					end
				end

				yield()
			end
		end
	end

	-- Randomly select and create formations
	random:Shuffle(potentialFormationSpots)

	local stalactiteCount = 0
	local stalagmiteCount = 0
	local columnCount = 0

	for _, spot in ipairs(potentialFormationSpots) do
		local formationType

		if spot.type == "column" then
			if randomChance(CaveConfig.ColumnChance) then
				formationType = "column"
			end
		elseif spot.type == "stalactite" then
			if randomChance(CaveConfig.StalactiteChance) then
				formationType = "stalactite"
			end
		elseif spot.type == "stalagmite" then
			if randomChance(CaveConfig.StalagmiteChance) then
				formationType = "stalagmite"
			end
		end

		if formationType then
			if formationType == "stalactite" then
				self:CreateStalactite(spot.x, spot.y, spot.z)
				stalactiteCount = stalactiteCount + 1
			elseif formationType == "stalagmite" then
				self:CreateStalagmite(spot.x, spot.y, spot.z)
				stalagmiteCount = stalagmiteCount + 1
			elseif formationType == "column" then
				self:CreateColumn(spot.x, spot.y, spot.z, spot.floorY, spot.ceilingY)
				columnCount = columnCount + 1
			end
		end
	end

	print("Created " .. stalactiteCount .. " stalactites, " .. stalagmiteCount .. " stalagmites, and " .. columnCount .. " columns")

	local endTime = os.clock()
	print("Phase 2 complete! Time taken: " .. string.format("%.2f", endTime - startTime) .. " seconds")
end

-- Helper function to create a stalactite
function CaveBuilder:CreateStalactite(x, y, z)
	local length = randomInt(CaveConfig.MinFormationLength_Cells, CaveConfig.MaxFormationLength_Cells)

	for i = 0, length - 1 do
		if y - i <= 1 then break end

		local radius = CaveConfig.BaseFormationRadius_Factor * (length - i) / length
		local radiusCells = math.max(1, math.floor(radius))

		for rx = -radiusCells, radiusCells do
			for rz = -radiusCells, radiusCells do
				local distance = math.sqrt(rx * rx + rz * rz)
				if distance <= radius then
					local nx, ny, nz = x + rx, y - i, z + rz
					if self.grid:isInBounds(nx, ny, nz) then
						self.grid:set(nx, ny, nz, SOLID)
					end
				end
			end
		end

		yield()
	end
end

-- Helper function to create a stalagmite
function CaveBuilder:CreateStalagmite(x, y, z)
	local length = randomInt(CaveConfig.MinFormationLength_Cells, CaveConfig.MaxFormationLength_Cells)

	for i = 0, length - 1 do
		if y + i >= self.gridSizeY then break end

		local radius = CaveConfig.BaseFormationRadius_Factor * (length - i) / length
		local radiusCells = math.max(1, math.floor(radius))

		for rx = -radiusCells, radiusCells do
			for rz = -radiusCells, radiusCells do
				local distance = math.sqrt(rx * rx + rz * rz)
				if distance <= radius then
					local nx, ny, nz = x + rx, y + i, z + rz
					if self.grid:isInBounds(nx, ny, nz) then
						self.grid:set(nx, ny, nz, SOLID)
					end
				end
			end
		end

		yield()
	end
end

-- Helper function to create a column
function CaveBuilder:CreateColumn(x, y, z, floorY, ceilingY)
	-- Column thickness varies along height
	local baseRadius = CaveConfig.BaseFormationRadius_Factor * 1.5

	for ny = floorY, ceilingY do
		-- Calculate radius at this height (thinner in middle)
		local heightFactor = 2 * math.abs((ny - floorY) / (ceilingY - floorY) - 0.5)
		local radius = baseRadius * (0.7 + 0.3 * heightFactor)
		local radiusCells = math.max(1, math.ceil(radius))

		for rx = -radiusCells, radiusCells do
			for rz = -radiusCells, radiusCells do
				local distance = math.sqrt(rx * rx + rz * rz)
				if distance <= radius then
					local nx, nz = x + rx, z + rz
					if self.grid:isInBounds(nx, ny, nz) then
						self.grid:set(nx, ny, nz, SOLID)
					end
				end
			end
		end

		yield()
	end
end

-- Phase 3: Smooth the cave to remove single blocks and jagged edges
function CaveBuilder:Phase3_Smoothing()
	print("Phase 3: Smoothing cave structures...")
	local startTime = os.clock()

	for iteration = 1, CaveConfig.SmoothingIterations do
		local tempGrid = Grid3D.new(self.gridSizeX, self.gridSizeY, self.gridSizeZ)

		for z = 1, self.gridSizeZ do
			for y = 1, self.gridSizeY do
				for x = 1, self.gridSizeX do
					local currentValue = self.grid:get(x, y, z)

					-- Skip edge cells, keep them solid
					if x == 1 or x == self.gridSizeX or y == 1 or y == self.gridSizeY or z == 1 or z == self.gridSizeZ then
						tempGrid:set(x, y, z, SOLID)
					else
						local solidNeighbors = self.grid:getNeighborCount(x, y, z, SOLID)
						local airNeighbors = 26 - solidNeighbors  -- 26 total neighbors (3x3x3 - 1)

						if currentValue == SOLID and airNeighbors >= CaveConfig.SmoothingThreshold_CarveRock then
							-- Too many air neighbors, carve this solid into air
							tempGrid:set(x, y, z, AIR)
						elseif currentValue == AIR and solidNeighbors >= CaveConfig.SmoothingThreshold_FillAir then
							-- Too many solid neighbors, fill this air with solid
							tempGrid:set(x, y, z, SOLID)
						else
							-- Keep current value
							tempGrid:set(x, y, z, currentValue)
						end
					end

					yield()
				end
			end
		end

		-- Replace grid with smoothed version
		self.grid = tempGrid
		print("Completed smoothing iteration " .. iteration)
	end

	local endTime = os.clock()
	print("Phase 3 complete! Time taken: " .. string.format("%.2f", endTime - startTime) .. " seconds")
end

-- Phase 4: Ensure connectivity between cave chambers
function CaveBuilder:Phase4_EnsureConnectivity()
	print("Phase 4: Ensuring cave connectivity...")
	local startTime = os.clock()

	-- Find air chambers
	local chambers = self:FindDisconnectedChambers()
	print("Found " .. #chambers .. " disconnected chambers")

	if #chambers <= 1 then
		print("Cave system is already connected.")
		return
	end

	-- Sort chambers by size (descending)
	table.sort(chambers, function(a, b) return #a.cells > #b.cells end)

	-- Connect each smaller chamber to the largest chamber or nearest chamber
	local mainChamber = chambers[1]

	for i = 2, #chambers do
		local chamber = chambers[i]

		-- Find closest cells between this chamber and either main chamber or another already-connected chamber
		local closestDistance = math.huge
		local startCell, endCell

		for _, cell1 in ipairs(chamber.cells) do
			-- Try to connect to main chamber
			for _, cell2 in ipairs(mainChamber.cells) do
				local dist = math.sqrt((cell1.x - cell2.x)^2 + (cell1.y - cell2.y)^2 + (cell1.z - cell2.z)^2)
				if dist < closestDistance then
					closestDistance = dist
					startCell = cell1
					endCell = cell2
				end
			end

			yield()
		end

		if startCell and endCell then
			self:CreateTunnel(startCell, endCell)
			print("Connected chamber " .. i .. " to main chamber, distance: " .. closestDistance)
		end
	end

	local endTime = os.clock()
	print("Phase 4 complete! Time taken: " .. string.format("%.2f", endTime - startTime) .. " seconds")
end

-- Helper function for Phase 4: Find disconnected air chambers using flood fill
function CaveBuilder:FindDisconnectedChambers()
	local chambers = {}
	local visited = {}

	-- Initialize visited grid
	for z = 1, self.gridSizeZ do
		for y = 1, self.gridSizeY do
			for x = 1, self.gridSizeX do
				local index = self.grid:index(x, y, z)
				visited[index] = false
			end
		end
	end

	-- Find chambers using flood fill
	for z = 1, self.gridSizeZ do
		for y = 1, self.gridSizeY do
			for x = 1, self.gridSizeX do
				local index = self.grid:index(x, y, z)

				if self.grid:get(x, y, z) == AIR and not visited[index] then
					local chamber = {cells = {}}
					local queue = Queue.new()
					queue:push({x=x, y=y, z=z})
					visited[index] = true

					while not queue:isEmpty() do
						local cell = queue:pop()
						table.insert(chamber.cells, cell)

						-- Check 6-connected neighbors (up, down, left, right, front, back)
						local neighbors = {
							{cell.x+1, cell.y, cell.z},
							{cell.x-1, cell.y, cell.z},
							{cell.x, cell.y+1, cell.z},
							{cell.x, cell.y-1, cell.z},
							{cell.x, cell.y, cell.z+1},
							{cell.x, cell.y, cell.z-1}
						}

						for _, neighbor in ipairs(neighbors) do
							local nx, ny, nz = unpack(neighbor)
							local nIndex = self.grid:index(nx, ny, nz)

							if nIndex and self.grid:get(nx, ny, nz) == AIR and not visited[nIndex] then
								queue:push({x=nx, y=ny, z=nz})
								visited[nIndex] = true
							end
						end

						yield()
					end

					if #chamber.cells > 10 then -- Ignore tiny air pockets
						table.insert(chambers, chamber)
					end
				end
			end
		end
	end

	return chambers
end

-- Helper function for Phase 4: Create a tunnel between two points
function CaveBuilder:CreateTunnel(startCell, endCell)
	local tunnelRadius = math.max(1, math.floor(self.cellSize * CaveConfig.ConnectivityTunnelRadius_Factor))

	-- Create a bezier path between the two points
	local controlPoint = {
		x = (startCell.x + endCell.x) / 2,
		y = (startCell.y + endCell.y) / 2 + randomFloat(-5, 5),
		z = (startCell.z + endCell.z) / 2 + randomFloat(-5, 5)
	}

	-- Create tunnel along bezier path
	local steps = math.ceil(math.sqrt(
		(endCell.x - startCell.x)^2 + 
			(endCell.y - startCell.y)^2 + 
			(endCell.z - startCell.z)^2
		))

	for t = 0, 1, 1/steps do
		-- Quadratic bezier formula
		local mt = 1 - t
		local x = mt^2 * startCell.x + 2 * mt * t * controlPoint.x + t^2 * endCell.x
		local y = mt^2 * startCell.y + 2 * mt * t * controlPoint.y + t^2 * endCell.y
		local z = mt^2 * startCell.z + 2 * mt * t * controlPoint.z + t^2 * endCell.z

		-- Carve tunnel segment
		for rx = -tunnelRadius, tunnelRadius do
			for ry = -tunnelRadius, tunnelRadius do
				for rz = -tunnelRadius, tunnelRadius do
					local distance = math.sqrt(rx^2 + ry^2 + rz^2)
					if distance <= tunnelRadius then
						local nx, ny, nz = math.floor(x + rx), math.floor(y + ry), math.floor(z + rz)
						if self.grid:isInBounds(nx, ny, nz) then
							self.grid:set(nx, ny, nz, AIR)
						end
					end
				end
			end
		end

		yield()
	end
end