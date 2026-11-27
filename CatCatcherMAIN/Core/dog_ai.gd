class_name DogAI
extends RefCounted
## 狗每回合的行为决策。纯计算，不碰节点。
##
## 【硬规矩 1】实战和「敌方行动预览」必须调**同一个函数**（ARCHITECTURE 6.2）。
## 【硬规矩 2】全确定性，不许掷随机（6.3）。同分一律按方向表顺序取第一个。
##
## 只有一种狗（野狗，贪心朝肉走）。决策优先级：
##   ⓪ 脚下被控制 => 逃跑（跑到安全格，见 Encircle.can_flee）
##   ① 嘴边有**吃得掉的无保护猫** => 先撞它（**高于一切对肉动作**：别让它一口把肉吞了）
##   ② 贴着肉格 => 肉格有猫就吃掉它 / 低吼过就吃肉 / 否则低吼（吃肉前摇）
##   ③ 朝肉方向那一格能走 => 走
##   ④ 退而求其次：走向离肉最近的可走格（同距离优先逃路多的）
##   ⑤ 什么都不能做 => 围死，玩家赢
##
## 返回 { "kind": String, "to": Vector2i, "cat": int }
##   "eat"：吃到肉（玩家输，由 Rules 结算）
##   "growl"：低吼，本回合不动
##   "flee"：被控制住了，跑向安全格
##   "move" / "flick" / "none"

static func plan(state: GameState) -> Dictionary:
	if Encircle.legal_actions(state).is_empty():
		return _none()

	# ⓪ 脚下那格被控制 => 先跑（逃跑优先于一切，包括朝肉走和吃肉前摇）
	#    这就是玩家"驱赶"狗的手段：罩住它站的格，它自己就会走向安全格。
	if Encircle.can_flee(state):
		return { "kind": "flee", "to": Encircle.flee_target(state), "cat": -1 }

	# ① 嘴边有吃得掉的无保护猫 => 撞它。**优先于所有对肉动作**（需求方定）：
	#    不然会出现"旁边挂着一只没人罩的猫，它却直接低吼/吞肉"这种看不懂的局面。
	#    垫在肉格上的那只最该被吃（它本来就在嘴边），先挑它 => 垫肉机制不受影响。
	var flicks := Encircle.flickable_cats(state)
	if not flicks.is_empty():
		for f in flicks:
			if f["cell"] == state.meat_pos:
				return { "kind": "flick", "to": f["cell"], "cat": f["cat"] }
		return { "kind": "flick", "to": flicks[0]["cell"], "cat": flicks[0]["cat"] }

	# ② 贴着肉格：低吼 / 吃肉（走到这儿说明嘴边没有能吃的猫）
	var meat := Encircle.meat_action(state)
	if not meat.is_empty():
		return meat

	var movable: Array = Encircle.movable_cells(state)
	var preferred := _preferred_step(state)

	if preferred.x >= 0 and movable.has(preferred):
		# ③ 朝肉那格能走就走进
		return { "kind": "move", "to": preferred, "cat": -1 }

	# ④ 朝肉的路被控制挡住 => 挑离肉最近的可走格
	if not movable.is_empty():
		return { "kind": "move", "to": _closest_to_meat(state, movable), "cat": -1 }

	return _none()


## 朝肉方向的那一格：四个邻格里离肉最近的（同分按方向表顺序）。没有再近的就 (-1,-1)。
static func _preferred_step(state: GameState) -> Vector2i:
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


## 离肉最近的可走格；**同样近时选"逃路更多"的安全格**（免得一头钻进死角）。
static func _closest_to_meat(state: GameState, cells: Array) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_d := _manhattan(best, state.meat_pos)
	var best_safe := Encircle.escape_count(state, best)
	for cell in cells:
		var d := _manhattan(cell, state.meat_pos)
		if d < best_d:
			best = cell
			best_d = d
			best_safe = Encircle.escape_count(state, cell)
		elif d == best_d:
			var safe := Encircle.escape_count(state, cell)
			if safe > best_safe:
				best = cell
				best_safe = safe
	return best


static func _none() -> Dictionary:
	return { "kind": "none", "to": Vector2i.ZERO, "cat": -1 }


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
