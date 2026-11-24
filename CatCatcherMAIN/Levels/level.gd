@tool
extends Node2D
## 关卡场景。**用 Godot 原生编辑方式做关卡**：
##   1. 把 Characters/ 里的单位场景拖进来（Cats/ 、Dogs/ 、Meat/ 、Objects/）；
##   2. 往格子上随便扔 —— 本脚本每帧把单位吸到格心，摆歪了自己跳回去；
##   3. 做下一关：在 FileSystem 里右键这个 .tscn → 复制（Ctrl+D），改名，挪几个单位；
##   4. 新增的关卡在 Levels/levels.gd 的 SCENES 里加一行，否则游戏不会加载它。
##
## ⚠️【单位类型不是导出属性，是从场景路径推出来的】（和隔壁按 Heros/Enemys 判阵营同一路数）：
##     Characters/Cats/cat_rook.tscn   -> kind=cat,  type=rook
##     Characters/Dogs/dog_stray.tscn  -> kind=dog,  type=stray
##     Characters/Meat/*               -> kind=meat
##     Characters/Objects/*            -> kind=obstacle
##   所以**别随手重命名文件或挪文件夹** —— 那会直接改掉这个单位的语义。
##
## 运行时本节点会被 board 实例化到场景树里，单位节点由 board 同步位置；编辑器里才画格子向导。

const GUIDE_FILL := Color(0.35, 0.55, 0.85, 0.10)
const GUIDE_LINE := Color(0.55, 0.72, 0.95, 0.55)
const GUIDE_EDGE := Color(0.75, 0.88, 1.0, 0.85)

@export var level_id: int = 1
@export var level_name: String = ""
@export var max_turns: int = 12
@export var grid_w: int = 6
@export var grid_h: int = 6

var _cell_size: int = 64
var _origin := Vector2i.ZERO
var _geometry_ready := false


func _ready() -> void:
	_ensure_geometry()
	if Engine.is_editor_hint():
		queue_redraw()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	for node in unit_nodes():
		var target := cell_to_pos(pos_to_cell(node.position))
		if not node.position.is_equal_approx(target):
			node.position = target
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var size := float(_cell_size)
	var rect := Rect2(Vector2(_origin), Vector2(grid_w, grid_h) * size)
	draw_rect(rect, GUIDE_FILL, true)
	for i in range(grid_w + 1):
		var x: float = float(_origin.x) + float(i) * size
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), GUIDE_LINE, 1.0)
	for j in range(grid_h + 1):
		var y: float = float(_origin.y) + float(j) * size
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GUIDE_LINE, 1.0)
	draw_rect(rect, GUIDE_EDGE, false, 2.0)


# ------------------------------------------------------------ 收集单位 ----

## 摆在本场景里的所有单位节点（只认"来自 Characters/ 的场景实例"）。
func unit_nodes() -> Array:
	var out: Array = []
	for child in get_children():
		if child is Node2D and not String(child.scene_file_path).is_empty() \
				and String(child.scene_file_path).contains("/Characters/"):
			out.append(child)
	return out


## [{ "kind", "type", "cell": Vector2i, "node": Node2D }]，顺序 = 子节点顺序。
## board 靠这个顺序把 cats 下标和场景节点对上，所以**别在运行时重排子节点**。
func collect_units() -> Array:
	var out: Array = []
	for node in unit_nodes():
		var info := classify(String(node.scene_file_path))
		out.append({
			"kind": String(info["kind"]),
			"type": String(info["type"]),
			"cell": pos_to_cell(node.position),
			"node": node,
		})
	return out


## 纯数据版（不要节点）。
func collect() -> Dictionary:
	var cats: Array = []
	var obstacles: Array = []
	var dog := {}
	var meat := Vector2i(-1, -1)

	for u in collect_units():
		match String(u["kind"]):
			"cat":
				cats.append({ "type": u["type"], "pos": u["cell"] })
			"dog":
				if dog.is_empty():
					dog = { "type": u["type"], "pos": u["cell"] }
				else:
					push_warning("关卡里放了不止一只狗，只认第一只: " + name)
			"meat":
				meat = u["cell"]
			"obstacle":
				obstacles.append(u["cell"])
			_:
				push_warning("认不出的单位，已忽略: " + String(u["kind"]))

	if meat.x < 0:
		push_warning("关卡没有肉: " + name)
	if dog.is_empty():
		push_warning("关卡没有狗: " + name)

	return {
		"id": level_id,
		"name": level_name,
		"max_turns": max_turns,
		"w": grid_w,
		"h": grid_h,
		"meat": meat,
		"dog": dog,
		"cats": cats,
		"obstacles": obstacles,
	}


## 场景路径 -> { kind, type }。文件夹和文件名就是这份数据本身，不另存一份。
static func classify(path: String) -> Dictionary:
	var stem := path.get_file().get_basename()
	if path.contains("/Cats/"):
		return { "kind": "cat", "type": stem.trim_prefix("cat_") }
	if path.contains("/Dogs/"):
		return { "kind": "dog", "type": stem.trim_prefix("dog_") }
	if path.contains("/Meat/"):
		return { "kind": "meat", "type": "" }
	if path.contains("/Objects/"):
		return { "kind": "obstacle", "type": "" }
	return { "kind": "", "type": "" }


# ---------------------------------------------------------------- 坐标 ----

## ⚠️ 必须惰性初始化：Levels.build() 只 instantiate() 不进场景树，_ready() 不会跑，
## 那时候要是直接算坐标，格子原点还是 (0,0)，所有单位会整体偏掉。
func _ensure_geometry() -> void:
	if _geometry_ready:
		return
	_read_geometry()
	_geometry_ready = true


func pos_to_cell(p: Vector2) -> Vector2i:
	_ensure_geometry()
	var local := p - Vector2(_origin)
	var c := Vector2i(int(floor(local.x / _cell_size)), int(floor(local.y / _cell_size)))
	return Vector2i(clampi(c.x, 0, grid_w - 1), clampi(c.y, 0, grid_h - 1))


func cell_to_pos(cell: Vector2i) -> Vector2:
	_ensure_geometry()
	return Vector2(_origin) + Vector2(cell) * _cell_size + Vector2(_cell_size, _cell_size) * 0.5


func _read_geometry() -> void:
	var cfg := Level.load_config()
	if cfg.is_empty():
		return
	_cell_size = int(cfg["board"]["cell_size"])
	var o: Array = cfg["board"]["origin"]
	_origin = Vector2i(int(o[0]), int(o[1]))
