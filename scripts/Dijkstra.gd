class_name Dijkstra
## Dijkstra.gd
## Pure shortest-path solver operating on an impedance-weighted adjacency graph.
## Accepts any adjacency Dictionary of Vector2i → Array of link objects that expose:
##   .to_node: Vector2i, .from_node: Vector2i, .base_time: float, .impedance(alpha) -> float
##
## "class_name" registers this script as a global type, so any other script in
## the project can call Dijkstra.find_route() without an import or preload.

# "static func" means the method belongs to the class itself, not an instance.
# No object needs to be created — callers just write Dijkstra.find_route(...).
static func find_route(adjacency: Dictionary, start: Vector2i, goal: Vector2i, alpha: float) -> Dictionary:
	# Dictionary is GDScript's hash map (like Python dict / JS object).
	# Keys and values are untyped Variants unless annotated.
	var dist:    Dictionary = {}  # best known cost to reach each node
	var prev:    Dictionary = {}  # the Link object we arrived on (for path reconstruction)
	var visited: Dictionary = {}  # settled nodes (used as a hash set — only keys matter)

	# Vector2i is a Godot built-in: an (x, y) pair of integers.
	# Here it doubles as a grid coordinate, e.g. Vector2i(3, 4) = column 3, row 4.
	for node in adjacency.keys():
		dist[node] = INF  # INF is a GDScript built-in float constant (like math.inf in Python)
	dist[start] = 0.0

	# Priority queue stored as a plain Array of [cost, node] pairs.
	# GDScript has no built-in heap, so we re-sort on every pop (fine for ~50 nodes).
	var queue: Array = [[0.0, start]]

	while queue.size() > 0:
		# sort_custom takes a lambda (GDScript calls these "Callable" / inline func).
		# This sorts ascending by index 0 (cost), making pop_front() return the cheapest entry.
		queue.sort_custom(func(a, b): return a[0] < b[0])
		var current_entry = queue.pop_front()  # removes and returns the first element
		var current: Vector2i = current_entry[1]

		if visited.has(current):  # .has() is Dictionary's equivalent of "in" (Python) / containsKey (Java)
			continue
		visited[current] = true

		if current == goal:
			break

		# adjacency.get(key, default) returns the default if the key is missing,
		# avoiding a KeyError / null crash. Equivalent to adjacency.get(current, []) in Python.
		for link in adjacency.get(current, []):
			# "link" is an untyped Variant here — GDScript resolves .to_node / .impedance()
			# at runtime via duck typing. The actual objects are CityNetwork.Link instances.
			var neighbor: Vector2i = link.to_node
			if visited.has(neighbor):
				continue
			var new_cost: float = current_entry[0] + link.impedance(alpha)
			if new_cost < dist[neighbor]:
				dist[neighbor] = new_cost
				prev[neighbor] = link
				queue.append([new_cost, neighbor])  # .append() is push_back — adds to the end

	if dist[goal] == INF:
		return {}  # no path exists; callers check for an empty Dictionary

	# Reconstruct path by walking prev[] backward from goal to start.
	# Array[Vector2i] is a typed array — GDScript enforces element type at runtime.
	var path: Array[Vector2i] = []
	var raw_time: float = 0.0
	var node: Vector2i = goal
	while node != start:
		path.push_front(node)  # push_front prepends (like unshift in JS / deque.appendleft in Python)
		var link = prev[node]
		raw_time += link.base_time  # base_time is physical travel time, unaffected by stress or β
		node = link.from_node
	path.push_front(start)

	# Returns a Dictionary with three keys. Callers use .get("key", default) to read them.
	#   path             — ordered Array[Vector2i] of node IDs from start to goal
	#   total_impedance  — weighted cost Dijkstra minimised (includes stress penalty)
	#   total_time       — raw travel time in minutes (sum of base_time, no stress weighting)
	return { "path": path, "total_impedance": dist[goal], "total_time": raw_time }
