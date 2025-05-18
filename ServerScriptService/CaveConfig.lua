-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
-- VERSION FOR DEBUGGING/STRESS TESTING (Full run of V6.0 CaveGenerator)
local Config = {}

--------------------------------------------------------------------------------
-- I. GENERAL SETTINGS
--------------------------------------------------------------------------------
Config.Seed = 67896 -- Keep your seed for consistency, or change to test variations
Config.DebugMode = true -- Set to true for VERY verbose logging from Perlin & your prints

Config.RegionSize    = Vector3.new(1024, 512, 1024) 
Config.CellSize      = 4 -- can reduce for higher res
Config.RockMaterial  = Enum.Material.Slate

-- !!! CRITICAL FOR MORE CAVES !!!
Config.Threshold     = 0.42 -- Significantly lowered from 0.46. Try 0.40 or 0.38 if still too few caves.

--------------------------------------------------------------------------------
-- II. FBM PARAMETERS (Used by 'localFractalNoise' via Perlin.FBM_Base)
--------------------------------------------------------------------------------
Config.P1_NoiseScale    = 0.022 
Config.P1_Octaves       = 5
Config.P1_Lacunarity    = 2.0
Config.P1_Persistence   = 0.5

-- SubFeatureFBM not directly used by the current main phases unless you add specific calls
Config.SubFeatureFBM = { Frequency = Config.P1_NoiseScale * 2.8, Octaves = 3, Persistence = 0.45, Lacunarity = 1.9 }

--------------------------------------------------------------------------------
-- III. CaveGenerator.lua FEATURE PARAMETERS (Toggles and values)
--------------------------------------------------------------------------------
-- Phase Toggles (Keep them enabled to test all phases)
Config.FormationPhaseEnabled = true
Config.SmoothingPhaseEnabled = true
Config.ConnectivityPhaseEnabled = true
Config.FloodFillPhaseEnabled = true       
Config.SurfaceEntrancesPhaseEnabled = true 
Config.BridgePhaseEnabled = true

-- Phase 1 Biases (Tweaked for debugging)
Config.P1_HeightBias_BottomZonePercent = 0.20
Config.P1_HeightBias_BottomValue = -0.05 
Config.P1_HeightBias_TopZonePercent = 0.80
Config.P1_HeightBias_TopValue    = -0.05 -- Now also encourages caves near top
Config.P1_HeightBias_MidFactor   = -0.02 -- Gentle encouragement in middle

Config.P1_DistanceBias_Max = 0.0 -- Temporarily neutralize distance bias to see raw effect.
-- Can set to a small negative value (e.g., -0.05) to encourage caves near edges.
-- Positive values discourage caves at edges with current bias logic.

Config.P1_VertConn_Strength = 0.08      -- Slightly increased vertical connection bias
Config.P1_VertConn_NoiseScaleFactor = 15 -- Slightly different scale for vertical noise

-- Phase 2: Formations
Config.FormationStartHeight_Cells = 1 
Config.FormationClearance_Cells = 2   
Config.MinFormationLength_Cells = 2
Config.MaxFormationLength_Cells = 7 -- Allow slightly longer formations
Config.BaseFormationRadius_Factor = 0.38 
Config.StalactiteChance = 0.30
Config.StalagmiteChance = 0.40
Config.ColumnChance = 0.15
Config.MinColumnHeight_Cells = 4 

-- Phase 3: Smoothing
Config.SmoothingIterations = 2
Config.SmoothingThreshold_FillAir = 22   -- Keeps air if < 16 rock neighbors
Config.SmoothingThreshold_CarveRock = 4  -- Carves rock if >= 6 air neighbors (original value, can make 5 to carve more)
-- Note: original was (26-solidNeighbors) >= CarveRock -> airNeighbors >= CarveRock

-- Phase 4: Connectivity
-- The original formula for ConnectivityDensity produced a very high number.
-- Forcing a lower, fixed number for initial testing.
Config.ConnectivityDensity = 10 -- Try connecting up to 10 largest components.
-- If you want the original dynamic calculation back:
-- Config.ConnectivityDensity = math.max(3, math.floor((Config.RegionSize.X*Config.RegionSize.Z)/(280*Config.CellSize)))

Config.ConnectivityTunnelRadius_Factor = 0.6 -- Slightly larger tunnels

-- Phase 6: Surface Entrances
Config.SurfaceCaveCount = math.max(2, math.floor((Config.RegionSize.X+Config.RegionSize.Z)/(90*Config.CellSize) )) -- Reduced denominator for potentially more entrances
Config.SurfaceCaveRadius_Factor = 2.5 
Config.SurfaceCaveEntranceIrregularity = 0.5 
Config.SurfaceCaveTunnelSteepness = -0.5 
Config.SurfaceCaveTunnelLength_Cells_MinMax = {15, 25} -- Slightly longer tunnels to help reach caves

-- Phase 7: Bridges
Config.BridgeChamberMinAirCells = 50  -- Reduced slightly
Config.BridgeChamberMinHeight_Cells = 5 -- Reduced slightly
Config.BridgeThickness_Cells_MinMax = {1, 2} -- Thinner bridges initially
Config.BridgeWidth_Cells_MinMax = {1, 2}   

--------------------------------------------------------------------------------
-- IV. ORE
--------------------------------------------------------------------------------
Config.OreVeins = { 
	Enabled = true, -- Test ore placement
	OreList = {
		{ Name = "Iron", Material = Enum.Material.CorrodedMetal, 
			NoiseScale = 0.07, Octaves = 3, Persistence = 0.5, Lacunarity = 2.0,
			Threshold = 0.75, Rarity = 0.18 -- Slightly increased rarity/threshold
		},
		{ Name = "Crystal", Material = Enum.Material.Glass, 
			NoiseScale = 0.11, Octaves = 2, Persistence = 0.6, Lacunarity = 1.9,
			Threshold = 0.80, Rarity = 0.12 -- Slightly increased
		},
		-- Add a more common ore for testing visibility
		{ Name = "DebugOre", Material = Enum.Material.Neon, -- Make it stand out
			NoiseScale = 0.05, Octaves = 4, Persistence = 0.5, Lacunarity = 2.0,
			Threshold = 0.65, Rarity = 0.30 -- More common
		},
	}
}
--------------------------------------------------------------------------------
-- V. PERFORMANCE / INTERNAL (Not directly changed by CaveGenerator phases unless used for advanced noise)
--------------------------------------------------------------------------------
Config.GlobalYieldBatchSize = 100000 -- Smaller for more responsive Studio during debug, but slower overall. Increase to 20000-50000 for "production" runs.
Config.VoxelSize = 4 -- Roblox's terrain voxel unit, not directly used by CaveGenerator grid logic but good for reference.

-- Default parameters for Perlin.lua's FBM functions IF they are called without explicit args
Config.FBM_DefaultOctaves = 6
Config.FBM_DefaultPersistence = 0.5
Config.FBM_DefaultLacunarity = 2.0
-- You can add other defaults here for DomainWarp, GuidedFBM etc. from Perlin.lua if you start using them without passing all params.
Config.P1_DomainWarp_Strength = 25       -- Example if you add domain warp to Phase 1
Config.P1_DomainWarp_FrequencyFactor = 0.4 -- Example

return Config