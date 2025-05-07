local lovr = {
    system = require "lovr.system",
}

--- @class v2
--- @field x number
--- @field y number
--- @operator add(v2): v2
--- @operator add(number): v2
--- @operator sub(v2): v2
--- @operator sub(number): v2
--- @operator mul(v2): v2
--- @operator mul(number): v2
--- @operator div(v2): v2
--- @operator div(number): v2
local v2 = {}
local v2meta = {}
v2meta.__index = v2

--- @param x number
--- @param y number
--- @return v2
local new = function(x, y)
    return setmetatable({ x = x, y = y }, v2meta)
end

if lovr.system.getOS() ~= "macOS" then
    local ffi = require "ffi"

    ffi.cdef [[
        typedef struct { double x, y; } v2_t;
    ]]
    local cons = ffi.typeof("v2_t")

    new = function(x, y)
        return cons(x, y) --[[@as v2]]
    end

    ffi.metatype(cons, v2meta)
end

--- @return number
function v2:length()
    return math.sqrt(self.x * self.x + self.y * self.y)
end

--- @param a v2
--- @param b v2|number
--- @return v2
function v2meta.__add(a, b)
    if type(b) == "number" then
        return new(a.x + b, a.y + b)
    else
        return new(a.x + b.x, a.y + b.y)
    end
end

--- @param a v2
--- @param b v2|number
--- @return v2
function v2meta.__sub(a, b)
    if type(b) == "number" then
        return new(a.x - b, a.y - b)
    else
        return new(a.x - b.x, a.y - b.y)
    end
end

--- @param a v2
--- @param b v2|number
--- @return v2
function v2meta.__mul(a, b)
    if type(b) == "number" then
        return new(a.x * b, a.y * b)
    else
        return new(a.x * b.x, a.y * b.y)
    end
end

--- @param a v2
--- @param b v2|number
--- @return v2
function v2meta.__div(a, b)
    if type(b) == "number" then
        return new(a.x / b, a.y / b)
    else
        return new(a.x / b.x, a.y / b.y)
    end
end

function v2meta.__tostring(a)
    return string.format("{x = %g, y = %g}", a.x, a.y)
end

return new
