local lovr = {
    timer = require "lovr.timer",
}

local utils = require "utils"

--- @param faceIndex number
--- @param lightPos v3
--- @param ctx TaskContext
--- @param image Image
return function(faceIndex, lightPos, ctx, image)
    local faces = ctx.faces
    local uvmap = ctx.uvmap

    local face = faces[faceIndex]
    local uv = uvmap.coords[face]
    local faceNorm = face.normal

    -- For each pixel
    for x, y, poses in utils.eachPixelAA(uv, face, ctx.quality.directSamples) do
        local shadowFraction = 0
        local lightDist = 0
        --- @type v3
        local lightDir

        -- For each sample position
        for i = 1, #poses do
            local pos = poses[i]

            lightDist = lightPos:distance(pos)
            lightDir = (lightPos - pos):normalize()

            -- Search the faces to check for line-of-sight blockage. We
            -- accumulate the result in `shadowFraction`. If we sample multiple
            -- positions per pixel, this will give our shadows an anti-aliased
            -- appearance.
            for faceIdx = 1, #faces do
                local testFace = faces[faceIdx]
                if testFace ~= face then
                    local _, intDist = utils.intersection(
                        pos, lightDir, testFace
                    )
                    if intDist and intDist < lightDist then
                        shadowFraction = shadowFraction + 1
                        break
                    end
                end
            end
        end
        shadowFraction = 1 - shadowFraction / #poses

        -- The `5` in `intensity` is a customizable intensity value. Tune it to
        -- change the "brightness" of the light.
        local falloff = (1 / (1 + lightDist * lightDist))
        local facing = math.max(faceNorm:dot(lightDir), 0)
        local intensity = falloff * facing * 5 * shadowFraction

        -- We don't have any custom light color support right now, so we just
        -- set the intensity for R, G, and B
        image:setPixel(x, y, intensity, intensity, intensity)
    end
end
