-- ModuleScript: NoiseGenerator
-- Path: ServerScriptService/NoiseGenerator.lua
-- VERSION 4: Simple wrapper for the NEW Perlin.Noise, mimicking your old Noise:GetValue behavior.

local Noise = {}

-- Requires the NEW Perlin module (your advanced one)
local Perlin = require(script.Perlin)

Noise.PerlinModule = Perlin -- Expose Perlin module if CaveBuilder needs direct access for other effects

-- Public API: get a single Perlin noise value [0,1] at world position
-- This is what CaveBuilder's internal FBM function will call repeatedly.
function Noise:GetValue(x, y, z)
	return Perlin.Noise(x, y, z) -- Uses the Perlin.Noise() from your advanced Perlin.lua
end

-- GetCaveDensity is no longer the primary density source for CaveBuilder's Phase 1.
-- CaveBuilder will now implement its own FBM loop as it did before.
-- We can keep this here if later phases want to use more complex pre-built noise patterns.
function Noise.GetComplexCaveDensity_DEPRECATED(worldX, worldY, worldZ)
	-- This would be the NoiseGenerator.GetCaveDensity from V3.1 if you ever wanted to switch back
	-- to a more complex, layered noise approach directly from this module.
	-- For now, CaveBuilder handles FBM itself.
	local cfg = require(script.Parent.CaveConfig) -- Re-require if used, or pass config
	local baseFbm = Perlin.FBM_Base(worldX, worldY, worldZ,
		cfg.ShapeNoise.Octaves, cfg.ShapeNoise.Persistence, cfg.ShapeNoise.Lacunarity,
		cfg.ShapeNoise.Frequency, cfg.ShapeNoise.Amplitude
	)
	return baseFbm -- Simplified example
end


return Noise