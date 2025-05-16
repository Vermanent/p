-- ModuleScript: Perlin
-- Path: ServerScriptService/NoiseGenerator.lua/Perlin.lua
local Perlin = {}

local grad3 = {
	{1,1,0},{-1,1,0},{1,-1,0},{-1,-1,0},
	{1,0,1},{-1,0,1},{1,0,-1},{-1,0,-1},
	{0,1,1},{0,-1,1},{0,1,-1},{0,-1,-1}
}

local p = {}
for i = 1, 256 do p[i] = i - 1 end

local Config = require(script.Parent.Parent.CaveConfig)
math.randomseed(Config.Seed)
for i = 256, 2, -1 do
	local j = math.random(i)
	p[i], p[j] = p[j], p[i]
end
for i = 1, 256 do p[256 + i] = p[i] end

local function fade(t) return t*t*t*(t*(t*6 - 15) + 10) end
local function lerp(a, b, t) return a + t * (b - a) end
local function dot(g, x, y, z) return g[1]*x + g[2]*y + g[3]*z end

function Perlin:Noise(x, y, z)
	local X = (math.floor(x) % 256) + 1
	local Y = (math.floor(y) % 256) + 1
	local Z = (math.floor(z) % 256) + 1

	x, y, z = x - math.floor(x), y - math.floor(y), z - math.floor(z)
	local u, v, w = fade(x), fade(y), fade(z)

	local A = p[X] + Y
	local AA = p[A] + Z
	local AB = p[A + 1] + Z
	local B = p[X + 1] + Y
	local BA = p[B] + Z
	local BB = p[B + 1] + Z

	local gAA, gBA = grad3[(p[AA] % 12) + 1], grad3[(p[BA] % 12) + 1]
	local gAB, gBB = grad3[(p[AB] % 12) + 1], grad3[(p[BB] % 12) + 1]
	local gAA1, gBA1 = grad3[(p[AA + 1] % 12) + 1], grad3[(p[BA + 1] % 12) + 1]
	local gAB1, gBB1 = grad3[(p[AB + 1] % 12) + 1], grad3[(p[BB + 1] % 12) + 1]

	local x1 = lerp(dot(gAA, x, y, z), dot(gBA, x - 1, y, z), u)
	local x2 = lerp(dot(gAB, x, y - 1, z), dot(gBB, x - 1, y - 1, z), u)
	local y1 = lerp(x1, x2, v)

	local x3 = lerp(dot(gAA1, x, y, z - 1), dot(gBA1, x - 1, y, z - 1), u)
	local x4 = lerp(dot(gAB1, x, y - 1, z - 1), dot(gBB1, x - 1, y - 1, z - 1), u)
	local y2 = lerp(x3, x4, v)

	return (lerp(y1, y2, w) + 1) * 0.5
end

return Perlin