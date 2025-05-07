local v2 = require "math.v2"

--- An internal type to assist assigning coordinates to faces.
---
--- We'll divide the UV map up into "rows", and then the faces will be placed
--- within the rows. Every row is the full width of the UV texture (and thus the
--- width is not stored), while the height is variable per row. The `x` and `y`
--- fields track where the next faces for this row will be positioned. The `x`
--- field will advance as faces are assigned.
---
--- Before placing the faces, we'll sort them by height, from tallest to
--- shortest. Since faces will only get shorter as we place them, we can
--- guarantee that all existing rows have enough vertical room to hold all
--- unassigned faces.
--- @class UVRow
--- @field x number
--- @field y number
--- @field height number

--- @class UVPair
--- @field margin number
--- @field topLeft v2
--- @field bottomRight v2

--- @class UVMap
--- @field size number
--- @field coords table<GeoFace, UVPair>

--- Returns `faces` sorted from tallest to shortest vertically.
--- @param faces GeoFace[]
--- @return GeoFace[]
local function sortedFaces(faces)
    local output = {}

    -- Perform a shallow copy.
    for _, face in ipairs(faces) do
        table.insert(output, face)
    end

    -- Sort faces from tallest height to shortest.

    --- @param a GeoFace
    --- @param b GeoFace
    table.sort(output, function(a, b)
        return a.up:length() > b.up:length()
    end)

    return output
end

--- @param sorted GeoFace[]
--- @param size number
--- @param quality Quality
local function attemptLayout(sorted, size, quality)
    local tpm = quality.texelsPerMeter
    local margin = 4 -- texels of padding surrounding each face

    --- @type UVMap
    local output = { size = size, coords = {} }

    --- @type UVRow[]
    local rows = {}

    for _, face in ipairs(sorted) do
        local faceWidth = face.right:length() * tpm * 2
        local faceHeight = face.up:length() * tpm * 2

        local cellWidth = math.ceil(faceWidth + margin * 2)
        local cellHeight = math.ceil(faceHeight + margin * 2)

        -- Attempt to find a place for this face in the existing rows.
        local x, y = 0, 0
        local foundRow = false
        for i = 1, #rows do
            local row = rows[i]
            -- Because the faces are sorted by height, all existing rows are
            -- guaranteed to hold all future faces vertically, so we only need
            -- to check if there's room in the row horizontally.
            if row.x + cellWidth <= size then
                x = row.x
                y = row.y
                row.x = row.x + cellWidth
                foundRow = true
                break
            elseif i == #rows then
                -- If we're out of rows, we'll be making a new one, so set `y`
                -- to the appropriate starting point.
                y = row.y + row.height
            end
        end

        -- If there was no row that fits the face, create a new one.
        if foundRow == false then
            -- Catch overflow.
            if y + cellHeight > size then
                return nil
            end

            -- We already have the `x` and `y` for this face, so prepare the row
            -- for the next face by initializing the row's `x` to `cellWidth`.
            table.insert(rows,
                { x = cellWidth, y = y, height = cellHeight }
            )
        end

        --- @type UVPair
        local uv = {
            margin = margin,
            topLeft = v2(x + margin, y + margin),
            bottomRight = v2(x + margin + faceWidth, y + margin + faceHeight)
        }

        output.coords[face] = uv
    end

    return output
end

--- @param faces GeoFace[]
--- @param quality Quality
--- @return UVMap
return function(faces, quality)
    local sorted = sortedFaces(faces)

    -- We're going to start by trying to create a 64px texture. If that's too
    -- small, we'll iteratively double the size.
    local size = 64
    while true do
        local output = attemptLayout(sorted, size, quality)
        if output ~= nil then
            return output
        end
        if size == 4096 then
            error("Max tex size reached")
        end
        size = size * 2
    end
end
