/datum/shuttle/ferry
	var/location = 0 //0 = at area_station, 1 = at area_offsite
	var/direction = 0 //0 = going to station, 1 = going to offsite.
	var/process_state = IDLE_STATE

	var/in_use = null //tells the controller whether this shuttle needs processing
	var/already_moving = 0 //makes sure we do not call the move shuttle proc twice.
	var/area_transition
	var/move_time = 0 //the time spent in the transition area
	var/transit_direction = null //needed for area/move_contents_to() to properly handle shuttle corners - not exactly sure how it works.

	var/area/area_station
	var/area/area_offsite
	//TODO: change location to a string and use a mapping for area and dock targets.
	var/dock_target_station
	var/dock_target_offsite

	var/last_dock_attempt_time = 0
	var/alerts_allowed = 1 //NOT A BOOLEAN. Number of alerts allowed on this particular shuttle, so only once
	var/locked = 0
	var/queen_locked = 0 //If the Queen locked the ship by interacting with its onboard console. If this happens, Marines lose control of the ship permanently
	var/last_locked = 0 //world.time value to determine if it can be contested
	var/door_override = 0 //similar to queen_locked, but only affects doors
	var/last_door_override = 0 //world.time value to determine if it can be contested

	var/in_transit_time_left = 0

/datum/shuttle/ferry/short_jump(var/area/origin,var/area/destination)
	if(isnull(location))
		return

	if(!destination)
		destination = get_location_area(!location)
	if(!origin)
		origin = get_location_area(location)

	direction = !location
	..(origin, destination)

/datum/shuttle/ferry/long_jump(area/departing, area/destination, area/interim, travel_time, direction)
	if(isnull(location))
		return

	if(!destination)
		destination = get_location_area(!location)
	if(!departing)
		departing = get_location_area(location)

	direction = !location

	..(departing, destination, interim, travel_time, direction)

/datum/shuttle/ferry/move(var/area/origin,var/area/destination)
	..(origin, destination)

	if (destination == area_station) location = 0
	if (destination == area_offsite) location = 1
	//if this is a long_jump retain the location we were last at until we get to the new one

/datum/shuttle/ferry/dock()
	..()
	last_dock_attempt_time = world.time

/datum/shuttle/ferry/proc/get_location_area(location_id = null)
	if (isnull(location_id))
		location_id = location

	if (!location_id)
		return area_station
	return area_offsite

/datum/shuttle/ferry/proc/preflight_checks()
	return 1

/datum/shuttle/ferry/proc/announce_preflight_failure()
	return

/*
	Please ensure that long_jump() and short_jump() are only called from here. This applies to subtypes as well.
	Doing so will ensure that multiple jumps cannot be initiated in parallel.
*/
/datum/shuttle/ferry/process()

	switch(process_state)
		if (WAIT_LAUNCH)
			if(!preflight_checks())
				announce_preflight_failure()
				process_state = SHUTTLE_IDLE
				return .
			if (skip_docking_checks() || docking_controller.can_launch())
				if (move_time && area_transition)
					long_jump(interim=area_transition, travel_time=move_time, direction=transit_direction)
				else
					short_jump()

				process_state = WAIT_ARRIVE

		if (FORCE_LAUNCH)
			if (move_time && area_transition)
				long_jump(interim=area_transition, travel_time=move_time, direction=transit_direction)
			else
				short_jump()

			process_state = WAIT_ARRIVE

		if (WAIT_ARRIVE)
			if (moving_status == SHUTTLE_IDLE)
				dock()
				in_use = null //release lock
				process_state = WAIT_FINISH

		if (WAIT_FINISH)
			if (skip_docking_checks() || docking_controller.docked() || world.time > last_dock_attempt_time + DOCK_ATTEMPT_TIMEOUT)
				process_state = IDLE_STATE
				arrived()

/datum/shuttle/ferry/current_dock_target()
	var/dock_target
	if (!location) //station
		dock_target = dock_target_station
	else
		dock_target = dock_target_offsite
	return dock_target


/datum/shuttle/ferry/proc/launch(var/user)
	if (!can_launch()) return

	in_use = user //obtain an exclusive lock on the shuttle
	locked = 1

	process_state = WAIT_LAUNCH
	undock()

/datum/shuttle/ferry/proc/force_launch(var/user)
	if (!can_force()) return

	in_use = user //obtain an exclusive lock on the shuttle

	process_state = FORCE_LAUNCH

/datum/shuttle/ferry/proc/cancel_launch(var/user)
	if (!can_cancel()) return

	moving_status = SHUTTLE_IDLE
	process_state = WAIT_FINISH
	in_use = null

	if (docking_controller && !docking_controller.undocked())
		docking_controller.force_undock()

	addtimer(CALLBACK(src, PROC_REF(dock)), 10)

	return

/datum/shuttle/ferry/proc/can_launch()
	if(moving_status != SHUTTLE_IDLE || locked || in_use)
		return FALSE
	return TRUE

/datum/shuttle/ferry/proc/can_force()
	if (moving_status == SHUTTLE_IDLE && process_state == WAIT_LAUNCH)
		return 1
	return 0

/datum/shuttle/ferry/proc/can_cancel()
	if (moving_status == SHUTTLE_WARMUP || process_state == WAIT_LAUNCH || process_state == FORCE_LAUNCH)
		return 1
	return 0

/datum/shuttle/ferry/proc/can_optimize()
	if(!(moving_status == SHUTTLE_WARMUP || process_state == WAIT_LAUNCH || process_state == FORCE_LAUNCH) && !transit_optimized && !recharging)
		return 1
	return 0

//returns 1 if the shuttle is getting ready to move, but is not in transit yet
/datum/shuttle/ferry/proc/is_launching()
	return (moving_status == SHUTTLE_WARMUP || process_state == WAIT_LAUNCH || process_state == FORCE_LAUNCH)

//This gets called when the shuttle finishes arriving at it's destination
//This can be used by subtypes to do things when the shuttle arrives.
/datum/shuttle/ferry/proc/arrived()
	locked = 0
	return //do nothing for now

