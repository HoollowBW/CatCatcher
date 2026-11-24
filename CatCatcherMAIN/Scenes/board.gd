extends Node2D
## M0：棋盘渲染 + 点击选格 + 单位占位显示。
##
## 表现层只做三件事：读 Core 的结果来画、把玩家输入翻译成 Core 的函数调用、播表现。
## 规则一律不写在这里 —— 写进来就没法给求解器复用了。
##
## 占位单位用**拉丁字母**标记，不用中文：Godot 内置字体没有 CJK 字形，
## 写中文在 web 版会画成方块。M4 换真图时这套字母标记整体删掉。

const LEVEL_PATH := "res://CatCatcherMAIN/Data/levels/level_01.json"

## 占位字母。M4 换美术后删。
const CAT_LETTER := { "pawn": "P", "rook": "R", "horse": "H" }
const DOG_LETTER := { "stray": "D", "collie": "C" }

var config: Dictionary
var level: Level
var controller: GameController

var cell_size: int = 64
var board_origin := Vector2i.ZERO
var colors: Dictionary = {}

## 选中的猫下标，-1 = 没选中
var _selected: int = -1


func _ready() -> void:
	config = Level.load_config()
	level = Level.from_file(LEVEL_PATH)
	if level == null or config.is_empty():
		push_error("关卡或配置加载失败 —— 框架没跑通")
		return

	cell_size = int(config["board"]["cell_size"])
	var o: Array = config["board"]["origin"]
	board_origin = Vector2i(int(o[0]), int(o[1]))
	colors = config["board"]["colors"]

	controller = GameController.new()
	controller.setup(level, config)

	RenderingServer.set_default_clear_color(_color("bg"))

	print("[CatCatcher] 框架 OK | 关卡 %d %s | %dx%d | 猫 %d 只 | 狗 %s @ %s | 肉 @ %s | HP %d" % [
		level.id,
		level.display_name,
		level.w,
		level.h,
		level.cat_spawns.size(),
		level.dog_type,
		str(level.dog_pos),
		str(level.meat_pos),
		controller.state.meat_hp,
	])

	queue_redraw()


# ---------------------------------------------------------------- 绘制 ----

func _draw() -> void:
	if level == null:
		return
	_draw_cells()
	_draw_units()
	_draw_selection()


func _draw_cells() -> void:
	for y in level.h:
		for x in level.w:
			var cell := Vector2i(x, y)
			var fill: Color = _color("cell") if (x + y) % 2 == 0 else _color("cell_alt")
			if controller.state.obstacles.has(cell):
				fill = _color("obstacle")
			draw_rect(_cell_rect(cell), fill)


func _draw_units() -> void:
	for cat in controller.state.cats:
		_draw_marker(cat["pos"], _color("cat"), String(CAT_LETTER.get(cat["type"], "?")), false)
	_draw_marker(controller.state.dog["pos"], _color("dog"), String(DOG_LETTER.get(controller.state.dog["type"], "?")), true)
	_draw_marker(controller.state.meat_pos, _color("meat"), "M", true)


func _draw_selection() -> void:
	if _selected < 0 or _selected >= controller.state.cats.size():
		return
	draw_rect(_cell_rect(controller.state.cats[_selected]["pos"]), _color("selected"), false, 4.0)


## 占位单位：方块/圆 + 一个字母。round_shape=true 用来区分狗和肉。
func _draw_marker(cell: Vector2i, fill: Color, letter: String, round_shape: bool) -> void:
	var rect := _cell_rect(cell)
	var pad := cell_size * 0.16
	var inner := rect.grow(-pad)

	if round_shape:
		draw_circle(rect.get_center(), inner.size.x * 0.5, fill)
	else:
		draw_rect(inner, fill)

	var font := ThemeDB.fallback_font
	var font_size := int(cell_size * 0.42)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var pos := Vector2(
		rect.get_center().x - text_size.x * 0.5,
		rect.get_center().y + (ascent - descent) * 0.5,
	)
	draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.08, 0.06))


# ---------------------------------------------------------------- 输入 ----

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var cell := _point_to_cell(get_global_mouse_position())
	if cell.x < 0:
		return

	# M0 只做到"选中/取消选中"。M1 在这里接 controller.try_move_cat()。
	_selected = controller.state.cat_at(cell)
	queue_redraw()


# ---------------------------------------------------------------- 坐标 ----

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(board_origin + cell * cell_size), Vector2(cell_size, cell_size))


## 屏幕坐标 -> 格子。棋盘外返回 (-1, -1)。
func _point_to_cell(p: Vector2) -> Vector2i:
	var local := p - Vector2(board_origin)
	if local.x < 0.0 or local.y < 0.0:
		return Vector2i(-1, -1)
	var cell := Vector2i(int(local.x / cell_size), int(local.y / cell_size))
	if cell.x >= level.w or cell.y >= level.h:
		return Vector2i(-1, -1)
	return cell


func _color(key: String) -> Color:
	return Color(String(colors.get(key, "#ffffff")))
