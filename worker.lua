require 'lovr.filesystem'

local lovr = {
    thread = require "lovr.thread",
    system = require "lovr.system",
    data = require "lovr.data",
    math = require "lovr.math",
    timer = require "lovr.timer",
}

if lovr.system.getOS() == "macOS" then
    jit.off()
end

local gf = require "geoface"
local uvmapper = require "uvmapper"
local v3 = require "math.v3"
local tasks = require "tasks"

--- @type number, Quality
local threadID, quality = ...

gf.load()
local uvmap = uvmapper(gf.faces, quality)

--- @type TaskContext
local ctx = { faces = gf.faces, uvmap = uvmap, quality = quality }

--- @class JobShared
--- @field faceIndex number

--- @class DirectJob: JobShared
--- @field kind "direct"
--- @field lightPos number[]
--- @field image Image

--- @class BounceJob: JobShared
--- @field kind "bounce"
--- @field srcImage Image
--- @field dstImage Image

--- @class AOJob: JobShared
--- @field kind "ao"
--- @field image Image

--- @class QuitJob: JobShared
--- @field kind "quit"

--- @alias Job DirectJob | BounceJob | AOJob | QuitJob

-- A worker thread receives jobs on the job channel, and sends responses on the
-- job done channel. It runs an infinite loop where it waits until it can
-- dequeue a job, runs the job, and then repeats.

local jobChannel = lovr.thread.getChannel("jobs")        --- @type Channel
local jobDoneChannel = lovr.thread.getChannel("jobDone") --- @type Channel

local running = true
while running do
    -- We wait forever for a job, but the API is typed to take a `number?`. So
    -- jump through a little hoop to make the type checker happy.
    local wait = true --- @type any
    local job = jobChannel:pop(wait) --[[@as Job]]

    if job.kind == "direct" then
        local lightPos = v3(job.lightPos[1], job.lightPos[2], job.lightPos[3])
        tasks.direct(job.faceIndex, lightPos, ctx, job.image)
    elseif job.kind == "bounce" then
        tasks.bounce(job.faceIndex, ctx, job.srcImage, job.dstImage)
    elseif job.kind == "ao" then
        tasks.ao(job.faceIndex, ctx, job.image)
    elseif job.kind == "quit" then
        running = false
    end
    jobDoneChannel:push("done")
end
