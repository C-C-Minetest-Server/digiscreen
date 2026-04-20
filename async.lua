digiscreen = {}

function digiscreen.render_single(bitmap, offset_x, offset_y, size)
    if type(size) ~= "number" or size < 1 then size = 16 end
    offset_x = offset_x or 0
    offset_y = offset_y or 0

    local bincolors = {}

    for y = 1 + offset_y, size + offset_y, 1 do
        for x = 1 + offset_x, size + offset_x, 1 do
            local bit_value = bitmap[y] and bitmap[y][x]
            local bit_type = type(bit_value)
            if bit_type == "string" then
                if string.len(bit_value) == 7 and string.sub(bit_value, 1, 1) == "#" then
                    bit_value = string.sub(bit_value, 2, -1)
                end

                bit_value = tonumber(bit_value, 16) or 0
            elseif bit_type == "number" then
                if bit_value < 0 or bit_value > 0xFFFFFF or math.floor(bit_value) ~= bit_value then
                    bit_value = 0
                end
            else
                bit_value = 0
            end
            bincolors[#bincolors+1] = core.colorspec_to_bytes(0xFF000000 + bit_value)
        end
    end

    return table.concat(bincolors, "")
end

function digiscreen.split_and_render_multi(bitmap, defs, size)
    -- defs: pos = vector, offset_x, offset_y

    local resp = {}

    for _, data in ipairs(defs) do
        local bincolors = digiscreen.render_single(
            bitmap,
            data.offset_x,
            data.offset_y,
            size
        )
        resp[#resp + 1] = {
            pos = data.pos,
            bincolors = bincolors,
            encoded = core.encode_base64(core.encode_png(size, size, bincolors, 1))
        }
    end

    return resp
end

function digiscreen.recompress(pos, bincolors, size)
    if (not size) or size < 1 then size = 16 end
    if string.len(bincolors) ~= (size ^ 2) * 4 then return false end
    return pos, core.encode_png(size, size, bincolors, 9)
end

if _G.tracy then
    for name, func in pairs(digiscreen) do
        if type(func) == "function" then
            digiscreen[name] = function(...)
                tracy.ZoneBeginN("digiscreen." .. name)
                local results = { func(...) }
                tracy.ZoneEnd()
                return unpack(results)
            end
        end
    end
end