class_name MoveRules
extends RefCounted
## 走法 = 控制范围 —— 同一个函数出同一份格子集合，绝不拆成两套（ARCHITECTURE 第 1 节）。
##
## 纯计算：只吃 GameState，不碰节点。求解器（M3）要在没有场景树的情况下跑几十万次，
## Core 里一旦出现 get_node / await，这个文件就永远搬不进求解器了。
##
## ⚠️ 控制范围**不受其他单位阻挡**（纯几何，只有障碍 / 出界 / 肉的格能挡）。
## 理由：玩家要在棋盘上读到稳定的色块，车速不该因为自家猫站位变化而忽长忽短。已定稿。

## 四个正交方向
const ORTHO_DIRS := [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

## 马猫的 8 个日字落点（可越过单位）
const HORSE_OFFSETS := [
	Vector2i(1, -2), Vector2i(-1, -2),
	Vector2i(2, -1), Vector2i(2, 1),
	Vector2i(1, 2), Vector2i(-1, 2),
	Vector2i(-2, -1), Vector2i(-2, 1),
]


## 占用表：键 = Vector2i，值 = true。
## ignore_cat：跳过这只猫自己（它不能因为自己站着而失去走法）。
static func occupancy(state: GameState, ignore_cat: int = -1) -> Dictionary:
	var occ := {}
	for i in state.cats.size():
		if i == ignore_cat:
			continue
		occ[state.cats[i]["pos"]] = true
	return occ


## 这只猫的控制范围（= 走法的几何基础）。不含自己所在的格，不含墙和肉的格。
## 顺序是确定的（方向表顺序 + 由近及远），求解器和提示都依赖这一点，别改成无序遍历。
static func reach_cells(state: GameState, cat_index: int) -> Array:
	if cat_index < 0 or cat_index >= state.cats.size():
		return []
	var cat: Dictionary = state.cats[cat_index]
	var origin: Vector2i = cat["pos"]

	match String(cat["type"]):
		"pawn":
			return _pawn_cells(state, origin)
		"rook":
			return _line_cells(state, origin)
		"horse":
			return _horse_cells(state, origin)

	push_error("未知的猫类型: %s" % cat["type"])
	return []


## 兵：相邻 1 格（正交）
static func _pawn_cells(state: GameState, origin: Vector2i) -> Array:
	var out := []
	for dir in ORTHO_DIRS:
		var cell: Vector2i = origin + dir
		if state.is_blocked(cell):
			continue
		if cell == origin:
			continue
		out.append(cell)
	return out


## 车：整行 + 整列，遇墙/障碍/肉即停（那一格本身也不算控制）
static func _line_cells(state: GameState, origin: Vector2i) -> Array:
	var out := []
	for dir in ORTHO_DIRS:
		var cell: Vector2i = origin + dir
		while not state.is_blocked(cell):
			out.append(cell)
			cell += dir
	return out


## 马：8 个日字落点，可越过单位；出界的丢弃
static func _horse_cells(state: GameState, origin: Vector2i) -> Array:
	var out := []
	for off in HORSE_OFFSETS:
		var cell: Vector2i = origin + off
		if state.is_blocked(cell):
			continue
		out.append(cell)
	return out


## 实际可走的格 = 控制范围 - 被其他猫占据的格 - 狗所在的格。
## （墙和肉的格已经由 reach_cells 过滤掉了；狗那格也不许猫踩上去）
static func legal_moves(state: GameState, cat_index: int) -> Array:
	var out := []
	var dog_cell: Vector2i = state.dog["pos"]
	for cell in reach_cells(state, cat_index):
		if state.cat_at(cell) != -1:
			continue
		if cell == dog_cell:
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
## 国际象棋那套：被保护的棋子，狗不能撞飞。规则来源见 ARCHITECTURE。
static func is_protected(state: GameState, cat_index: int) -> bool:
	if cat_index < 0 or cat_index >= state.cats.size():
		return false
	var cell: Vector2i = state.cats[cat_index]["pos"]
	for i in state.cats.size():
		if i == cat_index:
			continue
		if reach_cells(state, i).has(cell):
			return true
	return false
