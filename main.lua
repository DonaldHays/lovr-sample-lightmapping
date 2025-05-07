if lovr.system.getOS() == "macOS" then
    jit.off()
end

local gf = require "geoface"
local uvmapper = require "uvmapper"
local mesher = require "mesher"
local utils = require "utils"
local taskOutput = ""

local vertex = lovr.filesystem.read("shaders/vertex.glsl")
local fragment = lovr.filesystem.read("shaders/fragment.glsl")

--- @type Mesh
local mesh

--- @type Texture
local tex

--- @type Shader
local shader

--- @type Thread
local scheduler

local resultChannel = lovr.thread.getChannel("result") --- @type Channel

function lovr.load()
    shader = lovr.graphics.newShader(vertex, fragment)

    -----
    -- Quality settings for the project may be easily customized by adjusting
    -- this table.
    -----

    --- @type Quality
    local quality = {
        texelsPerMeter = 8,
        aoRayCount = 32,
        bounceRayCount = 32,
        bouncePassCount = 4,
        directSamples = "8x"
    }

    gf.load()
    local uvmap = uvmapper(gf.faces, quality)
    mesh = mesher(gf.faces, uvmap)

    --- @type TaskContext
    local ctx = {
        faces = gf.faces,
        uvmap = uvmap,
        quality = quality
    }

    -- Start the scheduler thread.
    scheduler = lovr.thread.newThread("scheduler.lua")
    scheduler:start(ctx.quality)

    -- Create the initial texture.
    local img = lovr.data.newImage(uvmap.size, uvmap.size, "rgba32f")
    img:mapPixel(function(x, y, r, g, b, a)
        return x / uvmap.size, y / uvmap.size, math.random(), 1
    end)

    tex = lovr.graphics.newTexture(utils.finalizeImage(img), {})
end

function lovr.update(dt)
    -- Attempt to pop results off the result channel. A result may have two
    -- keys, `img` and `stat`, providing an updated image, or an extra
    -- descriptive status line.
    while true do
        --- @type any
        local dontWait = false
        local result = resultChannel:pop(dontWait)
        if result == nil then
            break
        end

        if result.img then
            -- Lighting is calculated in linear space, so make sure we flag the
            -- texture appropriately.
            tex = lovr.graphics.newTexture(result.img, {
                linear = true
            })
        end

        if result.stat then
            taskOutput = taskOutput .. result.stat .. "\n"
        end
    end
end

-- local sampler = lovr.graphics.newSampler {
--     filter = "cubic"
-- }

function lovr.draw(pass)
    pass:setFaceCull("back")

    pass:setMaterial(tex)
    pass:setShader(shader)
    -- pass:setSampler(sampler)
    pass:draw(mesh, 0, 0, -2)

    pass:setShader()
    pass:setColor(0, 0, 0, 1)
    pass:text(taskOutput, -1, 1.5, -3, 0.1)

    -----
    -- Uncomment the next section to see a 2d overview of the lightmap.
    -----

    -- local width, height = lovr.system.getWindowDimensions()
    -- pass:setShader()
    -- pass:setFaceCull("none")
    -- pass:setViewport(0, 0, width / 1, height / 1)
    -- pass:setColor(1, 1, 1, 1)
    -- pass:fill(tex)

    return false
end

function lovr.quit()
    -- Wait for the scheduler thread to finish.
    scheduler:wait()
    return false
end
