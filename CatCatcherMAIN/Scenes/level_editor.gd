@tool
extends Node2D
## 关卡编辑器（照隔壁 HollowBastion 那套「关卡场景 + @tool」的路子搬过来的，但我们要导出 JSON）。
##
## 用法：
##   1. 在 Godot 里打开本场景（CatCatcherMAIN/Scenes/level_editor.tscn）；
##   2. 把 level_marker.tscn 拖进来几个当子节点，在 Inspector 里设 kind（cat / dog / meat / obstacle）；
##      猫还要设 cat_type（rook / horse / pawn）；
##   3. 往格子上拖 —— 本节点每帧把标记物吸到格心，摆歪了自己会跳回去；
##   4. Inspector 里点「导出关卡 JSON」，写进 output_path。
##   5. 想把已有关卡改一改：把 output_path 指到那一关，点「从 JSON 载入」。
##
## ⚠️ 导出之后还要手工做一件事：把新关卡加进 Level.LEVEL_PATHS 和 Level._EXPORT_DEPS，
##    否则游戏读不到（web 版尤其 —— 那两条是 JSON 能进 pck 的唯一途径）。
##
## 编辑器里画的是和游戏**完全同一套**格子坐标（直接用 game_config.json 的 origin / cell_size），
## 所以导出出来的坐标不会整体偏移。

const MARKER_SCENE := preload("res://CatCatcherMAIN/Scenes/level_marker.tscn")

const GUIDE_FILL := Color(0.35, 0.55, 0.85, 0.10)
const GUIDE_LINE := Color(0.55, 0.72, 0.95, 0.55)
const GUIDE_EDGE := Color(0.75, 0.88, 1.0, 0.85)

@export_group("关卡属性")
@export var level_id: int = 4
@export var level_name: String = "新关卡"
@export var max_turns: int = 12
@export var dog_type: String = "stray"

@export_group("输出")
@export var output_path: String = "res://CatCatcherMAIN/Data/levels/level_04.json"

@export_group("操作")
@export_tool_button("导出关卡 JSON", "Save") var export_action: Callable = export_level
@export_tool_button("从 JSON 载入（会清掉现有标记）", "Load") var load_action: Callable = load_level

var _cell_size: int = 64
var _origin := Vector2i.ZERO
var _w: int = 6
var _h: int = 6


func _ready() -> void:
	_read_geometry()
	if Engine.is_editor_hint():
		queue_redraw()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# 把标记物吸附到格心（和隔壁一个手法：只管往哪儿扔，摆歪了自己跳回去）
	for node in _markers():
		var target := _cell_to_pos(_pos_to_cell(node.position))
		if not node.position.is_equal_approx(target):
			node.position = target
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var size := float(_cell_size)
	var rect := Rect2(Vector2(_origin), Vector2(_w, _h) * size)
	draw_rect(rect, GUIDE_FILL, true)
	for i in range(_w + 1):
		var x: float = float(_origin.x) + float(i) * size
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), GUIDE_LINE, 1.0)
	for j in range(_h + 1):
		var y: float = float(_origin.y) + float(j) * size
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GUIDE_LINE, 1.0)
	draw_rect(rect, GUIDE_EDGE, false, 2.0)


# ---------------------------------------------------------------- 导出 ----

func export_level() -> void:
	var cats: Array = []
	var obstacles: Array = []
	var dog := {}
	var meat := Vector2i(-1, -1)
	var problems: Array = []

	for node in _markers():
		var cell := _pos_to_cell(node.position)
		var pos := [cell.x, cell.y]
		match String(node.kind):
			"cat":
				cats.append({ "pos": pos, "type": String(node.cat_type) })
			"dog":
				if not dog.is_empty():
					problems.append("放了不止一只狗")
				dog = { "pos": pos, "type": dog_type }
			"meat":
				if meat.x >= 0:
					problems.append("放了不止一块肉")
				meat = cell
			"obstacle":
				obstacles.append(pos)

	if dog.is_empty():
		problems.append("没有狗")
	if meat.x < 0:
		problems.append("没有肉")
	if cats.is_empty():
		problems.append("一只猫都没有")

	if not problems.is_empty():
		for p in problems:
			push_error("[关卡编辑器] " + String(p))
		return

	var data := {
		"id": level_id,
		"name": level_name,
		"grid": { "w": _w, "h": _h },
		"meat": [meat.x, meat.y],
		"dog": dog,
		"cats": cats,
		"obstacles": obstacles,
		"hint": [],
		"solution": [],
		"max_turns": max_turns,
	}

	var f := FileAccess.open(output_path, FileAccess.WRITE)
	if f == null:
		push_error("[关卡编辑器] 写不进去: %s" % output_path)
		return
	f.store_string(JSON.stringify(data, "  ") + "\n")
	f.close()

	print("[关卡编辑器] 已写入 %s（猫 %d 只 / 障碍 %d）" % [output_path, cats.size(), obstacles.size()])
	print("[关卡编辑器] ⚠️ 记得把这一关加进 Level.LEVEL_PATHS 和 Level._EXPORT_DEPS，否则读不到")
	print("[关卡编辑器] 然后跑：godot --headless --path . --script res://tests/solvecheck.gd")


# ---------------------------------------------------------------- 载入 ----

func load_level() -> void:
	var d := Level.read_json(output_path)
	if d.is_empty():
		return

	for node in _markers():
		node.get_parent().remove_child(node)
		node.queue_free()

	_add_marker("meat", "rook", Level._to_cell(d.get("meat", [0, 0])))
	var dog: Dictionary = d.get("dog", {})
	if not dog.is_empty():
		_add_marker("dog", "rook", Level._to_cell(dog.get("pos", [0, 0])))
	for c in d.get("cats", []):
		_add_marker("cat", String(c.get("type", "pawn")), Level._to_cell(c.get("pos", [0, 0])))
	for o in d.get("obstacles", []):
		_add_marker("obstacle", "rook", Level._to_cell(o))

	level_id = int(d.get("id", level_id))
	level_name = String(d.get("name", level_name))
	max_turns = int(d.get("max_turns", max_turns))
	var dog_info: Dictionary = d.get("dog", {})
	dog_type = String(dog_info.get("type", dog_type))

	print("[关卡编辑器] 已载入 %s（%d 个标记）" % [output_path, _markers().size()])
	queue_redraw()


func _add_marker(kind: String, cat_type: String, cell: Vector2i) -> void:
	var m := MARKER_SCENE.instantiate()
	m.name = "%s_%d_%d" % [kind, cell.x, cell.y]
	m.set("kind", kind)
	m.set("cat_type", cat_type)
	m.position = _cell_to_pos(cell)
	add_child(m)
	m.owner = owner          # 让节点真的存进场景（不然只是运行时临时节点）


# ---------------------------------------------------------------- 坐标 ----

func _markers() -> Array:
	var out: Array = []
	for node in get_children():
		if node is Node2D and node.get("kind") != null:
			out.append(node)
	return out


func _read_geometry() -> void:
	var cfg := Level.load_config()
	if cfg.is_empty():
		return
	_cell_size = int(cfg["board"]["cell_size"])
	var o: Array = cfg["board"]["origin"]
	_origin = Vector2i(int(o[0]), int(o[1]))


func _pos_to_cell(p: Vector2) -> Vector2i:
	var local := p - Vector2(_origin)
	var c := Vector2i(int(floor(local.x / _cell_size)), int(floor(local.y / _cell_size)))
	return Vector2i(clampi(c.x, 0, _w - 1), clampi(c.y, 0, _h - 1))


func _cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(_origin) + Vector2(cell) * _cell_size + Vector2(_cell_size, _cell_size) * 0.5
