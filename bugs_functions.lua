bugs = {} -- initialize table of functions for other mods to call
local stuck_timeout = 1 -- how long before stuck mod starts searching
local stuck_path_timeout = 10 -- how long will mob follow path before giving up
local enable_pathfinding = true
function bugs:mob_get_path_to(self, pos, searchdistance)
  local mob_pos = self.object:get_pos()
  local path = {}
  local dropheight = 6

  if self.fear_height ~= 0 then dropheight = self.fear_height end

  local jumpheight = 0

  if self.jump and self.jump_height >= 4 then
    jumpheight = min(ceil(self.jump_height / 4), 4)

  elseif self.stepheight > 0.5 then
    jumpheight = 1
  end

  path = minetest.find_path(mob_pos,pos,searchdistance,dropheight,jumpheight) or false

  return path
end

local los_switcher = false
local height_switcher = false
function bugs:mob_move_toward(self,pos,dtime)

  local s = self.object:get_pos()
  local p = pos
  local dist = ((pos.x-s.x)^2) + ((pos.y-s.y)^2) + ((pos.z-s.z)^2)

  if self.path then
    local s1 = self.path.lastpos or {x=0,y=0,z=0}
    local target_pos = p


    -- is it becoming stuck?
    if math.abs(s1.x - s.x) + math.abs(s1.z - s.z) < .5 then
      self.path.stuck_timer = self.path.stuck_timer + dtime
    else
      self.path.stuck_timer = 0
    end

    self.path.lastpos = {x = s.x, y = s.y, z = s.z}

    local use_pathfind = false
    local has_lineofsight = minetest.line_of_sight(
      {x = s.x, y = (s.y) + .5, z = s.z},
      {x = target_pos.x, y = (target_pos.y) + 1.5, z = target_pos.z}, .2)

    -- im stuck, search for path
    if not has_lineofsight then

      if los_switcher == true then
        use_pathfind = true
        los_switcher = false
      end -- cannot see target!
    else
      if los_switcher == false then

        los_switcher = true
        use_pathfind = false

        minetest.after(1, function(self)

          if self.object:get_luaentity() then

            if has_lineofsight then
              self.path.following = false
            end
          end
        end, self)
      end -- can see target!
    end

    if (self.path.stuck_timer > stuck_timeout and not self.path.following) then

      use_pathfind = true
      self.path.stuck_timer = 0

      minetest.after(1, function(self)

        if self.object:get_luaentity() then

          if has_lineofsight then
            self.path.following = false
          end
        end
      end, self)
    end

    if (self.path.stuck_timer > stuck_path_timeout and self.path.following) then

      use_pathfind = true
      self.path.stuck_timer = 0

      minetest.after(1, function(self)

        if self.object:get_luaentity() then

          if has_lineofsight then
            self.path.following = false
          end
        end
      end, self)
    end
  end

  if math.abs(vector.subtract(s,p).y) > self.stepheight then
		  if height_switcher then
			use_pathfind = true
			height_switcher = false
		  end
	else
		if not height_switcher then
			use_pathfind = false
			height_switcher = true
		end
	end

  if use_pathfind then

    -- round position to center of node to avoid stuck in walls
    -- also adjust height for player models!
    s.x = math.floor(s.x + 0.5)
    s.z = math.floor(s.z + 0.5)

    local ssight, sground = minetest.line_of_sight(s, {
      x = s.x, y = s.y - 4, z = s.z}, 1)

    -- determine node above ground
    if not ssight then
      s.y = sground.y + 1
    end

    local p1 = p

    p1.x = math.floor(p1.x + 0.5)
    p1.y = math.floor(p1.y + 0.5)
    p1.z = math.floor(p1.z + 0.5)


    self.path.way = bugs:mob_get_path_to(self,  p1, 16)

    self.state = ""

    --attack removed from here

    -- no path found, try something else
    if not self.path.way then

      self.path.following = false

      -- will try again in 2 second
      self.path.stuck_timer = stuck_timeout - 2

    elseif s.y < p1.y and (not self.fly) then
      self:do_jump() --add jump to pathfinding
      self.path.following = true
    else
      -- yay i found path

      self:set_velocity(self.walk_velocity)

      -- follow path now that it has it
      self.path.following = true
    end
  end
end
