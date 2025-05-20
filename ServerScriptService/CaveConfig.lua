-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
local Config = {}

--------------------------------------------------------------------------------
-- I. GENERAL SETTINGS
--------------------------------------------------------------------------------
Config.Seed = math.random(1,9999999) -- Or your preferred static seed like 67896
-- Config.DebugMode = true -- OLD! This is now controlled by Config.Logging.logLevelName

Config.RegionSize    = Vector3.new(1024, 512, 1024)
Config.CellSize      = 4
Config.RockMaterial  = Enum.Material.Rock
Config.Threshold     = 0.53

--------------------------------------------------------------------------------
-- II. FBM PARAMETERS (For DETAILED pass in Phase 1, or base if no hierarchy/adaptive)
--------------------------------------------------------------------------------
Config.P1_NoiseScale    = 0.015
Config.P1_Octaves       = 4
Config.P1_Lacunarity    = 2.0
Config.P1_Persistence   = 0.45

--------------------------------------------------------------------------------
-- III. CaveGenerator.lua FEATURE PARAMETERS (Toggles and values)
--------------------------------------------------------------------------------
Config.FormationPhaseEnabled = true
Config.SmoothingPhaseEnabled = true
Config.ConnectivityPhaseEnabled = true
Config.FloodFillPhaseEnabled = true
Config.SurfaceEntrancesPhaseEnabled = true
Config.BridgePhaseEnabled = true

-- Phase 1 Biases
Config.P1_HeightBias_BottomZonePercent = 0.10
Config.P1_HeightBias_BottomValue = -0.03
Config.P1_HeightBias_TopZonePercent = 0.95
Config.P1_HeightBias_TopValue    = 0.03
Config.P1_HeightBias_MidFactor   = -0.01
Config.P1_DistanceBias_Max = 0.05
Config.P1_VertConn_Strength = 0.08
Config.P1_VertConn_NoiseScaleFactor = 10

--------------------------------------------------------------------------------
-- III.B. PHASE 1 - DOMAIN WARPING PARAMETERS
--------------------------------------------------------------------------------
Config.P1_UseDomainWarp = true
Config.P1_DomainWarp_Strength = 120.0
Config.P1_DomainWarp_FrequencyFactor = 0.0015
Config.P1_DomainWarp_Octaves = 2
Config.P1_DomainWarp_Persistence = 0.5
Config.P1_DomainWarp_Lacunarity = 2.0

--------------------------------------------------------------------------------
-- III.C. PHASE 1 - HIERARCHICAL NOISE PASS (BROAD STRUCTURE)
--------------------------------------------------------------------------------
Config.P1_UseHierarchicalNoise = true
Config.P1_BroadStructure_NoiseScaleFactor = 0.08
Config.P1_BroadStructure_Octaves = 1
Config.P1_BroadStructure_Threshold = 0.58

--------------------------------------------------------------------------------
-- III.D. PHASE 1 - SURFACE ADAPTIVE FBM (for Detailed Pass)
--------------------------------------------------------------------------------
Config.P1_UseSurfaceAdaptiveFBM = false
Config.P1_Adaptive_TargetThreshold = Config.Threshold
Config.P1_Adaptive_NearSurfaceOctaves = Config.P1_Octaves + 1
Config.P1_Adaptive_FarSurfaceOctaves = Config.P1_Octaves - 2
Config.P1_Adaptive_TransitionRange = 0.08

Config.P1_UseAnisotropicFBM = false
Config.P1_Aniso_StressFreqFactor = 0.0008
Config.P1_Aniso_StressStrength = 0.75
Config.P1_Aniso_FoundationOctaves = 1
Config.P1_Aniso_AnisotropicScaleFactor = 0.5

--------------------------------------------------------------------------------
-- PHASE 2: Rock Formations
--------------------------------------------------------------------------------
Config.FormationStartHeight_Cells = 1
Config.FormationClearance_Cells = 2
Config.MinFormationLength_Cells = 2
Config.MaxFormationLength_Cells = 10
Config.BaseFormationRadius_Factor = 0.4
Config.StalactiteChance = 0.15
Config.StalagmiteChance = 0.18
Config.ColumnChance = 0.08
Config.MinColumnHeight_Cells = 4

--------------------------------------------------------------------------------
-- PHASE 3: Smoothing
--------------------------------------------------------------------------------
Config.SmoothingIterations = 1
Config.SmoothingThreshold_FillAir = 22
Config.SmoothingThreshold_CarveRock = 4

--------------------------------------------------------------------------------
-- PHASE 4: Connectivity
--------------------------------------------------------------------------------
Config.ConnectivityDensity = math.max(3, math.floor((Config.RegionSize.X*Config.RegionSize.Z)/(8000*Config.CellSize^2)))
Config.ConnectivityTunnelRadius_Factor = 1.0

--------------------------------------------------------------------------------
-- PHASE 5: Flood Fill Cleanup (No direct params here other than running it)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- PHASE 6: Surface Entrances
--------------------------------------------------------------------------------
Config.SurfaceCaveCount = math.max(1, math.floor(Config.RegionSize.X / 400))
Config.SurfaceCaveRadius_Factor = 2.0
Config.SurfaceCaveEntranceIrregularity = 0.4
Config.SurfaceCaveTunnelSteepness = -0.7
Config.SurfaceCaveTunnelLength_Cells_MinMax = {30, 55}

--------------------------------------------------------------------------------
-- PHASE 7: Bridges
--------------------------------------------------------------------------------
Config.BridgeChamberMinAirCells = 120
Config.BridgeChamberMinHeight_Cells = 5
Config.BridgeThickness_Cells_MinMax = {1, 2}
Config.BridgeWidth_Cells_MinMax = {2, 3}

--------------------------------------------------------------------------------
-- PHASE_AGENT_TUNNELS: Worm/Agent-based Tunneling
--------------------------------------------------------------------------------
Config.AgentTunnels_Enabled = true
Config.AgentTunnels_NumInitialAgents = 7
Config.AgentTunnels_MaxActiveAgents = 20
Config.AgentTunnels_MaxTotalAgentSteps = 75000
Config.AgentTunnels_AgentLifetime_MinMax = {min = 250, max = 500}
Config.AgentTunnels_TunnelRadius_MinMax = {min = 1, max = 3}
Config.AgentTunnels_UseNonAxialMovement = true
Config.AgentTunnels_TurnAngle_MinMax_Degrees = {min = 5, max = 45}
Config.AgentTunnels_CurlNoise_TurnStrength_Degrees = 30
Config.AgentTunnels_StepLength = 0.7
Config.AgentTunnels_PreferFlattening = true
Config.AgentTunnels_FlatteningStrength = 0.25
Config.AgentTunnels_TurnChance = 0.15
Config.AgentTunnels_AvoidImmediateReverse = true
Config.AgentTunnels_BranchChance = 0.008
Config.AgentTunnels_BranchLifetimeFactor = 0.5
Config.AgentTunnels_BranchTurnAngle = 75
Config.AgentTunnels_MaxStuckBeforeDeath = 8
Config.AgentTunnels_StartPolicy = "MainCaveAir"
Config.AgentTunnels_SeedPoints = {}
Config.AgentTunnels_CurlNoise_Enabled = true
Config.AgentTunnels_CurlNoise_Influence = 0.7
Config.AgentTunnels_CurlNoise_FrequencyFactor = 0.004
Config.AgentTunnels_CurlNoise_Octaves = 1
Config.AgentTunnels_CurlNoise_Persistence = 0.5
Config.AgentTunnels_CurlNoise_Lacunarity = 2.0
Config.AgentTunnels_CurlNoise_WorldScale = Config.CellSize * 15

--------------------------------------------------------------------------------
-- IV. ORE
--------------------------------------------------------------------------------
Config.OreVeins = {
	Enabled = true,
	OreList = {
		{ Name = "Iron", Material = Enum.Material.CorrodedMetal,
			NoiseScale = 0.05, Octaves = 3, Persistence = 0.5, Lacunarity = 2.0,
			Threshold = 0.80, Rarity = 0.10
		},
		{ Name = "Crystal", Material = Enum.Material.Glass,
			NoiseScale = 0.08, Octaves = 2, Persistence = 0.6, Lacunarity = 1.9,
			Threshold = 0.85, Rarity = 0.07
		},
		{ Name = "DebugOre", Material = Enum.Material.Neon,
			NoiseScale = 0.04, Octaves = 4, Persistence = 0.5, Lacunarity = 2.0,
			Threshold = 0.75, Rarity = 0.05
		},
	}
}
--------------------------------------------------------------------------------
-- V. PERFORMANCE / INTERNAL
--------------------------------------------------------------------------------
Config.GlobalYieldBatchSize = 200000

Config.FBM_DefaultOctaves = 4
Config.FBM_DefaultPersistence = 0.5
Config.FBM_DefaultLacunarity = 2.0
Config.RMF_DefaultOffset = 1.0
Config.RMF_DefaultGain = 2.0
Config.DomainWarp_DefaultFrequencyFactor = Config.P1_DomainWarp_FrequencyFactor
Config.DomainWarp_DefaultStrength = Config.P1_DomainWarp_Strength
Config.Curl_DefaultFrequencyFactor = Config.AgentTunnels_CurlNoise_FrequencyFactor
Config.GuidedFBM_BiasFreqFactor = 0.03
Config.GuidedFBM_BiasInfluence = 0.75
Config.GuidedFBM_DetailSuppressThresh = 0.65
Config.GuidedFBM_DetailBoostThresh = 0.35
Config.AnisoFBM_StressFreqFactor = Config.P1_Aniso_StressFreqFactor
Config.AnisoFBM_StressStrength = Config.P1_Aniso_StressStrength
Config.AnisoFBM_FoundationOctaves = Config.P1_Aniso_FoundationOctaves
Config.AnisoFBM_ScaleFactor = Config.P1_Aniso_AnisotropicScaleFactor
Config.SurfaceFBM_TargetThreshold = Config.P1_Adaptive_TargetThreshold
Config.SurfaceFBM_NearSurfaceOctaves = Config.P1_Adaptive_NearSurfaceOctaves
Config.SurfaceFBM_FarSurfaceOctaves = Config.P1_Adaptive_FarSurfaceOctaves
Config.SurfaceFBM_TransitionRange = Config.P1_Adaptive_TransitionRange

-- Specific verbosity controls (act as fine-tuning within DEBUG/TRACE levels)
Config.FloodFillContext_MaxInitialDebugAttempts = 1
Config.FloodFillContext_MaxInitialComponentLogs = 1
Config.FloodFillContext_LargeComponentThreshold = 50000
Config.FloodFillContext_SmallComponentThreshold = 50
Config.FloodFillLogFirstAirCellFound = false
Config.FloodFillMaxNilCellLogs = 1
Config.FloodFillZSliceLogDivisor = 20

Config.GreedyMesherZSliceLogDivisor_DebugMode = math.max(1, math.floor(Config.RegionSize.Z / Config.CellSize / 16))
Config.GreedyMesherZSliceLogDivisor_ReleaseMode = math.max(1, math.floor(Config.RegionSize.Z / Config.CellSize / 8))
Config.GreedyMesherInnerYieldThreshold = 50000
Config.GreedyMesherCallCountLogFrequency = 75000

--------------------------------------------------------------------------------
-- VI. LOGGING CONFIGURATION (NEW SECTION)
--------------------------------------------------------------------------------
Config.Logging = {
	-- Options for logLevelName: NONE, FATAL, ERROR, WARN, INFO, DEBUG, TRACE
	logLevelName = "DEBUG", -- Start with DEBUG for development. Change to "INFO" for less output.
	-- logLevelName = "TRACE", -- For maximum detail, can be very spammy. Use for deep diagnostics.
	-- logLevelName = "INFO",  -- For production-like minimal output (phase starts/ends, summaries).

	showTimestamp = true,   -- if true, prepends [HH:MM:SS] to messages
	showSource = true,      -- if true, prepends [SourceName] to messages
	defaultSource = "CaveGen", -- Default source name if not specified in a Logger call
}

return Config