class_name GameState
extends RefCounted
## 一局的完整可变状态。
##
## 悔棋 / 敌方行动预览 / 求解器（M3）全部在它的**副本**上试算，绝不动真身。
## 悔棋就是一坨快照字典，不许写"反向操作"来撤销（ARCHITECTURE 5.1）。
##
## 坐标一律 Vector2i(x = 列, y = 行)，左上角 (0, 0)。

var w: int = 6
var h: int = 6

## 猫：[{ "type": String, "pos": Vector2i, "home": Vector2i }]
## 用裸 Array 而不是 Array[Dictionary]：快照要 duplicate(true) 深拷贝，
## 类型化数组在 restore 时会因 Array != Array[Dictionary] 而报类型错。
var cats: Array = []

## 狗：{ "type": String, "pos": Vector2i }
var dog: Dictionary = {}

var meat_pos := Vector2i.ZERO
var meat_hp: int = 0

## 障碍格（Vector2i 数组）。关卡内恒定，所以不进快照。
var obstacles: Array = []

var turn: int = 0
var max_turns: int = 0


## 只拍**会变**的东西。w/h/obstacles/max_turns 在一关内恒定，不进快照。
func snapshot() -> Dictionary:
	return {
		"cats": cats.duplicate(true),
		"dog": dog.duplicate(true),
		"meat_pos": meat_pos,
		"meat_hp": meat_hp,
		"turn": turn,
	}


func restore(snap: Dictionary) -> void:
	cats = snap["cats"].duplicate(true)
	dog = snap["dog"].duplicate(true)
	meat_pos = snap["meat_pos"]
	meat_hp = snap["meat_hp"]
	turn = snap["turn"]


## 试算用副本：预览和求解器都拿它跑，跑完直接丢掉。
func clone() -> GameState:
	var c := GameState.new()
	c.w = w
	c.h = h
	c.obstacles = obstacles.duplicate()
	c.max_turns = max_turns
	c.restore(snapshot())
	return c


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < w and cell.y < h


## 出界或障碍 = 地形上不能站
func is_wall(cell: Vector2i) -> bool:
	return not in_bounds(cell) or obstacles.has(cell)


## 谁都不能站的格 = 地形墙 + 肉所在格。
## 肉自己占一格，狗只能"相邻啃食"，不能站上去；猫也一样，否则肉会被走法色块盖住。
func is_blocked(cell: Vector2i) -> bool:
	return is_wall(cell) or cell == meat_pos


## 该格上的猫下标；没有返回 -1
func cat_at(cell: Vector2i) -> int:
	for i in cats.size():
		if cats[i]["pos"] == cell:
			return i
	return -1


func dog_at() -> Vector2i:
	return dog["pos"]
