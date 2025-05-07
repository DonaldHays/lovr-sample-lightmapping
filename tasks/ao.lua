local utils = require "utils"

--- @param faceIndex number
--- @param ctx TaskContext
--- @param image Image
return function(faceIndex, ctx, image)
    local faces = ctx.faces

    local face = faces[faceIndex]
    local aoRayCount = ctx.quality.aoRayCount
    local uv = ctx.uvmap.coords[face]
    local faceNorm = face.normal

    local dirs = utils.hemiDirList(aoRayCount, faceNorm)

    -- For each pixel
    for x, y, rayOrigin in utils.eachPixel(uv, face) do
        local intSum = 0

        local potentialHits = utils.facesBroadlyWithin(1, rayOrigin, faces)

        -- For each ray
        for dirIndex = 1, #dirs do
            local rayDir = dirs[dirIndex]
            --- @type GeoFace?, number?
            local closestFace, closestDir = nil, nil
            -- Find the closest hit
            for i = 1, #potentialHits do
                local testFace = potentialHits[i]
                if testFace ~= face then
                    local _, intDist = utils.intersection(
                        rayOrigin, rayDir, testFace, closestDir or 1
                    )
                    if intDist then
                        if closestFace == nil or intDist < closestDir then
                            closestFace = testFace
                            closestDir = intDist
                        end
                    end
                end
            end
            -- If we found a hit, accumulate based on distance
            if closestFace ~= nil and closestDir ~= nil then
                intSum = intSum + (1 - closestDir)
            end
        end
        intSum = math.pow(1 - (intSum / aoRayCount), 2)

        local r, g, b = image:getPixel(x, y)
        image:setPixel(x, y, intSum * r, intSum * g, intSum * b)
    end
end
