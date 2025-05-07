--- @class Quality
--- @field texelsPerMeter number The number of light texels per worldspace meter. Higher for more detailed lightmaps, but will take longer to compute.
--- @field bouncePassCount number The number of bounce light passes. Higher for more passes.
--- @field bounceRayCount number The number of rays to fire per sample in the bounce light passes.
--- @field aoRayCount number The number of rays to fire during the ambient occlusion pass.
--- @field directSamples "1x" | "4x" | "8x" The number of samples per texel in the direct pass. This creates anti-aliasing along shadow edges.

--- @class TaskContext
--- @field faces GeoFace[]
--- @field uvmap UVMap
--- @field quality Quality

return {
    direct = require "tasks.direct",
    bounce = require "tasks.bounce",
    ao = require "tasks.ao"
}
