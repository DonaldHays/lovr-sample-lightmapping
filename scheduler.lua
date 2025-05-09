require 'lovr.filesystem'
local utils = require 'utils'

local lovr = {
    thread = require "lovr.thread",
    system = require "lovr.system",
    data = require "lovr.data",
    timer = require "lovr.timer",
}

if lovr.system.getOS() == "macOS" then
    jit.off()
end

local gf = require "geoface"
local uvmapper = require "uvmapper"

-- The scheduler manages the lightmap process. It spawns a collection of worker
-- threads. The worker threads wait on a job channel. The scheduler creates jobs
-- and pushes them on the job channel. Jobs are created in batches for each
-- pass. After dispatching the jobs, the scheduler waits for responses from the
-- workers. After all the jobs for a pass are completed, the scheduler sends an
-- update to the main thread over the result channel, and then repeats the whole
-- process for the next pass.

--- @type Quality
local quality = ...

-- Spawn the worker threads. We spawn one fewer than the number of CPU cores to
-- try to avoid contention with the main thread.

--- @type Thread[]
local workers = {}
local threadCount = math.max(1, lovr.system.getCoreCount() - 1)
for threadID = 1, threadCount do
    local worker = lovr.thread.newThread("worker.lua")
    table.insert(workers, worker)
    worker:start(threadID, quality)
end

-- The job channel is used to send jobs to the workers. The job done channel is
-- used to receive results from the workers. The result channel is used to
-- inform the main thread about progress.
local jobChannel = lovr.thread.getChannel("jobs")        --- @type Channel
local jobDoneChannel = lovr.thread.getChannel("jobDone") --- @type Channel
local resultChannel = lovr.thread.getChannel("result")   --- @type Channel

-- Tell the main thread how many threads we're using.
resultChannel:push({ stat = "Threads: " .. threadCount })

gf.load()
local uvmap = uvmapper(gf.faces, quality)

local function formatTime(start)
    return ("%.2fms"):format((lovr.timer.getTime() - start) * 1000)
end

--- Blocks the scheduler thread until `count` responses have come back from the
--- job done channel. When `count` equals the number of jobs sent to the job
--- channel, this is effectively a block until the workers complete.
--- @param count number
local function waitJobs(count)
    for _ = 1, count do
        -- We wait forever for a job, but the API is typed to take a `number?`.
        -- So jump through a little hoop to make the type checker happy.
        local wait = true --- @type any
        jobDoneChannel:pop(wait)
    end
end

-- Since we use random sampling in the bounce light passes, we want to denoise
-- the result. The denoiser performs a gaussian blur, limited by an edge
-- preservation term. The `gweight` (gaussian) and `iweight` (intensity) terms
-- can be tuned by adjusting the `sigma` local variables within in each.

local function gaussian(sigma, x, y)
    local d = 2 * math.pi * sigma * sigma
    local e = -(x * x + y * y) / (2 * sigma * sigma)
    return (1 / d) * math.exp(e)
end

local gweightCache = {}
local function gweight(x, y)
    if gweightCache[y] == nil then
        gweightCache[y] = {}
    end

    local yCache = gweightCache[y]

    local cached = yCache[x]
    if cached == nil then
        -- In gweight, sigma controls blur distance. Lower values are noisier,
        -- higher values are blurrier.
        local sigma = 2.5
        local v = gaussian(sigma, x, y)
        yCache[x] = v
        return v
    else
        return cached
    end
end

local function iweight(r1, g1, b1, r2, g2, b2)
    -- In iweight, sigma controls edge preservation. Lower values better
    -- preserve sharp edges, but remove less noise. Higher values remove more
    -- noise, but blur edges.
    local sigma = 0.5

    local n = (r1 - r2) * (r1 - r2) +
        (g1 - g2) * (g1 - g2) +
        (b1 - b2) * (b1 - b2)
    local w = math.exp(-n / (2 * sigma * sigma))
    return w
end

--- Returns a denoised version of `img`.
--- @param img Image
--- @return Image
local function denoised(img)
    local w, h = img:getDimensions()
    local out = lovr.data.newImage(w, h, "rgba32f")

    out:mapPixel(function(x, y)
        local r, g, b = 0, 0, 0
        local sum = 0

        local ir, ig, ib = img:getPixel(x, y)

        for sy = y - 4, y + 4 do
            for sx = x - 4, x + 4 do
                if sy >= 0 and sy < h and sx >= 0 and sx < w then
                    local br, bg, bb = img:getPixel(sx, sy)

                    local weight = iweight(ir, ig, ib, br, bg, bb)
                    weight = weight * gweight(sx - x, sy - y)

                    r = r + (br * weight)
                    g = g + (bg * weight)
                    b = b + (bb * weight)
                    sum = sum + weight
                end
            end
        end

        return r / sum, g / sum, b / sum, 1
    end)

    return out
end

--- Returns the sum of `src` and `dst`.
--- @param src Image
--- @param dst Image
--- @return Image
local function added(src, dst)
    local w, h = src:getDimensions()
    local out = lovr.data.newImage(w, h, "rgba32f")

    out:mapPixel(function(x, y)
        local rs, gs, bs = src:getPixel(x, y)
        local rd, gd, bd = dst:getPixel(x, y)

        return rs + rd, gs + gd, bs + bd, 1
    end)
    return out
end

-- Generate the initial image.

local img = lovr.data.newImage(uvmap.size, uvmap.size, "rgba32f")
img:mapPixel(function(x, y, _, _, _, _)
    return x / uvmap.size, y / uvmap.size, math.random(), 1
end)

-- The passes work by creating one job for each face in the GeoFace data. Some
-- jobs will be heavier than others by having larger faces, but if you have more
-- faces than CPU cores, the task load will roughly balance out, because cores
-- that grab smaller faces will process more jobs.

-- Direct light pass
print("direct async")
local start = lovr.timer.getTime()
-- For this sample, we're just hard-coding a single light position. Its
-- intensity and color are determined in the direct job. A good future expansion
-- could parameterize lights more, supporting multiple lights with varying
-- properties.
local lightPos = { -0.7, 2, -1.5 }
for i = 1, #gf.faces do
    --- @type DirectJob
    local job = {
        kind = "direct", faceIndex = i, lightPos = lightPos, image = img
    }
    jobChannel:push(job)
end

waitJobs(#gf.faces)
resultChannel:push({
    img = utils.finalizeImage(img),
    stat = "Direct: " .. formatTime(start)
})

-- Bounce Passes

-- We introduce a few variables for the bounce passes: a bounce source, image,
-- and accumulator. The bounce source represents the emmisive data that a bounce
-- pass will sample from. Initially, it's the result of the direct pass. In
-- later passes, it will be the result of the previous pass. The bounce image is
-- the result of the current bounce pass. The bounce accumulator is the sum of
-- the bounce images. The accumulator will later be added to the direct pass,
-- but we initially store it separately so that we can denoise it without
-- touching the direct light data.

local bounceSrc = img
local bounceImg = lovr.data.newImage(uvmap.size, uvmap.size, "rgba32f")
local bounceAcc = lovr.data.newImage(uvmap.size, uvmap.size, "rgba32f")
bounceAcc:mapPixel(function(x, y, r, g, b, a)
    return 0, 0, 0, 1
end)
for bounceIdx = 1, quality.bouncePassCount do
    print("bounce async", bounceIdx)
    start = lovr.timer.getTime()
    -- Fill `bounceImg` by sampling from `bounceSrc`
    for i = 1, #gf.faces do
        --- @type BounceJob
        local job = {
            kind = "bounce",
            faceIndex = i,
            srcImage = bounceSrc,
            dstImage = bounceImg
        }
        jobChannel:push(job)
    end

    waitJobs(#gf.faces)

    -- Add `bounceImg` to `bounceAcc`
    bounceAcc = added(bounceAcc, bounceImg)

    -- Send a noisy preview. Since we're still storing the direct pass
    -- separately from the accumulator, add them in a temporary image first.
    resultChannel:push({
        img = utils.finalizeImage(added(img, bounceAcc)),
        stat = "Bounce " .. bounceIdx .. ": " .. formatTime(start)
    })

    -- Move `bounceImg` into `bounceSrc` for the next image pass, and create a
    -- new `bounceImg`.
    if bounceIdx ~= quality.bouncePassCount then
        bounceSrc = bounceImg
        bounceImg = lovr.data.newImage(uvmap.size, uvmap.size, "rgba32f")
        bounceImg:mapPixel(function(x, y, r, g, b, a)
            return 0, 0, 0, 1
        end)
    end
end

-- Finalize bounce by denoising the accumulator, then committing it on top of
-- the direct lighting data.
bounceAcc = denoised(bounceAcc)
img = added(img, bounceAcc)

-- AO Pass
print("ao async")
start = lovr.timer.getTime()
for i = 1, #gf.faces do
    --- @type AOJob
    local job = {
        kind = "ao", faceIndex = i, image = img
    }
    jobChannel:push(job)
end

waitJobs(#gf.faces)

resultChannel:push({
    img = utils.finalizeImage(img),
    stat = "AO: " .. formatTime(start)
})

-- Tell the workers to quit.
for i = 1, threadCount do
    --- @type QuitJob
    local job = { kind = "quit", faceIndex = i }
    jobChannel:push(job)
end

-- Wait for the workers to quit.
for _, worker in ipairs(workers) do
    -- TODO: I appear to get crashes on Quest when this next line is uncommented
    -- worker:wait()
end
