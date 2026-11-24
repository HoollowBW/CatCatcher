class_name Encircle
extends RefCounted
## 狗的所有合法动作 + 围死判定。纯计算，不碰节点。
##
## 【核心机制，定稿】控制 = 硬阻挡：狗**不能**走进被任意一只猫控制的格。
## 于是「封死它的所有去路」是字面意思：
##   围死 = 合法动作为空 = 相邻没有空格 且 相邻没有猫。

## 枚举狗这一回合的所有合法动作。
## 返回：[{ "kind": "move" | "flick", "to": Vector2i, "cat": int }]
##   move  走到 to（空格、未被控制、不是肉的格）
##   flick 撞飞 cat（相邻的猫），本回合不移动
## 顺序由方向表决定 => 确定性，AI 和求解器都依赖这一点。
static func legal_actions(state: GameState) -> Array:
	var out := []
	var controlled := MoveRules.controlled_cells(state)
	var dog: Vector2i = state.dog["pos"]

	for dir in MoveRules.ORTHO_DIRS:
		var cell: Vector2i = dog + dir
		if state.is_wall(cell):
			continue

		var cat_index := state.cat_at(cell)
		if cat_index != -1:
			out.append({ "kind": "flick", "to": cell, "cat": cat_index })
			continue

		if cell == state.meat_pos:
			continue          # 肉自己占一格，狗只能相邻啃食
		if controlled.has(cell):
			continue          # 控制 = 硬阻挡

		out.append({ "kind": "move", "to": cell, "cat": -1 })

	return out


## 围死判定。独立成函数是硬要求 —— 求解器（M3）要直接调它。
static func is_encircled(state: GameState) -> bool:
	return legal_actions(state).is_empty()
