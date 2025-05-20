-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
local Config = {}

--------------------------------------------------------------------------------
-- I. GENERAL SETTINGS
--------------------------------------------------------------------------------
Config.Seed = math.random(1,9999999) -- Or your preferred static seed like 67896
Config.DebugMode = true -- START WITH TRUE for initial runs.

Config.RegionSize    = Vector3.new(1024, 512, 1024)
Config.CellSize      = 4
Config.RockMaterial  = Enum.Material.Rock

-- --- TWEAKED ---
Config.Threshold     = 0.53 -- Increased. Makes base carving harder, relies more on guided structures or biases.
-- The idea is to prevent noise alone from creating too many small, blobby air pockets.

--------------------------------------------------------------------------------
-- II. FBM PARAMETERS (For DETAILED pass in Phase 1, or base if no hierarchy/adaptive)
--------------------------------------------------------------------------------
-- --- TWEAKED ---
Config.P1_NoiseScale    = 0.015 -- Slightly lower frequency (larger features) for the detailed pass base.
Config.P1_Octaves       = 4     -- Reduced octaves for a slightly smoother base, more reliant on warping/guidance.
Config.P1_Lacunarity    = 2.0
Config.P1_Persistence   = 0.45  -- Slightly less persistence for smoother noise.

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
-- --- TWEAKED --- Biases are made more subtle initially, to let warping/other structural methods dominate.
Config.P1_HeightBias_BottomZonePercent = 0.10
Config.P1_HeightBias_BottomValue = -0.03       -- Less aggressive push for caves at bottom
Config.P1_HeightBias_TopZonePercent = 0.95
Config.P1_HeightBias_TopValue    = 0.03        -- Slightly discourage caves at the very top boundary
Config.P1_HeightBias_MidFactor   = -0.01       -- Very subtle general encouragement

Config.P1_DistanceBias_Max = 0.05             -- Slightly stronger push away from exact world border.

Config.P1_VertConn_Strength = 0.08            -- Subtle vertical connectivity
Config.P1_VertConn_NoiseScaleFactor = 10

--------------------------------------------------------------------------------
-- III.B. PHASE 1 - DOMAIN WARPING PARAMETERS
--------------------------------------------------------------------------------
Config.P1_UseDomainWarp = true
-- --- TWEAKED --- Domain Warping will be a primary driver for larger structures.
Config.P1_DomainWarp_Strength = 120.0         -- Significantly increased strength for major distortions.
Config.P1_DomainWarp_FrequencyFactor = 0.0015 -- Drastically lower frequency for very large, slow warp patterns.
Config.P1_DomainWarp_Octaves = 2              -- Fewer octaves for simpler, bolder warp paths.
Config.P1_DomainWarp_Persistence = 0.5
Config.P1_DomainWarp_Lacunarity = 2.0

--------------------------------------------------------------------------------
-- III.C. PHASE 1 - HIERARCHICAL NOISE PASS (BROAD STRUCTURE)
--------------------------------------------------------------------------------
Config.P1_UseHierarchicalNoise = true -- Keep this, but tune it.
-- --- TWEAKED --- Broad pass should define major solid areas OR major void conduits.
Config.P1_BroadStructure_NoiseScaleFactor = 0.08 -- Makes broad features ~12.5x larger. (0.015 * 0.08 = 0.0012)
Config.P1_BroadStructure_Octaves = 1             -- Max speed, very smooth broad strokes.
Config.P1_BroadStructure_Threshold = 0.58        -- INCREASED. This means the broad pass is MORE LIKELY TO CREATE SOLID.
-- The goal is for it to carve out only a FEW very large, definite "potential cave zones"
-- or to definitively mark most of the area as solid rock, forcing detailed pass
-- to work harder or along specific lines defined by domain warp.
-- EXPERIMENT: If P1 is too slow, or too much is SOLID, decrease this (e.g. 0.54).
-- If it's still too "Swiss cheese," increase this more (e.g. 0.62).

--------------------------------------------------------------------------------
-- III.D. PHASE 1 - SURFACE ADAPTIVE FBM (for Detailed Pass)
--------------------------------------------------------------------------------
Config.P1_UseSurfaceAdaptiveFBM = false -- Let's start with this OFF to see the impact of DW and Hierarchical first.
-- Can be re-enabled later for targeted detailing.
Config.P1_Adaptive_TargetThreshold = Config.Threshold -- Align with main threshold if re-enabled.
Config.P1_Adaptive_NearSurfaceOctaves = Config.P1_Octaves + 1 -- e.g., 5
Config.P1_Adaptive_FarSurfaceOctaves = Config.P1_Octaves - 2  -- e.g., 2
Config.P1_Adaptive_TransitionRange = 0.08

-- --- NEW --- Parameters if you modify CaveGenerator to use Anisotropic FBM for base noise in Phase 1
-- This would be an alternative to the Domain Warping + Base FBM strategy.
-- Not used unless CaveGenerator.Phase1_InitialCaveFormation is changed to call FBM_AnisotropicStress.
Config.P1_UseAnisotropicFBM = false -- MASTER TOGGLE (you'd need to read this in CaveGenerator)
Config.P1_Aniso_StressFreqFactor = 0.0008      -- Very low frequency for global stress direction.
Config.P1_Aniso_StressStrength = 0.75          -- Fairly strong directional influence.
Config.P1_Aniso_FoundationOctaves = 1          -- Stress affects primarily the largest noise features.
Config.P1_Aniso_AnisotropicScaleFactor = 0.5   -- How much stretching occurs.

--------------------------------------------------------------------------------
-- PHASE 2: Rock Formations
--------------------------------------------------------------------------------
Config.FormationStartHeight_Cells = 1
Config.FormationClearance_Cells = 2   -- Slightly less clearance needed if caves are less dense.
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
-- --- TWEAKED --- Less aggressive smoothing to preserve more structure.
Config.SmoothingIterations = 1          -- Only one pass initially.
Config.SmoothingThreshold_FillAir = 22    -- Harder to fill air (needs more neighbors).
Config.SmoothingThreshold_CarveRock = 4   -- Easier to carve isolated rock (needs fewer air neighbors, default from CA rules).

--------------------------------------------------------------------------------
-- PHASE 4: Connectivity
--------------------------------------------------------------------------------
Config.ConnectivityDensity = math.max(3, math.floor((Config.RegionSize.X*Config.RegionSize.Z)/(8000*Config.CellSize^2)))
Config.ConnectivityTunnelRadius_Factor = 1.0 -- Slightly larger tunnels for connection

--------------------------------------------------------------------------------
-- PHASE 5: Flood Fill Cleanup (No direct params here other than running it)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- PHASE 6: Surface Entrances
--------------------------------------------------------------------------------
Config.SurfaceCaveCount = math.max(1, math.floor(Config.RegionSize.X / 400)) -- e.g., 2-3 for 1024
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
Config.AgentTunnels_Enabled = true -- Set to true to run this phase.
-- CONSIDER RUNNING THIS *BEFORE* PHASE 1 for a skeletal structure.
-- (This would require a change in CaveGenerator.RunCaveGeneration phase order).

Config.AgentTunnels_NumInitialAgents = 7     -- --- TWEAKED --- More agents
Config.AgentTunnels_MaxActiveAgents = 20     -- --- TWEAKED ---
Config.AgentTunnels_MaxTotalAgentSteps = 75000 -- --- TWEAKED --- More steps
Config.AgentTunnels_AgentLifetime_MinMax = {min = 250, max = 500} -- --- TWEAKED --- Longer life
Config.AgentTunnels_TunnelRadius_MinMax = {min = 1, max = 3} -- Cell radius. Can make max 2 or 3 for larger main tunnels.

Config.AgentTunnels_UseNonAxialMovement = true
Config.AgentTunnels_TurnAngle_MinMax_Degrees = {min = 5, max = 45} -- Smaller turns for more gradual curves
Config.AgentTunnels_CurlNoise_TurnStrength_Degrees = 30
Config.AgentTunnels_StepLength = 0.7           -- --- TWEAKED --- Shorter steps for smoother paths
Config.AgentTunnels_PreferFlattening = true
Config.AgentTunnels_FlatteningStrength = 0.25  -- Stronger flattening

Config.AgentTunnels_TurnChance = 0.15         -- --- TWEAKED --- Less frequent random turns if curl noise is guiding well
Config.AgentTunnels_AvoidImmediateReverse = true

Config.AgentTunnels_BranchChance = 0.008       -- --- TWEAKED --- Slightly higher branch chance
Config.AgentTunnels_BranchLifetimeFactor = 0.5
Config.AgentTunnels_BranchTurnAngle = 75      -- Degrees

Config.AgentTunnels_MaxStuckBeforeDeath = 8
Config.AgentTunnels_StartPolicy = "MainCaveAir" -- If running AFTER P1/P5.
-- If running BEFORE P1, this needs a fallback or change to "RandomAirInGrid"
-- if grid is mostly AIR, or agents must carve from SOLID.
Config.AgentTunnels_SeedPoints = {}

Config.AgentTunnels_CurlNoise_Enabled = true
Config.AgentTunnels_CurlNoise_Influence = 0.7  -- --- TWEAKED --- Stronger curl influence
Config.AgentTunnels_CurlNoise_FrequencyFactor = 0.004 -- --- TWEAKED --- Even lower frequency for very large, guiding curl patterns
Config.AgentTunnels_CurlNoise_Octaves = 1
Config.AgentTunnels_CurlNoise_Persistence = 0.5
Config.AgentTunnels_CurlNoise_Lacunarity = 2.0
Config.AgentTunnels_CurlNoise_WorldScale = Config.CellSize * 15 -- Sample curl over a larger area

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
			Threshold = 0.75, Rarity = 0.05 -- Make debug ore rarer if main gen is working
		},
	}
}
--------------------------------------------------------------------------------
-- V. PERFORMANCE / INTERNAL
--------------------------------------------------------------------------------
Config.GlobalYieldBatchSize = 200000

-- Default parameters for Perlin.lua's FBM functions (as loaded by Perlin.lua)
Config.FBM_DefaultOctaves = 4 -- Was 6
Config.FBM_DefaultPersistence = 0.5
Config.FBM_DefaultLacunarity = 2.0
Config.RMF_DefaultOffset = 1.0
Config.RMF_DefaultGain = 2.0
Config.DomainWarp_DefaultFrequencyFactor = Config.P1_DomainWarp_FrequencyFactor -- Sync if used directly in Perlin
Config.DomainWarp_DefaultStrength = Config.P1_DomainWarp_Strength         -- Sync if used directly in Perlin
Config.Curl_DefaultFrequencyFactor = Config.AgentTunnels_CurlNoise_FrequencyFactor -- Sync for consistency
Config.GuidedFBM_BiasFreqFactor = 0.03
Config.GuidedFBM_BiasInfluence = 0.75
Config.GuidedFBM_DetailSuppressThresh = 0.65
Config.GuidedFBM_DetailBoostThresh = 0.35
Config.AnisoFBM_StressFreqFactor = Config.P1_Aniso_StressFreqFactor         -- Sync if used
Config.AnisoFBM_StressStrength = Config.P1_Aniso_StressStrength           -- Sync if used
Config.AnisoFBM_FoundationOctaves = Config.P1_Aniso_FoundationOctaves       -- Sync if used
Config.AnisoFBM_ScaleFactor = Config.P1_Aniso_AnisotropicScaleFactor     -- Sync if used
Config.SurfaceFBM_TargetThreshold = Config.P1_Adaptive_TargetThreshold     -- Sync
Config.SurfaceFBM_NearSurfaceOctaves = Config.P1_Adaptive_NearSurfaceOctaves -- Sync
Config.SurfaceFBM_FarSurfaceOctaves = Config.P1_Adaptive_FarSurfaceOctaves   -- Sync
Config.SurfaceFBM_TransitionRange = Config.P1_Adaptive_TransitionRange     -- Sync


Config.FloodFillContext_MaxInitialDebugAttempts = 1
Config.FloodFillContext_MaxInitialComponentLogs = 1
Config.FloodFillContext_LargeComponentThreshold = 50000
Config.FloodFillContext_SmallComponentThreshold = 50
Config.FloodFillLogFirstAirCellFound = false
Config.FloodFillMaxNilCellLogs = 1
Config.FloodFillZSliceLogDivisor = 20

Config.GreedyMesherZSliceLogDivisor_DebugMode = math.max(1, math.floor(Config.RegionSize.Z / Config.CellSize / 16))  -- Aim for ~16 logs in debug
Config.GreedyMesherZSliceLogDivisor_ReleaseMode = math.max(1, math.floor(Config.RegionSize.Z / Config.CellSize / 8)) -- Aim for ~8 logs in release
Config.GreedyMesherInnerYieldThreshold = 50000
Config.GreedyMesherCallCountLogFrequency = 75000

return Config