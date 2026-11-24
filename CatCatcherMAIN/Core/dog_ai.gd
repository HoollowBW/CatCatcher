class_name DogAI
extends RefCounted
## 狗每回合的行为决策。纯计算，不碰节点。
##
## 【硬规矩 1】实战和「敌方行动预览」必须调**同一个函数**（ARCHITECTURE 6.2）。
## 【硬规矩 2】全确定性，不许掷随机（6.3）。同分一律按方向表顺序取第一个。
##
## 只有一种狗（野狗，贪心朝肉走）。决策优先级：
##   ① 贴着肉格 => 肉格有猫就吃掉它 / 低吼过就吃肉 / 否则低吼（吃肉前摇）
##   ② 朝肉方向那一格能走 => 走
##   ③ 朝肉方向那一格是吃得掉的猫 => 吃掉它（吃子 = 移动到那格）
##   ④ 退而求其次：走向离肉最近的可走格
##   ⑤ 还有吃得掉的猫 => 随便吃一只（有动作就不算围死）
##   ⑥ 什么都不能做 => 围死，玩家赢
##
## 返回 { "kind": String, "to": Vector2i, "cat": int }
##   "eat"：吃到肉（玩家输，由 Rules 结算）
##   "growl"：低吼，本回合不动
##   "move" / "flick" / "none"

static func plan(state: GameState) -> Dictionary:
	if Encircle.legal_actions(state).is_empty():
		return _none()

	# ① 贴着肉格：一切以肉优先
	var meat := Encircle.meat_action(state)
	if not meat.is_empty():
		return meat

	var movable: Array = Encircle.movable_cells(state)
	var preferred := _preferred_step(state)

	if preferred.x >= 0:
		# ③ 朝肉那格蹲着吃得掉的猫 => 吃掉它（吃子会移动到那格，等于前进一格）
		var blocker := state.cat_at(preferred)
		if blocker != -1 and not MoveRules.is_protected(state, blocker):
			return { "kind": "flick", "to": preferred, "cat": blocker }
		# ② 那格能走就走进
		if movable.has(preferred):
			return { "kind": "move", "to": preferred, "cat": -1 }

	# ④ 朝肉的路被控制挡住 => 挑离肉最近的可走格
	if not movable.is_empty():
		return { "kind": "move", "to": _closest_to_meat(state, movable), "cat": -1 }

	# ⑤ 走不了但吃得掉 => 吃一只（否则会被误判成围死）
	var flicks := Encircle.flickable_cats(state)
	if not flicks.is_empty():
		return { "kind": "flick", "to": flicks[0]["cell"], "cat": flicks[0]["cat"] }

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
