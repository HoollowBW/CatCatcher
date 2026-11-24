class_name Encircle
extends RefCounted
## 狗的去路 + 围死判定。纯计算，不碰节点。
##
## 【核心机制，定稿】控制 = 硬阻挡：狗**不能**走进被任意一只猫控制的格。
##
## 【围死 = 没有空的可走格】相邻的猫**不算逃生路**。
## 早先的写法是"没有空格且相邻没有猫"，结果四邻被猫团团围住时狗还能一直「撞飞」苟着，
## 玩家看着明明困死了却不结算 —— 那不是玩家该去理解的东西，是规则没写对。

## 狗能真正走到的格：空、未被控制、不是肉。
## **这才是"去路"**，围死判定只看它。
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


## 相邻的、**可以被撞飞**的猫。顺序由方向表决定 => 确定性。
##
## ⚠️ 被别的猫保护的猫撞不动（国际象棋的"受保护棋子"，见 ARCHITECTURE）。
## 所以站成一排互相罩着的猫，狗一只都拍不飞 —— 撞飞只对落单的猫有效。
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


## 这只猫现在能不能被撞飞（相邻 + 没被保护）
static func is_flickable(state: GameState, cat_index: int) -> bool:
	if cat_index < 0 or cat_index >= state.cats.size():
		return false
	var cell: Vector2i = state.cats[cat_index]["pos"]
	if MoveRules.is_protected(state, cat_index):
		return false
	return absi(cell.x - state.dog["pos"].x) + absi(cell.y - state.dog["pos"].y) == 1


## 围死判定。独立成函数是硬要求 —— 求解器（M3）要直接调它。
static func is_encircled(state: GameState) -> bool:
	return movable_cells(state).is_empty()


## 给表现层用的完整动作表（走 + 撞飞），用来画"威胁范围"。
## ⚠️ 不要拿它判围死 —— 里面有撞飞，那会让"被围住"永远判不出来。
static func legal_actions(state: GameState) -> Array:
	var out := []
	for cell in movable_cells(state):
		out.append({ "kind": "move", "to": cell, "cat": -1 })
	for flick in flickable_cats(state):
		out.append({ "kind": "flick", "to": flick["cell"], "cat": flick["cat"] })
	return out
