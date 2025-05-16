-- Script: CaveBuilder
-- Path: ServerScriptService/CaveBuilder.lua
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local Config = require(script.Parent.CaveConfig)
local Noise = require(script.Parent.NoiseGenerator)

-- Set seed consistently
math.randomseed(Config.Seed)

local origin = Vector3.new(0, 0, 0)
local center = origin + Config.RegionSize / 2

-- Performance optimization - cache frequently used values
local cell = Config.CellSize
local xCount = math.floor(Config.RegionSize.X / cell)
local yCount = math.floor(Config.RegionSize.Y / cell)
local zCount = math.floor(Config.RegionSize.Z / cell)

-- Create a 3D grid to track carved spaces for connectivity checks
local caveGrid = {}
local function initGrid()
	for x = 0, xCount do
		caveGrid[x] = {}
		for y = 0, yCount do
			caveGrid[x][y] = {}
		end
	end
end

-- Check if position is valid in our grid
local function isValidGridPos(x, y, z)
	return x >= 0 and x <= xCount and y >= 0 and y <= yCount and z >= 0 and z <= zCount
end

-- Convert world position to grid indices
local function worldToGrid(pos)
	local gx = math.floor((pos.X - origin.X) / cell)
	local gy = math.floor((pos.Y - origin.Y) / cell)
	local gz = math.floor((pos.Z - origin.Z) / cell)
	return gx, gy, gz
end

-- Convert grid indices to world position
local function gridToWorld(gx, gy, gz)
	return Vector3.new(
		origin.X + gx * cell + cell/2,
		origin.Y + gy * cell + cell/2,
		origin.Z + gz * cell + cell/2
	)
end

-- Fill solid rock
print("Filling terrain with rock...")
Terrain:FillBlock(CFrame.new(center), Config.RegionSize, Config.RockMaterial)
task.wait(1) -- Give time for the fill operation to complete

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

	-- Normalize to [0,1] range
	return sum / normalizer
end

-- Initialize tracking grid
print("Initializing grid...")
initGrid()

print("Starting cave carving process...")
print("Total cells to process: " .. (xCount + 1) * (yCount + 1) * (zCount + 1))

local processed = 0
local total = (xCount + 1) * (yCount + 1) * (zCount + 1)
local startTime = os.clock()

-- First pass: Carve out primary caves
print("Phase 1: Carving primary caves...")
for ix = 0, xCount do
	for iy = 0, yCount do
		for iz = 0, zCount do
			local wp = gridToWorld(ix, iy, iz)

			-- Modified height bias: More caves near top and bottom
			-- This creates a U-shaped distribution - more caves at top and bottom, fewer in middle
			local heightRatio = wp.Y / Config.RegionSize.Y
			local heightBias

			if heightRatio < 0.3 or heightRatio > 0.7 then
				-- More caves near surface and deep underground
				heightBias = -0.1
			else
				-- Fewer caves in middle layers
				heightBias = 0.05
			end

			local density = fractalNoise(wp.X, wp.Y, wp.Z) + heightBias

			if density < Config.Threshold then
				-- Use FillBall for smooth caves, radius varies for natural shape
				local radiusBase = cell * 0.7
				local radiusVariation = cell * 0.5 * Noise:GetValue(wp.X/10, wp.Y/10, wp.Z/10)
				local radius = radiusBase + radiusVariation

				Terrain:FillBall(wp, radius, Enum.Material.Air)

				-- Mark this cell as carved in our grid
				caveGrid[ix][iy][iz] = true
			end

			processed = processed + 1
			if processed % 5000 == 0 then
				local elapsed = os.clock() - startTime
				local progress = processed / total
				local etaSeconds = elapsed / progress - elapsed

				print(string.format("Primary carving: %.2f%% (ETA: %.1f seconds)", 
					progress * 100, etaSeconds))
				task.wait() -- Yield to prevent script timeout
			end
		end
	end
end

-- Second pass: Create connectivity tunnels
if Config.EnableConnectivity then
	print("Phase 2: Enhancing cave connectivity...")

	-- Function to find adjacent cave cells
	local function getNearestCaveCells(gx, gy, gz, radius)
		local caveCells = {}
		local searchRadius = radius or 5

		for dx = -searchRadius, searchRadius do
			for dy = -searchRadius, searchRadius do
				for dz = -searchRadius, searchRadius do
					local nx, ny, nz = gx + dx, gy + dy, gz + dz
					if isValidGridPos(nx, ny, nz) and
						caveGrid[nx] and caveGrid[nx][ny] and caveGrid[nx][ny][nz] then
						table.insert(caveCells, {x = nx, y = ny, z = nz})
					end
				end
			end
		end

		return caveCells
	end

	-- Scan for disconnected cave sections and connect them
	for i = 1, Config.ConnectivityDensity do
		-- Pick random points
		local startX = math.random(0, xCount)
		local startY = math.random(0, yCount)
		local startZ = math.random(0, zCount)

		-- Find closest cave cells
		local nearbyCaves = getNearestCaveCells(startX, startY, startZ, 12)

		if #nearbyCaves >= 2 then
			-- Select two random cave cells to connect
			local cave1 = nearbyCaves[math.random(1, #nearbyCaves)]
			local cave2
			repeat
				cave2 = nearbyCaves[math.random(1, #nearbyCaves)]
			until cave2.x ~= cave1.x or cave2.y ~= cave1.y or cave2.z ~= cave1.z

			-- Create points for Bezier curve
			local p1 = gridToWorld(cave1.x, cave1.y, cave1.z)
			local p2 = gridToWorld(cave2.x, cave2.y, cave2.z)

			-- Add some variation to path
			local midpoint = (p1 + p2) / 2
			local randomOffset = Vector3.new(
				(math.random() - 0.5) * 20,
				(math.random() - 0.5) * 20,
				(math.random() - 0.5) * 20
			)
			local controlPoint = midpoint + randomOffset

			-- Carve tunnel along path
			local steps = math.ceil((p1 - p2).Magnitude / (cell * 0.5))
			for t = 0, 1, 1/steps do
				-- Bezier formula: B(t) = (1-t)^2 * P1 + 2(1-t)t * CP + t^2 * P2
				local mt = 1 - t
				local point = (mt * mt * p1) + (2 * mt * t * controlPoint) + (t * t * p2)

				-- Carve with varied tunnel size
				local tunnelSize = cell * (0.8 + 0.4 * math.sin(t * math.pi))
				Terrain:FillBall(point, tunnelSize, Enum.Material.Air)

				-- Update grid
				local gx, gy, gz = worldToGrid(point)
				if isValidGridPos(gx, gy, gz) then
					if not caveGrid[gx] then caveGrid[gx] = {} end
					if not caveGrid[gx][gy] then caveGrid[gx][gy] = {} end
					caveGrid[gx][gy][gz] = true
				end
			end
		end

		if i % 10 == 0 then
			print(string.format("Creating connections: %.1f%%", i / Config.ConnectivityDensity * 100))
			task.wait()
		end
	end
end

-- Third pass: Fix floating terrain
if Config.RemoveFloatingBlocks then
	print("Phase 3: Removing floating terrain...")

	-- Sample grid with larger step to identify floating terrain
	local checkStep = 4
	processed = 0

	for ix = 0, xCount, checkStep do
		for iz = 0, zCount, checkStep do
			-- Scan columns from top to bottom
			local lastSolidY = nil
			local potentialFloatingSegments = {}

			for iy = yCount, 0, -checkStep do
				local wp = gridToWorld(ix, iy, iz)

				-- Check if this is solid terrain
				local isSolid = not (caveGrid[ix] and caveGrid[ix][iy] and caveGrid[ix][iy][iz])

				if isSolid then
					-- Check if there's a gap below
					if lastSolidY and (lastSolidY - iy) > Config.MinSupportedSize then
						-- This might be a floating segment, verify by checking surrounding area
						local hasSupport = false

						-- Check horizontally for support
						for dx = -2, 2 do
							for dz = -2, 2 do
								local nx, nz = ix + dx, iz + dz
								if isValidGridPos(nx, iy, nz) and 
									not (caveGrid[nx] and caveGrid[nx][iy-1] and caveGrid[nx][iy-1][nz]) then
									hasSupport = true
									break
								end
							end
							if hasSupport then break end
						end

						if not hasSupport then
							-- Mark this as floating terrain
							table.insert(potentialFloatingSegments, {y = iy, size = lastSolidY - iy})
						end
					end

					lastSolidY = iy
				else
					lastSolidY = nil
				end
			end

			-- Remove floating segments
			for _, segment in ipairs(potentialFloatingSegments) do
				-- Either remove completely or create supporting pillars
				if segment.size < 15 or math.random() < 0.7 then
					-- Remove small floating segments entirely
					for iy = segment.y, segment.y + segment.size, 2 do
						if isValidGridPos(ix, iy, iz) then
							local wp = gridToWorld(ix, iy, iz)
							Terrain:FillBall(wp, cell * 3, Enum.Material.Air)

							-- Update grid
							if not caveGrid[ix] then caveGrid[ix] = {} end
							if not caveGrid[ix][iy] then caveGrid[ix][iy] = {} end
							caveGrid[ix][iy][iz] = true
						end
					end
				else
					-- Create supporting pillars for larger segments
					local px, pz = ix + (math.random(-2, 2)), iz + (math.random(-2, 2))
					if isValidGridPos(px, 0, pz) then
						-- Find ground level
						local groundY = 0
						for gy = 0, segment.y, 4 do
							if caveGrid[px] and caveGrid[px][gy] and caveGrid[px][gy][pz] then
								groundY = gy + 4
							else
								break
							end
						end

						-- Create support pillar
						for iy = groundY, segment.y, 2 do
							local wp = gridToWorld(px, iy, pz)
							local radius = cell * (1.2 + 0.3 * Noise:GetValue(wp.X/5, wp.Y/5, wp.Z/5))
							Terrain:FillBall(wp, radius, Config.RockMaterial)

							-- Update grid
							if not caveGrid[px] then caveGrid[px] = {} end
							if not caveGrid[px][iy] then caveGrid[px][iy] = {} end
							caveGrid[px][iy][pz] = false
						end
					end
				end
			end

			processed = processed + 1
			if processed % 200 == 0 then
				print(string.format("Fixing floating terrain: %.1f%%", 
					processed / ((xCount/checkStep) * (zCount/checkStep)) * 100))
				task.wait()
			end
		end
	end
end

-- Fourth pass: Create surface cave entrances
print("Phase 4: Creating surface cave entrances...")
for i = 1, Config.SurfaceCaveCount do
	-- Pick random surface location
	local surfX = math.random() * Config.RegionSize.X
	local surfZ = math.random() * Config.RegionSize.Z
	local surfY = Config.RegionSize.Y - 10 -- Near the top

	local entrancePos = Vector3.new(surfX, surfY, surfZ)

	-- Create entrance tunnel
	local tunnelLength = 50 + math.random(20, 80)
	local tunnelDir = Vector3.new(
		(math.random() - 0.5) * 0.4,
		-1, -- Mostly downward
		(math.random() - 0.5) * 0.4
	).Unit

	-- Carve entrance tunnel
	for t = 0, tunnelLength, 3 do
		local point = entrancePos + (tunnelDir * t)

		-- Skip if out of bounds
		if point.Y < 0 or point.Y > Config.RegionSize.Y then
			continue
		end

		-- Variable tunnel size that gets larger as it goes deeper
		local tunnelRadius = Config.SurfaceCaveSize * (0.5 + 0.5 * (t/tunnelLength))
		-- Add some noise to the tunnel shape
		local noiseVal = Noise:GetValue(point.X/20, point.Y/20, point.Z/20)
		tunnelRadius = tunnelRadius * (0.8 + 0.4 * noiseVal)

		Terrain:FillBall(point, tunnelRadius, Enum.Material.Air)

		-- Update grid
		local gx, gy, gz = worldToGrid(point)
		if isValidGridPos(gx, gy, gz) then
			if not caveGrid[gx] then caveGrid[gx] = {} end
			if not caveGrid[gx][gy] then caveGrid[gx][gy] = {} end
			caveGrid[gx][gy][gz] = true
		end

		-- Add some horizontal branches occasionally
		if math.random() < 0.1 then
			local branchDir = Vector3.new(
				math.random() - 0.5,
				(math.random() - 0.5) * 0.3, -- Mostly horizontal
				math.random() - 0.5
			).Unit

			local branchLength = 10 + math.random(5, 20)

			for b = 0, branchLength, 2 do
				local branchPoint = point + (branchDir * b)
				local branchRadius = tunnelRadius * (1 - b/branchLength) * 0.7
				Terrain:FillBall(branchPoint, branchRadius, Enum.Material.Air)
			end
		end
	end

	if i % 2 == 0 then
		task.wait() -- Prevent script timeout
	end
end

-- Add water pools
print("Phase 5: Adding water pools...")

-- Create several water pools at different levels
for i = 1, Config.WaterPoolCount do
	local waterLevel = Config.MinWaterLevel + 
		math.random() * (Config.MaxWaterLevel - Config.MinWaterLevel)

	-- Find a good location for this water pool
	local poolX, poolZ
	local tries = 0
	local found = false

	while not found and tries < 50 do
		poolX = math.random(20, Config.RegionSize.X - 20)
		poolZ = math.random(20, Config.RegionSize.Z - 20)

		-- Check if there's a cave near this location at water level
		local gx, gy, gz = worldToGrid(Vector3.new(poolX, waterLevel, poolZ))
		if isValidGridPos(gx, gy, gz) then
			-- Check if there's a cave nearby
			local hasCaveNearby = false
			for dx = -5, 5 do
				for dz = -5, 5 do
					for dy = -3, 3 do
						local nx, ny, nz = gx + dx, gy + dy, gz + dz
						if isValidGridPos(nx, ny, nz) and
							caveGrid[nx] and caveGrid[nx][ny] and caveGrid[nx][ny][nz] then
							hasCaveNearby = true
							break
						end
					end
					if hasCaveNearby then break end
				end
				if hasCaveNearby then break end
			end

			if hasCaveNearby then
				found = true
			end
		end

		tries = tries + 1
	end

	if found then
		-- Create water pool
		local poolSize = 30 + math.random(10, 50)
		local poolDepth = 3 + math.random(2, 8)

		-- Create pool container (ensure it has walls)
		for dx = -poolSize, poolSize, 3 do
			for dz = -poolSize, poolSize, 3 do
				local dist = math.sqrt(dx*dx + dz*dz) / poolSize
				if dist <= 1 then
					-- Create air pocket for water
					local point = Vector3.new(poolX + dx, waterLevel, poolZ + dz)
					Terrain:FillBall(point, 5, Enum.Material.Air)

					-- Create floor under water
					if dist > 0.9 then -- Make walls thicker at the edges
						local wallPoint = Vector3.new(poolX + dx, waterLevel - poolDepth/2, poolZ + dz)
						Terrain:FillBall(wallPoint, 6, Config.RockMaterial)
					end
				end
			end
		end

		-- Add water
		Terrain:FillBlock(
			CFrame.new(poolX, waterLevel - 1, poolZ),
			Vector3.new(poolSize * 2, poolDepth, poolSize * 2),
			Enum.Material.Water
		)

		print("Created water pool at level " .. waterLevel)
	end

	task.wait() -- Prevent script timeout
end

-- Add some randomized ore veins
print("Adding ore deposits...")
for i = 1, Config.OreDepositCount do
	local pos = Vector3.new(
		math.random() * Config.RegionSize.X,
		math.random(20, Config.RegionSize.Y - 20),
		math.random() * Config.RegionSize.Z
	)

	-- Check if near cave wall
	local gx, gy, gz = worldToGrid(pos)
	local isNearCave = false

	if isValidGridPos(gx, gy, gz) then
		for dx = -2, 2 do
			for dy = -2, 2 do
				for dz = -2, 2 do
					local nx, ny, nz = gx + dx, gy + dy, gz + dz
					if isValidGridPos(nx, ny, nz) and
						caveGrid[nx] and caveGrid[nx][ny] and caveGrid[nx][ny][nz] then
						isNearCave = true
						break
					end
				end
				if isNearCave then break end
			end
			if isNearCave then break end
		end
	end

	if isNearCave then
		local oreSize = 3 + math.random() * Config.MaxOreSize
		local oreMaterial
		local roll = math.random()

		if roll < 0.2 then
			oreMaterial = Enum.Material.CobbleStone -- Common
		elseif roll < 0.5 then
			oreMaterial = Enum.Material.Basalt -- Uncommon
		elseif roll < 0.8 then
			oreMaterial = Enum.Material.Slate -- Uncommon
		elseif roll < 0.95 then
			oreMaterial = Enum.Material.Marble -- Rare
		else
			oreMaterial = Enum.Material.DiamondPlate -- Very rare
		end

		Terrain:FillBall(pos, oreSize, oreMaterial)
	end

	if i % 20 == 0 then
		task.wait() -- Prevent script timeout
	end
end

print("Cave system generation complete!")
print("Total generation time: " .. string.format("%.2f seconds", os.clock() - startTime))