class_name Solver
extends RefCounted
## 关卡求解器：迭代加深 DFS，返回**最短**的赢棋路线。
##
## 两个用途（ARCHITECTURE 里写死了必须共用一份）：
##   ① 启动时验证每关有解 —— 无解就报错，别让玩家撞进死局；
##   ② 提示系统 —— 从**当前局面**重算下一步，所以玩家走错路也还能拿到正确提示。
##
## 和实战共用 Rules.apply_turn，所以搜出来的路线实战一定走得通。
##
## ⚠️ 狗是确定性的，分支只来自玩家一侧（每只猫 × 它的可走格数）。深度一上去就是指数爆炸，
## 所以必须带 node_budget：宁可报"搜不到"，也不要卡死浏览器。

## 一条路线 = [{ "cat": [x, y], "to": [x, y] }, ...]，格式和关卡 JSON 里的 solution/hint 一致
const DEFAULT_DEPTH := 4
const DEFAULT_BUDGET := 200000


## 找一条最短赢棋路线。找不到（或超预算）返回 []。
static func find_line(state: GameState, config: Dictionary, max_depth: int = DEFAULT_DEPTH, node_budget: int = DEFAULT_BUDGET) -> Array:
	var budget := [node_budget]
	var seen := {}
	for depth in range(1, max_depth + 1):
		seen.clear()
		var line := _search(state.clone(), config, depth, seen, budget)
		if not line.is_empty():
			return line
		if int(budget[0]) <= 0:
			return []      # 预算烧完了，再加深也没意义
	return []


## 只要第一步（提示用）。找不到返回 {}。
static func first_step(state: GameState, config: Dictionary, max_depth: int = DEFAULT_DEPTH) -> Dictionary:
	var line := find_line(state, config, max_depth)
	if line.is_empty():
		return {}
	return line[0]


static func is_solvable(state: GameState, config: Dictionary, max_depth: int = DEFAULT_DEPTH) -> bool:
	return not find_line(state, config, max_depth).is_empty()


# ---------------------------------------------------------------- 内部 ----

static func _search(state: GameState, config: Dictionary, depth: int, seen: Dictionary, budget: Array) -> Array:
	if depth <= 0 or int(budget[0]) <= 0:
		return []

	for i in state.cats.size():
		var from: Vector2i = state.cats[i]["pos"]
		for cell in MoveRules.legal_moves(state, i):
			budget[0] = int(budget[0]) - 1
			if int(budget[0]) <= 0:
				return []

			var sim := state.clone()
			var outcome := String(Rules.apply_turn(sim, config, i, cell)["outcome"])
			var step := { "cat": [from.x, from.y], "to": [cell.x, cell.y] }

			if outcome == Rules.WON:
				return [step]
			if outcome == Rules.LOST:
				continue

			# 同一局面在更少剩余步数下已经展开过，就没必要再来一遍
			var key := _fingerprint(sim)
			if seen.has(key) and int(seen[key]) >= depth - 1:
				continue
			seen[key] = depth - 1

			var tail := _search(sim, config, depth - 1, seen, budget)
			if not tail.is_empty():
				return ([step] + tail)

	return []


## 状态指纹：猫按顺序取位置（叠放时也能区分），外加狗、肉 HP、回合数。
static func _fingerprint(state: GameState) -> String:
	var parts := PackedStringArray()
	for c in state.cats:
		var p: Vector2i = c["pos"]
		parts.append("%d,%d" % [p.x, p.y])
	parts.append("d%d,%d" % [state.dog["pos"].x, state.dog["pos"].y])
	parts.append("h%d" % state.meat_hp)
	parts.append("t%d" % state.turn)
	return "|".join(parts)
