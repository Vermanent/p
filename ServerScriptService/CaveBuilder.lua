-- CaveBuilder.lua

-- 1) Grab the Terrain
local Terrain = workspace:FindFirstChildOfClass("Terrain")
if not Terrain then
	error("CaveBuilder: Terrain not found in Workspace")
end

-- 2) Safe wrappers for all your terrain calls
local function safeFillBlock(cframe, size, material)
	-- only fill if 'size' is a Vector3 with all dimensions > 0
	if typeof(size) == "Vector3"
		and size.X > 0 and size.Y > 0 and size.Z > 0 then
		Terrain:FillBlock(cframe, size, material)
	end
end

local function safeFillBall(position, radius, material)
	-- only fill if 'radius' is a positive number
	if typeof(radius) == "number" and radius > 0 then
		Terrain:FillBall(position, radius, material)
	end
end

-- 3) Now require your config and noise modules
local Config = require(script.Parent.CaveConfig)
local Noise  = require(script.Parent.NoiseGenerator)

-- 4) Seed the RNG, set up origin/center, etc.
math.randomseed(Config.Seed)
local origin = Vector3.new(0, 0, 0)
local center = origin + Config.RegionSize / 2

-- 3) Now require your config and noise modules
local Config = require(script.Parent.CaveConfig)
local Noise  = require(script.Parent.NoiseGenerator)

-- 4) Seed the RNG, set up origin/center, etc.
math.randomseed(Config.Seed)
local origin = Vector3.new(0, 0, 0)
local center = origin + Config.RegionSize / 2

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
do
	local sz = Config.RegionSize
	if sz.X > 0 and sz.Y > 0 and sz.Z > 0 then
		safeFillBlock(CFrame.new(center), sz, Config.RockMaterial)
	else
		warn("Skipped initial FillBlock: invalid RegionSize", sz)
	end
end
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

-- New function: Get a biased noise value based on position for formation features
local function formationNoise(wp, type)
	local base = fractalNoise(wp.X/15, wp.Y/15, wp.Z/15)

	-- For stalactites, increase probability near ceiling
	if type == "stalactite" then
		local heightFactor = (wp.Y % 30) / 30
		if heightFactor > 0.7 then
			return base * (1.2 + heightFactor)
		end
	end

	-- For stalagmites, increase probability near floor
	if type == "stalagmite" then
		local heightFactor = (wp.Y % 25) / 25
		if heightFactor < 0.3 then
			return base * (1.3 - heightFactor)
		end
	end

	-- For columns/pillars, boost probability periodically
	if type == "column" then
		local xPeriod = math.sin(wp.X / 60) * 0.5 + 0.5
		local zPeriod = math.sin(wp.Z / 60) * 0.5 + 0.5
		return base * (xPeriod * zPeriod + 0.5)
	end

	return base
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

						-- Enhanced height-based cave distribution
						local heightRatio = wp.Y / Config.RegionSize.Y
						local heightBias
						if heightRatio < 0.2 then
							heightBias = 0.2  -- Increased cave density at lower levels
						elseif heightRatio > 0.8 then
							heightBias = 0.0  -- Reduced cave density near the surface
						else
							-- Create larger chambers in the middle section
							heightBias = 0.05 - 0.2 * math.abs(heightRatio - 0.5)
						end

						-- Enhanced distance-based cave distribution
						local distanceFromCenter = ((wp - center) / Config.RegionSize).Magnitude * 2
						-- Stronger bias to reduce caves near the edges
						local distanceBias = math.min(distanceFromCenter * 0.15, 0.15)

						-- Vertical connectivity enhancement
						local verticalConnectivity = Noise:GetValue(wp.X/50, 0, wp.Z/50) * 0.1

						local density = fractalNoise(wp.X, wp.Y, wp.Z) + heightBias + distanceBias - verticalConnectivity

						-- Check if we should carve air
						if density < Config.Threshold then
							-- Dynamic sizing based on location
							local radiusBase = cell * 0.6  -- Increased slightly for overall larger caves

							-- More variation in cave size based on lower-frequency noise for large-scale features
							local sizeNoise = Noise:GetValue(wp.X/40, wp.Y/40, wp.Z/40)
							local radiusVariation = cell * 0.4 * sizeNoise

							-- Create larger chambers periodically
							local chamberValue = fractalNoise(wp.X/100, wp.Y/100, wp.Z/100)
							local chamberBoost = chamberValue > 0.7 and chamberValue * cell * 1.5 or 0

							-- Make caves larger in the central region
							local centralBoost = (1.0 - distanceFromCenter) * cell * 0.5

							local radius = radiusBase + radiusVariation + chamberBoost + centralBoost

							safeFillBall(wp, radius, Enum.Material.Air)
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

-- Phase 2: Add stalactites, stalagmites and columns
print("Phase 2: Adding formation features...")
local formationCount = 0

-- Process in batches
local formationsBatchSize = 20
for ix = 0, xCount, formationsBatchSize do
	for iz = 0, zCount, formationsBatchSize do
		for iy = Config.FormationStartHeight, yCount - Config.FormationClearance, formationsBatchSize do
			-- Check for cave regions to add formations
			for ox = 0, formationsBatchSize - 1 do
				if ix + ox > xCount then continue end
				for oz = 0, formationsBatchSize - 1 do
					if iz + oz > zCount then continue end
					for oy = 0, formationsBatchSize - 1 do
						if iy + oy > yCount - Config.FormationClearance then continue end

						local cx, cy, cz = ix + ox, iy + oy, iz + oz

						-- Only place formations in air regions
						if isValidGridPos(cx, cy, cz) and caveGrid[cx][cy][cz] then
							local wp = gridToWorld(cx, cy, cz)

							-- Check surrounding cells to see if this is in a cave with space
							local hasSpace = true
							local airCount = 0

							for dx = -2, 2 do
								for dy = -2, 2 do
									for dz = -2, 2 do
										local nx, ny, nz = cx + dx, cy + dy, cz + dz
										if isValidGridPos(nx, ny, nz) and caveGrid[nx][ny][nz] then
											airCount = airCount + 1
										end
									end
								end
							end

							-- Only place formations in larger cave spaces
							if airCount >= 35 then
								-- Check above and below to determine formation type
								local hasAirAbove = cy < yCount and caveGrid[cx][cy+1][cz]
								local hasAirBelow = cy > 0 and caveGrid[cx][cy-1][cz]

								-- Skip if there's rock above AND below (likely in a narrow tunnel)
								if not hasAirAbove and not hasAirBelow then
									continue
								end

								-- Create different formations based on context
								if not hasAirAbove and hasAirBelow then
									-- Potential stalactite
									if formationNoise(wp, "stalactite") > 0.7 and math.random() < Config.StalactiteChance then
										-- Create a stalactite
										local height = math.random(Config.MinFormationHeight, Config.MaxFormationHeight)
										for h = 0, height do
											local point = wp - Vector3.new(0, h * 0.7, 0)

											-- Stalactites are thicker at top, thinner at bottom
											local taperFactor = 1 - (h / height)
											local radius = Config.BaseFormationRadius * taperFactor

											-- Add some variation to the radius
											radius = radius * (0.8 + 0.4 * Noise:GetValue(point.X/3, point.Y/3, point.Z/3))

											-- Add small offset to position for more natural look
											local offset = Vector3.new(
												(Noise:GetValue(point.X/5, 0, point.Z/5) - 0.5) * 0.8,
												0,
												(Noise:GetValue(0, point.Y/5, point.Z/5) - 0.5) * 0.8
											)

											safeFillBall(point + offset, radius, Config.RockMaterial)

											-- Update the grid (mark as solid)
											local gx, gy, gz = worldToGrid(point)
											if isValidGridPos(gx, gy, gz) then
												caveGrid[gx][gy][gz] = false
											end
										end
										formationCount = formationCount + 1
									end
								elseif hasAirAbove and not hasAirBelow then
									-- Potential stalagmite
									if formationNoise(wp, "stalagmite") > 0.7 and math.random() < Config.StalagmiteChance then
										-- Create a stalagmite
										local height = math.random(Config.MinFormationHeight, Config.MaxFormationHeight)
										for h = 0, height do
											local point = wp + Vector3.new(0, h * 0.7, 0)

											-- Stalagmites are thicker at bottom, thinner at top
											local taperFactor = 1 - (h / height)
											local radius = Config.BaseFormationRadius * taperFactor

											-- Add some variation to the radius
											radius = radius * (0.8 + 0.4 * Noise:GetValue(point.X/3, point.Y/3, point.Z/3))

											-- Add small offset to position for more natural look
											local offset = Vector3.new(
												(Noise:GetValue(point.X/5, 0, point.Z/5) - 0.5) * 0.8,
												0,
												(Noise:GetValue(0, point.Y/5, point.Z/5) - 0.5) * 0.8
											)

											safeFillBall(point + offset, radius, Config.RockMaterial)

											-- Update the grid (mark as solid)
											local gx, gy, gz = worldToGrid(point)
											if isValidGridPos(gx, gy, gz) then
												caveGrid[gx][gy][gz] = false
											end
										end
										formationCount = formationCount + 1
									end
								elseif hasAirAbove and hasAirBelow and airCount > 60 then
									-- Potential column/pillar in large air spaces
									if formationNoise(wp, "column") > 0.85 and math.random() < Config.ColumnChance then
										-- Create column by scanning up and down
										local scanDist = 15
										local topY, bottomY = cy, cy

										-- Scan up to find ceiling
										for sy = cy, math.min(cy + scanDist, yCount) do
											if not caveGrid[cx][sy][cz] then
												topY = sy - 1
												break
											end
											if sy == math.min(cy + scanDist, yCount) then
												topY = sy
											end
										end

										-- Scan down to find floor
										for sy = cy, math.max(cy - scanDist, 0), -1 do
											if not caveGrid[cx][sy][cz] then
												bottomY = sy + 1
												break
											end
											if sy == math.max(cy - scanDist, 0) then
												bottomY = sy
											end
										end

										-- Make sure there's enough vertical space for a column
										if topY - bottomY >= Config.MinColumnHeight then
											-- Create the column with varying radius
											for y = bottomY, topY do
												local heightPercent = (y - bottomY) / (topY - bottomY)
												local point = gridToWorld(cx, y, cz)

												-- Make columns thicker in middle, thinner at ends
												local thicknessFactor = 1.0 - math.abs(heightPercent - 0.5) * 0.7
												local radius = Config.BaseFormationRadius * 1.5 * thicknessFactor

												-- Add some horizontal waviness
												local waveFactor = 3 * Noise:GetValue(point.X/25, point.Y/10, point.Z/25)
												local offset = Vector3.new(
													math.sin(heightPercent * math.pi * 2) * waveFactor,
													0,
													math.cos(heightPercent * math.pi * 1.5) * waveFactor
												)

												safeFillBall(point + offset, radius, Config.RockMaterial)

												-- Update the grid (mark as solid)
												local gx, gy, gz = worldToGrid(point + offset)
												if isValidGridPos(gx, gy, gz) then
													caveGrid[gx][gy][gz] = false
												end
											end
											formationCount = formationCount + 1
										end
									end
								end
							end
						end
					end
				end
			end
		end

		-- Status update
		if formationCount % 50 == 0 and formationCount > 0 then
			print("Created " .. formationCount .. " cave formations")
			task.wait(0.01)
		end
	end
end

print("Created a total of " .. formationCount .. " cave formations")

-- Phase 3: Applying smoothing to remove small floating rocks...
print("Applying smoothing to remove small floating rocks...")
local iterations = 3  -- Increased from 2 originally
for iter = 1, iterations do
	local nextGrid = {}
	local processedCount = 0

	-- Build nextGrid by checking neighbors
	for x = 0, xCount do
		nextGrid[x] = {}
		for y = 0, yCount do
			nextGrid[x][y] = {}
			for z = 0, zCount do
				if caveGrid[x][y][z] then
					nextGrid[x][y][z] = true
				else
					local rockCount = 0
					local checkRange = (iter == 1) and 2 or 1
					for dx = -checkRange, checkRange do
						for dy = -checkRange, checkRange do
							for dz = -checkRange, checkRange do
								local nx, ny, nz = x + dx, y + dy, z + dz
								if isValidGridPos(nx, ny, nz) and not caveGrid[nx][ny][nz] then
									rockCount = rockCount + 1
								end
							end
						end
					end
					local threshold = (iter == 1) and 4 or 5
					nextGrid[x][y][z] = (rockCount <= threshold)
				end

				processedCount = processedCount + 1
				if processedCount % 5000 == 0 then
					task.wait()  -- yield every 5k cells
				end
			end
		end
	end

	-- Apply the changes to the world
	processedCount = 0
	for x = 0, xCount do
		for y = 0, yCount do
			for z = 0, zCount do
				if nextGrid[x][y][z] and not caveGrid[x][y][z] then
					local wp = gridToWorld(x, y, z)
					safeFillBall(wp, cell * 0.55, Config.RockMaterial)
				end

				processedCount = processedCount + 1
				if processedCount % 5000 == 0 then
					task.wait()  -- yield again during application
				end
			end
		end
	end

	caveGrid = nextGrid
	print("Smoothing iteration " .. iter .. " complete.")
	task.wait(0.01)  -- small pause before next iteration
end

-- Enhance cave connectivity with improved tunnels
if Config.EnableConnectivity then
	print("Phase 3: Enhancing cave connectivity...")
	local function getNearestCaveCells(gx, gy, gz, radius)
		local caveCells = {}
		local searchRadius = radius or 5
		for dx = -searchRadius, searchRadius do
			for dy = -searchRadius, searchRadius do
				for dz = -searchRadius, searchRadius do
					local nx, ny, nz = gx + dx, gy + dy, gz + dz
					if isValidGridPos(nx, ny, nz) and caveGrid[nx][ny][nz] then
						-- Weight by distance (favor closer cells slightly)
						local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
						if dist <= searchRadius then
							table.insert(caveCells, {x = nx, y = ny, z = nz, dist = dist})
						end
					end
				end
			end
		end
		-- Sort by distance to prefer closer connections when possible
		table.sort(caveCells, function(a, b) return a.dist < b.dist end)
		return caveCells
	end

	for i = 1, Config.ConnectivityDensity do
		-- Focus tunnel generation on mid-to-lower sections where cave density is higher
		local startY = math.random(0, math.floor(yCount * 0.8))
		local startX = math.random(0, xCount)
		local startZ = math.random(0, zCount)

		local nearbyCaves = getNearestCaveCells(startX, startY, startZ, 20)

		if #nearbyCaves >= 2 then
			-- Choose caves based on optimized criteria - don't just use random selection
			local cave1 = nearbyCaves[1]  -- Closest cave

			-- Try to find a suitable second cave that's not too close
			local cave2
			local minDistForSecondCave = 8  -- Must be at least this far in grid units
			for j = 2, math.min(15, #nearbyCaves) do
				local candidate = nearbyCaves[j]
				local dx = cave1.x - candidate.x
				local dy = cave1.y - candidate.y
				local dz = cave1.z - candidate.z
				local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

				if dist >= minDistForSecondCave then
					cave2 = candidate
					break
				end
			end

			-- If we couldn't find a suitable second cave, use a random one
			if not cave2 and #nearbyCaves > 1 then
				repeat
					cave2 = nearbyCaves[math.random(2, #nearbyCaves)]
				until cave2.x ~= cave1.x or cave2.y ~= cave1.y or cave2.z ~= cave1.z
			end

			if cave2 then
				local p1 = gridToWorld(cave1.x, cave1.y, cave1.z)
				local p2 = gridToWorld(cave2.x, cave2.y, cave2.z)
				local midpoint = (p1 + p2) / 2

				-- Create winding tunnels with more controlled size
				local randomOffset = Vector3.new(
					(math.random() - 0.5) * 8,
					(math.random() - 0.5) * 5,
					(math.random() - 0.5) * 8
				)
				local controlPoint = midpoint + randomOffset

				-- Calculate a reasonable number of steps based on distance
				local dist = (p1 - p2).Magnitude
				local steps = math.ceil(dist / (cell * 0.4))
				steps = math.max(5, math.min(steps, 30))  -- Ensure reasonable range

				-- Tunnel size parameters
				local tunnelSizeBase = cell * 0.4  -- Start with smaller tunnels
				local tunnelMaxSize = cell * 0.7   -- Maximum tunnel size

				-- Generate the tunnel with a quadratic curve
				for t = 0, 1, 1/steps do
					local mt = 1 - t
					local point = (mt * mt * p1) + (2 * mt * t * controlPoint) + (t * t * p2)

					-- Vary tunnel size based on distance along path (wider in middle)
					-- Use sine function for smoother transition
					local tunnelSize = tunnelSizeBase + (tunnelMaxSize - tunnelSizeBase) * math.sin(t * math.pi)

					-- Add small variation based on position
					tunnelSize = tunnelSize * (0.9 + 0.2 * Noise:GetValue(point.X/8, point.Y/8, point.Z/8))

					safeFillBall(point, tunnelSize, Enum.Material.Air)
					local gx, gy, gz = worldToGrid(point)
					if isValidGridPos(gx, gy, gz) then
						caveGrid[gx][gy][gz] = true
					end
				end
			end
		end

		if i % 10 == 0 then
			print(string.format("Creating connections: %.1f%%", i / Config.ConnectivityDensity * 100))
			task.wait(0.01)
		end
	end
end

-- Phase 4: Remove floating terrains with flood fill from all boundaries
print("Phase 4: Removing floating terrains with flood fill from all boundaries...")
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
				safeFillBall(wp, cell * 0.5, Enum.Material.Air)
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

-- Phase 5: Create surface cave entrances
print("Phase 5: Creating surface cave entrances...")
for i = 1, Config.SurfaceCaveCount do
	local surfX = math.random() * Config.RegionSize.X
	local surfZ = math.random() * Config.RegionSize.Z
	local surfY = Config.RegionSize.Y - 10
	local entrancePos = Vector3.new(surfX, surfY, surfZ)

	local tunnelLength = 40 + math.random(15, 60)  -- Longer tunnels to better connect with cave network
	local tunnelDir = Vector3.new(
		(math.random() - 0.5) * 0.4,
		-1,
		(math.random() - 0.5) * 0.4
	).Unit

	for t = 0, tunnelLength, 2 do
		local point = entrancePos + (tunnelDir * t)
		if point.Y < 0 or point.Y > Config.RegionSize.Y then
			continue
		end

		-- Entrance tunnels are wider at the top, narrower deeper
		local entranceRatio = math.max(0, 1 - (t / tunnelLength))
		local tunnelRadius = Config.SurfaceCaveSize * (0.6 + 0.4 * entranceRatio)

		-- Add some irregular variation to tunnel shape
		local noiseVal = Noise:GetValue(point.X/20, point.Y/20, point.Z/20)
		tunnelRadius = tunnelRadius * (0.8 + 0.4 * noiseVal)

		-- Add some subtle meandering to the tunnel path
		local meander = Vector3.new(
			math.sin(t/10) * 3 * noiseVal,
			0,
			math.cos(t/15) * 3 * noiseVal
		)

		safeFillBall(point + meander, tunnelRadius, Enum.Material.Air)
		local gx, gy, gz = worldToGrid(point + meander)
		if isValidGridPos(gx, gy, gz) then
			caveGrid[gx][gy][gz] = true
		end

		-- Occasionally add small chamber off the main tunnel
		if math.random() < 0.05 then
			local branchDir = Vector3.new(
				math.random() - 0.5,
				(math.random() - 0.5) * 0.3,
				math.random() - 0.5
			).Unit
			local branchLength = 8 + math.random(3, 12)
			for b = 0, branchLength, 2 do
				local branchPoint = point + (branchDir * b)
				local branchRadius = tunnelRadius * (1 - b/branchLength) * 0.7
				safeFillBall(branchPoint, branchRadius, Enum.Material.Air)
			end
		end
	end

	-- Create a larger chamber at the bottom of some entrance tunnels
	if math.random() < 0.4 then
		local chamberPoint = entrancePos + (tunnelDir * tunnelLength)
		local chamberSize = Config.SurfaceCaveSize * (1.2 + 0.8 * math.random())

		-- Create irregular chamber shape with multiple overlapping spheres
		for c = 1, 5 do
			local offset = Vector3.new(
				(math.random() - 0.5) * chamberSize * 0.8,
				(math.random() - 0.5) * chamberSize * 0.8,
				(math.random() - 0.5) * chamberSize * 0.8
			)
			local sphereSize = chamberSize * (0.6 + 0.4 * math.random())
			safeFillBall(chamberPoint + offset, sphereSize, Enum.Material.Air)
		end
	end

	if i % 3 == 0 then
		task.wait(0.01)
	end
end

-- Final pass: Add rock bridges in large chambers to provide more support
print("Final phase: Adding support bridges in large chambers...")
local bridgeCount = 0

local function findLargeAirPockets()
	local pockets = {}
	local checked = {}

	for x = 0, xCount, 5 do
		for y = 0, yCount, 5 do
			for z = 0, zCount, 5 do
				local key = x..","..y..","..z
				if not checked[key] and caveGrid[x][y][z] then
					local queue = {{x, y, z}}
					local airCells = {}
					local airSize = 0
					local maxAir = 100
					local minX, minY, minZ = x, y, z
					local maxX, maxY, maxZ = x, y, z

					while #queue > 0 and airSize < maxAir do
						local cell = table.remove(queue, 1)
						local cx, cy, cz = cell[1], cell[2], cell[3]
						local cellKey = cx..","..cy..","..cz
						if not checked[cellKey] and isValidGridPos(cx, cy, cz) and caveGrid[cx][cy][cz] then
							checked[cellKey] = true
							airSize = airSize + 1
							table.insert(airCells, {x = cx, y = cy, z = cz})

							-- update bounds
							minX = math.min(minX, cx); minY = math.min(minY, cy); minZ = math.min(minZ, cz)
							maxX = math.max(maxX, cx); maxY = math.max(maxY, cy); maxZ = math.max(maxZ, cz)

							if airSize < maxAir then
								if cx > 0       then table.insert(queue, {cx-1, cy, cz}) end
								if cx < xCount then table.insert(queue, {cx+1, cy, cz}) end
								if cy > 0       then table.insert(queue, {cx, cy-1, cz}) end
								if cy < yCount then table.insert(queue, {cx, cy+1, cz}) end
								if cz > 0       then table.insert(queue, {cx, cy, cz-1}) end
								if cz < zCount then table.insert(queue, {cx, cy, cz+1}) end
							end
						end
					end

					if airSize >= 70 and (maxY - minY) >= 10 then
						table.insert(pockets, {
							size      = airSize,
							minBounds = Vector3.new(minX, minY, minZ),
							maxBounds = Vector3.new(maxX, maxY, maxZ),
							center    = Vector3.new((minX + maxX)/2, (minY + maxY)/2, (minZ + maxZ)/2),
							cells     = airCells,
						})
					end
				end
			end
		end
	end

	return pockets
end


-- Find all large chambers
local largeChambers = findLargeAirPockets()
print("Found " .. #largeChambers .. " large chambers for potential bridge support")

-- Build bridges
for _, chamber in ipairs(largeChambers) do
	local bridgesNeeded = math.min(5, math.max(1, math.floor(chamber.size / 80)))
	for b = 1, bridgesNeeded do
		local minB = chamber.minBounds
		local maxB = chamber.maxBounds
		local bridgeY = math.floor(minB.Y + (maxB.Y - minB.Y) * (0.3 + 0.4 * math.random()))
		local horizontal = math.random() < 0.5

		if horizontal then
			-- X-direction bridge
			local bridgeZ = math.floor(minB.Z + (maxB.Z - minB.Z) * math.random())
			local startX, endX = minB.X, maxB.X
			local thickness = 2 + math.floor(math.random() * 3)
			local width     = 2 + math.floor(math.random() * 2)

			for x = startX, endX do
				local distC = 2 * math.abs((x - startX) / (endX - startX) - 0.5)
				local archH = math.floor(thickness * (1 - 0.7 * distC))

				for h = 0, archH do
					for w = -width, width do
						local wx, wy, wz = x, bridgeY - h, bridgeZ + w
						if isValidGridPos(wx, wy, wz) and caveGrid[wx][wy][wz] then
							caveGrid[wx][wy][wz] = false
							local wp = gridToWorld(wx, wy, wz)
							safeFillBall(wp, cell * 0.5, Config.RockMaterial)
						end
					end
				end
			end

		else
			-- Z-direction bridge
			local bridgeX = math.floor(minB.X + (maxB.X - minB.X) * math.random())
			local startZ, endZ = minB.Z, maxB.Z
			local thickness    = 2 + math.floor(math.random() * 3)
			local width        = 2 + math.floor(math.random() * 2)

			for z = startZ, endZ do
				local distC = 2 * math.abs((z - startZ) / (endZ - startZ) - 0.5)
				local archH = math.floor(thickness * (1 - 0.7 * distC))

				for h = 0, archH do
					for w = -width, width do
						local wx, wy, wz = bridgeX + w, bridgeY - h, z
						if isValidGridPos(wx, wy, wz) and caveGrid[wx][wy][wz] then
							caveGrid[wx][wy][wz] = false
							local wp = gridToWorld(wx, wy, wz)
							safeFillBall(wp, cell * 0.5, Config.RockMaterial)
						end
					end
				end
			end

		end  -- if horizontal

		bridgeCount = bridgeCount + 1
	end
end

print("Added " .. bridgeCount .. " rock bridges for structural support")



print("Cave system generation complete!")
print("Total generation time: " .. string.format("%.2f seconds", os.clock() - startTime))