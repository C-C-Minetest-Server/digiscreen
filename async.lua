local digiscreen = {}
_G.digiscreen = digiscreen

local type, ipairs = type, ipairs
local s_len, s_byte, t_concat, m_floor = string.len, string.byte, table.concat, math.floor
local b_lshift, b_bor = bit.lshift, bit.bor
local color_to_bytes = core.colorspec_to_bytes
local enc_b64, enc_png = core.encode_base64, core.encode_png

local function render_from_string(bitmap, offset_x, offset_y, size)
    local w_hi, w_lo, h_hi, h_lo = s_byte(bitmap, 9, 12)
    local total_w = b_bor(b_lshift(w_hi or 0, 8), w_lo or 0)
    local total_h = b_bor(b_lshift(h_hi or 0, 8), h_lo or 0)

    local bincolors = {}
    local count = 1

    for y = 1 + offset_y, size + offset_y do
        for x = 1 + offset_x, size + offset_x do
            local bit_value = 0
            
            -- Boundary check
            if y >= 1 and y <= total_h and x >= 1 and x <= total_w then
                local ptr = 13 + ((y - 1) * total_w + (x - 1)) * 3
                local r, g, b = s_byte(bitmap, ptr, ptr + 2)
                bit_value = b_bor(b_lshift(r or 0, 16), b_lshift(g or 0, 8), b or 0)
            end
            
            bincolors[count] = color_to_bytes(0xFF000000 + bit_value)
            count = count + 1
        end
    end
    return t_concat(bincolors)
end

local function render_from_table(bitmap, offset_x, offset_y, size)
    local bincolors = {}

    for y = 1 + offset_y, size + offset_y, 1 do
        for x = 1 + offset_x, size + offset_x, 1 do
            local bit_value = bitmap[y] and bitmap[y][x]
            if type(bit_value) == "number" then
                if bit_value < 0 or bit_value > 0xFFFFFF or m_floor(bit_value) ~= bit_value then
                    bit_value = 0
                end
            else
                bit_value = 0
            end
            bincolors[#bincolors+1] = color_to_bytes(0xFF000000 + bit_value)
        end
    end

    return t_concat(bincolors, "")
end

function digiscreen.render_single(bitmap, offset_x, offset_y, size)
    if type(bitmap) == "string" then
        return render_from_string(bitmap, offset_x, offset_y, size)
    else
        return render_from_table(bitmap, offset_x, offset_y, size)
    end
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
            encoded = enc_b64(enc_png(size, size, bincolors, 1))
        }
    end

    return resp
end

function digiscreen.recompress(pos, bincolors, size)
    if (not size) or size < 1 then size = 16 end
    if s_len(bincolors) ~= (size ^ 2) * 4 then return false end
    return pos, enc_b64(enc_png(size, size, bincolors, 9))
end

if _G.tracy then
    local tracy, unpack = _G.tracy, unpack
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