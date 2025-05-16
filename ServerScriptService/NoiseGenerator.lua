-- ModuleScript: NoiseGenerator
-- Path: ServerScriptService/NoiseGenerator.lua
local Noise = {}
local Perlin = require(script.Perlin)

-- Public API: get noise value at world position
function Noise:GetValue(x, y, z)
    return Perlin:Noise(x, y, z)
end

return Noise