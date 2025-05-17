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
Config.Octaves       = 4     -- Increased from 3 for more detailed cave shapes

-- Frequency multiplier per octave
Config.Lacunarity    = 2.0

-- Amplitude multiplier per octave
-- Lower values = smoother caves; higher values = more chaotic caves
Config.Persistence   = 0.5   -- Increased from 0.45 for slightly more chaotic, natural caves

-- Seed for random permutation - change for different cave layouts
Config.Seed          = 67890

-- Material for solid rock fill
Config.RockMaterial  = Enum.Material.Granite

-- Enable cave connectivity pass
Config.EnableConnectivity = true
Config.ConnectivityDensity = 20  -- Increased from 12 for more connecting tunnels

-- Enable anti-floating terrain system
Config.RemoveFloatingBlocks = true
Config.FloatingCheckRadius = 30
Config.MinSupportedSize = 25     -- Reduced from 35 to catch smaller floating segments

-- Water settings - Multiple water bodies
Config.WaterPoolCount = 6
Config.MinWaterLevel = 50
Config.MaxWaterLevel = 200

-- Ore frequency settings
Config.OreDepositCount = 100
Config.MaxOreSize = 10

-- Surface caves (entrance) settings
Config.SurfaceCaveCount = 12  -- Increased from 8 for more entrances
Config.SurfaceCaveSize = 20  -- Increased from 15 for larger, noticeable entrances

return Config