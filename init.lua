digiscreen = {}

function digiscreen.removeEntity(pos)
	local entitiesNearby = core.get_objects_inside_radius(pos,0.5)
	for _,i in pairs(entitiesNearby) do
		if i:get_luaentity() and i:get_luaentity().name == "digiscreen:image" then
			i:remove()
		end
	end
end

function digiscreen.processDigilinesMessage(pos,msg,size)
	if (not size) or size < 1 then size = 16 end
	local offset_x = msg.offset_x or 0
	local offset_y = msg.offset_y or 0
	local bincolors = ""
	for y=1 + offset_y,size + offset_y,1 do
		if type(msg[y]) ~= "table" then msg[y] = {} end
		for x=1 + offset_x,size + offset_x,1 do
			local bit_value = msg[y][x] or 0
			local bit_type = type(bit_value)
			if bit_type == "string" then
				if string.len(bit_value) == 7 and string.sub(bit_value,1,1) == "#" then
					bit_value = string.sub(bit_value, 2, -1)
				end

				bit_value = tonumber(bit_value,16) or 0
			elseif bit_type == "number" then
				if bit_value < 0 or bit_value > 0xFFFFFF or math.floor(bit_value) ~= bit_value then
					bit_value = 0
				end
			end

			bincolors = bincolors..core.colorspec_to_bytes(0xFF000000 + bit_value)
		end
	end
	local img = core.encode_png(size,size,bincolors,1)
	return pos,"[png:"..core.encode_base64(img),bincolors
end

function digiscreen.updateDisplay(pos)
	digiscreen.removeEntity(pos)
	local meta = core.get_meta(pos)
	local texture = meta:get_string("texture")
	if (not texture) or texture == "" then
		local oldData = meta:get_string("data")
		if oldData and string.len(oldData) > 1 then
			oldData = core.deserialize(oldData)
			if not oldData then return end
			core.handle_async(digiscreen.processDigilinesMessage,digiscreen.asyncDone,pos,oldData)
			return
		end
	end
	local entity = core.add_entity(pos,"digiscreen:image")
	local fdir = core.facedir_to_dir(core.get_node(pos).param2)
	entity:set_properties({textures={texture}})
	entity:set_yaw((fdir.x ~= 0) and math.pi/2 or 0)
	entity:set_pos(vector.add(pos,vector.multiply(fdir,0.39)))
end

function digiscreen.asyncDone(pos,texture,bincolors)
	local node = core.get_node(pos)
	if core.get_item_group(node.name,"digiscreen") ~= 1 then return end
	local meta = core.get_meta(pos)
	meta:set_string("data","")
	meta:set_string("bincolors",bincolors)
	meta:set_string("texture",texture)
	meta:mark_as_private({"data","bincolors","texture"})
	digiscreen.updateDisplay(pos)
	core.get_node_timer(pos):start(5)
end

function digiscreen.recompress(pos,bincolors,size)
	if (not size) or size < 1 then size = 16 end
	if string.len(bincolors) ~= (size^2)*4 then return false end
	local img = core.encode_png(size,size,bincolors,9)
	return true,pos,"[png:"..core.encode_base64(img)
end

function digiscreen.recompressDone(ok,pos,texture)
	if not ok then return end
	local node = core.get_node(pos)
	if core.get_item_group(node.name,"digiscreen") ~= 1 then return end
	local meta = core.get_meta(pos)
	meta:set_string("bincolors","")
	meta:set_string("texture",texture)
	meta:mark_as_private({"bincolors","texture"})
	digiscreen.updateDisplay(pos)
end

function digiscreen.on_construct(pos,size)
	if (not size) or size < 1 then size = 16 end
	local meta = core.get_meta(pos)
	meta:set_string("formspec","field[channel;Channel;${channel}]")
	local disp = {}
	for y=1,size,1 do
		disp[y] = {}
		for x=1,size,1 do
			disp[y][x] = "000000"
		end
	end
	meta:set_string("data",core.serialize(disp))
	meta:mark_as_private("data")
	meta:set_int("size",size)
	digiscreen.updateDisplay(pos)
end

function digiscreen.on_receive_fields(pos,_,fields,sender)
	local name = sender:get_player_name()
	if not fields.channel then return end
	if core.is_protected(pos,name) and not core.check_player_privs(name,"protection_bypass") then
		core.record_protection_violation(pos,name)
		return
	end
	local meta = core.get_meta(pos)
	meta:set_string("channel",fields.channel)
end

function digiscreen.on_punch(screenpos,_,player)
	local meta = core.get_meta(screenpos)
	local size = meta:get_int("size")
	if (not size) or size < 1 then size = 16 end
	if player and not player.is_fake_player then
		local eyepos = vector.add(player:get_pos(),vector.add(player:get_eye_offset(),vector.new(0,1.5,0)))
		local lookdir = player:get_look_dir()
		local distance = vector.distance(eyepos,screenpos)
		local endpos = vector.add(eyepos,vector.multiply(lookdir,distance+1))
		local ray = core.raycast(eyepos,endpos,true,false)
		local pointed,screen,hitpos
		repeat
			pointed = ray:next()
			if pointed and pointed.type == "node" then
				local node = core.get_node(pointed.under)
				if node.name == "digiscreen:digiscreen" or node.name == "digiscreen:digiscreen_big" then
					screen = pointed.under
					hitpos = vector.subtract(pointed.intersection_point,screen)
				end
			end
		until screen or not pointed
		if not hitpos then return end
		local facedir = core.facedir_to_dir(core.get_node(screen).param2)
		if facedir.x > 0 then
			hitpos.x = -1*hitpos.z
		elseif facedir.x < 0 then
			hitpos.x = hitpos.z
		elseif facedir.z < 0 then
			hitpos.x = -1*hitpos.x
		end
		hitpos.y = -1*hitpos.y
		local hitpixel = {}
		hitpixel.x = math.floor((hitpos.x+0.5)*size+0.5)+1
		hitpixel.y = math.floor((hitpos.y+0.5)*size+0.5)+1
		if hitpixel.x < 1 or hitpixel.x > size or hitpixel.y < 1 or hitpixel.y > size then return end
		local message = {
			x = hitpixel.x,
			y = hitpixel.y,
			player = player:get_player_name(),
		}
		digilines.receptor_send(screenpos,digilines.rules.default,meta:get_string("channel"),message)
	end
end

function digiscreen.on_timer(pos)
	local bincolors = core.get_meta(pos):get_string("bincolors")
	local size = core.get_meta(pos):get_int("size")
	if (not size) or size < 1 then size = 16 end
	if string.len(bincolors) > 0 then
		core.handle_async(digiscreen.recompress,digiscreen.recompressDone,pos,bincolors,size)
	end
end

function digiscreen.show_content(pos, content)
	local meta = core.get_meta(pos)
	local size = meta:get_int("size")
	if (not size) or size < 1 then size = 16 end

	core.handle_async(digiscreen.processDigilinesMessage,digiscreen.asyncDone,pos,content,size)
end

function digiscreen.on_digilines(pos,_,channel,msg)
	local meta = core.get_meta(pos)
	local setchan = meta:get_string("channel")
	if type(msg) ~= "table" or setchan ~= channel then return end

	if msg.batch then
		local node = core.get_node(pos)
		local back_dir = core.facedir_to_dir(node.param2)
		local right = vector.rotate(back_dir, {x = 0, y = -math.pi/2, z = 0})
		for offset_y, row in ipairs(msg) do
			for offset_x, sub_msg in ipairs(row) do
				if not sub_msg.batch then -- prevent infinite loops
					local new_pos = vector.add(pos, vector.multiply(right, offset_x - 1))
					new_pos.y = new_pos.y - offset_y + 1

					digiscreen.show_content(new_pos, sub_msg)
				end
			end
		end
		return
	end

	digiscreen.show_content(pos, msg)
end

core.register_entity("digiscreen:image",{
	initial_properties = {
		visual = "upright_sprite",
		physical = false,
		collisionbox = {0,0,0,0,0,0,},
		textures = {"digiscreen_pixel.png",},
		glow = 14,
		shaded = true,
		static_save = false,
	},
})

core.register_node("digiscreen:digiscreen",{
	description = "Digilines Graphical Display",
	tiles = {"digiscreen_pixel.png",},
	groups = {cracky = 3,digiscreen = 1,},
	paramtype = "light",
	paramtype2 = "facedir",
	on_rotate = core.global_exists("screwdriver") and screwdriver.rotate_simple,
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {-0.5,-0.5,0.4,0.5,0.5,0.5},
	},
	_digistuff_channelcopier_fieldname = "channel",
	light_source = 10,
	on_construct = digiscreen.on_construct,
	on_destruct = digiscreen.removeEntity,
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

core.register_node("digiscreen:digiscreen_big",{
	description = "High-Resolution Digilines Graphical Display",
	tiles = {"digiscreen_pixel.png",},
	groups = {cracky = 3,digiscreen = 1,},
	paramtype = "light",
	paramtype2 = "facedir",
	on_rotate = core.global_exists("screwdriver") and screwdriver.rotate_simple,
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {-0.5,-0.5,0.4,0.5,0.5,0.5},
	},
	_digistuff_channelcopier_fieldname = "channel",
	light_source = 10,
	on_construct = function(pos) digiscreen.on_construct(pos,64) end,
	on_destruct = digiscreen.removeEntity,
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
	nodenames = {"group:digiscreen",},
	run_at_every_load = true,
	action = digiscreen.updateDisplay,
})

local luacontroller = "mesecons_luacontroller:luacontroller0000"
local rgblightstone = "rgblightstone:rgblightstone_truecolor_0"

core.register_craft({
	output = "digiscreen:digiscreen",
	recipe = {
		{luacontroller,rgblightstone,rgblightstone,},
		{rgblightstone,rgblightstone,rgblightstone,},
		{rgblightstone,rgblightstone,rgblightstone,},
	},
})

core.register_craft({
	output = "digiscreen:digiscreen_big",
	recipe = {
		{"digiscreen:digiscreen","digiscreen:digiscreen",},
		{"digiscreen:digiscreen","digiscreen:digiscreen",},
	},
})
