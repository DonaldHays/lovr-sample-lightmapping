local lovr = {
    math = require "lovr.math"
}

local v3 = require "math.v3"
local utils = require "utils"

local vec3 = lovr.math.vec3
local quat = lovr.math.quat

--- @param faceIndex number
--- @param ctx TaskContext
--- @param srcImage Image
--- @param dstImage Image
return function(faceIndex, ctx, srcImage, dstImage)
    local faces = ctx.faces
    local uvmap = ctx.uvmap
    local bounceRayCount = ctx.quality.bounceRayCount

    local face = faces[faceIndex]
    local uv = uvmap.coords[face]
    local faceNorm = face.normal

    -- local dirs = utils.hemiDirList(bounceRayCount, faceNorm, true)
    local q = quat(vec3(0, 0, 1), vec3(faceNorm.x, faceNorm.y, faceNorm.z))

    -- For each pixel
    for x, y, rayOrigin in utils.eachPixel(uv, face) do
        -- Accumulate random light samples into a vector.
        local acc = v3(0, 0, 0)

        -- For each ray
        for dirIndex = 1, bounceRayCount do
            -- Calculate a random cosine-weighted ray.
            local rayDir = utils.randomHemiDir(q)

            -- Find the nearest intersection.
            --- @type GeoFace?, v3?, number?
            local closestFace, closestPoint, closestDist = nil, nil, nil
            for i = 1, #faces do
                local testFace = faces[i]
                if testFace ~= face then
                    local intPoint, intDist = utils.intersection(
                        rayOrigin, rayDir, testFace, closestDist
                    )
                    if intDist and testFace then
                        if closestFace == nil or intDist < closestDist then
                            closestFace = testFace
                            closestPoint = intPoint
                            closestDist = intDist
                        end
                    end
                end
            end

            -- If we hit a face, sample it into the accumulator.
            if closestFace ~= nil and closestPoint ~= nil then
                local facing = math.max(-rayDir:dot(closestFace.normal), 0)
                if facing > 0 then
                    local bounceUV = utils.world2UV(
                        closestPoint, uvmap.coords[closestFace], closestFace
                    )
                    local r, g, b = srcImage:getPixel(bounceUV.x, bounceUV.y)
                    local color = closestFace.color

                    -- The sample is the input lightmap color, multiplied by the
                    -- surface color, attenuated by a facing direction term.
                    local bounce = v3(r, g, b) * color * facing
                    acc = acc + bounce
                end
            end
        end

        -- Scale the accumulator, then store it in the output texel.
        acc = acc / bounceRayCount
        dstImage:setPixel(x, y, acc.x, acc.y, acc.z)
    end
    lovr.math.drain()
end
