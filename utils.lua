local lovr = {
    math = require "lovr.math",
    data = require "lovr.data",
}

local v2 = require "math.v2"
local v3 = require "math.v3"

local quat = lovr.math.quat
local vec3 = lovr.math.vec3

local utils = {}

--- @param n number
--- @return number
local function signof(n)
    if n > 0 then
        return 1
    elseif n < 0 then
        return -1
    else
        return 0
    end
end

--- Returns a list of `n` unit vectors pointing out from a hemisphere having the
--- direction `dir`, optionally cosine-weighted.
---
--- If `cosineWeight` is falsey, the vectors will have uniform distribution. If
--- truthy, they will be cosine-weighted towards `dir`.
---
--- @param n number The number of vectors to generate
--- @param dir v3 a vector pointing in the direction of the hemisphere
--- @param cosineWeight? boolean
--- @return v3[]
function utils.hemiDirList(n, dir, cosineWeight)
    local phi = math.pi * (3 - math.sqrt(5))
    local q = quat(vec3(0, 0, 1), vec3(dir.x, dir.y, dir.z))
    local output = {}
    for i = 0, n - 1 do
        local z = i / (n - 1)
        if cosineWeight then
            z = math.sqrt(z)
        end
        local r = math.sqrt(1 - z * z)
        local t = phi * i

        local x = math.cos(t) * r
        local y = math.sin(t) * r
        local v = vec3(x, y, z):rotate(q)
        table.insert(output, v3(v[1], v[2], v[3]))
    end
    return output
end

--- Returns a single hemispherical unit vector, rotated by `q`.
---
--- The vector will be randomised, with cosine-weighted distribution.
---
--- @param q Quat
--- @return v3
function utils.randomHemiDir(q)
    local r1 = math.random()
    local r2 = math.random()

    local pi2r2 = 2 * math.pi * r2
    local sr1 = math.sqrt(r1)

    local x = math.cos(pi2r2) * sr1
    local y = math.sin(pi2r2) * sr1
    local z = math.sqrt(1 - r1)

    local v = vec3(x, y, z):rotate(q)
    return v3(v[1], v[2], v[3])
end

--- Returns the worldspace coordinate for a `uv` in `face`.
--- @param uv v2
--- @param uvpair UVPair
--- @param face GeoFace
--- @return v3
function utils.uv2World(uv, uvpair, face)
    -- Currently adding 0.5 to every coord to account for texel center offset
    local tl = uvpair.topLeft
    local br = uvpair.bottomRight

    local sizeX = br.x - tl.x
    local sizeY = br.y - tl.y

    local px = ((uv.x + 0.5) - tl.x) / sizeX --- @type number
    local py = ((uv.y + 0.5) - tl.y) / sizeY --- @type number

    local sx = (px - 0.5) * 2
    local sy = -(py - 0.5) * 2

    return face.origin + face.right * sx + face.up * sy
end

--- Returns a uv-space coordinate by projecting `pos` onto `face`.
--- @param pos v3
--- @param uvpair UVPair
--- @param face GeoFace
--- @return v2
function utils.world2UV(pos, uvpair, face)
    -- Currently subtracting 0.5 to every coord to account for texel center
    -- offset
    local tl = uvpair.topLeft
    local br = uvpair.bottomRight

    local sx = br.x - tl.x
    local sy = br.y - tl.y

    local mx = sx / 2
    local my = sy / 2

    local vx = pos.x - face.origin.x
    local vy = pos.y - face.origin.y
    local vz = pos.z - face.origin.z

    local up = face.upDir
    local right = face.rightDir

    -- x or y = v:dot(right or up)
    local x = vx * right.x + vy * right.y + vz * right.z
    local y = -(vx * up.x + vy * up.y + vz * up.z)

    return v2(
        tl.x + mx - 0.5 + (x / face.size.x) * sx,
        tl.y + my - 0.5 + (y / face.size.y) * sy
    )
end

--- Returns an iterator that steps over every pixel of `uvpair`, margins
--- inclusive, and returns the pixelspace `x` and `y` coordinates, and the
--- worldspace location of that pixel.
---
--- @param uvpair UVPair
--- @param face GeoFace
--- @return fun(): number, number, v3
function utils.eachPixel(uvpair, face)
    local minX = uvpair.topLeft.x - uvpair.margin
    local y = uvpair.topLeft.y - uvpair.margin
    local x = minX

    local maxX = uvpair.bottomRight.x + uvpair.margin
    local maxY = uvpair.bottomRight.y + uvpair.margin

    return function()
        -- Did we overflow x?
        if x >= maxX then
            x = minX
            y = y + 1

            -- Did we overflow y?
            if y >= maxY then
                -- Can't figure out annotation to make LuaLS happy about this.
                --- @diagnostic disable-next-line
                return nil
            end
        end

        local outX = x
        local outY = y
        local outPos = utils.uv2World(v2(outX, outY), uvpair, face)

        x = x + 1

        return outX, outY, outPos
    end
end

--- Returns an iterator that steps over every pixel of `uvpair`, margins
--- inclusive, and returns a list of pixelspace `x` and `y` coordinates, and the
--- worldspace locations of those pixels.
---
--- @param uvpair UVPair
--- @param face GeoFace
--- @param samples "1x" | "4x" | "8x"
--- @return fun(): x: number, y: number, poses: v3[]
function utils.eachPixelAA(uvpair, face, samples)
    local minX = uvpair.topLeft.x - uvpair.margin
    local y = uvpair.topLeft.y - uvpair.margin
    local x = minX

    local maxX = uvpair.bottomRight.x + uvpair.margin
    local maxY = uvpair.bottomRight.y + uvpair.margin

    return function()
        -- Did we overflow x?
        if x >= maxX then
            x = minX
            y = y + 1

            -- Did we overflow y?
            if y >= maxY then
                -- Can't figure out annotation to make LuaLS happy about this.
                --- @diagnostic disable-next-line
                return nil
            end
        end

        local outX = x
        local outY = y

        --- @type v3[]
        local poses

        if samples == "1x" then
            poses = {
                utils.uv2World(v2(outX, outY), uvpair, face),
            }
        elseif samples == "4x" then
            poses = {
                utils.uv2World(v2(outX - 0.125, outY + 0.375), uvpair, face),
                utils.uv2World(v2(outX + 0.375, outY + 0.125), uvpair, face),
                utils.uv2World(v2(outX + 0.125, outY - 0.375), uvpair, face),
                utils.uv2World(v2(outX - 0.375, outY - 0.125), uvpair, face),
            }
        else
            poses = {
                utils.uv2World(v2(outX - 0.435, outY + 0.063), uvpair, face),
                utils.uv2World(v2(outX - 0.188, outY + 0.313), uvpair, face),
                utils.uv2World(v2(outX + 0.063, outY + 0.188), uvpair, face),
                utils.uv2World(v2(outX + 0.435, outY + 0.435), uvpair, face),
                utils.uv2World(v2(outX - 0.313, outY - 0.313), uvpair, face),
                utils.uv2World(v2(outX - 0.063, outY - 0.188), uvpair, face),
                utils.uv2World(v2(outX + 0.188, outY - 0.435), uvpair, face),
                utils.uv2World(v2(outX + 0.313, outY - 0.063), uvpair, face),
            }
        end

        x = x + 1

        return outX, outY, poses
    end
end

--- If a ray starting from `rayPos` and pointing in `rayDir` intersects `face`,
--- returns the intersection point and the distance from `rayPos` to the
--- intersection.
---
--- If `limit` is not `nil`, an intersection will only be returned if its
--- distance is less than or equal to `limit`.
---
--- **NOTE:** This function takes up the majority of the time of bounce light
--- passes. Optimizing this function will have the greatest impact in those
--- passes.
---
--- @param rayPos v3
--- @param rayDir v3
--- @param face GeoFace
--- @param limit? number
--- @return v3?, number?
function utils.intersection(rayPos, rayDir, face, limit)
    local norm = face.normal

    -- If the ray is parallel to the plane, there's no intersection.
    local div = rayDir:dot(norm)
    if div == 0 then
        return nil
    end

    -- Find the distance from the ray origin to the plane.
    local fo = face.origin
    local ox = fo.x - rayPos.x
    local oy = fo.y - rayPos.y
    local oz = fo.z - rayPos.z

    local nx, ny, nz = norm.x, norm.y, norm.z

    local t = (ox * nx + oy * ny + oz * nz) / div

    -- If it's negative, the plane is behind us, so there's no intersection.
    -- And if the intersection is further than the limit, we also want to exit
    -- early.
    if t < 0 or (limit and t > limit) then
        return nil
    end

    -- local p = rayPos + rayDir * t
    local px = rayPos.x + rayDir.x * t
    local py = rayPos.y + rayDir.y * t
    local pz = rayPos.z + rayDir.z * t

    -- Do an early out if the intersection point is further than the bounding
    -- radius.
    if math.sqrt(
            (px - fo.x) * (px - fo.x) +
            (py - fo.y) * (py - fo.y) +
            (pz - fo.z) * (pz - fo.z)
        ) > face.boundingRadius then
        return
    end

    -- Test the side of each edge.
    local edges = face.edges
    local sign = 0
    for i = 1, #edges do
        local edge = edges[i]
        local edgeStart = edge.start
        local edgeDir = edge.dir

        local edx, edy, edz = edgeDir.x, edgeDir.y, edgeDir.z

        ox = px - edgeStart.x
        oy = py - edgeStart.y
        oz = pz - edgeStart.z

        local cx = edy * oz - edz * oy
        local cy = edz * ox - edx * oz
        local cz = edx * oy - edy * ox

        local c = cx * nx + cy * ny + cz * nz

        if c ~= 0 then
            if sign == 0 then
                sign = signof(c)
            elseif sign ~= signof(c) then
                return
            end
        end
    end

    return v3(px, py, pz), t
end

--- @param face GeoFace
--- @param p v3
--- @return number
function utils.broadDistance(face, p)
    local aabb = face.aabb

    local closest = v3(
        math.min(math.max(p.x, aabb.x.min), aabb.x.max),
        math.min(math.max(p.y, aabb.y.min), aabb.y.max),
        math.min(math.max(p.z, aabb.z.min), aabb.z.max)
    )

    return p:distance(closest)
end

--- @param dist number
--- @param pos v3
--- @param faces GeoFace[]
--- @return GeoFace[]
function utils.facesBroadlyWithin(dist, pos, faces)
    local output = {} --- @type GeoFace[]
    for i = 1, #faces do
        local testFace = faces[i]
        if utils.broadDistance(testFace, pos) <= dist then
            table.insert(output, testFace)
        end
    end
    return output
end

--- @param img Image
--- @return Image
function utils.finalizeImage(img)
    -- We originally calculate using a floating point format, with an unbound
    -- dynamic range. But the texture needs to range from 0.0 - 1.0 (at least,
    -- conceptually, in reality it's 0-255), so we have to cap it.
    --
    -- As an extra trick (inspired by Quake), we divide by 2 before capping.
    -- Then, in the shader, we multiply by 2. This allows us to overbrighten
    -- surfaces. To see what lightmaps look like without this trick, remove the
    -- divisions by 2 here and the multiplication by 2.0f in `lovrmain` in
    -- `shaders/fragment.glsl`. Note how flat the highlights look.

    local w, h = img:getDimensions()
    local finalImg = lovr.data.newImage(w, h)
    finalImg:mapPixel(
        function(x, y, _, _, _, _)
            local fr, fg, fb = img:getPixel(x, y)
            return math.min(fr / 2, 1),
                math.min(fg / 2, 1),
                math.min(fb / 2, 1),
                1
        end
    )
    return finalImg
end

return utils
