local S = core.get_translator("digiscreen")

digiscreen = {}

core.register_async_dofile(core.get_modpath("digiscreen") .. "/async.lua")

local handle_async = core.handle_async

function digiscreen.split_and_render_multi_callback(resp)
    for _, data in ipairs(resp) do
        local pos = data.pos
        local bincolors = data.bincolors
        local encoded = data.encoded

        local node = core.get_node(pos)
        if core.get_item_group(node.name, "digiscreen") == 0 then return end

        local meta = core.get_meta(pos)
        meta:set_string("data", "")
        meta:set_string("bincolors", bincolors)
        meta:set_string("texture", "[png:" .. encoded)
        meta:mark_as_private({ "data", "bincolors", "texture" })

        digiscreen.update_display(pos)
        core.get_node_timer(pos):start(5)
    end
end

function digiscreen.recompress_callback(pos, encoded)
    if type(pos) == "boolean" then return end

    local node = core.get_node(pos)
    if core.get_item_group(node.name, "digiscreen") == 0 then return end

    local meta = core.get_meta(pos)
    meta:set_string("data", "")
    meta:set_string("bincolors", "")
    meta:set_string("texture", "[png:" .. encoded)
    meta:mark_as_private({ "data", "texture" })

    digiscreen.update_display(pos)
end

function digiscreen.update_display(pos)
    local obj

    do
        local objs = core.get_objects_inside_radius(pos, 0.5)
        for _, i in ipairs(objs) do
            if i:get_luaentity() and i:get_luaentity().name == "digiscreen:image" then
                if obj then
                    i:remove()
                else
                    obj = i
                end
            end
        end
    end

    local meta = core.get_meta(pos)
    local texture = meta:get_string("texture")
    if texture == "" then
        local oldData = meta:get_string("data")
        if oldData ~= "" then
            oldData = core.deserialize(oldData)
            if not oldData then return end
            handle_async(
                function(bitmap, defs, size) return digiscreen.split_and_render_multi(bitmap, defs, size) end,
                digiscreen.split_and_render_multi_callback,
                oldData,
                { { pos = pos } },
                16
            )
            return
        end
    end

    if not obj then
        obj = core.add_entity(pos, "digiscreen:image")
    end

    local fdir = core.facedir_to_dir(core.get_node(pos).param2)
    obj:set_properties({ textures = { texture } })
    obj:set_yaw((fdir.x ~= 0) and math.pi / 2 or 0)
    obj:set_pos(vector.add(pos, vector.multiply(fdir, 0.39)))
end

function digiscreen.on_construct(pos, size)
    if (not size) or size < 1 then size = 16 end

    local meta = core.get_meta(pos)
    meta:set_string("formspec", "field[channel;Channel;${channel}]")

    local disp = {}
    for y = 1, size, 1 do
        disp[y] = {}
        for x = 1, size, 1 do
            disp[y][x] = 0
        end
    end
    meta:set_string("data", core.serialize(disp))
    meta:mark_as_private("data")
    meta:set_int("size", size)
    digiscreen.update_display(pos)
end

function digiscreen.on_destruct(pos)
    local objs = core.get_objects_inside_radius(pos, 0.5)
    for _, i in ipairs(objs) do
        if i:get_luaentity() and i:get_luaentity().name == "digiscreen:image" then
            i:remove()
        end
    end
end

function digiscreen.on_receive_fields(pos, _, fields, sender)
    local name = sender:get_player_name()
    if not fields.channel then return end
    if core.is_protected(pos, name) and not core.check_player_privs(name, "protection_bypass") then
        core.record_protection_violation(pos, name)
        return
    end
    local meta = core.get_meta(pos)
    meta:set_string("channel", fields.channel)
end

function digiscreen.on_punch(screenpos, _, player)
    local meta = core.get_meta(screenpos)
    local size = meta:get_int("size")
    if (not size) or size < 1 then size = 16 end
    if player and not player.is_fake_player then
        local eyepos = vector.add(player:get_pos(), vector.add(player:get_eye_offset(), vector.new(0, 1.5, 0)))
        local lookdir = player:get_look_dir()
        local distance = vector.distance(eyepos, screenpos)
        local endpos = vector.add(eyepos, vector.multiply(lookdir, distance + 1))
        local ray = core.raycast(eyepos, endpos, true, false)
        local pointed, screen, hitpos
        repeat
            pointed = ray:next()
            if pointed and pointed.type == "node" then
                local node = core.get_node(pointed.under)
                if node.name == "digiscreen:digiscreen" or node.name == "digiscreen:digiscreen_big" then
                    screen = pointed.under
                    hitpos = vector.subtract(pointed.intersection_point, screen)
                end
            end
        until screen or not pointed
        if not hitpos then return end
        local facedir = core.facedir_to_dir(core.get_node(screen).param2)
        if facedir.x > 0 then
            hitpos.x = -1 * hitpos.z
        elseif facedir.x < 0 then
            hitpos.x = hitpos.z
        elseif facedir.z < 0 then
            hitpos.x = -1 * hitpos.x
        end
        hitpos.y = -1 * hitpos.y
        local hitpixel = {}
        hitpixel.x = math.floor((hitpos.x + 0.5) * size + 0.5) + 1
        hitpixel.y = math.floor((hitpos.y + 0.5) * size + 0.5) + 1
        if hitpixel.x < 1 or hitpixel.x > size or hitpixel.y < 1 or hitpixel.y > size then return end
        local message = {
            x = hitpixel.x,
            y = hitpixel.y,
            player = player:get_player_name(),
        }
        digilines.receptor_send(screenpos, digilines.rules.default, meta:get_string("channel"), message)
    end
end

function digiscreen.on_timer(pos)
    local meta = core.get_meta(pos)
    local bincolors = meta:get_string("bincolors")
    local size = meta:get_int("size")
    if (not size) or size < 1 then size = 16 end
    if string.len(bincolors) > 0 then
        handle_async(
            function(pos, bincolors, size) return digiscreen.recompress(pos, bincolors, size) end,
            digiscreen.recompress_callback,
            pos,
            bincolors,
            size
        )
    end
end

function digiscreen.on_digilines(pos, node, channel, msg)
    local meta = core.get_meta(pos)
    local setchan = meta:get_string("channel")
    if type(msg) ~= "table" or type(msg[1]) ~= "table" or setchan ~= channel then return end

    local size = meta:get_int("size")
    if (not size) or size < 1 then size = 16 end

    local back_dir = core.facedir_to_dir(node.param2)
    local right = vector.rotate(back_dir, { x = 0, y = -math.pi / 2, z = 0 })

    local name = node.name
    local bitmap_h = #msg
    local bitmap_w = #msg[1]
    local count_h = math.ceil(bitmap_h / size)
    local count_w = math.ceil(bitmap_w / size)
    local specs = {}

    for y = 1, count_h do
        local row_first_pos = vector.new(pos.x, pos.y + y - 1, pos.z)
        local row_first_node = core.get_node(row_first_pos)
        if row_first_node.name ~= name then break end
        specs[#specs + 1] = {
            pos = row_first_pos,
            offset_x = 0,
            offset_y = size * (y - 1),
        }

        for x = 2, count_w do
            local new_pos = vector.add(row_first_pos, vector.multiply(right, x - 1))
            local new_node = core.get_node(new_pos)
            if new_node.name ~= name then break end
            specs[#specs + 1] = {
                pos = new_pos,
                offset_x = size * (x - 1),
                offset_y = size * (y - 1),
            }
        end
    end

    handle_async(
        function(bitmap, defs, size) return digiscreen.split_and_render_multi(bitmap, defs, size) end,
        digiscreen.split_and_render_multi_callback,
        msg,
        specs,
        size
    )
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

    handle_async = function(...)
        tracy.ZoneBeginN("(digiscreen) core.handle_async")
        local results = { core.handle_async(...) }
        tracy.ZoneEnd()
        return unpack(results)
    end
end

core.register_entity("digiscreen:image", {
    initial_properties = {
        visual = "upright_sprite",
        physical = false,
        collisionbox = { 0, 0, 0, 0, 0, 0, },
        textures = { "digiscreen_pixel.png", },
        glow = 14,
        shaded = true,
        static_save = false,
    },
})

core.register_node("digiscreen:digiscreen", {
    description = S("Digilines Graphical Display"),
    tiles = { "digiscreen_pixel.png", },
    groups = { cracky = 3, digiscreen = 1, },
    paramtype = "light",
    paramtype2 = "facedir",
    on_rotate = core.global_exists("screwdriver") and screwdriver.rotate_simple,
    drawtype = "nodebox",
    node_box = {
        type = "fixed",
        fixed = { -0.5, -0.5, 0.4, 0.5, 0.5, 0.5 },
    },
    _digistuff_channelcopier_fieldname = "channel",
    light_source = 10,
    on_construct = digiscreen.on_construct,
    on_destruct = digiscreen.on_destruct,
    on_receive_fields = digiscreen.on_receive_fields,
    on_punch = digiscreen.on_punch,
    on_timer = digiscreen.on_timer,
    digiline = {
        wire = {
            rules = digilines.rules.default,
        },
        effector = {
            action = digiscreen.on_digilines,
        },
    },
})

core.register_node("digiscreen:digiscreen_big", {
    description = S("High-Resolution Digilines Graphical Display"),
    tiles = { "digiscreen_pixel.png", },
    groups = { cracky = 3, digiscreen = 1, },
    paramtype = "light",
    paramtype2 = "facedir",
    on_rotate = core.global_exists("screwdriver") and screwdriver.rotate_simple,
    drawtype = "nodebox",
    node_box = {
        type = "fixed",
        fixed = { -0.5, -0.5, 0.4, 0.5, 0.5, 0.5 },
    },
    _digistuff_channelcopier_fieldname = "channel",
    light_source = 10,
    on_construct = function(pos) digiscreen.on_construct(pos, 64) end,
    on_destruct = digiscreen.on_destruct,
    on_receive_fields = digiscreen.on_receive_fields,
    on_punch = digiscreen.on_punch,
    on_timer = digiscreen.on_timer,
    digiline = {
        wire = {
            rules = digilines.rules.default,
        },
        effector = {
            action = digiscreen.on_digilines,
        },
    },
})

core.register_lbm({
    name = "digiscreen:respawn",
    label = "Respawn/upgrade digiscreen entities",
    nodenames = { "group:digiscreen", },
    run_at_every_load = true,
    action = digiscreen.update_display,
})

local luacontroller = "mesecons_luacontroller:luacontroller0000"
local rgblightstone = "rgblightstone:rgblightstone_truecolor_0"

core.register_craft({
    output = "digiscreen:digiscreen",
    recipe = {
        { luacontroller, rgblightstone, rgblightstone, },
        { rgblightstone, rgblightstone, rgblightstone, },
        { rgblightstone, rgblightstone, rgblightstone, },
    },
})

core.register_craft({
    output = "digiscreen:digiscreen_big",
    recipe = {
        { "digiscreen:digiscreen", "digiscreen:digiscreen", },
        { "digiscreen:digiscreen", "digiscreen:digiscreen", },
    },
})