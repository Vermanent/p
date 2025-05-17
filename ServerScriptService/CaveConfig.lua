-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
-- VERSION 4.9 (Suitable for full run of V5.2 CaveBuilder)
local Config = {}

--------------------------------------------------------------------------------
-- I. GENERAL SETTINGS
--------------------------------------------------------------------------------
Config.Seed = 67896 
Config.DebugMode = false -- Set to true for VERY verbose logging from CaveBuilder's P1 & NoiseGenerator

Config.RegionSize    = Vector3.new(1024, 512, 1024) 
Config.CellSize      = 7 
Config.RockMaterial  = Enum.Material.Slate

Config.Threshold     = 0.46 

--------------------------------------------------------------------------------
-- II. FBM PARAMETERS (Used by CaveBuilder's internal 'fractalNoise')
--------------------------------------------------------------------------------
Config.P1_NoiseScale    = 0.022 
Config.P1_Octaves       = 5
Config.P1_Lacunarity    = 2.0
Config.P1_Persistence   = 0.5

Config.SubFeatureFBM = { Frequency = Config.P1_NoiseScale * 2.8, Octaves = 3, Persistence = 0.45, Lacunarity = 1.9 }

--------------------------------------------------------------------------------
-- III. CaveBuilder.lua FEATURE PARAMETERS (Toggles and values)
--------------------------------------------------------------------------------
Config.FormationPhaseEnabled = true
Config.SmoothingPhaseEnabled = true
Config.ConnectivityPhaseEnabled = true
Config.FloodFillPhaseEnabled = true       
Config.SurfaceEntrancesPhaseEnabled = true 
Config.BridgePhaseEnabled = true

Config.P1_HeightBias_BottomZonePercent = 0.20; Config.P1_HeightBias_BottomValue = -0.10
Config.P1_HeightBias_TopZonePercent = 0.80;    Config.P1_HeightBias_TopValue = 0.15  
Config.P1_HeightBias_MidFactor = -0.10       
Config.P1_DistanceBias_Max = 0.10            
Config.P1_VertConn_Strength = 0.07
Config.P1_VertConn_NoiseScaleFactor = 20      

Config.FormationStartHeight_Cells = 2 
Config.FormationClearance_Cells = 2   
Config.MinFormationLength_Cells = 2; Config.MaxFormationLength_Cells = 6
Config.BaseFormationRadius_Factor = 0.38 
Config.StalactiteChance = 0.35; Config.StalagmiteChance = 0.45; Config.ColumnChance = 0.20
Config.MinColumnHeight_Cells = 4 

Config.SmoothingIterations = 2
Config.SmoothingThreshold_FillAir = 16
Config.SmoothingThreshold_CarveRock = 6 

Config.ConnectivityDensity = math.max(3, math.floor((Config.RegionSize.X*Config.RegionSize.Z)/(280*Config.CellSize)))
Config.ConnectivityTunnelRadius_Factor = 0.5

Config.SurfaceCaveCount = math.max(2, math.floor((Config.RegionSize.X+Config.RegionSize.Z)/(70*Config.CellSize) ))
Config.SurfaceCaveRadius_Factor = 2.2 
Config.SurfaceCaveEntranceIrregularity = 0.4 
Config.SurfaceCaveTunnelSteepness = -0.35 
Config.SurfaceCaveTunnelLength_Cells_MinMax = {8, 15} 

Config.BridgeChamberMinAirCells = 60
Config.BridgeChamberMinHeight_Cells = 6 
Config.BridgeThickness_Cells_MinMax = {1, 3}
Config.BridgeWidth_Cells_MinMax = {1, 2}   
--------------------------------------------------------------------------------
-- IV. ORE (Logic for placement still needs to be added to CB if desired)
--------------------------------------------------------------------------------
Config.OreVeins = { 
	Enabled = false, -- Set true to try ore placement
	OreList = {
		{ Name = "Iron", Material = Enum.Material.CorrodedMetal, 
			NoiseScale = 0.07, Octaves = 3, Persistence = 0.5, Lacunarity = 2.0, -- For fractalNoise
			Threshold = 0.78, Rarity = 0.15 
		},
		{ Name = "Crystal", Material = Enum.Material.Glass, 
			NoiseScale = 0.11, Octaves = 2, Persistence = 0.6, Lacunarity = 1.9,
			Threshold = 0.83, Rarity = 0.1 
		},
	}
}
--------------------------------------------------------------------------------
-- V. PERFORMANCE
--------------------------------------------------------------------------------
Config.GlobalYieldBatchSize = 18000 
Config.VoxelSize = 4
Config.FBM_DefaultOctaves=6; Config.FBM_DefaultPersistence=0.5; Config.FBM_DefaultLacunarity=2.0

return Config