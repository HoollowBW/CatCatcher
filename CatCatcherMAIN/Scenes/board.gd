extends Node2D
## M1：棋盘 + 控制范围 + 单位 + 敌方行动预览 + 悔棋/重开 + 胜负提示。
##
## 表现层只做三件事：读 Core 的结果来画、把玩家输入翻译成 Core 的函数调用、播表现。
## 规则一律不写在这里 —— 写进来就没法给求解器复用了。
##
## 所有屏幕文字都是 ASCII：Godot 内置字体没有 CJK 字形，中文在 web 版会画成方块。
## 占位贴图借自隔壁 hollow-bastion（战车/骑士/白猫士兵/恐惧之影），M4 换真美术时整体替换。

const LEVEL_PATH := "res://CatCatcherMAIN/Data/levels/level_01.json"

const TEX_CAT := {
	"pawn": preload("res://CatCatcherMAIN/Graphics/placeholders/cat_pawn.png"),
	"rook": preload("res://CatCatcherMAIN/Graphics/placeholders/cat_rook.png"),
	"horse": preload("res://CatCatcherMAIN/Graphics/placeholders/cat_horse.png"),
}
const TEX_DOG := preload("res://CatCatcherMAIN/Graphics/placeholders/dog.png")

const FONT_BIG := 30
const FONT_MID := 18
const FONT_SMALL := 14

## Core 只给 code，屏幕文案在这里 —— 默认字体没有 CJK 字形，中文会画成空白
const REASON_TEXT := {
	"encircled": "the dog has nowhere to go",
	"meat_gone": "the meat is gone",
	"timeout": "the meat rotted away",
}

var config: Dictionary
var level: Level
var controller: GameController

var cell_size: int = 64
var board_origin := Vector2i.ZERO
var colors: Dictionary = {}
var meat_max_hp: int = 20

## 选中的猫下标，-1 = 没选中
var _selected: int = -1
## 鼠标下的格子，(-1,-1) = 不在棋盘上
var _hover := Vector2i(-1, -1)


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
	meat_max_hp = int(config["meat"]["max_hp"])

	controller = GameController.new()
	controller.setup(level, config)
	controller.state_changed.connect(queue_redraw)
	controller.game_over.connect(_on_game_over)

	RenderingServer.set_default_clear_color(_color("bg"))

	print("[CatCatcher] M1 OK | 关卡 %d %s | 猫 %d 只 | 狗 %s @ %s | 肉 @ %s | HP %d" % [
		level.id, level.display_name, level.cat_spawns.size(),
		level.dog_type, str(level.dog_pos), str(level.meat_pos), controller.state.meat_hp,
	])
	print("[CatCatcher] 左键点猫选中 / 点高亮格移动 | Z 悔棋 | R 重开")

	queue_redraw()


# ---------------------------------------------------------------- 绘制 ----

func _draw() -> void:
	if level == null:
		return
	var state := controller.state
	_draw_cells()

	var controlled := MoveRules.controlled_cells(state)
	_draw_control(controlled)
	_draw_selected_reach()
	_draw_units()
	_draw_dog_warning(controlled)
	_draw_preview()
	_draw_selection()
	_draw_hud()

	if controller.finished:
		_draw_result()


func _draw_cells() -> void:
	for y in level.h:
		for x in level.w:
			var cell := Vector2i(x, y)
			var fill: Color = _color("cell") if (x + y) % 2 == 0 else _color("cell_alt")
			if controller.state.obstacles.has(cell):
				fill = _color("obstacle")
			draw_rect(_cell_rect(cell), fill)


func _draw_control(controlled: Dictionary) -> void:
	for cell in controlled:
		draw_rect(_cell_rect(cell), _color("control"))


## 选中的猫自己的控制范围再压一层，方便看清"这只猫管到哪"
func _draw_selected_reach() -> void:
	if _selected < 0:
		return
	for cell in MoveRules.reach_cells(controller.state, _selected):
		draw_rect(_cell_rect(cell), _color("control").lightened(0.15))
	# 可落的格画个内框，和"只是被控制"区分开
	for cell in MoveRules.legal_moves(controller.state, _selected):
		draw_rect(_cell_rect(cell).grow(-6), _color("selected"), false, 2.0)


func _draw_units() -> void:
	var state := controller.state

	# 肉（没有合适贴图，先画方块 + 字）
	var meat_rect := _cell_rect(state.meat_pos).grow(-10)
	draw_rect(meat_rect, _color("meat"))
	_text_centered("MEAT", meat_rect.get_center().x, meat_rect.get_center().y, FONT_SMALL, Color(1, 0.95, 0.9))

	for cat in state.cats:
		var tex = TEX_CAT.get(cat["type"])
		var rect := _cell_rect(cat["pos"]).grow(-3)
		if tex != null:
			draw_texture_rect(tex, rect, false)
		else:
			draw_rect(rect.grow(-6), _color("cat"))

	draw_texture_rect(TEX_DOG, _cell_rect(state.dog["pos"]).grow(-3), false)


## 狗站在被控制的格上 => 红色描边（"它已经被罩住了"）
func _draw_dog_warning(controlled: Dictionary) -> void:
	var dog_cell: Vector2i = controller.state.dog["pos"]
	if not controlled.has(dog_cell):
		return
	var dog_cfg: Dictionary = config.get("dog", {})
	var width := float(dog_cfg.get("warning_width", 3))
	draw_rect(_cell_rect(dog_cell), Color(String(dog_cfg.get("warning_outline", "#e03e3e"))), false, width)


## 敌方行动预览：选中猫 + 悬停在某个可落格上时，显示狗下一步会干什么。
## 走的是 GameController.preview_after -> DogAI.plan，和实战同一个函数。
func _draw_preview() -> void:
	if controller.finished or _selected < 0 or _hover.x < 0:
		return
	if not MoveRules.legal_moves(controller.state, _selected).has(_hover):
		return

	var preview := controller.preview_after(_selected, _hover)
	if preview.is_empty():
		return

	var kind := String(preview["kind"])
	if kind == "none":
		return

	var warn := Color("#e07a3e")

	if kind == "encircled":
		var dog_rect := _cell_rect(controller.state.dog["pos"])
		_text_centered("ENCIRCLED", dog_rect.get_center().x, dog_rect.position.y - 8, FONT_MID, Color("#7fb069"))
		return

	var target: Vector2i = preview["to"]
	if kind == "eat":
		target = controller.state.meat_pos

	var from := _cell_rect(controller.state.dog["pos"]).get_center()
	var to := _cell_rect(target).get_center()
	draw_line(from, to, warn, 3.0)
	draw_arc(to, cell_size * 0.32, 0.0, TAU, 24, warn, 3.0)


func _draw_selection() -> void:
	if _selected < 0 or _selected >= controller.state.cats.size():
		return
	draw_rect(_cell_rect(controller.state.cats[_selected]["pos"]), _color("selected"), false, 4.0)


func _draw_hud() -> void:
	var state := controller.state
	var bar_w := level.w * cell_size
	var bar_pos := Vector2(board_origin.x, board_origin.y + level.h * cell_size + 14)
	var bar := Rect2(bar_pos, Vector2(bar_w, 18))

	draw_rect(bar, Color(0.13, 0.11, 0.09))
	var frac := clampf(float(state.meat_hp) / float(maxi(meat_max_hp, 1)), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), _color("meat"))
	draw_rect(bar, Color(0.55, 0.5, 0.44), false, 2.0)

	_text("MEAT %d / %d" % [state.meat_hp, meat_max_hp], bar_pos + Vector2(0, 38), FONT_MID, Color(0.9, 0.87, 0.8))
	_text("TURN %d / %d" % [state.turn, state.max_turns], bar_pos + Vector2(bar_w - 92, 38), FONT_MID, Color(0.9, 0.87, 0.8))
	_text("LMB pick / move     Z undo     R restart", bar_pos + Vector2(0, 62), FONT_SMALL, Color(0.62, 0.58, 0.5))


func _draw_result() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.66))
	var headline := "YOU WIN" if controller.won else "YOU LOSE"
	var tint := Color("#8fd17a") if controller.won else Color("#e0705e")
	_text_centered(headline, vp.x * 0.5, vp.y * 0.5 - 12, FONT_BIG, tint)
	_text_centered(String(REASON_TEXT.get(controller.result_reason, controller.result_reason)),
		vp.x * 0.5, vp.y * 0.5 + 26, FONT_MID, Color(0.85, 0.82, 0.76))
	_text_centered("press R to restart", vp.x * 0.5, vp.y * 0.5 + 58, FONT_SMALL, Color(0.62, 0.58, 0.5))


# ---------------------------------------------------------------- 输入 ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _point_to_cell(get_global_mouse_position())
		if hovered != _hover:
			_hover = hovered
			queue_redraw()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z:
				controller.undo()
				_selected = -1
			KEY_R:
				controller.restart()
				_selected = -1
			KEY_ESCAPE:
				_selected = -1
		queue_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var cell := _point_to_cell(get_global_mouse_position())
	if cell.x < 0:
		return

	# 已经选了猫，且点的是合法落点 => 走这一步（狗会立刻行动）
	if _selected >= 0 and not controller.finished:
		if MoveRules.legal_moves(controller.state, _selected).has(cell):
			controller.try_move_cat(_selected, cell)
			_selected = -1
			queue_redraw()
			return

	# 否则：点猫 = 选中，点别处 = 取消选中
	_selected = -1 if controller.finished else controller.state.cat_at(cell)
	queue_redraw()


func _on_game_over(_is_win: bool, _reason: String) -> void:
	_selected = -1
	queue_redraw()


# ---------------------------------------------------------------- 工具 ----

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


func _text(txt: String, pos: Vector2, size: int, tint: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)


func _text_centered(txt: String, cx: float, cy: float, size: int, tint: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var ascent := font.get_ascent(size)
	var descent := font.get_descent(size)
	draw_string(font, Vector2(cx - w * 0.5, cy + (ascent - descent) * 0.5), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)
