--- @param faces GeoFace[]
--- @param uvmap UVMap
--- @return Mesh
return function(faces, uvmap)
    local format = {
        { "VertexColor",    "vec4" },
        { "VertexPosition", "vec3" },
        { "VertexUV",       "vec2" },
    }

    local vertices = {}
    for _, face in ipairs(faces) do
        local uvCell = uvmap.coords[face]
        local uvtl = uvCell.topLeft / uvmap.size
        local uvbr = uvCell.bottomRight / uvmap.size

        local tl = face.origin + face.up - face.right
        local tr = face.origin + face.up + face.right
        local bl = face.origin - face.up - face.right
        local br = face.origin - face.up + face.right
        local r, g, b = face.color:unpack()

        local tlv = { r, g, b, 1, tl.x, tl.y, tl.z, uvtl.x, uvtl.y }
        local trv = { r, g, b, 1, tr.x, tr.y, tr.z, uvbr.x, uvtl.y }
        local blv = { r, g, b, 1, bl.x, bl.y, bl.z, uvtl.x, uvbr.y }
        local brv = { r, g, b, 1, br.x, br.y, br.z, uvbr.x, uvbr.y }

        table.insert(vertices, tlv)
        table.insert(vertices, blv)
        table.insert(vertices, trv)

        table.insert(vertices, trv)
        table.insert(vertices, blv)
        table.insert(vertices, brv)
    end

    return lovr.graphics.newMesh(format, vertices, "gpu")
end
