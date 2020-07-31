
local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP .. "/bugs_functions.lua")



--SETTINGS---
local max_obj = 50 -- what is the maxium number of objects after which no more ants will spawn
local stuck_timeout = 1 -- how long before stuck mod starts searching
local stuck_path_timeout = 10 -- how long will mob follow path before giving up
local enable_pathfinding = true



-- functions --
local get_horizantal_dist_sq = function(pos1,pos2)
  local x1 = pos1.x
  local z1 = pos1.z
  local x2 = pos2.x
  local z2 = pos2.z
  return ((x2-x1)^2) + ((z2 - z1)^2)
end

local get_distance = function(a, b)

	local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z

	return (x * x + y * y + z * z)*(x * x + y * y + z * z)
end
--##############################################################



--##############################################################
-- turn mob to face position
local yaw_to_pos = function(self, target, rot)

	rot = rot or 0

	local pos = self.object:get_pos()
	local vec = {x = target.x - pos.x, z = target.z - pos.z}
	local yaw = (atan(vec.z / vec.x) + rot + pi / 2) - self.rotate

	if target.x > pos.x then
		yaw = yaw + pi
	end

	yaw = self:set_yaw(yaw, 6)

	return yaw
end


--############################################################

-- helper function for initializing worker ant destinations in connection with an ant nest
local find_destinations = function(pos) -- pos is that of the nest
  local instructions = {pos,} -- will need to return this, if it exists... the first pos in instructions is always the home node
  local facing = math.random(1,4) --choose one of 4 directions to start writing the path in
  local steps = math.random(1,1) --how many insturctions are we going to have past the first
  for i = 1, steps do --we will have 1 to 1 more locations after the first one
    --- the order here is: move dist in facing direction, log an instruction point, turn left or right and update facing
    local start_pos = instructions[i]

    local dist = math.random(3,10) -- choose random distance to travel to the next point
    local new_pos = {}
    --find the new pos based on dist and facing direction;   1= +x, 2 = +z, 3 = -x, 4= -z
    if facing == 1 then
      new_pos = {x=start_pos.x + dist, y=start_pos.y, z=start_pos.z}
    end
    if facing == 2 then
      new_pos = {x=start_pos.x, y=start_pos.y, z=start_pos.z + dist}
    end
    if facing == 3 then
      new_pos = {x=start_pos.x - dist, y=start_pos.y, z=start_pos.z}
    end
    if facing == 4 then
      new_pos = {x=start_pos.x, y=start_pos.y, z=start_pos.z - dist}
    end
    instructions[i+1] = new_pos -- add a new position to the instructions list

    -- choose a new direction, by turing left or right
    facing = facing + math.random(-1,1)
    if facing == 5 then
      facing = 1
    end
    if facing == 0 then
      facing = 4
    end
  end -- this finishes the for loop, and will make a list of positions that form a path.
  return instructions -- this returns the list of position instructions
end








mobs:register_mob("bugs:ant_worker", {
	type = "animal",
	visual = "mesh",
  jump = false,
	visual_size = {x = 7, y = 7},
	mesh = "bugs_ant.b3d",
	collisionbox = {-0.07, -0.01, -0.07, 0.07, 0.07, 0.07},
	animation = {
		speed_normal = 1,
		speed_run = 1,
		stand_start = 1,
		stand_end = 10,
		walk_start = 20,
		walk_end = 24,
		run_start = 20,
		run_end = 24,
    jump_start = 28,
    jump_end = 32,
	},
	textures = {
		{"bugs_ant.png"},
	},
	fear_height = 3,
	runaway = false,
	fly = false,
	walk_chance = 99,
  stand_chance = 1,
  walk_velocity = 1,
  run_velocity = 1,
	view_range = 5,
	passive = true,
	hp_min = 1,
	hp_max = 2,
	armor = 200,
	lava_damage = 5,
	fall_damage = 0,
	water_damage = 2,
	makes_footstep_sound = false,
	drops = {},
	sounds = {},
  ant_instructions = {},
  ant_goal_number = 2,
  time_on_goal = 0,
  reach = .2,
  ant_debug = false,


  on_rightclick = function(self, clicker)
    self.ant_debug = true
    minetest.chat_send_all("Following Ant!")
    minetest.chat_send_all("This ant should be going to ".. dump(self.ant_instructions[self.ant_goal_number]))
  end,

  do_custom = function(self, dtime) -- this allows for the custom movement
    if not(self.path) then
      self.path = {}
    	self.path.way = {} -- path to follow, table of positions
    	self.path.lastpos = {x = 0, y = 0, z = 0}
    	self.path.stuck = false
    	self.path.following = false -- currently following path?
    	self.path.stuck_timer = 0 -- if stuck for too long search for path
    end

    if self.ant_debug then
      if get_horizantal_dist_sq(self.object:get_pos(), self.ant_instructions[self.ant_goal_number]) < 1 then
        minetest.chat_send_all("your ant reached goal #"..dump(self.ant_goal_number))
      end
    end

    local time_on_goal = self.time_on_goal or 0
    --minetest.chat_send_all(dump(dtime).. time_on_goal)
    local goal_timeout = 10 -- # of seconds the ant should take to try to get to the next goal. If it fails to reach it before that time, It will move on to the next goal or go home.

    local ant_instructions = nil -- if there aren't any instructions then it will use nil for the value
    if self.ant_instructions then -- what if there are
      ant_instructions = self.ant_instructions
      self.pathfinding = 1
    end

    if not ant_instructions then -- if the ant doesnt have any instructions, then use regular api for movement

      return true
    end

    if not self.ant_goal_number then -- if for some reason we dont have a goal, then set it to the home position
      self.ant_goal_number = 1
    end



    local goal_pos = ant_instructions[self.ant_goal_number] --where are we going?
    self.time_on_goal = time_on_goal + dtime -- keep track of how long we have been on the current goal

    --so now move towards our goal, if we can
    --###############################################################
  	-- set positions
  	local pos1 = self.object:get_pos() -- ant's current position
  	local pos2 = goal_pos

  	-- if no path set then setup mob
  	if not self.path or not self.path.way then
  		self.pathfinding = 1 -- just incase it's not set in mobdef
  	end

  	-- call pathfinding function to control player movement
  	if self.pathfinding then
  		local horiz_dist = get_horizantal_dist_sq(pos1, pos2) -- if we have not reached our goal yet then we will call the smart mobs func to move us towards the goal
  		if horiz_dist > 1 then
        local dist = get_distance(pos1, pos2)
  			bugs:mob_move_toward(self,pos2,dtime)
  		else --if we have reached our goal, then we need to get our next goal, and reset the goal timer
        self.ant_goal_number = self.ant_goal_number + 1
        self.time_on_goal = 0 -- reset the time
        if self.ant_goal_number > #self.ant_instructions then -- if we advance the goal number beyond the nuber of goals, go home
          self.ant_goal_number = 1
        end
   		end
  	end
    --#################################################################
    --ok we have moved, so now we need to double-check our goals. We need to recognize if we are stuck, because there are no paths to the goal. that will be determined by how long we have had the same goal.
    if self.time_on_goal > 10 then --if we have been trying to get to the same goal for more than 10 sec, move on to the next one and reset the goal timer. Hopefully it wont take more than 10 sec to reach the next goal
      self.ant_goal_number = self.ant_goal_number + 1
      self.time_on_goal = 0 -- reset the time
      if self.ant_goal_number > #self.ant_instructions then -- if we advance the goal number beyond the nuber of goals, go home
        self.ant_goal_number = 1
      end
    end

  end
})








minetest.register_node("bugs:ant_nest",{
  description = "Ant Nest",
  tiles = {"default_dirt.png"},
  drawtype = "normal",
  groups = {crumbly=1, oddly_breakable_by_hand = 1},
  after_place_node = function(pos, placer, itemstack, pointed_thing)
    local destination_table = find_destinations(pos) -- gets the instruction list for the ants to follow.
    --debug
    minetest.chat_send_all(dump(destination_table))
    local timer = minetest.get_node_timer(pos) --start a timer to make the node keep producing ants
    timer:start(1)
    if destination_table then -- just to make sure
    --place the destination table in the node's meta here. After this, the destination table is stored in metadata as a string. Use something like data = minetest.deserialize(minetest:get_string("foo")) to de-strigify it.
      local meta = minetest.get_meta(pos)
      meta:set_string("instruction", minetest.serialize(destination_table))
      -- show goals using add_particlespawner
      for posi in ipairs(destination_table) do
        minetest.add_particle({
        pos = posi,
        velocity = {x=0, y=0, z=0},
        acceleration = {x=0, y=0, z=0},
        expirationtime = 4000,
        size = 4,
        collisiondetection = false,
        vertical = false,
        texture = "heart.png",
        })
      end


    end
  end,
  on_timer = function(pos)

    local timer = minetest.get_node_timer(pos)
    local meta = minetest.get_meta(pos)
    local next_timer = 1 -- how long until this function runs again, init at 1

    local objs = minetest.get_objects_inside_radius(pos, 30) --checking for ants and other objs within 30 nodes
    if #objs < max_obj then -- only spawn more ants if the max objects in the area is low enough
      local worker_ant_obj = minetest.add_entity(pos, "bugs:ant_worker", nil) --spawn a worker ant, and, below, try to give it instructions. This returns the object
      local worker_ant_ent = worker_ant_obj:get_luaentity() -- this gets the entity from the object
      local destination_table = minetest.deserialize(meta:get_string("instruction")) --retrieve the destination table from the metadata
      if destination_table then -- just to make sure it exists and not cause crashes
        worker_ant_ent.ant_instructions = destination_table --give this ant instructions
        worker_ant_ent.ant_goal_number = 2 -- set the goal for the second position in the instruction list (the fisrt is the home position)
        worker_ant_ent.time_on_goal = 0 --init goal timer
      end
    end
    timer:start(next_timer) -- restart the timer
  end,

})
