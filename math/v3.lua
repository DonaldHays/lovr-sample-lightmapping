local lovr = {
    system = require "lovr.system",
}

--- @class v3
--- @field x number
--- @field y number
--- @field z number
--- @operator add(v3): v3
--- @operator add(number): v3
--- @operator sub(v3): v3
--- @operator sub(number): v3
--- @operator mul(v3): v3
--- @operator mul(number): v3
--- @operator div(v3): v3
--- @operator div(number): v3
local v3 = {}
local v3meta = {}
v3meta.__index = v3

--- @param x number
--- @param y number
--- @param z number
--- @return v3
local new = function(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, v3meta)
end

if lovr.system.getOS() ~= "macOS" then
    local ffi = require "ffi"

    ffi.cdef [[
        typedef struct { double x, y, z; } v3_t;
    ]]
    local cons = ffi.typeof("v3_t")

    new = function(x, y, z)
        return cons(x, y, z) --[[@as v3]]
    end

    ffi.metatype(cons, v3meta)
end

--- @return number
function v3:length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

--- @return v3
function v3:normalize()
    return self / self:length()
end

--- @param u v3
--- @return number
function v3:distance(u)
    return (self - u):length()
end

--- @param u v3
--- @return v3
function v3:cross(u)
    return new(
        self.y * u.z - self.z * u.y,
        self.z * u.x - self.x * u.z,
        self.x * u.y - self.y * u.x
    )
end

--- @param u v3
--- @return number
function v3:dot(u)
    return self.x * u.x + self.y * u.y + self.z * u.z
end

--- @return number x
--- @return number y
--- @return number z
function v3:unpack()
    return self.x, self.y, self.z
end

--- @param a v3
--- @param b v3|number
--- @return v3
function v3meta.__add(a, b)
    if type(b) == "number" then
        return new(a.x + b, a.y + b, a.z + b)
    else
        return new(a.x + b.x, a.y + b.y, a.z + b.z)
    end
end

--- @param a v3
--- @param b v3|number
--- @return v3
function v3meta.__sub(a, b)
    if type(b) == "number" then
        return new(a.x - b, a.y - b, a.z - b)
    else
        return new(a.x - b.x, a.y - b.y, a.z - b.z)
    end
end

--- @param a v3
--- @param b v3|number
--- @return v3
function v3meta.__mul(a, b)
    if type(b) == "number" then
        return new(a.x * b, a.y * b, a.z * b)
    else
        return new(a.x * b.x, a.y * b.y, a.z * b.z)
    end
end

--- @param a v3
--- @param b v3|number
--- @return v3
function v3meta.__div(a, b)
    if type(b) == "number" then
        return new(a.x / b, a.y / b, a.z / b)
    else
        return new(a.x / b.x, a.y / b.y, a.z / b.z)
    end
end

function v3meta.__tostring(a)
    return string.format("{x = %g, y = %g, z = %g}", a.x, a.y, a.z)
end

return new
