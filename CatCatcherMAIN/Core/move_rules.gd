class_name MoveRules
extends RefCounted
## 走法 = 控制范围 —— 同一个函数出同一份格子集合，绝不拆成两套（ARCHITECTURE 第 1 节）。
##
## 纯计算：只吃 GameState，不碰节点。求解器（M3）要在没有场景树的情况下跑几十万次，
## Core 里一旦出现 get_node / await，这个文件就永远搬不进求解器了。
##
## ⚠️ 控制范围**不受其他单位阻挡**（纯几何，只有障碍和出界能挡）。
## 理由：玩家要在棋盘上读到稳定的色块，车速不该因为自家猫站位变化而忽长忽短。
## 这条是待确认项，见 ARCHITECTURE 第 10 节第 4 条。

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


## 这只猫的控制范围（= 走法的几何基础）。不含自己所在的格。
## 障碍格和出界会挡住直线；其他单位不挡。
static func reach_cells(state: GameState, cat_index: int) -> Array:
	assert(false, "TODO(M1): MoveRules.reach_cells(%d)" % cat_index)
	return []


## 实际可走的格 = 控制范围 - 墙 - 被其他猫占据的格。
## 这层过滤与猫的类型无关，所以直接写死，不用等 reach_cells 实现。
static func legal_moves(state: GameState, cat_index: int) -> Array:
	var out := []
	for cell in reach_cells(state, cat_index):
		if state.is_wall(cell):
			continue
		if state.cat_at(cell) != -1:
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
