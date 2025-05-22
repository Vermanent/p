-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
local Config = {}

--------------------------------------------------------------------------------
-- I. GENERAL SETTINGS
--------------------------------------------------------------------------------
Config.Seed = math.random(1,9999999) -- Or a static seed like 12345 for reproducible tests
Config.RegionSize    = Vector3.new(1024, 512, 1024)
Config.CellSize      = 4
Config.RockMaterial  = Enum.Material.Rock
Config.Threshold     = 0.53 -- Main threshold for Phase_InitialNoiseCarve (if enabled)

--------------------------------------------------------------------------------
-- II. LOGGING CONFIGURATION
--------------------------------------------------------------------------------
Config.Logging = {
	logLevelName = "DEBUG", 
	showTimestamp = false, -- Set to true if timestamps are desired in output
	showSource = true,
	defaultSource = "CaveGen",
}

--------------------------------------------------------------------------------
-- III. GLOBAL PERFORMANCE & INTERNAL DEBUG SETTINGS
--------------------------------------------------------------------------------
Config.GlobalYieldBatchSize = 200000
Config.SurfaceScanYieldBatchSize = 10000
Config.GreedyMesherInnerYieldThreshold = 50000
Config.GreedyMesherCallCountLogFrequency = 75000

Config.FloodFillContext_MaxInitialDebugAttempts = 1
Config.FloodFillContext_MaxInitialComponentLogs = 1
Config.FloodFillContext_LargeComponentThreshold = 50000
Config.FloodFillContext_SmallComponentThreshold = 50
Config.FloodFillLogFirstAirCellFound = false -- Set true to log coords of first air cell encountered by flood fill iterator
Config.FloodFillMaxNilCellLogs = 1
Config.FloodFillZSliceLogDivisor = 20 -- How often to log progress during flood fill main scan

Config.GreedyMesherZSliceLogDivisor_DebugMode = math.max(1, math.floor(Config.RegionSize.Z / Config.CellSize / 16))
Config.GreedyMesherZSliceLogDivisor_ReleaseMode = math.max(1, math.floor(Config.RegionSize.Z / Config.CellSize / 8))

--------------------------------------------------------------------------------
-- IV. CORE NOISE FUNCTION DEFAULTS (Used by Perlin.lua if not overridden)
--------------------------------------------------------------------------------
Config.FBM_DefaultOctaves = 4
Config.FBM_DefaultPersistence = 0.5
Config.FBM_DefaultLacunarity = 2.0
Config.RMF_DefaultOffset = 1.0 -- For Ridged Multifractal
Config.RMF_DefaultGain = 2.0   -- For Ridged Multifractal

--------------------------------------------------------------------------------
-- V. PATH GENERATION PARAMETERS (For _generateWindingPath_PerlinAdvanced)
--------------------------------------------------------------------------------
Config.PathGeneration = {
	GlobalTargetInfluence = 0.3,    -- (0-1) How much a global (noisy) target pulls the main trunk.
	GlobalTargetNoiseScale = 0.002, -- Scale for the noise affecting the global target point.

	ObstacleAvoidance = { 
		LookAheadDistanceCells = 1,  -- How many path-segment-multiples to look ahead
		MaxSteerAttempts = 5,        -- Number of attempts to steer away
		SteerAngleDeg = 50,          -- Angle (degrees) to steer by on each attempt
		CarveRadiusForCheckFactor = 0.8 -- (Currently for future advanced checking)
	},

	Trunk = {
		SegmentBaseLengthStuds = 12,    
		PathPerlin_MaxTurnDeg = 20,          
		PathPerlin_YawNoiseScale = 0.015,  
		PathPerlin_YawStrengthFactor = 0.9,
		PathPerlin_PitchNoiseScale = 0.02,   
		PathPerlin_PitchStrengthFactor = 0.3,
		-- Dynamic modulation along the path
		RadiusVarianceNoiseScale = 0.03,  
		RadiusVarianceFactor = 0.15,     
		TurnTendencyNoiseScale = 0.02,    
		TurnTendencyVariance = 0.2,
		-- For initial clearance at the start of the trunk
		CarveInitialClearanceAtStart = true,
		InitialClearanceRadiusCells = 5 
	},
	Branch = { 
		SegmentBaseLengthStuds = 9,
		PathPerlin_MaxTurnDeg = 30,
		PathPerlin_YawNoiseScale = 0.035,
		PathPerlin_YawStrengthFactor = 0.95, -- Increased slightly from previous example
		PathPerlin_PitchNoiseScale = 0.04,
		PathPerlin_PitchStrengthFactor = 0.5,
		RadiusVarianceNoiseScale = 0.06,
		RadiusVarianceFactor = 0.20, -- Adjusted from example
		TurnTendencyNoiseScale = 0.05,
		TurnTendencyVariance = 0.35,
		-- For how branches initially aim from parent
		BranchOutwardMinMax = {min = 0.4, max = 0.8}, 
		BranchTangentInfluenceMinMax = {min = -0.1, max = 0.3}, 
		CarveInitialClearanceAtStart = false, -- Branches typically start from existing AIR
		InitialClearanceRadiusCells = 0 
	},
	Spur = { 
		SegmentBaseLengthStuds = 7,
		PathPerlin_MaxTurnDeg = 40,
		PathPerlin_YawNoiseScale = 0.045,
		PathPerlin_YawStrengthFactor = 1.0,
		PathPerlin_PitchNoiseScale = 0.05,
		PathPerlin_PitchStrengthFactor = 0.6,
		RadiusVarianceNoiseScale = 0.07,
		RadiusVarianceFactor = 0.25,
		TurnTendencyNoiseScale = 0.06,
		TurnTendencyVariance = 0.4,
		CarveInitialClearanceAtStart = false,
		InitialClearanceRadiusCells = 0
	},
	LoopConnector = { 
		SegmentBaseLengthStuds = 10, -- Numeric value
		PathPerlin_MaxTurnDeg = 28,  -- <<< THIS FIELD (or similar) IS CRITICAL
		PathPerlin_YawNoiseScale = 0.03,
		PathPerlin_YawStrengthFactor = 0.9,
		PathPerlin_PitchNoiseScale = 0.035,
		PathPerlin_PitchStrengthFactor = 0.45,
		-- These dynamic parameters are for _generateWindingPath_PerlinAdvanced:
		RadiusVarianceNoiseScale = 0.055, 
		RadiusVarianceFactor = 0.15,   
		TurnTendencyNoiseScale = 0.045,
		TurnTendencyVariance = 0.25,
		-- These are specific to Phase_ConnectLoops itself:
		RadiusStuds_MinMax = {min = 3, max = 5}, 
		MaxDistanceStuds = 90                   
	},
	-- MultiLevel_Trunk_PathPerlin = { ... } -- Define if making multi-level trunks also use PerlinAdvanced
}

--------------------------------------------------------------------------------
-- VI. SKELETON STRUCTURE PARAMETERS (Trunk, Branch, Spur general properties)
--------------------------------------------------------------------------------
Config.Skeleton_Trunk = {
	StartRadiusStuds = 10,       -- Base start radius for the trunk tunnel
	EndRadiusStuds = 14,        -- Base end radius for the trunk tunnel
	RadiusVarianceFactor = 0.10,-- Additional overall random variance applied to the lerped base radius (this is separate from Perlin-based radius variance along path)
	TargetLengthStuds = 200,   
	Count_MinMax = {min = 4, max = 6}, -- Number of primary branches to attempt from trunk

	StartX_Range = {0.15, 0.25}, -- Start position ranges (as factor of grid size)
	StartY_Range = {0.45, 0.55}, 
	StartZ_Range = {0.15, 0.25}, 
	-- Note: Detailed path style parameters (winding, segment length) are in Config.PathGeneration.Trunk
}

Config.Skeleton_Branch = { 
	-- These are parameters for individual branches, not controlled by PathGeneration table
	RadiusStuds_MinMax = {min = 5, max = 8},  
	LengthStuds_MinMax = {min = 40, max = 80}, 
	-- Count_MinMax_PerTrunk is effectively defined in Config.Skeleton_Trunk.Count_MinMax
	-- Note: Detailed path style parameters are in Config.PathGeneration.Branch
}

Config.Skeleton_Spur = { 
	RadiusStuds_MinMax = {min = 3, max = 5},   
	LengthStuds_MinMax = {min = 20, max = 40},  
	Count_MinMax_PerTrunk = {min=3, max=7}, -- Number of spurs to attempt from trunk
	MinDistFromBranchSegments = 2, -- Min trunk segments away from a primary branch start
	-- Note: Detailed path style parameters are in Config.PathGeneration.Spur
}

--------------------------------------------------------------------------------
-- VII. PHASE-SPECIFIC PARAMETERS 
--------------------------------------------------------------------------------

-- SECTION A: Initial FBM Carving (Phase_InitialNoiseCarve - Set enabled=false in phasesToRun if using Skeleton as primary)
Config.P1_UseHierarchicalNoise = false 
Config.P1_BroadStructure_NoiseScaleFactor = 0.08 
Config.P1_BroadStructure_Octaves = 1
Config.P1_BroadStructure_Threshold = 0.65 -- Higher threshold = less SOLID from broad pass

Config.P1_NoiseScale    = 0.018 -- Slightly larger scale for bigger initial voids if used
Config.P1_Octaves       = 3     -- Fewer octaves for broader shapes
Config.P1_Lacunarity    = 2.0
Config.P1_Persistence   = 0.40

Config.P1_UseDomainWarp = true -- Generally good for organic shapes
Config.P1_DomainWarp_Strength = 100.0
Config.P1_DomainWarp_FrequencyFactor = 0.0020
Config.P1_DomainWarp_Octaves = 2
Config.P1_DomainWarp_Persistence = 0.5
Config.P1_DomainWarp_Lacunarity = 2.0

Config.P1_HeightBias_BottomZonePercent = 0.10
Config.P1_HeightBias_BottomValue = -0.05 -- Slightly stronger bias against bottom if FBM used
Config.P1_HeightBias_TopZonePercent = 0.95
Config.P1_HeightBias_TopValue    = 0.02
Config.P1_HeightBias_MidFactor   = -0.02
Config.P1_DistanceBias_Max = 0.04
Config.P1_VertConn_Strength = 0.06
Config.P1_VertConn_NoiseScaleFactor = 8

-- ... (P1_UseSurfaceAdaptiveFBM, P1_UseAnisotropicFBM settings - can often be false if basic P1 is minimal) ...
Config.P1_UseSurfaceAdaptiveFBM = false
Config.P1_Adaptive_TargetThreshold = Config.Threshold
Config.P1_Adaptive_NearSurfaceOctaves = (Config.P1_Octaves or 4)
Config.P1_Adaptive_FarSurfaceOctaves = (Config.P1_Octaves or 4) - 2
Config.P1_Adaptive_TransitionRange = 0.08

Config.P1_UseAnisotropicFBM = false
Config.P1_Aniso_StressFreqFactor = 0.0008
Config.P1_Aniso_StressStrength = 0.75
Config.P1_Aniso_FoundationOctaves = 1
Config.P1_Aniso_AnisotropicScaleFactor = 0.5

-- SECTION B: Rock Formations (Phase_GrowRockFormations)
Config.FormationPhaseEnabled = true
Config.FormationStartHeight_Cells = 1
Config.FormationClearance_Cells = 2
Config.MinFormationLength_Cells = 3    -- Slightly longer min
Config.MaxFormationLength_Cells = 12   -- Slightly longer max
Config.BaseFormationRadius_Factor = 0.4 
Config.StalactiteChance = 0.25         -- More typical chances now
Config.StalagmiteChance = 0.30
Config.ColumnChance = 0.10
Config.MinColumnHeight_Cells = 4
Config.FormationMinDistanceFromTunnel_Cells = 3 -- Tuned value
Config.FormationHorizontalMinAirNeighbors = 4 

-- SECTION C: Smoothing (Phase_ApplySmoothing)
Config.SmoothingPhaseEnabled = true
Config.SmoothingIterations = 1
Config.SmoothingThreshold_FillAir = 22 
Config.SmoothingThreshold_CarveRock = 5 -- Slightly more aggressive carving

-- SECTION D: Connectivity (Phase_EnsureMainConnectivity)
Config.ConnectivityPhaseEnabled = true
Config.ConnectivityDensity = math.max(2, math.floor((Config.RegionSize.X*Config.RegionSize.Z)/(10000*Config.CellSize^2))) -- Slightly less dense
Config.ConnectivityTunnelRadius_Factor = 1.0 

-- SECTION E: Flood Fill Cleanup (Phase_CleanupIsolatedAir)
Config.FloodFillPhaseEnabled = true 

-- SECTION F: Surface Entrances (Phase_CreateSurfaceEntrances)
Config.SurfaceEntrancesPhaseEnabled = true
Config.SurfaceCaveCount = math.max(1, math.floor(Config.RegionSize.X / 450)) -- Slightly fewer
Config.SurfaceCaveRadius_Factor = 1.8 
Config.SurfaceCaveEntranceIrregularity = 0.5
Config.SurfaceCaveTunnelSteepness = -0.65
Config.SurfaceCaveTunnelLength_Cells_MinMax = {min=25, max=50}

-- SECTION G: Bridges (Phase_BuildBridges)
Config.BridgePhaseEnabled = true
Config.BridgeChamberMinAirCells = 100
Config.BridgeChamberMinHeight_Cells = 4
Config.BridgeThickness_Cells_MinMax = {1, 2}
Config.BridgeWidth_Cells_MinMax = {1, 3} -- Allow thinner bridges

-- SECTION H: Agent Tunnels (Phase_AgentTunnels)
Config.AgentTunnels_Enabled = false -- Keep false until explicitly tuning its performance
Config.AgentTunnels_NumInitialAgents = 4    
Config.AgentTunnels_MaxActiveAgents = 10     
Config.AgentTunnels_MaxTotalAgentSteps = 30000 
Config.AgentTunnels_AgentLifetime_MinMax = {min = 120, max = 280} 
Config.AgentTunnels_TunnelRadius_MinMax = {min = 1, max = 2}
Config.AgentTunnels_UseNonAxialMovement = true
Config.AgentTunnels_TurnAngle_MinMax_Degrees = {min = 15, max = 55}
Config.AgentTunnels_CurlNoise_TurnStrength_Degrees = 40
Config.AgentTunnels_StepLength = 0.75 
Config.AgentTunnels_PreferFlattening = true
Config.AgentTunnels_FlatteningStrength = 0.3
Config.AgentTunnels_TurnChance = 0.18 
Config.AgentTunnels_AvoidImmediateReverse = true
Config.AgentTunnels_BranchChance = 0.009 
Config.AgentTunnels_BranchLifetimeFactor = 0.45
Config.AgentTunnels_BranchTurnAngle = 70
Config.AgentTunnels_MaxStuckBeforeDeath = 7
Config.AgentTunnels_StartPolicy = "MainCaveAir" 
Config.AgentTunnels_SeedPoints = {}
Config.AgentTunnels_CurlNoise_Enabled = true
Config.AgentTunnels_CurlNoise_Influence = 0.65
Config.AgentTunnels_CurlNoise_FrequencyFactor = 0.0045
Config.AgentTunnels_CurlNoise_Octaves = 1
Config.AgentTunnels_CurlNoise_Persistence = 0.5
Config.AgentTunnels_CurlNoise_Lacunarity = 2.0
Config.AgentTunnels_CurlNoise_WorldScale = Config.CellSize * 18

-- SECTION I: Ore Veins
Config.OreVeins = {
	Enabled = true,
	OreList = {
		{ Name = "Iron", Material = Enum.Material.CorrodedMetal,
			NoiseScale = 0.05, Octaves = 3, Persistence = 0.5, Lacunarity = 2.0,
			Threshold = 0.78, Rarity = 0.07 -- Adjusted thresholds/rarity
		},
		{ Name = "Crystal", Material = Enum.Material.Glass,
			NoiseScale = 0.075, Octaves = 2, Persistence = 0.6, Lacunarity = 1.9,
			Threshold = 0.83, Rarity = 0.04
		},
	}
}
--------------------------------------------------------------------------------
-- VIII. Multi-Level Parameters (if separated from Phase_GenerateMultiLevels internal logic)
--------------------------------------------------------------------------------
Config.MultiLevel = {
	CreateUpperLevel = true,
	UpperLevelYOffsetStuds_MinMax = {min = 20, max = 32}, -- Increased offset a bit from default in phase
	UpperLevelRadiusStuds_MinMax = {min = 6, max = 10},

	CreateLowerLevel = true,
	LowerLevelYOffsetStuds_MinMax = {min = 16, max = 28},
	LowerLevelRadiusStuds_MinMax = {min = 5, max = 8},

	NumConnectingShaftsPerLevel_MinMax = {min = 2, max = 3},
	ShaftRadiusStuds_MinMax = {min = 2, max = 4},
	ShaftBlendRadiusFactor = 1.3,
}

--------------------------------------------------------------------------------
-- IX. Meso Detailing Parameters (for Phase_MesoDetailing)
--------------------------------------------------------------------------------
Config.MesoDetailing = {
	ScallopChance = 0.04, 
	ScallopRadiusStuds_MinMax = {min = 1, max = 2.5},
	ScallopDepthFactor = 0.55, 

	LedgeChancePerWallSurface = 0.025, 
	LedgeRadiusStuds_MinMax = {min = 2, max = 4.5},
	LedgeProtrusionFactor = 0.7, 
	MinLedgeHeightAboveFloorGuessCells = 3,
}

return Config