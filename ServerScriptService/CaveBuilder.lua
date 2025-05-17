local Terrain = workspace:FindFirstChildOfClass("Terrain")
local Config = require(script.Parent.CaveConfig)
local Noise = require(script.Parent.NoiseGenerator)

math.randomseed(Config.Seed)

local origin = Vector3.new(0, 0, 0)
local center = origin + Config.RegionSize / 2

local cell = Config.CellSize
local xCount = math.floor(Config.RegionSize.X / cell)
local yCount = math.floor(Config.RegionSize.Y / cell)
local zCount = math.floor(Config.RegionSize.Z / cell)

local caveGrid = {}

-- Initialize the 3D grid
local function initGrid()
	for x = 0, xCount do
		caveGrid[x] = {}
		for y = 0, yCount do
			caveGrid[x][y] = {}
		end
	end
end

-- Check if a grid position is valid
local function isValidGridPos(x, y, z)
	return x >= 0 and x <= xCount and y >= 0 and y <= yCount and z >= 0 and z <= zCount
end

-- Convert world coordinates to grid coordinates
local function worldToGrid(pos)
	local gx = math.floor((pos.X - origin.X) / cell)
	local gy = math.floor((pos.Y - origin.Y) / cell)
	local gz = math.floor((pos.Z - origin.Z) / cell)
	return gx, gy, gz
end

-- Convert grid coordinates to world coordinates
local function gridToWorld(gx, gy, gz)
	return Vector3.new(
		origin.X + gx * cell + cell/2,
		origin.Y + gy * cell + cell/2,
		origin.Z + gz * cell + cell/2
	)
end

print("Filling terrain with rock...")
Terrain:FillBlock(CFrame.new(center), Config.RegionSize, Config.RockMaterial)
task.wait(0.5)

-- Generate fractal noise for cave carving
local function fractalNoise(x, y, z)
	local sum = 0
	local amplitude = 1
	local frequency = Config.NoiseScale
	local normalizer = 0

	for i = 1, Config.Octaves do
		sum = sum + Noise:GetValue(x * frequency, y * frequency, z * frequency) * amplitude
		normalizer = normalizer + amplitude
		frequency = frequency * Config.Lacunarity
		amplitude = amplitude * Config.Persistence
	end

	return sum / normalizer
end

print("Initializing grid...")
initGrid()

print("Starting cave carving process...")
print("Total cells to process: " .. (xCount + 1) * (yCount + 1) * (zCount + 1))

local processed = 0
local total = (xCount + 1) * (yCount + 1) * (zCount + 1)
local startTime = os.clock()

-- Phase 1: Carve primary caves
print("Phase 1: Carving primary caves...")
local batchSize = 10
for ix = 0, xCount, batchSize do
	for iy = 0, yCount, batchSize do
		for iz = 0, zCount, batchSize do
			for ox = 0, batchSize - 1 do
				if ix + ox > xCount then continue end
				for oy = 0, batchSize - 1 do
					if iy + oy > yCount then continue end
					for oz = 0, batchSize - 1 do
						if iz + oz > zCount then continue end

						local cx, cy, cz = ix + ox, iy + oy, iz + oz
						local wp = gridToWorld(cx, cy, cz)

						local heightRatio = wp.Y / Config.RegionSize.Y
						local heightBias
						if heightRatio < 0.15 then
							heightBias = 0.15
						elseif heightRatio > 0.85 then
							heightBias = 0.05
						else
							heightBias = -0.05
						end

						local distanceFromCenter = ((wp - center) / Config.RegionSize).Magnitude * 2
						local distanceBias = math.min(distanceFromCenter * 0.1, 0.1)

						local density = fractalNoise(wp.X, wp.Y, wp.Z) + heightBias + distanceBias

						if density < Config.Threshold then
							local radiusBase = cell * 0.5
							local radiusVariation = cell * 0.3 * Noise:GetValue(wp.X/10, wp.Y/10, wp.Z/10)
							local radius = radiusBase + radiusVariation
							local caveSizeMultiplier = 1.0 + 0.3 * Noise:GetValue(wp.X/25, wp.Y/25, wp.Z/25)
							radius = radius * caveSizeMultiplier

							Terrain:FillBall(wp, radius, Enum.Material.Air)
							caveGrid[cx][cy][cz] = true
						end

						processed = processed + 1
					end
				end
			end

			if processed % 15000 == 0 then
				local elapsed = os.clock() - startTime
				local progress = processed / total
				local etaSeconds = elapsed / progress - elapsed
				print(string.format("Primary carving: %.2f%% (ETA: %.1f seconds)", 
					progress * 100, etaSeconds))
				task.wait(0.01)
			end
		end
	end
end

-- Apply smoothing to remove small floating rocks
print("Applying smoothing to remove small floating rocks...")
local iterations = 2
for iter = 1, iterations do
	local nextGrid = {}
	for x = 0, xCount do
		nextGrid[x] = {}
		for y = 0, yCount do
			nextGrid[x][y] = {}
			for z = 0, zCount do
				if caveGrid[x][y][z] then
					nextGrid[x][y][z] = true
				else
					local rockCount = 0
					for dx = -1, 1 do
						for dy = -1, 1 do
							for dz = -1, 1 do
								local nx, ny, nz = x + dx, y + dy, z + dz
								if isValidGridPos(nx, ny, nz) and not caveGrid[nx][ny][nz] then
									rockCount = rockCount + 1
								end
							end
						end
					end
					if rockCount <= 5 then
						nextGrid[x][y][z] = true
					else
						nextGrid[x][y][z] = false
					end
				end
			end
		end
	end
	for x = 0, xCount do
		for y = 0, yCount do
			for z = 0, zCount do
				if nextGrid[x][y][z] and not caveGrid[x][y][z] then
					local wp = gridToWorld(x, y, z)
					Terrain:FillBall(wp, cell * 0.5, Enum.Material.Air)
				end
			end
		end
	end
	caveGrid = nextGrid
	print("Smoothing iteration " .. iter .. " complete.")
	task.wait(0.01)
end

-- Enhance cave connectivity
if Config.EnableConnectivity then
	print("Phase 2: Enhancing cave connectivity...")
	local function getNearestCaveCells(gx, gy, gz, radius)
		local caveCells = {}
		local searchRadius = radius or 5
		for dx = -searchRadius, searchRadius do
			for dy = -searchRadius, searchRadius do
				for dz = -searchRadius, searchRadius do
					local nx, ny, nz = gx + dx, gy + dy, gz + dz
					if isValidGridPos(nx, ny, nz) and caveGrid[nx][ny][nz] then
						table.insert(caveCells, {x = nx, y = ny, z = nz})
					end
				end
			end
		end
		return caveCells
	end

	for i = 1, Config.ConnectivityDensity do
		local startX = math.random(0, xCount)
		local startY = math.random(0, yCount)
		local startZ = math.random(0, zCount)
		local nearbyCaves = getNearestCaveCells(startX, startY, startZ, 20)

		if #nearbyCaves >= 2 then
			local cave1 = nearbyCaves[math.random(1, #nearbyCaves)]
			local cave2
			repeat
				cave2 = nearbyCaves[math.random(1, #nearbyCaves)]
			until cave2.x ~= cave1.x or cave2.y ~= cave1.y or cave2.z ~= cave1.z

			local p1 = gridToWorld(cave1.x, cave1.y, cave1.z)
			local p2 = gridToWorld(cave2.x, cave2.y, cave2.z)
			local midpoint = (p1 + p2) / 2
			local randomOffset = Vector3.new(
				(math.random() - 0.5) * 10,
				(math.random() - 0.5) * 10,
				(math.random() - 0.5) * 10
			)
			local controlPoint = midpoint + randomOffset

			local steps = math.ceil((p1 - p2).Magnitude / (cell * 0.5))
			for t = 0, 1, 1/steps do
				local mt = 1 - t
				local point = (mt * mt * p1) + (2 * mt * t * controlPoint) + (t * t * p2)
				local tunnelSize = cell * (0.6 + 0.3 * math.sin(t * math.pi))
				Terrain:FillBall(point, tunnelSize, Enum.Material.Air)
				local gx, gy, gz = worldToGrid(point)
				if isValidGridPos(gx, gy, gz) then
					caveGrid[gx][gy][gz] = true
				end
			end
		end

		if i % 10 == 0 then
			print(string.format("Creating connections: %.1f%%", i / Config.ConnectivityDensity * 100))
			task.wait(0.01)
		end
	end
end

-- Phase 3: Remove floating terrains with flood fill from all boundaries
print("Phase 3: Removing floating terrains with flood fill from all boundaries...")
local connected = {}
for x = 0, xCount do
	connected[x] = {}
	for y = 0, yCount do
		connected[x][y] = {}
		for z = 0, zCount do
			connected[x][y][z] = false
		end
	end
end

local function floodFill(startX, startY, startZ)
	local queue = {{startX, startY, startZ}}
	local processed = 0
	while #queue > 0 do
		local cell = table.remove(queue, 1)
		local x, y, z = cell[1], cell[2], cell[3]
		if isValidGridPos(x, y, z) and not caveGrid[x][y][z] and not connected[x][y][z] then
			connected[x][y][z] = true
			table.insert(queue, {x+1, y, z})
			table.insert(queue, {x-1, y, z})
			table.insert(queue, {x, y+1, z})
			table.insert(queue, {x, y-1, z})
			table.insert(queue, {x, y, z+1})
			table.insert(queue, {x, y, z-1})
			processed = processed + 1
			if processed % 5000 == 0 then
				print("Flood fill processed " .. processed .. " cells...")
				task.wait()
			end
		end
	end
end

-- Collect starting points from all boundaries
local startingPoints = {}

-- X boundaries
for y = 0, yCount do
	for z = 0, zCount do
		if not caveGrid[0][y][z] then
			table.insert(startingPoints, {0, y, z})
		end
		if not caveGrid[xCount][y][z] then
			table.insert(startingPoints, {xCount, y, z})
		end
	end
end

-- Y boundaries
for x = 0, xCount do
	for z = 0, zCount do
		if not caveGrid[x][0][z] then
			table.insert(startingPoints, {x, 0, z})
		end
		if not caveGrid[x][yCount][z] then
			table.insert(startingPoints, {x, yCount, z})
		end
	end
end

-- Z boundaries
for x = 0, xCount do
	for y = 0, yCount do
		if not caveGrid[x][y][0] then
			table.insert(startingPoints, {x, y, 0})
		end
		if not caveGrid[x][y][zCount] then
			table.insert(startingPoints, {x, y, zCount})
		end
	end
end

print("Starting flood fill from " .. #startingPoints .. " boundary points...")
for _, point in ipairs(startingPoints) do
	floodFill(point[1], point[2], point[3])
end

-- Remove all unconnected rock
local removeCount = 0
for x = 0, xCount do
	for y = 0, yCount do
		for z = 0, zCount do
			if not caveGrid[x][y][z] and not connected[x][y][z] then
				local wp = gridToWorld(x, y, z)
				Terrain:FillBall(wp, cell * 0.5, Enum.Material.Air)
				caveGrid[x][y][z] = true
				removeCount = removeCount + 1
				if removeCount % 1000 == 0 then
					task.wait()
				end
			end
		end
	end
end
print("Floating terrains removed. Total cells deleted: " .. removeCount)

-- Phase 4: Create surface cave entrances
print("Phase 4: Creating surface cave entrances...")
for i = 1, Config.SurfaceCaveCount do
	local surfX = math.random() * Config.RegionSize.X
	local surfZ = math.random() * Config.RegionSize.Z
	local surfY = Config.RegionSize.Y - 10
	local entrancePos = Vector3.new(surfX, surfY, surfZ)

	local tunnelLength = 30 + math.random(15, 50)
	local tunnelDir = Vector3.new(
		(math.random() - 0.5) * 0.4,
		-1,
		(math.random() - 0.5) * 0.4
	).Unit

	for t = 0, tunnelLength, 3 do
		local point = entrancePos + (tunnelDir * t)
		if point.Y < 0 or point.Y > Config.RegionSize.Y then
			continue
		end
		local tunnelRadius = Config.SurfaceCaveSize * 0.7 * (0.5 + 0.5 * (t/tunnelLength))
		local noiseVal = Noise:GetValue(point.X/20, point.Y/20, point.Z/20)
		tunnelRadius = tunnelRadius * (0.8 + 0.4 * noiseVal)
		Terrain:FillBall(point, tunnelRadius, Enum.Material.Air)
		local gx, gy, gz = worldToGrid(point)
		if isValidGridPos(gx, gy, gz) then
			caveGrid[gx][gy][gz] = true
		end
		if math.random() < 0.05 then
			local branchDir = Vector3.new(
				math.random() - 0.5,
				(math.random() - 0.5) * 0.3,
				math.random() - 0.5
			).Unit
			local branchLength = 8 + math.random(3, 12)
			for b = 0, branchLength, 2 do
				local branchPoint = point + (branchDir * b)
				local branchRadius = tunnelRadius * (1 - b/branchLength) * 0.6
				Terrain:FillBall(branchPoint, branchRadius, Enum.Material.Air)
			end
		end
	end
	if i % 3 == 0 then
		task.wait(0.01)
	end
end

print("Cave system generation complete!")
print("Total generation time: " .. string.format("%.2f seconds", os.clock() - startTime))