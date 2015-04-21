local lamp = {}

local util = require 'lib/util'
local zentropy = require 'lib/zentropy'
    		
function lamp.init(map, data, timeout)
    local enemy = map:get_entity('enemy')

	local doors = {}
	for dir, door_data in util.pairs_by_keys(data.doors) do
        assert((door_data.open or 'open') == 'open')
        local door = data.room:door({open='closed', name=door_data.name, room_events=data.room_events}, dir)
        table.insert(doors, door)
	end

    if enemy then
        zentropy.inject_enemy(enemy, data.rng:refine('enemy'))
    end

	local hidden_chest = nil

	if data.treasure1 then
		local x, y = map:get_entity('treasure_obstacle_chest'):get_position()
		x, y = x + 8, y + 13
		hidden_chest = map:create_chest{
            sprite="entities/chest",
            layer=1,
            x = x,
            y = y,
            treasure_name=data.treasure1.item_name,
            treasure_savegame_variable=data.treasure1.name,
        }
        if not hidden_chest:is_open() then
            hidden_chest:set_enabled(false)
        end
	else
		map:set_entities_enabled('treasure_obstacle_', false)
	end

	if data.treasure2 then
		local x, y = map:get_entity('treasure_open_chest'):get_position()
		x, y = x + 8, y + 13
		map:create_chest{
            sprite="entities/chest",
            layer=1,
            x = x,
            y = y,
            treasure_name=data.treasure2.item_name,
            treasure_savegame_variable=data.treasure2.name,
        }
	else
		map:set_entities_enabled('treasure_open_', false)
	end
	
	local torches = map:get_entities('torch_')
	local torch_count = map:get_entities_count('torch_')
	local lit_count = 0 
	for torch in torches do
		if timeout then torch:set_timeout(timeout) end
		function torch:on_lit()
			lit_count = lit_count + 1
			if lit_count == torch_count then
				local sound = nil
				if data.treasure1 then
					hidden_chest:set_enabled(true)
					sound = 'chest_appears'
				end
				for _, component in ipairs(doors) do
					component:open()
					sound = 'secret'
				end
				sol.audio.play_sound(sound)
			end	
        end
		function torch:on_unlighting()
			if lit_count == torch_count then
				return false
			else
				lit_count = lit_count - 1
			end
		end
	end

    data.room_events:add_door_sensor_activated_listener(function ()
        if lit_count ~= torch_count then
            for _, component in ipairs(doors) do
                component:close()
            end
        end
    end)
end

return lamp
