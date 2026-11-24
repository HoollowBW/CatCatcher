class_name Level
extends RefCounted
## 关卡数据 + JSON 读取。纯数据，不碰节点。

const LEVEL_DIR := "res://CatCatcherMAIN/Data/levels/"
const CONFIG_PATH := "res://CatCatcherMAIN/Data/game_config.json"

## 关卡顺序 = 通关顺序。加关卡时这里和 _EXPORT_DEPS 各补一行。
const LEVEL_PATHS := [
	"res://CatCatcherMAIN/Data/levels/level_01.json",
	"res://CatCatcherMAIN/Data/levels/level_02.json",
	"res://CatCatcherMAIN/Data/levels/level_03.json",
]

## ⚠️ 这一坨别删，它不是死代码。
## 实测两件事（别再重走一遍弯路）：
##   1. `include_filter="*.json"` 在 headless 导出里**不生效** —— 放个 *.txt 进去也照样不进 pck；
##   2. 只有被静态 preload 的 JSON 才会被打进 pck，而且是**烧进 GDScript 编译块**里，
##      并不会在 pck 里留下一个 res://.../x.json 文件。所以 FileAccess.get_file_as_string()
##      在 web 版必然读不到 —— 必须走 load()/preload 这条资源加载路径（见 read_json）。
## 新增关卡时在这里补一行，否则 web 版会读不到那一关。
const _EXPORT_DEPS := [
	preload("res://CatCatcherMAIN/Data/game_config.json"),
	preload("res://CatCatcherMAIN/Data/levels/level_01.json"),
	preload("res://CatCatcherMAIN/Data/levels/level_02.json"),
	preload("res://CatCatcherMAIN/Data/levels/level_03.json"),
]

var id: int = 0
var display_name: String = ""
var w: int = 6
var h: int = 6
var meat_pos := Vector2i.ZERO
var dog_type: String = "stray"
var dog_pos := Vector2i.ZERO

## [{ "type": String, "pos": Vector2i }]
var cat_spawns: Array = []

## Vector2i 数组
var obstacles: Array = []

## 提示序列，元素 { "cat": [x,y], "to": [x,y] }。前几关教学用，空数组 = 交给求解器（M3）
var hint: Array = []

## 参考解法，元素同 hint 格式。**只给自检和求解器验收用，不展示给玩家**。
## 每关必须有一条能走通的解法，selftest 会照着重放一遍 —— 这是关卡不会变成死局的保证。
var solution: Array = []

var max_turns: int = 12


static func count() -> int:
	return LEVEL_PATHS.size()


static func path_at(index: int) -> String:
	if index < 0 or index >= LEVEL_PATHS.size():
		return ""
	return LEVEL_PATHS[index]


static func from_index(index: int) -> Level:
	var p := path_at(index)
	if p.is_empty():
		push_error("关卡下标越界: %d" % index)
		return null
	return from_file(p)


## 启动时把关卡全部验一遍：每关必须有解，而且开局不能已经是围死（那是白送）。
## 返回问题描述数组，空 = 全部正常。用 Solver 真搜，不是读 solution 糊弄。
static func validate_all(config: Dictionary) -> Array:
	var problems: Array = []
	var depth := int(config.get("solver", {}).get("validate_depth", Solver.DEFAULT_DEPTH))

	for i in count():
		var lv := from_index(i)
		if lv == null:
			problems.append("关卡 %d 加载失败" % (i + 1))
			continue

		var st := lv.to_state(config)
		if Encircle.is_encircled(st):
			problems.append("关卡 %d「%s」开局就是围死，等于白送" % [i + 1, lv.display_name])
			continue
		if not Solver.is_solvable(st, config, depth):
			problems.append("关卡 %d「%s」在 %d 步内搜不到解" % [i + 1, lv.display_name, depth])
	return problems


## 读一个 JSON 成 Dictionary。
## 【只能走 load()，不能用 FileAccess】—— 原因见上面 _EXPORT_DEPS 的注释。
## 读不到/解析失败就 push_error 返回 {}，让上层显式判空。
static func read_json(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		push_error("找不到数据文件: %s" % path)
		return {}
	var res = load(path)
	if res is JSON and res.data is Dictionary:
		return res.data
	push_error("JSON 解析失败（不是对象）: %s" % path)
	return {}


static func load_config() -> Dictionary:
	return read_json(CONFIG_PATH)


static func from_file(path: String) -> Level:
	var d := read_json(path)
	if d.is_empty():
		return null

	var lv := Level.new()
	lv.id = int(d.get("id", 0))
	lv.display_name = String(d.get("name", ""))

	var grid: Dictionary = d.get("grid", {})
	lv.w = int(grid.get("w", 6))
	lv.h = int(grid.get("h", 6))

	lv.meat_pos = _to_cell(d.get("meat", [0, 0]))

	var dog: Dictionary = d.get("dog", {})
	lv.dog_type = String(dog.get("type", "stray"))
	lv.dog_pos = _to_cell(dog.get("pos", [0, 0]))

	for c in d.get("cats", []):
		lv.cat_spawns.append({
			"type": String(c.get("type", "pawn")),
			"pos": _to_cell(c.get("pos", [0, 0])),
		})

	for o in d.get("obstacles", []):
		lv.obstacles.append(_to_cell(o))

	lv.hint = d.get("hint", [])
	lv.solution = d.get("solution", [])
	lv.max_turns = int(d.get("max_turns", 12))
	return lv


## [x, y] -> Vector2i。JSON 里坐标是数组，不是对象 —— 别写反。
static func _to_cell(arr) -> Vector2i:
	if typeof(arr) != TYPE_ARRAY or arr.size() < 2:
		push_error("坐标格式错误，应为 [x, y]：%s" % str(arr))
		return Vector2i.ZERO
	return Vector2i(int(arr[0]), int(arr[1]))


## 关卡 + 全局配置 -> 开局状态。肉的 HP 来自 config，不从关卡读。
func to_state(config: Dictionary) -> GameState:
	var s := GameState.new()
	s.w = w
	s.h = h
	s.obstacles = obstacles.duplicate()
	s.max_turns = max_turns
	s.meat_pos = meat_pos
	s.meat_hp = int(config.get("meat", {}).get("max_hp", 20))
	s.turn = 0

	s.dog = { "type": dog_type, "pos": dog_pos }

	s.cats.clear()
	for spawn in cat_spawns:
		s.cats.append({
			"type": spawn["type"],
			"pos": spawn["pos"],
		})
	return s
