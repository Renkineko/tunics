local map = ...
local game = map:get_game()
local entrance_x, entrance_y = map:get_entity('entrance'):get_position()

local Class = require 'lib/class.lua'
local Tree = require 'lib/tree.lua'
local TreeBuilder = require 'lib/treebuilder.lua'

math.randomseed(666)




function intermingle(a, b)
    local result = {}
    local i = 1
    local j = 1
    local total = #a + #b
    while total > 0 do
        if math.random(total) <= #a - i + 1 then
            table.insert(result, a[i])
            i = i + 1
        else
            table.insert(result, b[j])
            j = j + 1
        end
        total = total - 1
    end
    return result
end

function concat(a, b)
    for _, value in ipairs(b) do
        table.insert(a, value)
    end
    return a
end

function shuffle(array)
    for i, _ in ipairs(array) do
        local j = math.random(#array)
        array[i], array[j] = array[j], array[i]
    end
end



function max_heads(n)
    return function (root)
        while #root.children > n do
            local fork = Tree.Room:new()
            fork:merge_child(root:remove_child(root:random_child()))
            fork:merge_child(root:remove_child(root:random_child()))
            root:add_child(fork)
        end
    end
end

function compass_puzzle()
    return {
        TreeBuilder.hide_treasures,
        TreeBuilder.add_treasure('compass'),
    }
end

function map_puzzle()
    local steps = {
        TreeBuilder.add_treasure('bomb'),
        TreeBuilder.add_treasure('map'),
    }
    shuffle(steps)
    table.insert(steps, 1, TreeBuilder.bomb_doors)
    return steps
end

function items_puzzle(item_names)
    shuffle(item_names)
    local steps = {}
    for _, item_name in ipairs(item_names) do
        table.insert(steps, TreeBuilder.hard_to_reach(item_name))
        table.insert(steps, TreeBuilder.add_big_chest(item_name))
    end
    table.insert(steps, TreeBuilder.add_treasure('big_key'))
    return steps
end

function lock_puzzle()
    return {
        function (root)
            if TreeBuilder.locked_door(root) then
                TreeBuilder.add_treasure('small_key')(root)
            end
        end,
    }
end

function dungeon_puzzle(nkeys, item_names)
    local puzzles = {
        items_puzzle(item_names),
        map_puzzle(),
        compass_puzzle(),
    }
    for i = 1, nkeys do
        table.insert(puzzles, lock_puzzle())
    end
    shuffle(puzzles)

    local steps = {}
    for _, puzzle in ipairs(puzzles) do
        local n = math.random(2)
        if n == 1 then
            steps = intermingle(steps, puzzle)
        else
            steps = concat(steps, puzzle)
        end
    end
    table.insert(steps, 1, TreeBuilder.add_boss)
    return steps
end


function filter_keys(table, keys)
    local result = {}
    for _, key in ipairs(keys) do
        if table[key] then result[key] = table[key] end
    end
    return result
end

local function stdout_room(properties)
    function print_access(thing)
        if thing.see and thing.see ~= 'nothing' then print(string.format("\t\tto see: %s", thing.see)) end
        if thing.reach and thing.reach ~= 'nothing' then print(string.format("\t\tto reach: %s", thing.reach)) end
        if thing.open and thing.open ~= 'nothing' then print(string.format("\t\tto open: %s", thing.open)) end
    end
    print(string.format("Room %d;%d", properties.x, properties.y))
    for dir, door in pairs(properties.doors) do
        print(string.format("  Door %s", dir))
        print_access(door)
    end
    for _, item in ipairs(properties.items) do
        print(string.format("  Item %s", item.name))
        print_access(item)
    end
    for _, enemy in ipairs(properties.enemies) do
        print(string.format("  Enemy %s", enemy.name))
        print_access(enemy)
    end
    print()
end

local function solarus_room(properties)
    local x0 = entrance_x - 160 + 320 * properties.x
    local y0 = entrance_y + 3 - 240 + 240 * (properties.y - 9)
    map:include(x0, y0, 'rooms/room1', filter_keys(properties, {'doors', 'items', 'enemies'}))
end

local LayoutVisitor = Class:new()

function LayoutVisitor:visit_enemy(enemy)
    table.insert(self.enemies, enemy)
end

function LayoutVisitor:visit_treasure(treasure)
    table.insert(self.items, treasure)
end

local DIRECTIONS = { east=0, north=1, west=2, south=3, }
function add_doorway(separators, x, y, direction, savegame_variable)
    separators[y] = separators[y] or {}
    separators[y][x] = separators[y][x] or {}
    separators[y][x][DIRECTIONS[direction]] = savegame_variable
end

function LayoutVisitor:visit_room(room)
    local y = self.y
    local x0 = self.x
    local x1 = x0
    local doors = {}
    local items = {}
    local enemies = {}
    local old_nkids = self.nkids

    if self.doors then
        self.doors.north = filter_keys(room, {'see','reach','open'})
    end

    self.nkids = 0
    room:each_child(function (key, child)
        self.y = y - 1
        self.items = items
        self.enemies = enemies
        if child.class == 'Room' then
            x1 = self.x
            doors[x1] = doors[x1] or {}
            self.doors = doors[x1]
        end
        child:accept(self)
    end)

    for x = x0, x1 do
        doors[x] = doors[x] or {}
        if x == x0 then doors[x].south = filter_keys(room, {'open'}) end
        if x < x1 then doors[x].east = {} end
        if x > x0 then doors[x].west = {} end
        if doors[x].north then
            doors[x].north.name = string.format('door_%d_%d_n', x, y)
        end
        self.render{
            x=x,
            y=y,
            doors=doors[x],
            items=items,
            enemies=enemies,
        }
        local savegame_variable = room.savegame_variable .. '_' .. (x - x0)
        add_doorway(self.separators, x,   y+1, 'north', doors[x].south and savegame_variable or false)
        add_doorway(self.separators, x,   y,   'east',  doors[x].west  and savegame_variable or false)
        add_doorway(self.separators, x,   y,   'south', doors[x].north and savegame_variable or false)
        add_doorway(self.separators, x+1, y,   'west',  doors[x].east  and savegame_variable or false)

        items = {}
        enemies = {}
    end

    if self.nkids == 0 then
        self.x = self.x + 1
    end
    self.nkids = self.old_nkids
end


local puzzle = dungeon_puzzle(3, {'hookshot'})
local root = Tree.Room:new()
for i, step in ipairs(puzzle) do
    max_heads(3)(root)
    step(root)
end
root:each_child(function (key, child)
    if child.class ~= 'Room' then
        local room = Tree.Room:new()
        room:add_child(child)
        root:update_child(key, room)
    end
end)
local tree = Tree.Room:new{open='entrance'}
local tree = root
tree.open = 'entrance'


function map_room(x, y)
    game:set_value(string.format('room_%d_%d', x, y), true)
end

--tree:accept(Tree.PrintVisitor:new{})
--tree:accept(LayoutVisitor:new{x=0, y=0,render=stdout_room})
local separators = {}
tree:accept(LayoutVisitor:new{x=0, y=9,render=solarus_room, separators=separators})
map_room(0, 9)


for y, row in pairs(separators) do
    for x, room in pairs(row) do
        if room[DIRECTIONS.north] ~= nil or room[DIRECTIONS.south] ~= nil then
            local properties = {
                x = entrance_x - 160 + 320 * x,
                y = entrance_y + 3 - 240 + 240 * (y - 9) - 8,
                layer = 1,
                width = 320,
                height = 16,
            }
            local sep = map:create_separator(properties)
            if room[DIRECTIONS.north] then
                function sep:on_activated(dir)
                    local my_y = (dir == DIRECTIONS.north) and y - 1 or y
                    local my_x = (dir == DIRECTIONS.west) and x - 1 or x
                    map_room(my_x, my_y)
                end
            end
        end
        if room[DIRECTIONS.east] ~= nil or room[DIRECTIONS.west] ~= nil then
            local properties = {
                x = entrance_x - 160 + 320 * x - 8,
                y = entrance_y + 3 - 240 + 240 * (y - 9),
                layer = 1,
                width = 16,
                height = 240,
            }
            local sep = map:create_separator(properties)
            if room[DIRECTIONS.west] then
                function sep:on_activated(dir)
                    local my_y = (dir == DIRECTIONS.north) and y - 1 or y
                    local my_x = (dir == DIRECTIONS.west) and x - 1 or x
                    map_room(my_x, my_y)
                end
            end
        end
    end
end

function map:render_map(map_menu)
    local render = function (properties)
        map_menu:draw_room(properties)
    end
    map_menu:clear_map()
    tree:accept(LayoutVisitor:new{x=0, y=9,render=render, separators={}})
end
