class_name DogAI
extends RefCounted
## 狗每回合的行为决策。纯计算，不碰节点。
##
## 【硬规矩 1】实战和「敌方行动预览」必须调**同一个函数**（ARCHITECTURE 5.2）。
## 【硬规矩 2】全确定性，不许掷随机（5.3）。同分一律按方向表顺序取第一个。
##
## 优先级（照设计文档写的，别自作主张调换）：
##   ① 相邻贴肉 -> 啃，优先于移动
##   ② 朝肉方向那一格是空的、且没被控制 -> 走进去
##   ③ 朝肉方向那一格**有猫** -> 撞飞它（前提是狗还有别的路，否则算围死）
##   ④ 朝肉方向被控制挡住 -> 退而求其次，走向离肉最近的其它可走格
##   ⑤ 一个可走格都没有 -> 围死
##
## 返回 { "kind": String, "to": Vector2i, "cat": int }
##   "eat" / "move" / "flick" / "none"
##
## 狗类型：
##   stray  野狗，贪心（哪个正交方向离肉近就往哪）
##   collie 边牧，BFS 绕开障碍

static func plan(state: GameState) -> Dictionary:
	var movable := Encircle.movable_cells(state)

	# ⑤ 一个可走格都没有 => 围死。注意**不是**看"有没有动作"：
	#    旁边还有猫能撞飞也不算逃生路（见 encircle.gd 顶部说明）
	if movable.is_empty():
		return _none()

	# ① 啃食优先于移动
	if _manhattan(state.dog["pos"], state.meat_pos) == 1:
		return { "kind": "eat", "to": state.meat_pos, "cat": -1 }

	var preferred := _preferred_step(state)

	# ② 朝肉那一步能走就走
	if preferred.x >= 0 and movable.has(preferred):
		return { "kind": "move", "to": preferred, "cat": -1 }

	# ③ 朝肉那一步上蹲着一只猫 => 撞飞它（此时狗还有别的路，所以不算围死）
	if preferred.x >= 0:
		var blocker := state.cat_at(preferred)
		if blocker != -1:
			return { "kind": "flick", "to": preferred, "cat": blocker }

	# ④ 朝肉的路被控制挡住（没人可撞）=> 挑一个离肉最近的可走格
	return _greedy_step(state, movable)


## 朝肉方向的那一格。没有更近的方向就返回 (-1,-1)。
## stray：四个邻格里离肉最近的；collie：BFS 最短路的第一步。
static func _preferred_step(state: GameState) -> Vector2i:
	if String(state.dog.get("type", "stray")) == "collie":
		var step := _bfs_first_step(state)
		if step.x >= 0:
			return step

	var dog: Vector2i = state.dog["pos"]
	var best := Vector2i(-1, -1)
	var best_d := _manhattan(dog, state.meat_pos)
	for dir in MoveRules.ORTHO_DIRS:
		var cell: Vector2i = dog + dir
		if not state.in_bounds(cell):
			continue
		var d := _manhattan(cell, state.meat_pos)
		if d < best_d:
			best_d = d
			best = cell
	return best


## 在一个动作里挑离肉最近的（同分按传入顺序，也就是方向表顺序）
static func _greedy_step(state: GameState, cells: Array) -> Dictionary:
	var best: Vector2i = cells[0]
	var best_d := _manhattan(best, state.meat_pos)
	for cell in cells:
		var d := _manhattan(cell, state.meat_pos)
		if d < best_d:
			best_d = d
			best = cell
	return { "kind": "move", "to": best, "cat": -1 }


static func _none() -> Dictionary:
	return { "kind": "none", "to": Vector2i.ZERO, "cat": -1 }


## 从狗出发 BFS 到"肉的相邻格"，返回最短路的第一步。走不通返回 (-1, -1)。
## 路径上不考虑猫的控制（控制由 movable_cells 处理），但猫本身和肉格不能穿过。
static func _bfs_first_step(state: GameState) -> Vector2i:
	var start: Vector2i = state.dog["pos"]
	var prev := { start: start }
	var queue := [start]
	var head := 0

	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1

		if cur != start and _manhattan(cur, state.meat_pos) == 1:
			var node := cur
			while prev[node] != start:
				node = prev[node]
			return node

		for dir in MoveRules.ORTHO_DIRS:
			var nxt: Vector2i = cur + dir
			if prev.has(nxt):
				continue
			if state.is_wall(nxt):
				continue
			if nxt == state.meat_pos:
				continue
			if state.cat_at(nxt) != -1:
				continue
			prev[nxt] = cur
			queue.append(nxt)

	return Vector2i(-1, -1)


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
