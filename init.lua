futil.check_version({ year = 2023, month = 6, day = 17 })

oia = fmod.create()

local f = string.format

local in_area = function(pos, pmin, pmax)
	return pmin.x <= pos.x
		and pos.x <= pmax.x
		and pmin.y <= pos.y
		and pos.y <= pmax.y
		and pmin.z <= pos.z
		and pos.z <= pmax.z
end

local v_distance = vector.distance

local S = oia.S

oia.pst = futil.PointSearchTree({})

minetest.register_globalstep(function()
	local pos_and_values = {}
	for _, obj in pairs(minetest.object_refs) do
		local pos = obj:get_pos()
		if pos then
			pos_and_values[#pos_and_values + 1] = { pos, obj }
		end
	end

	oia.pst = futil.PointSearchTree(pos_and_values)
end)

if oia.settings.verify_objects then
	function oia.get_objects_in_area(pmin, pmax)
		pmin, pmax = vector.sort(pmin, pmax)

		local objects = {}
		for _, obj in oia.pst:iterate_values_in_area(pmin, pmax) do
			local pos = obj:get_pos()
			if pos and in_area(pos, pmin, pmax) then
				objects[#objects + 1] = obj
			end
		end

		return objects
	end

	function oia.get_objects_inside_radius(center, radius)
		local objects = {}

		for _, obj in oia.pst:iterate_values_inside_radius(center, radius) do
			local pos = obj:get_pos()
			if pos and v_distance(center, pos) <= radius then
				objects[#objects + 1] = obj
			end
		end

		return objects
	end
else
	function oia.get_objects_in_area(pmin, pmax)
		return oia.pst:get_values_in_area(pmin, pmax)
	end

	function oia.get_objects_inside_radius(center, radius)
		return oia.pst:get_values_inside_radius(center, radius)
	end
end

local builtin_get_objects_in_area = minetest.get_objects_in_area
local builtin_get_objects_inside_radius = minetest.get_objects_inside_radius

minetest.register_chatcommand("oia_override", {
	description = S("set whether minetest.get_objects_in_area is overridden"),
	params = "[enable | disable]",
	privs = { server = true },
	func = function(name, param)
		if param:match("^%s*$") then
			if minetest.get_objects_in_area == builtin_get_objects_in_area then
				return true, S("get_objects_in_area is builtin")
			else
				return true, S("get_objects_in_area is overridden")
			end
		elseif param:match("^%s*enable%s*$") then
			minetest.get_objects_in_area = oia.get_objects_in_area
			minetest.get_objects_inside_radius = oia.get_objects_inside_radius
			return true, S("get_objects_in_area is now overridden")
		elseif param:match("^%s*disable%s*$") then
			minetest.get_objects_in_area = builtin_get_objects_in_area
			minetest.get_objects_inside_radius = builtin_get_objects_inside_radius
			return true, S("get_objects_in_area set to builtin")
		else
			return false, S("invalid argument")
		end
	end,
})

minetest.register_chatcommand("oia_validate", {
	description = S("test whether oia and the engine find the same entities"),
	params = "<radius>",
	privs = { server = true },
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("you are not connected")
		end

		local radius = param:match("^%s*(%S+)%s*$")
		radius = tonumber(radius)
		if not radius or radius < 0 then
			return false, S("invalid radius")
		end

		local ppos = player:get_pos()
		local pmin = vector.subtract(ppos, radius)
		local pmax = vector.add(ppos, radius)

		local builtin_oia = builtin_get_objects_in_area(pmin, pmax)
		local oia_oia = oia.get_objects_in_area(pmin, pmax)

		if #builtin_oia ~= #oia_oia then
			return false, f("goia: number of objects differ (builtin=%i; oia=%i)", #builtin_oia, #oia_oia)
		end

		local builtin_set = {}
		for _, obj in ipairs(builtin_oia) do
			builtin_set[obj] = true
		end

		local oia_set = {}
		for _, obj in ipairs(oia_oia) do
			oia_set[obj] = true
		end

		if not futil.equals(builtin_set, oia_set) then
			return false, f("goia: sets differ")
		end

		local builtin_oir = builtin_get_objects_inside_radius(ppos, radius)
		local oia_oir = oia.get_objects_inside_radius(ppos, radius)

		if #builtin_oir ~= #oia_oir then
			return false, f("goir: number of objects differ (builtin=%i; oia=%i)", #builtin_oir, #oia_oir)
		end

		builtin_set = {}
		for _, obj in ipairs(builtin_oir) do
			builtin_set[obj] = true
		end

		oia_set = {}
		for _, obj in ipairs(oia_oir) do
			oia_set[obj] = true
		end

		if not futil.equals(builtin_set, oia_set) then
			return false, f("goir: sets differ")
		end

		return true, f("validation successful (%i & %i objects found)", #builtin_oia, #builtin_oir)
	end,
})

minetest.register_chatcommand("oia_benchmark", {
	description = S("test whether oia is more efficient (will cause a lag spike)"),
	params = "<radius> <trials>",
	privs = { server = true },
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("you are not connected")
		end

		local radius, trials = param:match("^%s*(%S+)%s+(%S+)%s*$")
		radius, trials = tonumber(radius), tonumber(trials)
		if not (radius and trials) then
			return false, S("invalid arguments")
		end
		if radius < 0 or trials < 1 then
			return false, S("invalid arguments")
		end

		local total_objects = futil.table.size(minetest.object_refs)

		local ppos = player:get_pos()
		local pmin = vector.subtract(ppos, radius)
		local pmax = vector.add(ppos, radius)
		local clock = os.clock

		local goia = builtin_get_objects_in_area
		local start = clock()
		for _ = 1, trials do
			goia(pmin, pmax)
		end
		local builtin_elapsed = clock() - start

		goia = oia.get_objects_in_area
		start = clock()
		for _ = 1, trials do
			goia(pmin, pmax)
		end
		local oia_elapsed = clock() - start

		return true,
			S(
				"@1 objects; builtin: @2; oia: @3",
				tostring(total_objects),
				tostring(builtin_elapsed),
				tostring(oia_elapsed)
			)
	end,
})

if oia.settings.override_builtin then
	minetest.get_objects_in_area = oia.get_objects_in_area
	minetest.get_objects_inside_radius = oia.get_objects_inside_radius
end
