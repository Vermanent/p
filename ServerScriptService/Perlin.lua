-- ModuleScript: Perlin
-- Path: ServerScriptService/NoiseGenerator.lua/Perlin.lua
local Perlin = {}

local grad3 = {
	{1,1,0},{-1,1,0},{1,-1,0},{-1,-1,0},
	{1,0,1},{-1,0,1},{1,0,-1},{-1,0,-1},
	{0,1,1},{0,-1,1},{0,1,-1},{0,-1,-1}
}

-- Create permutation table with proper 1-based indexing for Lua
local p = {}
for i = 0, 255 do 
	p[i + 1] = i 
end

local Config = require(script.Parent.Parent.CaveConfig)
math.randomseed(Config.Seed)
-- Shuffle the permutation table properly
for i = 255, 1, -1 do
	local j = math.random(0, i)
	p[i + 1], p[j + 1] = p[j + 1], p[i + 1]
end

-- Duplicate the permutation table to avoid overflow
for i = 0, 255 do 
	p[i + 257] = p[i + 1] 
end

local function fade(t) 
	return t * t * t * (t * (t * 6 - 15) + 10) 
end

local function lerp(a, b, t) 
	return a + t * (b - a) 
end

local function dot(g, x, y, z) 
	return g[1] * x + g[2] * y + g[3] * z 
end

function Perlin:Noise(x, y, z)
	-- Convert to positive numbers and get integer indices
	local X = bit32.band(math.floor(x), 255) + 1
	local Y = bit32.band(math.floor(y), 255) + 1
	local Z = bit32.band(math.floor(z), 255) + 1

	-- Get fractional parts
	x = x - math.floor(x)
	y = y - math.floor(y)
	z = z - math.floor(z)

	-- Compute fade curves
	local u, v, w = fade(x), fade(y), fade(z)

	-- Hash coordinates
	local A  = p[X] + Y
	local AA = p[A] + Z
	local AB = p[A + 1] + Z
	local B  = p[X + 1] + Y
	local BA = p[B] + Z
	local BB = p[B + 1] + Z

	-- Get gradient indices and ensure they're within bounds for the grad3 table
	local AAi = bit32.band(p[AA], 11) + 1
	local BAi = bit32.band(p[BA], 11) + 1
	local ABi = bit32.band(p[AB], 11) + 1
	local BBi = bit32.band(p[BB], 11) + 1

	local AA1i = bit32.band(p[AA + 1], 11) + 1
	local BA1i = bit32.band(p[BA + 1], 11) + 1
	local AB1i = bit32.band(p[AB + 1], 11) + 1
	local BB1i = bit32.band(p[BB + 1], 11) + 1

	-- Get gradients
	local gAA, gBA = grad3[AAi], grad3[BAi]
	local gAB, gBB = grad3[ABi], grad3[BBi]
	local gAA1, gBA1 = grad3[AA1i], grad3[BA1i]
	local gAB1, gBB1 = grad3[AB1i], grad3[BB1i]

	-- Calculate dot products
	local x1 = lerp(dot(gAA, x, y, z), dot(gBA, x - 1, y, z), u)
	local x2 = lerp(dot(gAB, x, y - 1, z), dot(gBB, x - 1, y - 1, z), u)
	local y1 = lerp(x1, x2, v)

	local x3 = lerp(dot(gAA1, x, y, z - 1), dot(gBA1, x - 1, y, z - 1), u)
	local x4 = lerp(dot(gAB1, x, y - 1, z - 1), dot(gBB1, x - 1, y - 1, z - 1), u)
	local y2 = lerp(x3, x4, v)

	-- Map from [-1,1] to [0,1] range
	return (lerp(y1, y2, w) + 1) * 0.5
end

return Perlin