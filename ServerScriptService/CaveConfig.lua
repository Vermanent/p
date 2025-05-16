-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
local Config = {}

-- Total cave generation region (X, Y, Z)
Config.RegionSize    = Vector3.new(2048, 512, 2048)

-- Size of each sample cell (smaller = finer detail but slower generation)
Config.CellSize      = 5  -- Slightly increased for performance

-- Noise threshold: values below become air (cave)
-- Lower values = fewer, smaller caves; higher values = larger, more connected caves
Config.Threshold     = 0.45  -- Lowered to create less air, more terrain

-- Base scale for noise sampling (smaller = larger cave structures)
Config.NoiseScale    = 0.015  -- Adjusted for more defined cave structures

-- Number of noise octaves for fractal Brownian motion
-- More octaves = more detail but slower generation
Config.Octaves       = 3  -- Reduced for performance

-- Frequency multiplier per octave
Config.Lacunarity    = 2.0

-- Amplitude multiplier per octave
-- Lower values = smoother caves; higher values = more chaotic caves
Config.Persistence   = 0.45  -- Reduced for smoother caves

-- Seed for random permutation - change for different cave layouts
Config.Seed          = 67890

-- Material for solid rock fill
Config.RockMaterial  = Enum.Material.Granite

-- Enable cave connectivity pass
Config.EnableConnectivity = true
Config.ConnectivityDensity = 12  -- Increased for better connected caves

-- Enable anti-floating terrain system
Config.RemoveFloatingBlocks = true
Config.FloatingCheckRadius = 30
Config.MinSupportedSize = 35  -- Reduced slightly

-- Water settings - Multiple water bodies
Config.WaterPoolCount = 6
Config.MinWaterLevel = 50
Config.MaxWaterLevel = 200

-- Ore frequency settings
Config.OreDepositCount = 100
Config.MaxOreSize = 10

-- Surface caves (entrance) settings
Config.SurfaceCaveCount = 8  -- Reduced slightly
Config.SurfaceCaveSize = 15  -- Smaller entrances

return Config