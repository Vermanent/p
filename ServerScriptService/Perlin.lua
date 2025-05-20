-- ModuleScript: Perlin
-- Path: ServerScriptService/NoiseGenerator/Perlin.lua (Adjust path as needed)
local Perlin = {}

-- Standard 12 gradient vectors for 3D Perlin noise
local grad3 = {
	{1,1,0}, {-1,1,0}, {1,-1,0}, {-1,-1,0},
	{1,0,1}, {-1,0,1}, {1,0,-1}, {-1,0,-1},
	{0,1,1}, {0,-1,1}, {0,1,-1}, {0,-1,-1}
}
local p_table = {}
local Config -- Loaded below

-- Initialize Config and Permutation Table
do
	local success, configModule = pcall(function()
		return require(script.Parent.Parent.CaveConfig) -- Path: SSS/NoiseGenerator/Perlin.lua -> SSS/NoiseGenerator -> SSS -> SSS/CaveConfig.lua
	end)
	if not success or not configModule then
		warn("Perlin.lua: Could not load CaveConfig. Error: " .. tostring(configModule) .. ". Using default seed and limited params.")
		Config = {
			Seed = os.time(),
			FBM_DefaultOctaves = 6, FBM_DefaultPersistence = 0.5, FBM_DefaultLacunarity = 2.0,
			RMF_DefaultOffset = 1.0, RMF_DefaultGain = 2.0,
			DomainWarp_DefaultFrequencyFactor = 0.1, DomainWarp_DefaultStrength = 10,
			Curl_DefaultFrequencyFactor = 0.05,
			GuidedFBM_BiasFreqFactor = 0.05,
			GuidedFBM_BiasInfluence = 0.7,
			GuidedFBM_DetailSuppressThresh = 0.6,
			GuidedFBM_DetailBoostThresh = 0.3,
			AnisoFBM_StressFreqFactor = 0.02,
			AnisoFBM_StressStrength = 0.5, AnisoFBM_FoundationOctaves = 2, AnisoFBM_ScaleFactor = 0.3,
			SurfaceFBM_TargetThreshold = 0.5, SurfaceFBM_NearSurfaceOctaves = 6, SurfaceFBM_FarSurfaceOctaves = 3, SurfaceFBM_TransitionRange = 0.1,
		}
	else
		Config = configModule
		if Config.DebugMode then
			print("Perlin.lua: Successfully loaded CaveConfig. Seed: " .. Config.Seed)
		end
	end

	local rng = Random.new(Config.Seed)
	for i = 0, 255 do p_table[i + 1] = i end
	for i = 255, 1, -1 do
		local j = rng:NextInteger(0,i)
		p_table[i+1],p_table[j+1] = p_table[j+1],p_table[i+1]
	end
	for i = 0, 255 do p_table[i + 257] = p_table[i + 1] end
end

-- Core Math Functions (fade, lerp, dot)
local function fade(t) return t*t*t*(t*(t*6-15)+10) end
local function lerp(a,b,t) return a+t*(b-a) end
local function dot(g,x,y,z) return g[1]*x+g[2]*y+g[3]*z end

-- [[ CORE PERLIN NOISE ]]
function Perlin.Noise_Raw(xin,yin,zin) -- Outputs roughly [-1, 1]
	local x = tonumber(xin) or 0
	local y = tonumber(yin) or 0
	local z = tonumber(zin) or 0
	local xf = math.floor(x)
	local yf = math.floor(y)
	local zf = math.floor(z)
	local Xi = bit32.band(xf,255)
	local Yi = bit32.band(yf,255)
	local Zi = bit32.band(zf,255)
	local xd = x-xf
	local yd = y-yf
	local zd = z-zf
	local u = fade(xd)
	local v = fade(yd)
	local w = fade(zd)
	local pX = p_table[Xi+1]
	local pX1 = p_table[Xi+1+1]
	local h1 = pX+Yi
	local h2 = pX1+Yi
	local AA = p_table[h1+1]+Zi
	local BA = p_table[h2+1]+Zi
	local AB = p_table[h1+1+1]+Zi
	local BB = p_table[h2+1+1]+Zi
	local ng = #grad3
	local g000 = grad3[(p_table[AA+1]%ng)+1]
	local g100 = grad3[(p_table[BA+1]%ng)+1]
	local g010 = grad3[(p_table[AB+1]%ng)+1]
	local g110 = grad3[(p_table[BB+1]%ng)+1]
	local g001 = grad3[(p_table[AA+1+1]%ng)+1]
	local g101 = grad3[(p_table[BA+1+1]%ng)+1]
	local g011 = grad3[(p_table[AB+1+1]%ng)+1]
	local g111 = grad3[(p_table[BB+1+1]%ng)+1]
	local n000 = dot(g000,xd,yd,zd)
	local n100 = dot(g100,xd-1,yd,zd)
	local n010 = dot(g010,xd,yd-1,zd)
	local n110 = dot(g110,xd-1,yd-1,zd)
	local n001 = dot(g001,xd,yd,zd-1)
	local n101 = dot(g101,xd-1,yd,zd-1)
	local n011 = dot(g011,xd,yd-1,zd-1)
	local n111 = dot(g111,xd-1,yd-1,zd-1)
	local nx00 = lerp(n000,n100,u)
	local nx10 = lerp(n010,n110,u)
	local nx01 = lerp(n001,n101,u)
	local nx11 = lerp(n011,n111,u)
	return lerp(lerp(nx00,nx10,v), lerp(nx01,nx11,v), w)
end
function Perlin.Noise(x,y,z) return (Perlin.Noise_Raw(x,y,z)+1)*0.5 end

-- [[ FBM VARIANTS ]]
function Perlin.FBM_Base(x, y, z, octaves, persistence, lacunarity, frequency, amplitude, noiseFunc)
	noiseFunc = noiseFunc or Perlin.Noise_Raw
	octaves = octaves or Config.FBM_DefaultOctaves
	persistence = persistence or Config.FBM_DefaultPersistence
	lacunarity = lacunarity or Config.FBM_DefaultLacunarity
	frequency = frequency or 1.0
	amplitude = amplitude or 1.0

	local total = 0
	local maxVal = 0
	local curAmp = amplitude
	local curFreq = frequency

	for _ = 1, octaves do
		total = total + noiseFunc(x * curFreq, y * curFreq, z * curFreq) * curAmp
		maxVal = maxVal + curAmp
		curAmp = curAmp * persistence
		curFreq = curFreq * lacunarity
	end

	if maxVal == 0 then
		return 0.5
	else
		return (total / maxVal + 1) * 0.5
	end
end

function Perlin.FBM_Ridged(x, y, z, octaves, persistence, lacunarity, frequency, amplitude, offset, gain, noiseFunc)
	noiseFunc = noiseFunc or Perlin.Noise_Raw
	octaves = octaves or Config.FBM_DefaultOctaves
	persistence = persistence or Config.FBM_DefaultPersistence
	lacunarity = lacunarity or Config.FBM_DefaultLacunarity
	frequency = frequency or 1.0
	amplitude = amplitude or 1.0
	offset = offset or Config.RMF_DefaultOffset
	gain = gain or Config.RMF_DefaultGain

	local total = 0
	local curFreq = frequency
	local curAmp = amplitude
	local weight = 1.0
	local signal -- = 0 -- Unused assignment removed

	for _ = 1, octaves do
		signal = noiseFunc(x * curFreq, y * curFreq, z * curFreq)
		signal = offset - math.abs(signal)
		signal = signal * signal
		signal = signal * weight
		total = total + signal * curAmp
		weight = math.clamp(signal * gain, 0, 1)
		curFreq = curFreq * lacunarity
		curAmp = curAmp * persistence
		if curAmp < 0.001 then break end
	end
	return math.clamp(total * 0.75 + 0.25, 0, 1)
end

function Perlin.FBM_Guided(x,y,z, octaves,persistence,lacunarity,frequency,amplitude, biasFunc,biasFreqFactor,biasInfluence, suppressThresh,boostThresh, noiseFunc)
	noiseFunc = noiseFunc or Perlin.Noise_Raw
	octaves = octaves or Config.FBM_DefaultOctaves
	persistence = persistence or Config.FBM_DefaultPersistence
	lacunarity = lacunarity or Config.FBM_DefaultLacunarity
	frequency = frequency or 1.0
	amplitude = amplitude or 1.0

	biasFunc = biasFunc or function(bx,by,bz) return Perlin.Noise(bx,by,bz) end
	biasFreqFactor = biasFreqFactor or Config.GuidedFBM_BiasFreqFactor
	local actualBiasFreq = frequency * biasFreqFactor
	biasInfluence = biasInfluence or Config.GuidedFBM_BiasInfluence
	suppressThresh = suppressThresh or Config.GuidedFBM_DetailSuppressThresh
	boostThresh = boostThresh or Config.GuidedFBM_DetailBoostThresh

	local total = 0
	local curAmp = amplitude
	local curFreq = frequency
	local maxVal = 0
	local structuralBias = biasFunc(x * actualBiasFreq, y * actualBiasFreq, z * actualBiasFreq)

	for i = 1, octaves do
		local octAmp = curAmp
		local biasEffect = 1.0
		if i > 1 then 
			if structuralBias > suppressThresh then
				local suppressAmount = (structuralBias - suppressThresh) / (1 - suppressThresh + 1e-6)
				biasEffect = lerp(1.0 - suppressAmount^2, 1.0, 1.0 - biasInfluence)
			elseif structuralBias < boostThresh then
				local boostAmount = (boostThresh - structuralBias) / (boostThresh + 1e-6)
				biasEffect = lerp(1.0 + boostAmount * 0.5, 1.0, 1.0 - biasInfluence)
			end
		end
		octAmp = octAmp * biasEffect
		octAmp = math.max(0, octAmp) 

		if octAmp > 0.001 then 
			total = total + noiseFunc(x * curFreq, y * curFreq, z * curFreq) * octAmp
		end
		maxVal = maxVal + curAmp 

		curAmp = curAmp * persistence
		curFreq = curFreq * lacunarity
		if curAmp < 0.001 and i > 2 then break end 
	end

	if maxVal == 0 then
		return 0.5
	else
		return (total / maxVal + 1) * 0.5
	end
end

function Perlin.FBM_AnisotropicStress(x, y, z,
	octaves, persistence, lacunarity, frequency, amplitude,
	stressNoiseFunc, stressFreqFactor, stressStrength, foundationOctaves, anisotropicScaleFactor,
	noiseFunc)

	noiseFunc = noiseFunc or Perlin.Noise_Raw
	stressNoiseFunc = stressNoiseFunc or function(sx,sy,sz) return Perlin.Noise(sx,sy,sz) end
	octaves = octaves or Config.FBM_DefaultOctaves
	persistence = persistence or Config.FBM_DefaultPersistence
	lacunarity = lacunarity or Config.FBM_DefaultLacunarity
	frequency = frequency or 1.0
	amplitude = amplitude or 1.0

	stressFreqFactor = stressFreqFactor or Config.AnisoFBM_StressFreqFactor
	stressStrength = stressStrength or Config.AnisoFBM_StressStrength
	foundationOctaves = foundationOctaves or Config.AnisoFBM_FoundationOctaves
	anisotropicScaleFactor = anisotropicScaleFactor or Config.AnisoFBM_ScaleFactor

	local total = 0
	local currentAmplitude = amplitude
	local currentFrequency = frequency
	local maxValue = 0

	local stressSampleFreq = frequency * stressFreqFactor
	local svx = (stressNoiseFunc(x * stressSampleFreq + 100.1, y * stressSampleFreq + 200.2, z * stressSampleFreq + 300.3) * 2 - 1) * stressStrength
	local svy = (stressNoiseFunc(x * stressSampleFreq - 150.4, y * stressSampleFreq - 250.5, z * stressSampleFreq - 350.6) * 2 - 1) * stressStrength
	local svz = (stressNoiseFunc(x * stressSampleFreq + 220.7, y * stressSampleFreq + 320.8, z * stressSampleFreq + 420.9) * 2 - 1) * stressStrength

	local stressDir = Vector3.new(svx, svy, svz)

	for i = 1, octaves do
		local sx, sy, sz = x * currentFrequency, y * currentFrequency, z * currentFrequency

		if i <= foundationOctaves and stressDir.Magnitude > 1e-6 then
			local sampleVec = Vector3.new(sx,sy,sz)
			local anisotropically_scaled_sample_vec
			if stressDir.Magnitude > 1e-4 then
				local stressNormal = stressDir.Unit
				local projection = sampleVec:Dot(stressNormal)
				anisotropically_scaled_sample_vec = stressNormal * projection + (sampleVec - stressNormal * projection) * (1 - anisotropicScaleFactor * (1 - (i-1)/math.max(1,foundationOctaves-1)) ) -- fixed potential div by zero if foundationOctaves is 1
			else
				anisotropically_scaled_sample_vec = sampleVec
			end
			sx, sy, sz = anisotropically_scaled_sample_vec.X, anisotropically_scaled_sample_vec.Y, anisotropically_scaled_sample_vec.Z
		end

		total = total + noiseFunc(sx, sy, sz) * currentAmplitude
		maxValue = maxValue + currentAmplitude
		currentAmplitude = currentAmplitude * persistence
		currentFrequency = currentFrequency * lacunarity
		if currentAmplitude < 0.001 and i > 2 then break end
	end

	if maxValue == 0 then return 0.5 end
	return (total / maxValue + 1) * 0.5
end

function Perlin.FBM_SurfaceAdaptive(x, y, z,
	maxOctaves, persistence, lacunarity, frequency, amplitude,
	targetThreshold, nearSurfaceOctaves, farSurfaceOctaves, transitionRange,
	noiseFunc)

	noiseFunc = noiseFunc or Perlin.Noise_Raw
	maxOctaves = maxOctaves or Config.FBM_DefaultOctaves
	persistence = persistence or Config.FBM_DefaultPersistence
	lacunarity = lacunarity or Config.FBM_DefaultLacunarity
	frequency = frequency or 1.0
	amplitude = amplitude or 1.0

	targetThreshold = targetThreshold or Config.SurfaceFBM_TargetThreshold
	nearSurfaceOctaves = nearSurfaceOctaves or Config.SurfaceFBM_NearSurfaceOctaves
	farSurfaceOctaves = farSurfaceOctaves or Config.SurfaceFBM_FarSurfaceOctaves
	transitionRange = transitionRange or Config.SurfaceFBM_TransitionRange

	local total = 0
	-- local currentAmplitude = amplitude -- unused direct assignment
	-- local currentFrequency = frequency -- unused direct assignment

	local sumOfAllPossibleAmplitudes = 0
	do 
		local tempAmp = amplitude
		for _ = 1, maxOctaves do
			sumOfAllPossibleAmplitudes = sumOfAllPossibleAmplitudes + tempAmp
			tempAmp = tempAmp * persistence
		end
	end
	if sumOfAllPossibleAmplitudes == 0 then return 0.5 end

	local initialEstimateValue = 0
	local initialEstimateMaxValueSum = 0 
	local tempCurrentAmplitude = amplitude
	local tempCurrentFrequency = frequency

	local octavesForInitialEstimate = math.min(farSurfaceOctaves, maxOctaves)

	for i = 1, octavesForInitialEstimate do
		initialEstimateValue = initialEstimateValue + noiseFunc(x * tempCurrentFrequency, y * tempCurrentFrequency, z * tempCurrentFrequency) * tempCurrentAmplitude
		initialEstimateMaxValueSum = initialEstimateMaxValueSum + tempCurrentAmplitude
		if i < octavesForInitialEstimate then -- Only update if there are more est. octaves or main octaves to compute
			tempCurrentAmplitude = tempCurrentAmplitude * persistence
			tempCurrentFrequency = tempCurrentFrequency * lacunarity
		end
	end

	total = initialEstimateValue

	local normalizedInitialEstimate = 0.5
	if initialEstimateMaxValueSum > 0 then
		normalizedInitialEstimate = (initialEstimateValue / initialEstimateMaxValueSum + 1) * 0.5
	end

	local effectiveOctavesToCompute = farSurfaceOctaves
	local distToThreshold = math.abs(normalizedInitialEstimate - targetThreshold)

	if distToThreshold < transitionRange then
		local proximityFactor = 1 - (distToThreshold / (transitionRange + 1e-6)) 
		effectiveOctavesToCompute = math.floor(lerp(farSurfaceOctaves, nearSurfaceOctaves, proximityFactor^2))
	elseif normalizedInitialEstimate <= targetThreshold - transitionRange or normalizedInitialEstimate >= targetThreshold + transitionRange then
		effectiveOctavesToCompute = farSurfaceOctaves
	end

	effectiveOctavesToCompute = math.clamp(effectiveOctavesToCompute, 1, maxOctaves)

	local currentAmplitudeForMainLoop = tempCurrentAmplitude
	local currentFrequencyForMainLoop = tempCurrentFrequency
	if octavesForInitialEstimate > 0 then -- If we computed estimate octaves, advance amp/freq for next one
		currentAmplitudeForMainLoop = currentAmplitudeForMainLoop * persistence
		currentFrequencyForMainLoop = currentFrequencyForMainLoop * lacunarity
	end


	for i = octavesForInitialEstimate + 1, effectiveOctavesToCompute do
		total = total + noiseFunc(x * currentFrequencyForMainLoop, y * currentFrequencyForMainLoop, z * currentFrequencyForMainLoop) * currentAmplitudeForMainLoop
		currentAmplitudeForMainLoop = currentAmplitudeForMainLoop * persistence
		currentFrequencyForMainLoop = currentFrequencyForMainLoop * lacunarity
		if currentAmplitudeForMainLoop < 0.001 then break end
	end

	return (total / sumOfAllPossibleAmplitudes + 1) * 0.5
end

-- [[ NOISE TRANSFORMATION & UTILITY FUNCTIONS ]]
function Perlin.Transform_Billow(value_01, strength)
	strength = strength or 1.0
	if value_01 == nil then return 0.5 end
	local val_neg1_1 = (value_01 * 2) - 1
	local billowed_val_neg1_1 = math.abs(val_neg1_1)
	billowed_val_neg1_1 = billowed_val_neg1_1 * 2 - 1 
	local blended_neg1_1 = lerp(val_neg1_1, billowed_val_neg1_1, strength)
	return (blended_neg1_1 + 1) * 0.5
end

function Perlin.Transform_Ridge(value_01, power, strength)
	power = power or 1.0
	strength = strength or 1.0
	if value_01 == nil then return 0.5 end 
	local val_neg1_1 = (value_01 * 2) - 1
	local abs_val = math.abs(val_neg1_1)
	local ridged_val_neg1_1 = (1 - math.pow(abs_val, power)) * 2 - 1
	local blended_neg1_1 = lerp(val_neg1_1, ridged_val_neg1_1, strength)
	return (blended_neg1_1 + 1) * 0.5
end


function Perlin.DomainWarp(x,y,z, warpFreqFactor, warpStr, warpNoiseFunc, warpOctaves, warpPersistence, warpLacunarity)
	warpNoiseFunc = warpNoiseFunc or Perlin.Noise_Raw 
	warpFreqFactor = warpFreqFactor or Config.DomainWarp_DefaultFrequencyFactor
	warpStr = warpStr or Config.DomainWarp_DefaultStrength

	local actualWarpFreq = warpFreqFactor 

	local ox,oy,oz

	if warpOctaves and warpOctaves > 1 then
		local getFBM_Displacement = function(vx,vy,vz,seedOffset)
			local noiseVal = Perlin.FBM_Base(vx,vy,vz,
				warpOctaves,
				warpPersistence or Config.FBM_DefaultPersistence,
				warpLacunarity or Config.FBM_DefaultLacunarity,
				1.0, 
				1.0,
				function(nx,ny,nz) return Perlin.Noise_Raw(nx+seedOffset,ny+seedOffset,nz+seedOffset) end
			)
			return (noiseVal * 2 - 1)
		end
		ox = getFBM_Displacement(x * actualWarpFreq, y * actualWarpFreq, z * actualWarpFreq, 10.37) * warpStr
		oy = getFBM_Displacement(x * actualWarpFreq, y * actualWarpFreq, z * actualWarpFreq, -40.51) * warpStr
		oz = getFBM_Displacement(x * actualWarpFreq, y * actualWarpFreq, z * actualWarpFreq, 70.63) * warpStr
	else
		ox = warpNoiseFunc(x*actualWarpFreq+10.37, y*actualWarpFreq+20.79, z*actualWarpFreq+30.13) * warpStr
		oy = warpNoiseFunc(x*actualWarpFreq-40.51, y*actualWarpFreq-50.93, z*actualWarpFreq-60.27) * warpStr
		oz = warpNoiseFunc(x*actualWarpFreq+70.63, y*actualWarpFreq+80.17, z*actualWarpFreq+90.31) * warpStr
	end
	return x + ox, y + oy, z + oz
end

local CURL_EPSILON = 0.01 
function Perlin.CurlNoise(x,y,z, baseFreq, curlNoiseFunc_param_not_used, curlOctaves, curlPersistence, curlLacunarity)
	-- Initial Parameter Sanity Check
	if type(x)~="number" or x~=x or type(y)~="number" or y~=y or type(z)~="number" or z~=z then
		error(string.format("CurlNoise Initial Coord Error: x(%s,%s) y(%s,%s) z(%s,%s)", type(x),tostring(x),type(y),tostring(y),type(z),tostring(z)),0)
	end
	if type(baseFreq)~="number" or baseFreq~=baseFreq then
		error(string.format("CurlNoise Initial baseFreq Error: baseFreq(%s,%s)", type(baseFreq), tostring(baseFreq)),0)
	end
	if curlOctaves and (type(curlOctaves)~="number" or curlOctaves~=curlOctaves) then
		error(string.format("CurlNoise Initial octaves Error: octaves(%s,%s)", type(curlOctaves),tostring(curlOctaves)),0)
	end
	if type(CURL_EPSILON)~="number" or CURL_EPSILON~=CURL_EPSILON or CURL_EPSILON==0 then -- Also check epsilon for zero
		error(string.format("CurlNoise CURL_EPSILON invalid: (%s,%s)",type(CURL_EPSILON),tostring(CURL_EPSILON)),0)
	end


	baseFreq = baseFreq or Config.Curl_DefaultFrequencyFactor

	local px_potential_func, py_potential_func, pz_potential_func

	if curlOctaves and curlOctaves > 0 then
		local getFBM_PotentialComponent = function(vx,vy,vz, fbm_frequency_param, fbm_octaves_param, fbm_persistence_param, fbm_lacunarity_param, seedOffset_for_raw_noise)
			local fbm_result = Perlin.FBM_Base(vx,vy,vz, 
				fbm_octaves_param,
				fbm_persistence_param, 
				fbm_lacunarity_param,  
				fbm_frequency_param,   
				1.0,                   
				function(raw_nx,raw_ny,raw_nz) 
					local raw_noise_res = Perlin.Noise_Raw(raw_nx+seedOffset_for_raw_noise, raw_ny+seedOffset_for_raw_noise, raw_nz+seedOffset_for_raw_noise)
					if type(raw_noise_res) ~= "number" then
						error("Noise_Raw inside FBM_Base lambda returned " .. type(raw_noise_res) .. "("..tostring(raw_noise_res)..") Coords: " .. tostring(raw_nx+seedOffset_for_raw_noise), 0)
					elseif raw_noise_res ~= raw_noise_res then
						error("Noise_Raw inside FBM_Base lambda returned NaN. Coords: " .. tostring(raw_nx+seedOffset_for_raw_noise), 0)
					end
					return raw_noise_res
				end 
			)
			if type(fbm_result) ~= "number" then
				error("getFBM_PotentialComponent: FBM_Base returned " .. type(fbm_result) .. "("..tostring(fbm_result)..") Input coords to FBM: "..tostring(vx)..", "..tostring(vy)..", "..tostring(vz) .. " Freq: "..tostring(fbm_frequency_param) , 0)
			elseif fbm_result ~= fbm_result then
				error("getFBM_PotentialComponent: FBM_Base returned NaN. Input coords to FBM: "..tostring(vx)..", "..tostring(vy)..", "..tostring(vz).. " Freq: "..tostring(fbm_frequency_param), 0)
			end
			return fbm_result
		end

		px_potential_func = function(lx,ly,lz) return getFBM_PotentialComponent(lx, ly, lz, baseFreq, curlOctaves, curlPersistence or Config.FBM_DefaultPersistence, curlLacunarity or Config.FBM_DefaultLacunarity, 123.45) end
		py_potential_func = function(lx,ly,lz) return getFBM_PotentialComponent(lx, ly, lz, baseFreq, curlOctaves, curlPersistence or Config.FBM_DefaultPersistence, curlLacunarity or Config.FBM_DefaultLacunarity, 678.91) end 
		pz_potential_func = function(lx,ly,lz) return getFBM_PotentialComponent(lx, ly, lz, baseFreq, curlOctaves, curlPersistence or Config.FBM_DefaultPersistence, curlLacunarity or Config.FBM_DefaultLacunarity, 234.56) end 
	else
		px_potential_func = function(lx,ly,lz) return Perlin.Noise((lx*baseFreq)+123.45, (ly*baseFreq)+0,      (lz*baseFreq)+0) end
		py_potential_func = function(lx,ly,lz) return Perlin.Noise((lx*baseFreq)+0,      (ly*baseFreq)+678.91, (lz*baseFreq)+0) end
		pz_potential_func = function(lx,ly,lz) return Perlin.Noise((lx*baseFreq)+0,      (ly*baseFreq)+0,      (lz*baseFreq)+234.56) end
	end

	local val_px_z_plus, val_px_z_minus
	local val_py_z_plus, val_py_z_minus
	local val_pz_y_plus, val_pz_y_minus
	local val_pz_x_plus, val_pz_x_minus
	local val_px_y_plus, val_px_y_minus
	local val_py_x_plus, val_py_x_minus

	val_px_z_plus = px_potential_func(x,y,z+CURL_EPSILON)
	if type(val_px_z_plus)=="nil" then error("val_px_z_plus IS LUA NIL. px_potential_func(x,y,z+eps)",0) elseif type(val_px_z_plus)~="number" then error("val_px_z_plus type "..type(val_px_z_plus),0) elseif val_px_z_plus~=val_px_z_plus then error("val_px_z_plus is NaN",0) end
	val_px_z_minus = px_potential_func(x,y,z-CURL_EPSILON)
	if type(val_px_z_minus)=="nil" then error("val_px_z_minus IS LUA NIL. px_potential_func(x,y,z-eps)",0) elseif type(val_px_z_minus)~="number" then error("val_px_z_minus type "..type(val_px_z_minus),0) elseif val_px_z_minus~=val_px_z_minus then error("val_px_z_minus is NaN",0) end
	local dPx_dz = (val_px_z_plus - val_px_z_minus) / (2*CURL_EPSILON)

	val_py_z_plus = py_potential_func(x,y,z+CURL_EPSILON)
	if type(val_py_z_plus)=="nil" then error("val_py_z_plus IS LUA NIL. py_potential_func(x,y,z+eps)",0) elseif type(val_py_z_plus)~="number" then error("val_py_z_plus type "..type(val_py_z_plus),0) elseif val_py_z_plus~=val_py_z_plus then error("val_py_z_plus is NaN",0) end
	val_py_z_minus = py_potential_func(x,y,z-CURL_EPSILON)
	if type(val_py_z_minus)=="nil" then error("val_py_z_minus IS LUA NIL. py_potential_func(x,y,z-eps)",0) elseif type(val_py_z_minus)~="number" then error("val_py_z_minus type "..type(val_py_z_minus),0) elseif val_py_z_minus~=val_py_z_minus then error("val_py_z_minus is NaN",0) end
	local dPy_dz = (val_py_z_plus - val_py_z_minus) / (2*CURL_EPSILON)

	val_pz_y_plus = pz_potential_func(x,y+CURL_EPSILON,z)
	if type(val_pz_y_plus)=="nil" then error("val_pz_y_plus IS LUA NIL. pz_potential_func(x,y+eps,z)",0) elseif type(val_pz_y_plus)~="number" then error("val_pz_y_plus type "..type(val_pz_y_plus),0) elseif val_pz_y_plus~=val_pz_y_plus then error("val_pz_y_plus is NaN",0) end
	val_pz_y_minus = pz_potential_func(x,y-CURL_EPSILON,z)
	if type(val_pz_y_minus)=="nil" then error("val_pz_y_minus IS LUA NIL. pz_potential_func(x,y-eps,z)",0) elseif type(val_pz_y_minus)~="number" then error("val_pz_y_minus type "..type(val_pz_y_minus),0) elseif val_pz_y_minus~=val_pz_y_minus then error("val_pz_y_minus is NaN",0) end
	local dPz_dy = (val_pz_y_plus - val_pz_y_minus) / (2*CURL_EPSILON)

	val_pz_x_plus = pz_potential_func(x+CURL_EPSILON,y,z)
	if type(val_pz_x_plus)=="nil" then error("val_pz_x_plus IS LUA NIL. pz_potential_func(x+eps,y,z)",0) elseif type(val_pz_x_plus)~="number" then error("val_pz_x_plus type "..type(val_pz_x_plus),0) elseif val_pz_x_plus~=val_pz_x_plus then error("val_pz_x_plus is NaN",0) end
	val_pz_x_minus = pz_potential_func(x-CURL_EPSILON,y,z)
	if type(val_pz_x_minus)=="nil" then error("val_pz_x_minus IS LUA NIL. pz_potential_func(x-eps,y,z)",0) elseif type(val_pz_x_minus)~="number" then error("val_pz_x_minus type "..type(val_pz_x_minus),0) elseif val_pz_x_minus~=val_pz_x_minus then error("val_pz_x_minus is NaN",0) end
	local dPz_dx = (val_pz_x_plus - val_pz_x_minus) / (2*CURL_EPSILON)

	val_px_y_plus = px_potential_func(x,y+CURL_EPSILON,z)
	if type(val_px_y_plus)=="nil" then error("val_px_y_plus IS LUA NIL. px_potential_func(x,y+eps,z)",0) elseif type(val_px_y_plus)~="number" then error("val_px_y_plus type "..type(val_px_y_plus),0) elseif val_px_y_plus~=val_px_y_plus then error("val_px_y_plus is NaN",0) end
	val_px_y_minus = px_potential_func(x,y-CURL_EPSILON,z) 
	if type(val_px_y_minus)=="nil" then error("val_px_y_minus IS LUA NIL. px_potential_func(x,y-eps,z)",0) elseif type(val_px_y_minus)~="number" then error("val_px_y_minus type "..type(val_px_y_minus),0) elseif val_px_y_minus~=val_px_y_minus then error("val_px_y_minus is NaN",0) end
	local dPx_dy = (val_px_y_plus - val_px_y_minus) / (2*CURL_EPSILON)

	val_py_x_plus = py_potential_func(x+CURL_EPSILON,y,z)
	if type(val_py_x_plus)=="nil" then error("val_py_x_plus IS LUA NIL. py_potential_func(x+eps,y,z)",0) elseif type(val_py_x_plus)~="number" then error("val_py_x_plus type "..type(val_py_x_plus),0) elseif val_py_x_plus~=val_py_x_plus then error("val_py_x_plus is NaN",0) end
	val_py_x_minus = py_potential_func(x-CURL_EPSILON,y,z)
	if type(val_py_x_minus)=="nil" then error("val_py_x_minus IS LUA NIL. py_potential_func(x-eps,y,z)",0) elseif type(val_py_x_minus)~="number" then error("val_py_x_minus type "..type(val_py_x_minus),0) elseif val_py_x_minus~=val_py_x_minus then error("val_py_x_minus is NaN",0) end
	local dPy_dx = (val_py_x_plus - val_py_x_minus) / (2*CURL_EPSILON)

	if dPy_dz~=dPy_dz or dPz_dy~=dPz_dy or dPz_dx~=dPz_dx or dPx_dz~=dPx_dz or dPx_dy~=dPx_dy or dPy_dx~=dPy_dx then
		local err_msg_deriv_nan = "Perlin.CurlNoise Error PostCalc: One or more final derivatives are NaN. Input xyz("..tostring(x)..","..tostring(y)..","..tostring(z).."). Derivs: dPy_dz:"..tostring(dPy_dz)..", dPz_dy:"..tostring(dPz_dy)..", dPz_dx:"..tostring(dPz_dx)..", dPx_dz:"..tostring(dPx_dz)..", dPx_dy:"..tostring(dPx_dy)..", dPy_dx:"..tostring(dPy_dx)
		error(err_msg_deriv_nan, 0)
	end

	local curlVec = Vector3.new(
		dPy_dz - dPz_dy, 
		dPz_dx - dPx_dz, 
		dPx_dy - dPy_dx
	)

	if curlVec.Magnitude > 1e-6 then
		return curlVec.Unit 
	else
		return Vector3.zero 
	end
end


return Perlin