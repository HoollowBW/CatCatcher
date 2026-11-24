extends Node2D
## 棋盘主场景：画格子 / 控制范围 / 预览 / HUD，把输入翻译成 Core 的调用。
##
## 表现层只做三件事：读 Core 的结果来画、把玩家输入翻译成 Core 的函数调用、播表现。
## 规则一律不写在这里 —— 写进来就没法给求解器复用了。
##
## 【单位是场景】棋子上场不是这里画出来的：关卡场景（Levels/level_XX.tscn）整个被实例化进来，
## 单位就是那里面拖好的 Sprite2D / Polygon2D 节点，本脚本只负责按 Core 的坐标去挪它们。
## 想换美术就改 Characters/ 里的场景，不用碰这个文件。
##
## 所有屏幕文字都是 ASCII：Godot 内置字体没有 CJK 字形，中文在 web 版会画成方块。

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

## ---- 关卡场景与单位节点 ----
var _level_root: Node2D = null      # 装着实例化进来的关卡场景
var _cat_nodes: Array = []          # 顺序必须和 controller.state.cats 一致
var _dog_node: Node2D = null
var _meat_node: Node2D = null

## ---- 结算界面（CanvasLayer，永远在最上层）----
var _result_layer: CanvasLayer = null
var _result_title: Label = null
var _result_reason: Label = null
var _result_prompt: Label = null

## 选中的猫下标，-1 = 没选中
var _selected: int = -1
## 鼠标下的格子，(-1,-1) = 不在棋盘上
var _hover := Vector2i(-1, -1)
## 当前关卡在 Levels.SCENES 里的下标
var _level_index: int = 0

## ---- 提示系统（M3）----
## 前 tutorial_levels 关强引导；之后的关卡要连续失败 fail_threshold 次、或挂机 idle_seconds 秒才给
var _hint_step: Dictionary = {}
var _hint_version: int = -1       # 提示是基于哪一版局面算的
var _version: int = 0             # 局面版本号，每次行动 +1
var _fail_count: int = 0          # 本关失败次数
var _idle: float = 0.0            # 距上次操作的秒数
var _hint_time: float = 0.0       # 引导箭头的浮动动画计时


func _ready() -> void:
	config = Level.load_config()
	if config.is_empty():
		push_error("配置加载失败 —— 框架没跑通")
		return

	cell_size = int(config["board"]["cell_size"])
	var o: Array = config["board"]["origin"]
	board_origin = Vector2i(int(o[0]), int(o[1]))
	colors = config["board"]["colors"]
	meat_max_hp = int(config["meat"]["max_hp"])

	controller = GameController.new()
	controller.state_changed.connect(_on_state_changed)
	controller.game_over.connect(_on_game_over)

	RenderingServer.set_default_clear_color(_color("bg"))
	_build_result_layer()
	print("[CatCatcher] 左键点猫选中 / 悬停格子看威胁范围 | 点高亮格移动 | Z 悔棋 | R 重开 | 通关后 SPACE 下一关")

	# 启动校验：每关都必须有解（求解器真搜，不是读标准答案糊弄）
	var problems := Levels.validate_all(config)
	for p in problems:
		push_error("[关卡校验] " + String(p))
	if problems.is_empty():
		print("[CatCatcher] 关卡校验通过（%d 关全部有解）" % Levels.count())

	# 从编辑器里 F6 单独跑某一关时，关卡场景会先把路径写进 RunRequest
	var start := Levels.index_of_path(RunRequest.level_path)
	RunRequest.level_path = ""
	_start_level(maxi(start, 0))


## 载入第 index 关。重开本关也走这里。
func _start_level(index: int) -> void:
	_level_index = clampi(index, 0, Levels.count() - 1)

	# 整个关卡场景实例化进来 —— 单位就是它里面拖好的节点，本脚本只负责挪位置
	if _level_root != null:
		_level_root.queue_free()
	_level_root = Node2D.new()
	_level_root.name = "LevelRoot"
	add_child(_level_root)

	var scene_node: Node = Levels.SCENES[_level_index].instantiate()
	_level_root.add_child(scene_node)

	level = Level.from_dict(scene_node.collect())

	_cat_nodes.clear()
	_dog_node = null
	_meat_node = null
	for u in scene_node.collect_units():
		match String(u["kind"]):
			"cat":
				_cat_nodes.append(u["node"])
			"dog":
				if _dog_node == null:
					_dog_node = u["node"]
			"meat":
				_meat_node = u["node"]

	if level == null:
		push_error("关卡加载失败: index %d" % _level_index)
		return

	controller.setup(level, config)
	_selected = -1
	_hover = Vector2i(-1, -1)
	_fail_count = 0
	_idle = 0.0
	_bump_version()
	_update_hint()
	_sync_units()
	_hide_result()
	queue_redraw()

	print("[CatCatcher] 关卡 %d/%d %s | 猫 %d 只 | 狗 %s @ %s | 肉 @ %s | HP %d" % [
		_level_index + 1, Levels.count(), level.display_name,
		level.cat_spawns.size(), level.dog_type,
		str(level.dog_pos), str(level.meat_pos), controller.state.meat_hp,
	])


func _has_next_level() -> bool:
	return _level_index + 1 < Levels.count()


func _on_state_changed() -> void:
	_sync_units()
	queue_redraw()


## 把场景里的单位节点挪到 Core 说的位置上。**单位是场景，不是这里画的。**
func _sync_units() -> void:
	if controller == null or controller.state == null:
		return
	var state := controller.state

	for i in _cat_nodes.size():
		if i >= state.cats.size():
			break
		_cat_nodes[i].position = _cell_center(state.cats[i]["pos"])
		_cat_nodes[i].visible = true

	if _dog_node != null:
		_dog_node.position = _cell_center(state.dog["pos"])
	if _meat_node != null:
		_meat_node.position = _cell_center(state.meat_pos)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(board_origin) + Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5


# ---------------------------------------------------------------- 提示 ----

func _bump_version() -> void:
	_version += 1


func _hint_cfg(key: String, fallback: float) -> float:
	return float(config.get("hint", {}).get(key, fallback))


## 这一关现在该不该给提示。
func _hint_due() -> bool:
	if controller.finished:
		return false
	if _level_index < int(_hint_cfg("tutorial_levels", 2)):
		return true                                       # 前几关强引导
	if _fail_count >= int(_hint_cfg("fail_threshold", 2)):
		return true                                       # 失败够多次了
	return _idle >= _hint_cfg("idle_seconds", 60.0)        # 或者卡住了


## 提示 = 求解器从**当前局面**算出的第一步。
## 用当前局面而不是关卡里写死的序列 —— 玩家走偏了也还能拿到正确提示。
func _update_hint() -> void:
	if not _hint_due():
		_hint_step = {}
		_hint_version = -1
		return
	if _hint_version == _version:
		return

	_hint_version = _version
	var depth := int(config.get("solver", {}).get("hint_depth", 5))
	_hint_step = Solver.first_step(controller.state, config, depth)

	# 求解器在这个深度搜不到 -> 退回关卡里手写的提示（只在开局位置有意义）
	if _hint_step.is_empty() and controller.state.turn == 0 and not level.hint.is_empty():
		_hint_step = level.hint[0]


func _process(delta: float) -> void:
	if level == null or controller.finished:
		return
	_idle += delta
	if _idle >= _hint_cfg("idle_seconds", 60.0):
		_update_hint()
		queue_redraw()

	# 引导箭头的浮动动画：只在有提示时每帧重画（没提示就一次都不重画）
	if not _hint_step.is_empty():
		_hint_time += delta
		queue_redraw()


func _reset_idle() -> void:
	_idle = 0.0


# ---------------------------------------------------------------- 绘制 ----

func _draw() -> void:
	if level == null:
		return
	var state := controller.state
	_draw_cells()

	var controlled := MoveRules.controlled_cells(state)
	_draw_control(controlled)
	_draw_focus_reach()
	_draw_dog_warning(controlled)
	_draw_preview()
	_draw_selection()
	_draw_hint()
	_draw_hud()
	# 结算界面不在这里画 —— 单位是场景子节点，会盖住 _draw() 的内容。
	# 结算用 CanvasLayer（永远在最上层），见 _build_result_layer。


func _draw_cells() -> void:
	for y in level.h:
		for x in level.w:
			var cell := Vector2i(x, y)
			var fill: Color = _color("cell") if (x + y) % 2 == 0 else _color("cell_alt")
			draw_rect(_cell_rect(cell), fill)


func _draw_control(controlled: Dictionary) -> void:
	for cell in controlled:
		draw_rect(_cell_rect(cell), _color("control"))


## 选中那只猫的控制范围再压一层，方便看清"这只猫管到哪"。
## 和隔壁一样：**只有选中了才显示**，悬停不算（否则鼠标扫过棋盘时整盘乱闪）。
func _draw_focus_reach() -> void:
	if _selected < 0:
		return
	for cell in MoveRules.reach_cells(controller.state, _selected):
		draw_rect(_cell_rect(cell), _color("control").lightened(0.15))
	# 可落的格画个内框，和"只是被控制"区分开
	for cell in MoveRules.legal_moves(controller.state, _selected):
		draw_rect(_cell_rect(cell).grow(-6), _color("selected"), false, 2.0)


## 单位不在这里画 —— 它们是关卡场景里拖好的节点，由 _sync_units() 挪位置。


## 狗站在被控制的格上 => 红色描边（"它已经被罩住了"）
func _draw_dog_warning(controlled: Dictionary) -> void:
	var dog_cell: Vector2i = controller.state.dog["pos"]
	if not controlled.has(dog_cell):
		return
	var dog_cfg: Dictionary = config.get("dog", {})
	var width := float(dog_cfg.get("warning_width", 3))
	draw_rect(_cell_rect(dog_cell), Color(String(dog_cfg.get("warning_outline", "#e03e3e"))), false, width)


## 敌方行动预览 + 威胁范围：鼠标停在一个可走的格子上就显示。
##
## 显示三样东西：
##   ① 橙色箭头 = 狗这一回合会干什么（走 / 撞飞 / 啃肉）
##   ② 橙圈     = 那个动作的落点
##   ③ 红色格子 = **狗下一步还能碰到的地方**（威胁范围）—— 落点确定后，它下回合的合法动作格
##
## 全部走 Core 的同一套函数（DogAI.plan / Rules.apply_turn / Encircle.legal_actions），
## 不是另写一套预测逻辑，所以永远和实战一致。
func _draw_preview() -> void:
	if controller.finished or _hover.x < 0:
		return
	var cat_index := _preview_cat_index()
	if cat_index < 0:
		return

	var warn := Color("#e07a3e")

	# ① 狗这一回合的动作
	var preview := controller.preview_after(cat_index, _hover)
	if preview.is_empty():
		return
	var kind := String(preview["kind"])

	if kind == "encircled":
		var dog_rect := _cell_rect(controller.state.dog["pos"])
		_text_centered("ENCIRCLED", dog_rect.get_center().x, dog_rect.position.y - 8, FONT_MID, Color("#7fb069"))
		return
	if kind == "none":
		return

	var target: Vector2i = preview["to"]
	if kind == "eat":
		target = controller.state.meat_pos
	var from := _cell_rect(controller.state.dog["pos"]).get_center()
	var to := _cell_rect(target).get_center()

	# ① 先画"走到这一格之后，这只猫会控住哪些格"—— 这是玩家最想知道的那件事
	var after_move := controller.state.clone()
	after_move.cats[cat_index]["pos"] = _hover
	var hyp_fill := _color("control").lightened(0.28)
	var hyp_edge := Color(0.60, 0.86, 0.44, 0.9)
	for cell in MoveRules.reach_cells(after_move, cat_index):
		draw_rect(_cell_rect(cell), hyp_fill)
		draw_rect(_cell_rect(cell).grow(-3), hyp_edge, false, 1.5)

	# ② 威胁范围：把这一步真的走一遍，看狗**再下一步**能碰到哪些格
	var sim := controller.state.clone()
	var outcome := String(Rules.apply_turn(sim, config, cat_index, _hover)["outcome"])
	if outcome != Rules.WON:
		var threat_fill := Color(warn.r, warn.g, warn.b, 0.26)
		for action in Encircle.legal_actions(sim):
			var threat_cell: Vector2i = action["to"]
			draw_rect(_cell_rect(threat_cell), threat_fill)
			draw_rect(_cell_rect(threat_cell).grow(-2), warn, false, 2.0)

	# ③ 箭头和落点画在最上面
	draw_line(from, to, warn, 3.0)
	draw_arc(to, cell_size * 0.32, 0.0, TAU, 24, warn, 3.0)


## 预览只对**选中的那只猫**生效 —— 和隔壁一致，鼠标闲着扫棋盘不会到处冒预览。
func _preview_cat_index() -> int:
	if _selected < 0 or _hover.x < 0:
		return -1
	if MoveRules.legal_moves(controller.state, _selected).has(_hover):
		return _selected
	return -1


func _draw_selection() -> void:
	if _selected < 0 or _selected >= controller.state.cats.size():
		return
	draw_rect(_cell_rect(controller.state.cats[_selected]["pos"]), _color("selected"), false, 4.0)


## 引导：多邻国那套 —— 一条从"该动的那只猫"指向目标格的大箭头，
## 外加猫头顶上下浮动的小箭头（"点这一只"）。所有形状都先画深色描边再画本体，
## 保证在任何底色上都看得清。来源是求解器，见 _update_hint。
func _draw_hint() -> void:
	if _hint_step.is_empty() or controller.finished:
		return

	var from := _cell_rect(_hint_cell(_hint_step["cat"])).get_center()
	var to := _cell_rect(_hint_cell(_hint_step["to"])).get_center()
	var fill := _color("hint")
	var edge := Color(0.10, 0.13, 0.18, 0.92)

	# 一步之遥时格子之间本来就没多少空地，落点圈得缩小，否则箭头会被挤成一坨
	var ring_r := cell_size * (0.26 if from.distance_to(to) < cell_size * 1.45 else 0.36)

	_draw_hint_arrow(from, to, ring_r, fill, edge)

	# 落点圈：强调"就是这里"（箭头停在圈外）
	draw_arc(to, ring_r, 0.0, TAU, 28, edge, 5.0)
	draw_arc(to, ring_r, 0.0, TAU, 28, fill, 2.5)

	# 猫头顶浮动的指示箭头
	var bob := sin(_hint_time * 4.5) * cell_size * 0.07
	_draw_hint_chevron(Vector2(from.x, from.y - cell_size * 0.62 + bob), fill, edge)


## 从 from 指向 to 的粗箭头（描边 + 本体 + 箭头三角）
## 一格距离时改画"朝目标方向"的指示三角 —— 长箭头在那个距离上根本铺不开。
func _draw_hint_arrow(from: Vector2, to: Vector2, ring_r: float, fill: Color, edge: Color) -> void:
	var dir := to - from
	var dist := dir.length()
	if dist < 1.0:
		return
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)

	if dist < cell_size * 1.45:
		var tip := to - dir * (ring_r + 5.0)
		var base := from + dir * cell_size * 0.24
		if base.distance_to(tip) > 10.0:
			_draw_hint_pointer(base, tip, dir, side, fill, edge)
		return

	var start := from + dir * cell_size * 0.26
	var tip := to - dir * (ring_r + 8.0)
	var head_len := clampf(dist * 0.34, cell_size * 0.18, cell_size * 0.26)
	var head_half := cell_size * 0.17
	var base := tip - dir * head_len

	# 描边层
	draw_line(start, base, edge, 9.0)
	draw_colored_polygon(PackedVector2Array([
		tip + dir * 4.0,
		base + side * (head_half + 4.0),
		base - side * (head_half + 4.0),
	]), edge)

	# 本体
	draw_line(start, base, fill, 5.0)
	draw_colored_polygon(PackedVector2Array([
		tip,
		base + side * head_half,
		base - side * head_half,
	]), fill)


## 一个从 base 指到 tip 的指示三角（短距离提示用）
func _draw_hint_pointer(base: Vector2, tip: Vector2, dir: Vector2, side: Vector2, fill: Color, edge: Color) -> void:
	var head_half := cell_size * 0.17
	var head_base := tip - dir * minf(cell_size * 0.22, base.distance_to(tip) * 0.8)
	draw_line(base, head_base, edge, 9.0)
	draw_line(base, head_base, fill, 5.0)
	draw_colored_polygon(PackedVector2Array([
		tip + dir * 4.0,
		head_base + side * (head_half + 4.0),
		head_base - side * (head_half + 4.0),
	]), edge)
	draw_colored_polygon(PackedVector2Array([
		tip,
		head_base + side * head_half,
		head_base - side * head_half,
	]), fill)


## 朝下的指示三角（"点这一只"）
func _draw_hint_chevron(tip: Vector2, fill: Color, edge: Color) -> void:
	var w := cell_size * 0.20
	var h := cell_size * 0.24
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(0, 4),
		tip + Vector2(-w - 4, -h - 4),
		tip + Vector2(w + 4, -h - 4),
	]), edge)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + Vector2(-w, -h),
		tip + Vector2(w, -h),
	]), fill)


func _hint_cell(arr: Array) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))


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
	# 只显示关卡序号，不显示 level.display_name —— 那是中文，桌面端靠系统字体回退能画，
	# web 版不一定有回退。关名字留给文档，M4 引入中文字体后再上屏。
	_text("LEVEL %d / %d" % [_level_index + 1, Levels.count()],
		bar_pos + Vector2(0, 62), FONT_SMALL, Color(0.78, 0.74, 0.66))
	_text("LMB pick / move     Z undo     R restart", bar_pos + Vector2(0, 84), FONT_SMALL, Color(0.62, 0.58, 0.5))

	# 提示文字放棋盘右侧空白处，别挤 HUD 下面那点地方
	if not _hint_step.is_empty() and not controller.finished:
		var cat_cell := _hint_cell(_hint_step["cat"])
		var to_cell := _hint_cell(_hint_step["to"])
		_text("HINT", bar_pos + Vector2(bar_w + 24, 6), FONT_SMALL, _color("hint"))
		_text("(%d,%d)" % [cat_cell.x, cat_cell.y], bar_pos + Vector2(bar_w + 24, 26), FONT_SMALL, Color(0.85, 0.82, 0.76))
		_text("-> (%d,%d)" % [to_cell.x, to_cell.y], bar_pos + Vector2(bar_w + 24, 44), FONT_SMALL, Color(0.85, 0.82, 0.76))


# ------------------------------------------------------------ 结算界面 ----
#
# ⚠️ 结算界面**不能**画在 _draw() 里：单位现在是关卡场景的子节点，子节点永远画在
# 父节点自己的 _draw() 之上 —— 遮罩会被障碍物和猫盖住（踩过）。
# 所以用 CanvasLayer（永远在最上层的原生命名空间），里面放 ColorRect + Label。

func _build_result_layer() -> void:
	_result_layer = CanvasLayer.new()
	_result_layer.layer = 10
	_result_layer.visible = false
	add_child(_result_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(dim)

	# 960x540 基准分辨率下的三条横带
	_result_title = _make_result_label(215, 44, 30, Color.WHITE)
	_result_reason = _make_result_label(262, 28, FONT_MID, Color(0.85, 0.82, 0.76))
	_result_prompt = _make_result_label(300, 24, FONT_SMALL, Color(0.62, 0.58, 0.5))


## 一条占满整个视口宽度的横带，文字居中。
func _make_result_label(top: int, height: int, size: int, tint: Color) -> Label:
	var l := Label.new()
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_left = 0.0
	l.offset_right = 0.0
	l.offset_top = float(top)
	l.offset_bottom = float(top + height)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(l)
	return l


func _show_result() -> void:
	if _result_layer == null:
		return
	_result_title.text = "YOU WIN" if controller.won else "YOU LOSE"
	_result_title.add_theme_color_override("font_color",
		Color("#8fd17a") if controller.won else Color("#e0705e"))
	_result_reason.text = String(REASON_TEXT.get(controller.result_reason, controller.result_reason))

	var prompt := "press R to restart"
	if controller.won:
		if _has_next_level():
			prompt = "press SPACE for the next level"
		else:
			prompt = "all levels cleared - press R to replay"
	_result_prompt.text = prompt
	_result_layer.visible = true


func _hide_result() -> void:
	if _result_layer != null:
		_result_layer.visible = false


# ---------------------------------------------------------------- 输入 ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _point_to_cell(get_global_mouse_position())
		if hovered != _hover:
			_hover = hovered
			queue_redraw()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		_reset_idle()
		match event.keycode:
			KEY_Z:
				controller.undo()
				_selected = -1
				_bump_version()
				_update_hint()
				_hide_result()      # 悔棋可能把"已经结束"的局面悔回去
				_sync_units()
			KEY_R:
				_start_level(_level_index)      # 重开本关（不是从头玩）
			KEY_SPACE:
				if controller.finished and controller.won and _has_next_level():
					_start_level(_level_index + 1)
			KEY_ESCAPE:
				_selected = -1
		queue_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	_reset_idle()
	var cell := _point_to_cell(get_global_mouse_position())
	if cell.x < 0:
		return

	# 已经选了猫，且点的是合法落点 => 走这一步（狗会立刻行动）
	if _selected >= 0 and not controller.finished:
		if MoveRules.legal_moves(controller.state, _selected).has(cell):
			controller.try_move_cat(_selected, cell)
			_selected = -1
			_bump_version()
			_update_hint()
			queue_redraw()
			return

	# 否则：点猫 = 选中，点别处 = 取消选中
	_selected = -1 if controller.finished else controller.state.cat_at(cell)
	queue_redraw()


func _on_game_over(is_win: bool, _reason: String) -> void:
	_selected = -1
	if not is_win:
		_fail_count += 1
	_show_result()
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
