class_name Respawn
extends RefCounted
## 「撞飞 / 扫中之后猫去哪」—— 动态投放到离主战场最远的格（ARCHITECTURE 8.1）。
##
## 纯计算，不碰节点。**必须确定性**：同分按固定顺序取，绝不掷随机 ——
## 一旦随机，预览和实战就对不上，玩家会觉得游戏在骗人（ARCHITECTURE 5.3）。

## 主战场 = {狗, 肉}。越靠近这两样，越不该作为投放点。
static func pick_cell(state: GameState) -> Vector2i:
	var best_empty := Vector2i(-1, -1)
	var best_empty_score := -1

	var best_any := Vector2i(-1, -1)
	var best_any_crowd := 1 << 30
	var best_any_score := -1

	# 遍历顺序固定为 先 y 后 x，配合严格大于比较 => 同分时取第一个，结果确定
	for y in state.h:
		for x in state.w:
			var cell := Vector2i(x, y)
			if state.is_blocked(cell):
				continue
			if cell == state.dog["pos"]:
				continue

			var score := _focus_distance(state, cell)
			var crowd := _cat_count(state, cell)

			if crowd == 0 and score > best_empty_score:
				best_empty = cell
				best_empty_score = score

			if crowd < best_any_crowd or (crowd == best_any_crowd and score > best_any_score):
				best_any = cell
				best_any_crowd = crowd
				best_any_score = score

	# 有空位就投到最远的空格；棋盘满了才允许堆叠（挑当前猫最少的格）
	if best_empty.x >= 0:
		return best_empty
	if best_any.x >= 0:
		return best_any

	# 理论上到不了：棋盘上至少有一格（狗自己那格之外）可以放
	return Vector2i.ZERO


static func _focus_distance(state: GameState, cell: Vector2i) -> int:
	return min(_manhattan(cell, state.dog["pos"]), _manhattan(cell, state.meat_pos))


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _cat_count(state: GameState, cell: Vector2i) -> int:
	var n := 0
	for cat in state.cats:
		if cat["pos"] == cell:
			n += 1
	return n
