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
##
## avoid_sacrifice：**优先给不送子的路线**。送子 = 那回合有猫被狗吃掉、靠 Respawn 复活到出生点。
## 玩家反馈"送掉再复活"的将杀没有策略感，所以先整轮禁掉送子；只有干净路线压根不存在时，
## 才退回允许送子（否则某些局面会一点提示都给不出）。两轮共用一个预算，最坏开销不变。
static func find_line(state: GameState, config: Dictionary, max_depth: int = DEFAULT_DEPTH, node_budget: int = DEFAULT_BUDGET, avoid_sacrifice: bool = true) -> Array:
	var passes: Array = [true, false] if avoid_sacrifice else [false]
	for ban in passes:
		# ponytail: 每轮各给一份预算 —— 共用一份的话，第一轮烧完会让第二轮（兜底）直接空手而归，
		# 提示就没了。代价是不送子路线不存在时最坏开销翻倍（200k -> 400k 节点，仍是有界的）。
		var budget := [node_budget]
		var seen := {}
		for depth in range(1, max_depth + 1):
			seen.clear()
			var line := _search(state.clone(), config, depth, seen, budget, bool(ban))
			if not line.is_empty():
				return line
			if int(budget[0]) <= 0:
				break      # 预算烧完了，再加深也没意义（这一轮放弃，走下一轮）
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

static func _search(state: GameState, config: Dictionary, depth: int, seen: Dictionary, budget: Array, ban_sacrifice: bool) -> Array:
	if depth <= 0 or int(budget[0]) <= 0:
		return []

	for i in state.cats.size():
		var from: Vector2i = state.cats[i]["pos"]
		for cell in MoveRules.legal_moves(state, i):
			budget[0] = int(budget[0]) - 1
			if int(budget[0]) <= 0:
				return []

			var sim := state.clone()
			var result := Rules.apply_turn(sim, config, i, cell)
			var outcome := String(result["outcome"])
			var step := { "cat": [from.x, from.y], "to": [cell.x, cell.y] }

			# 赢棋那一步不查送子：最后一下结束对局，玩家不会觉得那是"送"
			if outcome == Rules.WON:
				return [step]
			if outcome == Rules.LOST:
				continue
			if ban_sacrifice and bool(result.get("cat_lost", false)):
				continue

			# 同一局面在更少剩余步数下已经展开过，就没必要再来一遍
			var key := _fingerprint(sim)
			if seen.has(key) and int(seen[key]) >= depth - 1:
				continue
			seen[key] = depth - 1

			var tail := _search(sim, config, depth - 1, seen, budget, ban_sacrifice)
			if not tail.is_empty():
				return ([step] + tail)

	return []


## 状态指纹：猫按顺序取位置（叠放时也能区分），外加狗的位置、低吼状态、回合数。
## ⚠️ growling 必须进指纹 —— 否则"低吼过/没低吼过"两种局面会被当成同一个而错误剪枝。
static func _fingerprint(state: GameState) -> String:
	var parts := PackedStringArray()
	for c in state.cats:
		var p: Vector2i = c["pos"]
		parts.append("%d,%d" % [p.x, p.y])
	parts.append("d%d,%d" % [state.dog["pos"].x, state.dog["pos"].y])
	parts.append("g%d" % int(state.growling))
	parts.append("t%d" % state.turn)
	return "|".join(parts)
