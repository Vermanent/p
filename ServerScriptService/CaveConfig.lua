-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
local Config = {}

-- Total cave generation region (X, Y, Z)
Config.RegionSize    = Vector3.new(2048, 512, 2048)
-- Size of each sample cell (smaller = finer detail)
Config.CellSize      = 6
-- Noise threshold: values below become air (cave)
Config.Threshold     = 0.45
-- Base scale for noise sampling
Config.NoiseScale    = 0.01
-- Number of noise octaves for fractal Brownian motion
Config.Octaves       = 3
-- Frequency multiplier per octave
Config.Lacunarity    = 2.0
-- Amplitude multiplier per octave
Config.Persistence   = 0.5
-- Seed for random permutation
Config.Seed          = 67890
-- Material for solid rock fill
Config.RockMaterial  = Enum.Material.Granite
-- Height at which to add water plane
Config.WaterLevel    = 40

return Config