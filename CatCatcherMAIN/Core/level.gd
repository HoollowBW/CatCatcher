class_name Level
extends RefCounted
## 运行期关卡数据。**纯数据，不碰节点** —— GameState / Solver 都吃它。
##
## 关卡内容本身住在 `Levels/level_XX.tscn` 里（Godot 编辑器里拖放编辑，见 Levels/level.gd），
## 这里只是把那个场景收成一份纯数据。别在这儿再读文件/找节点。

const CONFIG_PATH := "res://CatCatcherMAIN/Data/game_config.json"

## ⚠️ 这一行别删：`include_filter="*.json"` 在 headless 导出里不生效，
## 只有被静态 preload 的 JSON 才会被打进 pck（而且是烧进 GDScript 编译块，pck 里没有独立文件）。
## 所以 FileAccess 读不到它，必须走 load() —— 见下面的 load_config()。
const _EXPORT_DEPS := [
	preload("res://CatCatcherMAIN/Data/game_config.json"),
]

var id: int = 0
var display_name: String = ""
var w: int = 6
var h: int = 6
var meat_pos := Vector2i.ZERO
var dog_type: String = "stray"
var dog_pos := Vector2i.ZERO

## [{ "type": String, "pos": Vector2i }]，顺序 = 关卡场景里的节点顺序
var cat_spawns: Array = []

## Vector2i 数组
var obstacles: Array = []

var max_turns: int = 12


## 读全局数值配置。走 load() 不用 FileAccess —— 原因见上面 _EXPORT_DEPS。
static func load_config() -> Dictionary:
	if not ResourceLoader.exists(CONFIG_PATH):
		push_error("找不到配置: %s" % CONFIG_PATH)
		return {}
	var res = load(CONFIG_PATH)
	if res is JSON and res.data is Dictionary:
		return res.data
	push_error("配置解析失败（不是对象）: %s" % CONFIG_PATH)
	return {}


## 从 Levels/level.gd 的 collect() 结果造一份数据。
static func from_dict(d: Dictionary) -> Level:
	var lv := Level.new()
	lv.id = int(d.get("id", 0))
	lv.display_name = String(d.get("name", ""))
	lv.w = int(d.get("w", 6))
	lv.h = int(d.get("h", 6))
	lv.meat_pos = d.get("meat", Vector2i.ZERO)
	lv.max_turns = int(d.get("max_turns", 12))

	var dog: Dictionary = d.get("dog", {})
	lv.dog_type = String(dog.get("type", "stray"))
	lv.dog_pos = dog.get("pos", Vector2i.ZERO)

	lv.cat_spawns = d.get("cats", [])
	lv.obstacles = d.get("obstacles", [])
	return lv


## 关卡 + 全局配置 -> 开局状态。
func to_state(config: Dictionary) -> GameState:
	var s := GameState.new()
	s.w = w
	s.h = h
	s.obstacles = obstacles.duplicate()
	s.max_turns = max_turns
	s.meat_pos = meat_pos
	s.growling = false
	s.turn = 0

	s.dog = { "type": dog_type, "pos": dog_pos }

	s.cats.clear()
	for spawn in cat_spawns:
		s.cats.append({ "type": spawn["type"], "pos": spawn["pos"] })
	return s
