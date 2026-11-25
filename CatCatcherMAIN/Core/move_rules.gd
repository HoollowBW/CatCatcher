class_name MoveRules
extends RefCounted
## 走法 = 控制范围 —— 同一个函数出同一份格子集合，绝不拆成两套（ARCHITECTURE 第 5 节）。
##
## 纯计算：只吃 GameState，不碰节点。求解器要在没有场景树的情况下跑几十万次。
##
## ⚠️ 控制范围**不受其他单位阻挡**（纯几何，只有障碍 / 出界能挡）。
## ⚠️ **肉格不算控制格**，但也不阻挡车 / 象的视线 —— 肉不是单位，是地物。
## ⚠️ **站在肉格上的猫，控制范围 = 0**，但它**可以走下来**（玩家能把守肉的猫撤回）。
##    这是"走法=控制"的唯一例外，规则定稿。

const ORTHO_DIRS := [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

## 象猫的四条斜线
const DIAG_DIRS := [
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

## 马猫的 8 个日字落点（可越过单位）
const HORSE_OFFSETS := [
	Vector2i(1, -2), Vector2i(-1, -2),
	Vector2i(2, -1), Vector2i(2, 1),
	Vector2i(1, 2), Vector2i(-1, 2),
	Vector2i(-2, -1), Vector2i(-2, 1),
]


## 这只猫的控制范围（= 走法的几何基础）。**不含肉格**，不含自己所在的格，不含墙。
## 顺序是确定的（方向表顺序 + 由近及远），求解器和提示都依赖这一点。
static func reach_cells(state: GameState, cat_index: int) -> Array:
	return _geometry(state, cat_index, false)


## 实际可走的格 = 走法几何（**含**肉格）+ 排掉别的猫占的格 + 排掉狗所在的格。
## 肉格只有空着才能走上去（最多一只猫）。
static func legal_moves(state: GameState, cat_index: int) -> Array:
	var out := []
	var dog_cell: Vector2i = state.dog["pos"]
	for cell in _geometry(state, cat_index, true):
		if state.cat_at(cell) != -1:
			continue
		if cell == dog_cell:
			continue
		out.append(cell)
	return out


## 走法几何。with_meat=true 时把肉格也算进去（走法可以踩上肉格）。
static func _geometry(state: GameState, cat_index: int, with_meat: bool) -> Array:
	if cat_index < 0 or cat_index >= state.cats.size():
		return []
	var cat: Dictionary = state.cats[cat_index]
	var origin: Vector2i = cat["pos"]

	# 站在肉格上的猫：**控制范围为 0**（reach_cells 返回空），但它自己**能走下来**
	# （玩家可以把守肉的猫撤回；这是"控制=走法"的唯一例外，规则里明写）。
	if origin == state.meat_pos and not with_meat:
		return []

	match String(cat["type"]):
		"pawn":
			return _pawn_cells(state, origin, with_meat)
		"rook":
			return _line_cells(state, origin, ORTHO_DIRS, with_meat)
		"bishop":
			return _line_cells(state, origin, DIAG_DIRS, with_meat)
		"horse":
			return _horse_cells(state, origin, with_meat)

	push_error("未知的猫类型: %s" % cat["type"])
	return []


## 兵：相邻 1 格（正交）
static func _pawn_cells(state: GameState, origin: Vector2i, with_meat: bool) -> Array:
	var out := []
	for dir in ORTHO_DIRS:
		var cell: Vector2i = origin + dir
		if state.is_wall(cell):
			continue
		if cell == state.meat_pos:
			if with_meat:
				out.append(cell)
			continue
		out.append(cell)
	return out


## 车（正交）/ 象（斜线）：一路走到底，遇障碍停（那格本身也不算）。
## 肉格：可以踩（with_meat），但不计入控制范围；视线穿过它继续。
static func _line_cells(state: GameState, origin: Vector2i, dirs: Array, with_meat: bool) -> Array:
	var out := []
	for dir in dirs:
		var cell: Vector2i = origin + dir
		while not state.is_wall(cell):
			if cell == state.meat_pos:
				if with_meat:
					out.append(cell)
			else:
				out.append(cell)
			cell += dir
	return out


## 马：8 个日字落点，可越过单位；出界的丢弃
static func _horse_cells(state: GameState, origin: Vector2i, with_meat: bool) -> Array:
	var out := []
	for off in HORSE_OFFSETS:
		var cell: Vector2i = origin + off
		if state.is_wall(cell):
			continue
		if cell == state.meat_pos:
			if with_meat:
				out.append(cell)
			continue
		out.append(cell)
	return out


## 全场控制格并集（键 = Vector2i）。给「控制范围显示」和「狗不能走进」共用。
static func controlled_cells(state: GameState) -> Dictionary:
	var out := {}
	for i in state.cats.size():
		for cell in reach_cells(state, i):
			out[cell] = true
	return out


## 这只猫是否被**别的猫保护**（它所在的格落在另一只猫的控制范围内）。
## ⚠️ 站在肉格上的猫**永远不受保护** —— 站肉就是拿命换一回合，
##    否则"把兵垫到肉上"会变成无敌防守（规则定稿，别翻案）。
static func is_protected(state: GameState, cat_index: int) -> bool:
	if cat_index < 0 or cat_index >= state.cats.size():
		return false
	var cell: Vector2i = state.cats[cat_index]["pos"]
	if cell == state.meat_pos:
		return false
	for i in state.cats.size():
		if i == cat_index:
			continue
		if reach_cells(state, i).has(cell):
			return true
	return false
