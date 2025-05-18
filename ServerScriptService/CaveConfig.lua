-- ModuleScript: CaveConfig
-- Path: ServerScriptService/CaveConfig.lua
local Config = {}

--------------------------------------------------------------------------------
-- I. GENERAL SETTINGS
--------------------------------------------------------------------------------
Config.Seed = 12345 -- Or your preferred static seed like 67896
Config.DebugMode = true -- START WITH TRUE for initial runs of this new config. Set to false later for speed.

Config.RegionSize    = Vector3.new(1024, 512, 1024)
Config.CellSize      = 4
Config.RockMaterial  = Enum.Material.Rock -- Changed to Rock for a more "natural cave" feel, Slate is fine too.

-- Config.Threshold: This defines how "easy" it is to carve air.
-- For a large region, if we want substantial caves, we might keep this moderate.
-- If hierarchical culling works well, this threshold will primarily affect the detailed pass.
Config.Threshold     = 0.43 -- Slightly higher than before, to make the detailed pass a bit more selective.
-- The broad pass should handle large solid areas.

--------------------------------------------------------------------------------
-- II. FBM PARAMETERS (For DETAILED pass in Phase 1)
--------------------------------------------------------------------------------
Config.P1_NoiseScale    = 0.018 -- Slightly smaller scale (larger features) for the detailed pass, fitting for a larger region.
Config.P1_Octaves       = 5     -- Keep 5 for detail, hierarchical pass aims to reduce how often this is calculated.
Config.P1_Lacunarity    = 2.0
Config.P1_Persistence   = 0.5

--------------------------------------------------------------------------------
-- III. CaveGenerator.lua FEATURE PARAMETERS (Toggles and values)
--------------------------------------------------------------------------------
Config.FormationPhaseEnabled = true
Config.SmoothingPhaseEnabled = true         -- Smoothing is important for large, potentially noisy caves
Config.ConnectivityPhaseEnabled = true      -- Crucial for large regions to connect disparate areas
Config.FloodFillPhaseEnabled = true         -- Essential to remove isolated pockets
Config.SurfaceEntrancesPhaseEnabled = true  -- We will tune this to be very limited
Config.BridgePhaseEnabled = true

-- Phase 1 Biases
Config.P1_HeightBias_BottomZonePercent = 0.10  -- Small zone near true bottom
Config.P1_HeightBias_BottomValue = -0.10       -- Moderate encouragement for caves at the very bottom
Config.P1_HeightBias_TopZonePercent = 0.95     -- Affects only top 5% of Y-grid
Config.P1_HeightBias_TopValue    = 0.0         -- Change to NEUTRAL in this top zone. (Was 0.05)
Config.P1_HeightBias_MidFactor   = -0.05       -- General encouragement in the middle bulk of the cave system

Config.P1_DistanceBias_Max = 0.03             -- SLIGHTLY discourage caves right at the world border (positive value).
-- Encourages caves to form more towards the center.

Config.P1_VertConn_Strength = 0.10            -- Slightly stronger vertical connectivity influence
Config.P1_VertConn_NoiseScaleFactor = 12      -- Adjust scale

--------------------------------------------------------------------------------
-- III.B. PHASE 1 - DOMAIN WARPING PARAMETERS
--------------------------------------------------------------------------------
Config.P1_UseDomainWarp = true
Config.P1_DomainWarp_Strength = 30.0          -- More strength for visible warping in a large area
Config.P1_DomainWarp_FrequencyFactor = 0.007  -- Even lower frequency for larger, smoother warp patterns
Config.P1_DomainWarp_Octaves = 3
Config.P1_DomainWarp_Persistence = 0.5
Config.P1_DomainWarp_Lacunarity = 2.0

--------------------------------------------------------------------------------
-- III.C. PHASE 1 - HIERARCHICAL NOISE PASS (BROAD STRUCTURE)
--------------------------------------------------------------------------------
Config.P1_UseHierarchicalNoise = true
Config.P1_BroadStructure_NoiseScaleFactor = 0.10 -- Results in broad noise scale P1_NoiseScale * 0.1 = 0.0018
-- This makes broad features ~10x larger than detailed.
Config.P1_BroadStructure_Octaves = 1             -- MAX SPEED for broad pass.
Config.P1_BroadStructure_Threshold = 0.52        -- STARTING POINT.
-- This is very sensitive. If too many broad solid cells: decrease to 0.50, 0.48.
-- If too few broad solid (still slow P1): increase to 0.55.
-- The goal is that this broad pass marks ~30-60% of cells as SOLID.

--------------------------------------------------------------------------------
-- III.D. PHASE 1 - SURFACE ADAPTIVE FBM (for Detailed Pass)
--------------------------------------------------------------------------------
Config.P1_UseSurfaceAdaptiveFBM = false -- Set to true to enable Surface Adaptive FBM for the detailed pass
-- If true, the detailed pass will use Perlin.FBM_SurfaceAdaptive instead of Perlin.FBM_Base.
-- Config.P1_Octaves will serve as the 'maxOctaves' parameter for FBM_SurfaceAdaptive.
-- Config.P1_NoiseScale will serve as the 'frequency' parameter.

Config.P1_Adaptive_TargetThreshold = 0.45 -- Value in [0,1]. Noise values (pre-bias) near this will get more octaves.
-- This is the threshold the adaptive algorithm aims for.
-- A common starting point might be 0.5, or aligned with Config.Threshold.

Config.P1_Adaptive_NearSurfaceOctaves = 6 -- Number of octaves to calculate when the noise is near the TargetThreshold.
-- Will be internally clamped by Config.P1_Octaves (as maxOctaves).
-- Example: If P1_Octaves = 5, and this is 6, effectively 5 octaves will be used.

Config.P1_Adaptive_FarSurfaceOctaves = 2  -- Number of octaves for the initial estimate and when noise is far from TargetThreshold.
-- Should be less than P1_Adaptive_NearSurfaceOctaves.

Config.P1_Adaptive_TransitionRange = 0.1  -- Range around TargetThreshold (e.g., Target +/- Range) to transition
-- from FarSurfaceOctaves to NearSurfaceOctaves.


--------------------------------------------------------------------------------
-- PHASE 2: Rock Formations
--------------------------------------------------------------------------------
Config.FormationStartHeight_Cells = 1 -- Can still form from near the bottom
Config.FormationClearance_Cells = 3   -- Need more clearance in potentially larger caverns
Config.MinFormationLength_Cells = 3
Config.MaxFormationLength_Cells = 12  -- Allow for larger formations
Config.BaseFormationRadius_Factor = 0.45 -- Slightly thicker base for larger formations
Config.StalactiteChance = 0.20        -- Slightly lower chance to prevent over-cluttering
Config.StalagmiteChance = 0.25        -- "
Config.ColumnChance = 0.10            -- "
Config.MinColumnHeight_Cells = 5

--------------------------------------------------------------------------------
-- PHASE 3: Smoothing
--------------------------------------------------------------------------------
Config.SmoothingIterations = 2          -- 2 should be good. 3 might be too much for this scale unless very noisy.
Config.SmoothingThreshold_FillAir = 20    -- Fill air if >= 20 (was 22) solid neighbors (more aggressive filling of small air pockets)
Config.SmoothingThreshold_CarveRock = 5   -- Carve rock if >= 5 (was 4) air neighbors (more aggressive carving of thin walls)
-- (Original: 26-solidNeighbors >= Carve -> airNeighbors >= Carve)

--------------------------------------------------------------------------------
-- PHASE 4: Connectivity
--------------------------------------------------------------------------------
Config.ConnectivityDensity = math.max(5, math.floor((Config.RegionSize.X*Config.RegionSize.Z)/(5000*Config.CellSize^2))) -- Dynamic, but capped lower initially.
-- For 1024x1024, Cell 4: (1M)/(5000*16) = 1M/80000 = ~12 connections.
-- Ensure it connects enough major sections. Min of 5.
Config.ConnectivityTunnelRadius_Factor = 0.8 -- Wider tunnels for larger scale connections

--------------------------------------------------------------------------------
-- PHASE 5: Flood Fill Cleanup (No direct params here other than running it)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- PHASE 6: Surface Entrances (Tuned for FEW entrances)
--------------------------------------------------------------------------------
Config.SurfaceCaveCount = 3 -- Fixed to a low number, e.g., 2-3 entrances for the whole map. Adjust as desired.
Config.SurfaceCaveRadius_Factor = 2.5 -- Slightly larger. (Was 2.0)
Config.SurfaceCaveEntranceIrregularity = 0.3 -- Less irregularity for more direct tunnels.
Config.SurfaceCaveTunnelSteepness = -0.6 -- Maintain reasonable steepness.
Config.SurfaceCaveTunnelLength_Cells_MinMax = {25, 45} -- Give more length to dig. (Was {20,35})
-- But fewer of them overall.

--------------------------------------------------------------------------------
-- PHASE 7: Bridges
--------------------------------------------------------------------------------
Config.BridgeChamberMinAirCells = 100   -- Larger chambers needed to justify bridges
Config.BridgeChamberMinHeight_Cells = 6
Config.BridgeThickness_Cells_MinMax = {2, 3} -- Slightly thicker bridges for scale
Config.BridgeWidth_Cells_MinMax = {2, 4}     -- Slightly wider

--------------------------------------------------------------------------------
-- IV. ORE
--------------------------------------------------------------------------------
Config.OreVeins = {
	Enabled = true,
	OreList = {
		{ Name = "Iron", Material = Enum.Material.CorrodedMetal,
			NoiseScale = 0.06, Octaves = 3, Persistence = 0.5, Lacunarity = 2.0,
			Threshold = 0.78, Rarity = 0.15 -- Slightly rarer/higher threshold
		},
		{ Name = "Crystal", Material = Enum.Material.Glass,
			NoiseScale = 0.10, Octaves = 2, Persistence = 0.6, Lacunarity = 1.9,
			Threshold = 0.82, Rarity = 0.10 -- Slightly rarer/higher threshold
		},
		{ Name = "DebugOre", Material = Enum.Material.Neon, -- Keep for testing visibility
			NoiseScale = 0.05, Octaves = 4, Persistence = 0.5, Lacunarity = 2.0,
			Threshold = 0.70, Rarity = 0.25 -- Still somewhat common for testing
		},
	}
}
--------------------------------------------------------------------------------
-- V. PERFORMANCE / INTERNAL
--------------------------------------------------------------------------------
Config.GlobalYieldBatchSize = 250000 -- Adjusted for very large cell count

-- Default parameters for Perlin.lua's FBM functions
Config.FBM_DefaultOctaves = 6
Config.FBM_DefaultPersistence = 0.5
Config.FBM_DefaultLacunarity = 2.0
Config.RMF_DefaultOffset = 1.0
Config.RMF_DefaultGain = 2.0
Config.DomainWarp_DefaultFrequencyFactor = 0.1
Config.DomainWarp_DefaultStrength = 10
Config.Curl_DefaultFrequencyFactor = 0.05
Config.GuidedFBM_BiasFreqFactor = 0.05
Config.GuidedFBM_BiasInfluence = 0.7
Config.GuidedFBM_DetailSuppressThresh = 0.6
Config.GuidedFBM_DetailBoostThresh = 0.3
Config.AnisoFBM_StressFreqFactor = 0.02
Config.AnisoFBM_StressStrength = 0.5
Config.AnisoFBM_FoundationOctaves = 2
Config.AnisoFBM_ScaleFactor = 0.3
Config.SurfaceFBM_TargetThreshold = 0.5
Config.SurfaceFBM_NearSurfaceOctaves = 6
Config.SurfaceFBM_FarSurfaceOctaves = 3
Config.SurfaceFBM_TransitionRange = 0.1


-- Debug Settings (Adjusted for large scale)
Config.FloodFillContext_MaxInitialDebugAttempts = 1
Config.FloodFillContext_MaxInitialComponentLogs = 1
Config.FloodFillContext_LargeComponentThreshold = 75000
Config.FloodFillContext_SmallComponentThreshold = 100
Config.FloodFillLogFirstAirCellFound = false -- Probably too much spam for this size
Config.FloodFillMaxNilCellLogs = 1
Config.FloodFillZSliceLogDivisor = 25 -- Log ~4% progress slices

-- For P8 Greedy Mesher (Critical for performance at this scale)
Config.GreedyMesherZSliceLogDivisor_DebugMode = 64  -- Log ~4 times (256 Z-slices / 64)
Config.GreedyMesherZSliceLogDivisor_ReleaseMode = 32 -- Log ~8 times
Config.GreedyMesherInnerYieldThreshold = 75000    -- More work between inner yields for P8
Config.GreedyMesherCallCountLogFrequency = 50000 -- Log FillBlock info less frequently

return Config