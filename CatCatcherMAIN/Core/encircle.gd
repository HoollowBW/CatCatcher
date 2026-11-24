class_name Encircle
extends RefCounted
## 狗的动作表 + 围死判定。纯计算，不碰节点。
##
## 【核心机制】控制 = 硬阻挡：狗不能走进被任意一只猫控制的格。
## 【撞飞 = 吃子】狗吃掉相邻的**未受保护**的猫，并移动到那一格（受保护 = 撞不动）。
## 【肉】狗贴着肉格时永远有动作：
##     肉格空 + 没低吼  -> 低吼
##     肉格空 + 已低吼  -> 吃到肉（玩家输）
##     肉格上有猫       -> 吃掉那只猫（站肉格的猫永不受保护），狗停在原地、低吼清零
##    ⇒ 所以**狗一旦贴身，就再也围不死了**，玩家必须在它离肉 ≥2 格时动手。
##
## 【围死 = 狗没有任何合法动作】走、吃子、对肉动作都算动作。这是新的胜利条件。

## 狗能走进去的格：空、未被控制、不是肉格、不在墙上。
## 注意肉格不在这里 —— 进肉格是"吃到肉"，属于对肉动作（见 meat_action）。
static func movable_cells(state: GameState) -> Array:
	var out := []
	var controlled := MoveRules.controlled_cells(state)
	var dog: Vector2i = state.dog["pos"]

	for dir in MoveRules.ORTHO_DIRS:
		var cell: Vector2i = dog + dir
		if state.is_wall(cell):
			continue
		if cell == state.meat_pos:
			continue
		if state.cat_at(cell) != -1:
			continue
		if controlled.has(cell):
			continue
		out.append(cell)

	return out


## 相邻的、**吃得掉**的猫（没被别的猫保护）。顺序由方向表决定 => 确定性。
## 站肉格的猫永远可吃（MoveRules.is_protected 里已经把这条写死了）。
static func flickable_cats(state: GameState) -> Array:
	var out := []
	var dog: Vector2i = state.dog["pos"]
	for dir in MoveRules.ORTHO_DIRS:
		var cell: Vector2i = dog + dir
		if state.is_wall(cell):
			continue
		var cat_index := state.cat_at(cell)
		if cat_index == -1:
			continue
		if MoveRules.is_protected(state, cat_index):
			continue
		out.append({ "cat": cat_index, "cell": cell })
	return out


## 这只猫现在能不能被吃（相邻 + 没被保护）
static func is_flickable(state: GameState, cat_index: int) -> bool:
	if cat_index < 0 or cat_index >= state.cats.size():
		return false
	var cell: Vector2i = state.cats[cat_index]["pos"]
	if MoveRules.is_protected(state, cat_index):
		return false
	return _manhattan(cell, state.dog["pos"]) == 1


## 狗贴着肉格时"对肉"的动作。不贴肉返回 {}。
## 返回 { "kind": "growl" / "eat" / "flick", "to": Vector2i, "cat": int }
static func meat_action(state: GameState) -> Dictionary:
	var dog: Vector2i = state.dog["pos"]
	if _manhattan(dog, state.meat_pos) != 1:
		return {}

	var blocker := state.cat_at(state.meat_pos)
	if blocker != -1:
		return { "kind": "flick", "to": state.meat_pos, "cat": blocker }
	if state.growling:
		return { "kind": "eat", "to": state.meat_pos, "cat": -1 }
	return { "kind": "growl", "to": dog, "cat": -1 }


## 给表现层用的完整动作表（走 + 吃子 + 对肉）。
## 这**就是**围死判定的依据：空表才算玩家赢。
static func legal_actions(state: GameState) -> Array:
	var out := []
	for cell in movable_cells(state):
		out.append({ "kind": "move", "to": cell, "cat": -1 })
	for flick in flickable_cats(state):
		out.append({ "kind": "flick", "to": flick["cell"], "cat": flick["cat"] })
	var meat := meat_action(state)
	if not meat.is_empty() and String(meat["kind"]) != "flick":
		out.append(meat)
	return out


## 围死判定 = 狗没有任何合法动作。独立成函数是硬要求 —— 求解器直接调它。
static func is_encircled(state: GameState) -> bool:
	return legal_actions(state).is_empty()


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
