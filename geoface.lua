local v3 = require "math.v3"
local v2 = require "math.v2"

-- GeoFaces are the definition format for geometry in this code sample. The
-- project only supports colored quads.
--
-- Originally, I was thinking this file would only be imported in `main.lua`,
-- and the data would be sent to worker threads via channels. Unfortunately,
-- `v2` and `v3` may have FFI backings, in which case they cannot be transported
-- across channels. As a result, every thread imports this data independently,
-- which results in a recalculation of all the helper data, which seems
-- wasteful. In a production project, this would be worth optimizing.

--- The raw user-defined data for a GeoFace.
--- @class GeoFaceData
--- @field origin v3 The center of the face.
--- @field up v3 A vector from the origin to the center of the top edge.
--- @field right v3 A vector from the origin to the center of the right edge.
--- @field color v3 An RGB vector.

--- Additional fields that describe a GeoFace.
---
--- This class is separated from `GeoFaceData` to only require the user to
--- implement the minimum necessary amount of data. The rest of this data can be
--- computed.
--- @class GeoFace: GeoFaceData
--- @field normal v3 A vector projecting out of the face.
--- @field vertices v3[] A list of all four vertices of the face.
--- @field edges Edge[] A list of the face's four edges.
--- @field aabb AABB A minimal box that holds all of the face's vertices.
--- @field boundingRadius number The maximum distance of a vertex from the origin.
--- @field rightDir v3 A normalized version of `right`.
--- @field upDir v3 A normalized version of `up`.
--- @field size v2 The 2D size of the face.

--- @class AABB
--- @field x { min: number, max: number }
--- @field y { min: number, max: number }
--- @field z { min: number, max: number }

--- @class Edge
--- @field start v3
--- @field stop v3
--- @field dir v3

local gf = {}

--- @type GeoFace[]
gf.faces = {}

--- @param face GeoFace
local function calculateNormal(face)
    face.normal = face.right:cross(face.up):normalize()
end

--- @param face GeoFace
local function calculateVertices(face)
    local tl = face.origin - face.right + face.up
    local tr = face.origin + face.right + face.up
    local bl = face.origin - face.right - face.up
    local br = face.origin + face.right - face.up

    face.vertices = { tl, bl, br, tr }
end

--- @param face GeoFace
local function calculateEdges(face)
    local tl, bl, br, tr = unpack(face.vertices)

    face.edges = {
        { start = tl, stop = tr, dir = (tr - tl):normalize() },
        { start = tr, stop = br, dir = (br - tr):normalize() },
        { start = br, stop = bl, dir = (bl - br):normalize() },
        { start = bl, stop = tl, dir = (tl - bl):normalize() },
    }
end

--- @param face GeoFace
local function calculateAABB(face)
    local minX, minY, minZ = face.origin:unpack()
    local maxX, maxY, maxZ = minX, minY, minZ

    for _, v in ipairs(face.vertices) do
        minX = math.min(minX, v.x)
        maxX = math.max(maxX, v.x)

        minY = math.min(minY, v.y)
        maxY = math.max(maxY, v.y)

        minZ = math.min(minZ, v.z)
        maxZ = math.max(maxZ, v.z)
    end

    face.aabb = {
        x = { min = minX, max = maxX },
        y = { min = minY, max = maxY },
        z = { min = minZ, max = maxZ },
    }
end

--- @param face GeoFace
local function calculateBoundingRadius(face)
    local tl, bl, br, tr = unpack(face.vertices)
    face.boundingRadius = math.max(
        (tl - face.origin):length(),
        (tr - face.origin):length(),
        (bl - face.origin):length(),
        (br - face.origin):length()
    )
end

--- @param face GeoFace
local function calculateDirSize(face)
    face.upDir = face.up:normalize()
    face.rightDir = face.right:normalize()
    face.size = v2(face.right:length() * 2, face.up:length() * 2)
end

function gf.load()
    -- +x to the right
    -- +y up in the air
    -- +z towards the screen

    -- let north be -z, and east be +x
    --- @type GeoFaceData[]
    local data = {
        -- Boundary --

        -- Ground
        {
            origin = v3(0, 0, 0),
            up = v3(0, 0, -2.5),
            right = v3(2.5, 0, 0),
            color = v3(0.4, 0.6, 0.8)
        },
        -- Ceiling
        {
            origin = v3(0, 3, 0),
            up = v3(0, 0, 2.5),
            right = v3(2.5, 0, 0),
            color = v3(0.8, 0.8, 0.8)
        },
        -- North
        {
            origin = v3(0, 1.5, -2.5),
            up = v3(0, 1.5, 0),
            right = v3(2.5, 0, 0),
            color = v3(0.8, 0.8, 0.8)
        },
        -- East
        {
            origin = v3(2.5, 1.5, 0),
            up = v3(0, 1.5, 0),
            right = v3(0, 0, 2.5),
            color = v3(0.0, 1.0, 0.0)
        },
        -- South
        {
            origin = v3(0, 1.5, 2.5),
            up = v3(0, 1.5, 0),
            right = v3(-2.5, 0, 0),
            color = v3(0.8, 0.8, 0.8)
        },
        -- West
        {
            origin = v3(-2.5, 1.5, 0),
            up = v3(0, 1.5, 0),
            right = v3(0, 0, -2.5),
            color = v3(1.0, 0.0, 0.0)
        },

        -- Column --

        -- South
        {
            origin = v3(1, 1.5, -0.5),
            up = v3(0, 1.5, 0),
            right = v3(0.5, 0, 0),
            color = v3(0.6, 0.6, 0.6)
        },
        -- North
        {
            origin = v3(1, 1.5, -1.5),
            up = v3(0, 1.5, 0),
            right = v3(-0.5, 0, 0),
            color = v3(0.6, 0.6, 0.6)
        },
        -- East
        {
            origin = v3(1.5, 1.5, -1),
            up = v3(0, 1.5, 0),
            right = v3(0, 0, -0.5),
            color = v3(0.7, 0.7, 0.7)
        },
        -- West
        {
            origin = v3(0.5, 1.5, -1),
            up = v3(0, 1.5, 0),
            right = v3(0, 0, 0.5),
            color = v3(0.7, 0.7, 0.7)
        },
    }

    gf.faces = data

    for i = 1, #gf.faces do
        local face = gf.faces[i]
        calculateNormal(face)
        calculateVertices(face)
        calculateEdges(face)
        calculateAABB(face)
        calculateBoundingRadius(face)
        calculateDirSize(face)
    end
end

return gf
