class_name DogAI
extends RefCounted
## 狗每回合的行为决策。纯计算，不碰节点。
##
## 【硬规矩 1】实战和「敌方行动预览」必须调**同一个函数**（ARCHITECTURE 5.2）。
##   预览 = DogAI.plan(某个副本)，实战 = DogAI.plan(真身)，就这一行差别。
##   另写一套预测逻辑的下场：预览和实战对不上，玩家觉得游戏在骗人。
## 【硬规矩 2】全确定性，不许掷随机（5.3）。同分一律按方向表顺序取第一个。
##
## 返回 { "kind": String, "to": Vector2i, "cat": int }
##   "eat"   相邻啃肉（优先于移动），to = 肉所在格，cat = -1
##   "move"  朝肉推进一格，to = 目标格，cat = -1
##   "flick" 前进方向被猫挡住 -> 撞飞它（动态投放），本回合不移动，cat = 猫下标
##   "none"  围死，无动作
##
## 狗类型：
##   stray  野狗，贪心走法（直接挑离肉最近的合法格）
##   collie 边牧，BFS 绕开障碍走最短路

static func plan(state: GameState) -> Dictionary:
	var actions := Encircle.legal_actions(state)
	if actions.is_empty():
		return _none()

	# ① 啃食优先于移动
	if _can_bite(state):
		return { "kind": "eat", "to": state.meat_pos, "cat": -1 }

	var moves := []
	var flicks := []
	for a in actions:
		if String(a["kind"]) == "move":
			moves.append(a)
		else:
			flicks.append(a)

	# ② 能走就走（朝肉推进）
	if not moves.is_empty():
		return _best_move(state, moves)

	# ③ 走不动但旁边有猫 -> 撞飞
	if not flicks.is_empty():
		return _best_flick(state, flicks)

	return _none()


static func _none() -> Dictionary:
	return { "kind": "none", "to": Vector2i.ZERO, "cat": -1 }


## 狗正交贴着肉 = 可以啃
static func _can_bite(state: GameState) -> bool:
	return _manhattan(state.dog["pos"], state.meat_pos) == 1


static func _best_move(state: GameState, moves: Array) -> Dictionary:
	# 边牧：先算真实最短路的第一步，那一步合法就直接走
	if String(state.dog.get("type", "stray")) == "collie":
		var step := _bfs_first_step(state)
		if step.x >= 0:
			for a in moves:
				if a["to"] == step:
					return a

	# 野狗 / 边牧兜底：挑离肉最近的合法格
	var best: Dictionary = moves[0]
	var best_d := _manhattan(best["to"], state.meat_pos)
	for a in moves:
		var d := _manhattan(a["to"], state.meat_pos)
		if d < best_d:
			best_d = d
			best = a
	return best


## 撞飞"最靠近肉"的那只猫；同距离时取下标小的，保证确定性
static func _best_flick(state: GameState, flicks: Array) -> Dictionary:
	var best: Dictionary = flicks[0]
	var best_d := _manhattan(best["to"], state.meat_pos)
	for a in flicks:
		var d := _manhattan(a["to"], state.meat_pos)
		if d < best_d or (d == best_d and int(a["cat"]) < int(best["cat"])):
			best_d = d
			best = a
	return best


## 从狗出发 BFS 到"肉的相邻格"，返回最短路的第一步。走不通返回 (-1, -1)。
## 路径上不考虑猫的控制（控制由 legal_actions 处理），但猫本身和肉格不能穿过。
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
