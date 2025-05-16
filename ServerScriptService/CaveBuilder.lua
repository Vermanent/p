-- Script: CaveBuilder
-- Path: ServerScriptService/CaveBuilder.lua
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local Config = require(script.Parent.CaveConfig)
local Noise = require(script.Parent.NoiseGenerator)

math.randomseed(Config.Seed)

local origin = Vector3.new(0, 0, 0)
local center = origin + Config.RegionSize / 2

-- Fill solid rock
Terrain:FillBlock(CFrame.new(center), Config.RegionSize, Config.RockMaterial)

local function fractalNoise(x, y, z)
	local sum = 0
	local amplitude = 1
	local frequency = Config.NoiseScale
	for i = 1, Config.Octaves do
		sum = sum + Noise:GetValue(x * frequency, y * frequency, z * frequency) * amplitude
		frequency = frequency * Config.Lacunarity
		amplitude = amplitude * Config.Persistence
	end
	local norm = (2 - math.pow(Config.Persistence, Config.Octaves))
	return sum / norm
end

local cell = Config.CellSize
local xCount = math.floor(Config.RegionSize.X / cell)
local yCount = math.floor(Config.RegionSize.Y / cell)
local zCount = math.floor(Config.RegionSize.Z / cell)
local processed = 0
local total = xCount * yCount * zCount

for ix = 0, xCount do
	for iy = 0, yCount do
		for iz = 0, zCount do
			local wp = origin + Vector3.new(
				ix * cell + cell / 2,
				iy * cell + cell / 2,
				iz * cell + cell / 2
			)
			local density = fractalNoise(wp.X, wp.Y, wp.Z)
			if density < Config.Threshold then
				-- Use FillBall for smooth caves, radius varies for natural shape
				local radius = cell * (0.6 + 0.4 * Noise:GetValue(wp.X, wp.Y, wp.Z))
				Terrain:FillBall(wp, radius, Enum.Material.Air)
			end

			processed += 1
			if processed % 5000 == 0 then
				print(string.format("Progress: %.2f%%", processed / total * 100))
				task.wait()
			end
		end
	end
end

-- Add water plane at specified water level
Terrain:FillBlock(
	CFrame.new(
		origin.X + Config.RegionSize.X / 2,
		Config.WaterLevel,
		origin.Z + Config.RegionSize.Z / 2
	),
	Vector3.new(Config.RegionSize.X, 1, Config.RegionSize.Z),
	Enum.Material.Water
)