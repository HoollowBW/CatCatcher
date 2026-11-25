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
	"meat_eaten": "the dog got the meat",
	"timeout": "you ran out of turns",
}

## 音效：占位素材借自隔壁 hollow-bastion（Audio/Sound_effect），改名成 ASCII 便于 web 导出。
## 需要换音效时只改这里 + 替换文件，代码不用动。
const SFX := {
	"click": preload("res://CatCatcherMAIN/Audio/sfx_click.mp3"),
	"move": preload("res://CatCatcherMAIN/Audio/sfx_move.mp3"),
	"flick": preload("res://CatCatcherMAIN/Audio/sfx_flick.mp3"),
	"growl": preload("res://CatCatcherMAIN/Audio/sfx_growl.mp3"),
	"win": preload("res://CatCatcherMAIN/Audio/sfx_win.mp3"),
	"lose": preload("res://CatCatcherMAIN/Audio/sfx_lose.mp3"),
}

var config: Dictionary
var level: Level
var controller: GameController

var cell_size: int = 64
var board_origin := Vector2i.ZERO
var colors: Dictionary = {}

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

## ---- 屏幕按钮（手机用）----
var _ui_layer: CanvasLayer = null
var _undo_btn: Button = null
var _restart_btn: Button = null

## ---- 音效播放器（3 个轮着用，避免互相打断）----
var _sfx_players: Array = []
var _sfx_next: int = 0

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

## ---- 演出（M4 里不需要美术的那部分）----
var _fx_layer: CanvasLayer = null
var _flash: ColorRect = null
var _banner_wrap: Control = null
var _banner: Label = null

var _fx_seq: String = ""          # "" / "win" / "lose"，用 _process 驱动，不用 await
var _fx_t: float = 0.0

var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _shake_amp: float = 0.0

## 撞飞命中环：被吃的那一刻在那格炸一圈，保证"哪一格被吃"看得见（飞到画外也还剩这一下）
var _hit_cell := Vector2i(-1, -1)
var _hit_t: float = 0.0


func _ready() -> void:
	config = Level.load_config()
	if config.is_empty():
		push_error("配置加载失败 —— 框架没跑通")
		return

	cell_size = int(config["board"]["cell_size"])
	var o: Array = config["board"]["origin"]
	board_origin = Vector2i(int(o[0]), int(o[1]))
	colors = config["board"]["colors"]

	controller = GameController.new()
	controller.state_changed.connect(_on_state_changed)
	controller.game_over.connect(_on_game_over)

	RenderingServer.set_default_clear_color(_color("bg"))
	_build_fx_layer()
	_build_result_layer()
	_build_ui_layer()
	_build_audio()
	print("[CatCatcher] 点猫选中 / 点高亮格移动（狗立刻行动）/ 悬停看威胁范围 | 右上角按钮或 Z 悔棋、R 重开 | 通关后任意键或点屏幕进下一关")

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
	_clear_fx()          # 上一关的演出（闪白/文字/震屏）可能还没播完
	queue_redraw()

	print("[CatCatcher] 关卡 %d/%d %s | 猫 %d 只 | 狗 %s @ %s | 肉 @ %s | 上限 %d 回合" % [
		_level_index + 1, Levels.count(), level.display_name,
		level.cat_spawns.size(), level.dog_type,
		str(level.dog_pos), str(level.meat_pos), level.max_turns,
	])


func _has_next_level() -> bool:
	return _level_index + 1 < Levels.count()


func _on_state_changed() -> void:
	_sync_units()
	_refresh_buttons()
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

	# 图层顺序：猫和狗压在肉的上面 —— 守肉的那只猫必须看得见（不然它就像消失了）
	if _meat_node != null:
		_meat_node.z_index = 0
	for node in _cat_nodes:
		node.z_index = 2
	if _dog_node != null:
		_dog_node.z_index = 3


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


func _process(delta: float) -> void:
	_apply_shake(delta)
	if level == null or controller == null:
		return

	if not controller.finished:
		_idle += delta
		if _idle >= _hint_cfg("idle_seconds", 60.0):
			_update_hint()
			queue_redraw()

		# 引导箭头的浮动动画：只在有提示时每帧重画（没提示就一次都不重画）
		if not _hint_step.is_empty():
			_hint_time += delta
			queue_redraw()

	_update_fx(delta)
	_update_meat_rot()

	# 撞飞命中环的生命周期
	if _hit_t > 0.0:
		_hit_t = maxf(0.0, _hit_t - delta)
		queue_redraw()


## 肉随时间变质：越接近回合上限越暗、越往烂掉的黄绿走（纯 modulate，不用新美术）
func _update_meat_rot() -> void:
	if _meat_node == null or level == null or controller == null or controller.state == null:
		return
	var budget := maxi(level.max_turns, 1)
	var frac := clampf(float(controller.state.turn) / float(budget), 0.0, 1.0)
	_meat_node.modulate = Color(1, 1, 1).lerp(Color(0.52, 0.60, 0.34), frac)


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
	_draw_hit_burst()
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


## 撞飞命中环：从被吃的那格往外炸一圈，越扩越淡（画在最底层，猫飞在上面）
func _draw_hit_burst() -> void:
	if _hit_t <= 0.0 or _hit_cell.x < 0:
		return
	var k := 1.0 - clampf(_hit_t / 0.45, 0.0, 1.0)        # 0 -> 1
	var c := _cell_rect(_hit_cell).get_center()
	var tint := Color(1.0, 0.95, 0.75, 1.0 - k)
	draw_arc(c, cell_size * (0.20 + 0.55 * k), 0.0, TAU, 32, tint, 4.0 * (1.0 - k) + 1.0)
	draw_circle(c, cell_size * (0.30 - 0.24 * k), Color(tint.r, tint.g, tint.b, 0.35 * (1.0 - k)))


## 狗站在被控制的格上 => 红色描边（"它已经被罩住了"）
## 狗贴着肉格 => 肉格描红；已经低吼过 => 加粗 + "EAT!"，这是最后的警告
func _draw_dog_warning(controlled: Dictionary) -> void:
	var state := controller.state
	var dog_cell: Vector2i = state.dog["pos"]
	var dog_cfg: Dictionary = config.get("dog", {})
	var width := float(dog_cfg.get("warning_width", 3))

	if controlled.has(dog_cell):
		draw_rect(_cell_rect(dog_cell), Color(String(dog_cfg.get("warning_outline", "#e03e3e"))), false, width)

		if not controller.finished:
			if Encircle.can_flee(state):
				# 会被赶走：它下回合自己跑
				_text_centered("FLEE", _cell_rect(dog_cell).get_center().x,
					_cell_rect(dog_cell).position.y - 8.0, FONT_SMALL,
					Color(String(dog_cfg.get("warning_outline", "#e03e3e"))))
			else:
				# 罩住了但赶不动：旁边有吃得掉的猫，它会先咬那只
				_text_centered("WILL BITE", _cell_rect(dog_cell).get_center().x,
					_cell_rect(dog_cell).position.y - 8.0, FONT_SMALL, _color("selected"))
				var bite := Color("#e07a3e")
				for f in Encircle.flickable_cats(state):
					var r := _cell_rect(f["cell"]).grow(-4)
					draw_rect(r, bite, false, 2.5)
					_text_centered("!", r.get_center().x, r.position.y + 12.0, FONT_SMALL, bite)

	var d: Vector2i = dog_cell - state.meat_pos
	if absi(d.x) + absi(d.y) == 1:
		var meat_rect := _cell_rect(state.meat_pos)
		draw_rect(meat_rect, _color("growl"), false, width if state.growling else 2.0)
		if state.growling:
			_text_centered("EAT!", meat_rect.get_center().x, meat_rect.position.y - 8, FONT_MID, _color("growl"))


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
	if kind == "growl":
		var growl_rect := _cell_rect(controller.state.dog["pos"])
		_text_centered("GROWL", growl_rect.get_center().x, growl_rect.position.y - 8, FONT_MID, warn)
		return
	if kind == "flee":
		# 罩住它站的格 => 它下回合会往安全格跑
		var flee_to := _cell_rect(preview["to"]).get_center()
		var flee_from := _cell_rect(controller.state.dog["pos"]).get_center()
		draw_line(flee_from, flee_to, warn, 3.0)
		draw_arc(flee_to, cell_size * 0.32, 0.0, TAU, 24, warn, 3.0)
		_text_centered("FLEE", flee_from.x, _cell_rect(controller.state.dog["pos"]).position.y - 8, FONT_SMALL, warn)
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

	var cat_cell := _hint_cell(_hint_step["cat"])
	var from := _cell_rect(cat_cell).get_center()
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

	_text("TURN %d / %d" % [state.turn, level.max_turns], bar_pos, FONT_MID, Color(0.9, 0.87, 0.8))
	_text("LEVEL %d / %d" % [_level_index + 1, Levels.count()],
		bar_pos + Vector2(bar_w - 96, 0), FONT_MID, Color(0.9, 0.87, 0.8))

	# 回合流程：点猫 -> 点高亮格 => 走完狗立刻行动
	if not controller.finished:
		_text("tap a cat, then a highlighted cell",
			bar_pos + Vector2(0, 26), FONT_SMALL, Color(0.78, 0.74, 0.66))
		# 狗已经低吼过 => 下一回合就吃肉了，这是最后的警告
		if state.growling:
			_text("THE DOG IS GROWLING - COVER THE MEAT!",
				bar_pos + Vector2(0, 46), FONT_SMALL, _color("growl"))
		elif Encircle.can_flee(state):
			_text("covering the dog makes it run - herd it into a corner",
				bar_pos + Vector2(0, 46), FONT_SMALL, _color("selected"))
		elif MoveRules.controlled_cells(state).has(state.dog["pos"]):
			# 常见误解：罩住了不等于赶得走 —— 它旁边有能吃的猫就先咬人
			_text("it would bite an unprotected cat first",
				bar_pos + Vector2(0, 46), FONT_SMALL, Color("#e07a3e"))

	_text("Z undo     R restart", bar_pos + Vector2(0, 84), FONT_SMALL, Color(0.62, 0.58, 0.5))

	# 提示文字放棋盘右侧空白处，别挤 HUD 下面那点地方
	if not _hint_step.is_empty() and not controller.finished:
		var cat_cell := _hint_cell(_hint_step["cat"])
		var to_cell := _hint_cell(_hint_step["to"])
		_text("HINT", bar_pos + Vector2(bar_w + 24, 6), FONT_SMALL, _color("hint"))
		_text("(%d,%d)" % [cat_cell.x, cat_cell.y], bar_pos + Vector2(bar_w + 24, 26), FONT_SMALL, Color(0.85, 0.82, 0.76))
		_text("-> (%d,%d)" % [to_cell.x, to_cell.y], bar_pos + Vector2(bar_w + 24, 44), FONT_SMALL, Color(0.85, 0.82, 0.76))


# ------------------------------------------------------------ 演出（无美术）----
#
# 这几样全靠代码和现成占位贴图，不需要任何新美术：
#   · 屏幕震动（board 整体平移 + 衰减）
#   · 闪白 / 闪红 + 大号文字弹入（CanvasLayer，永远盖在单位上面）
#   · 猫被撞飞时在原格留一个残影，用 dissolve.gdshader 烧掉

func _build_fx_layer() -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 5            # 在结算层（10）下面
	add_child(_fx_layer)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_flash)

	_banner_wrap = Control.new()
	_banner_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_wrap.visible = false
	_fx_layer.add_child(_banner_wrap)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 52)
	_banner.add_theme_color_override("font_color", Color("#fff4d6"))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_wrap.add_child(_banner)


func _shake(duration: float, amplitude: float) -> void:
	_shake_dur = maxf(duration, 0.001)
	_shake_t = _shake_dur
	_shake_amp = amplitude


## 震屏：整体平移 board 节点，幅度随时间线性衰减到 0。
## ⚠️ 因为 board 会动，_point_to_cell 必须用 to_local(get_global_mouse_position())，
##    否则震屏那零点几秒里点击会错位。
func _apply_shake(delta: float) -> void:
	if _shake_t <= 0.0:
		if position != Vector2.ZERO:
			position = Vector2.ZERO
		return
	_shake_t -= delta
	var k := clampf(_shake_t / _shake_dur, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	position = Vector2(sin(t * 61.0), cos(t * 47.0)) * _shake_amp * k


## 受击反馈：狗啃肉 => 小震 + 红光
func _punch_meat() -> void:
	_shake(0.22, 6.0)
	_flash.color = Color(0.85, 0.15, 0.1, 0.22)


func _start_finish_fx(is_win: bool) -> void:
	_fx_seq = "win" if is_win else "lose"
	_fx_t = 0.0
	if is_win:
		_banner.text = "ENCIRCLED!"
		_banner.add_theme_color_override("font_color", Color("#c9f08a"))
		_shake(0.6, 14.0)
	else:
		_shake(0.45, 9.0)


## 结算演出：先播完再弹结算面板，节奏按 _fx_t 走，不用 await（悔棋/重开时能干净打断）
func _update_fx(delta: float) -> void:
	if _fx_seq.is_empty():
		return
	_fx_t += delta

	var flash_alpha := 0.0
	if _fx_seq == "win":
		flash_alpha = 0.9 * maxf(0.0, 1.0 - _fx_t / 0.22)
		if _fx_t >= 0.10:
			_banner_wrap.visible = true
			var p := clampf((_fx_t - 0.10) / 0.26, 0.0, 1.0)
			# ease-out + 轻微回弹，比线性有精神
			var s := 0.55 + 0.55 * (1.0 - pow(1.0 - p, 3.0))
			_banner_wrap.scale = Vector2(s, s)
			_banner_wrap.pivot_offset = get_viewport_rect().size * 0.5
		if _fx_t >= 1.0:
			_end_finish_fx()
			return
	else:
		flash_alpha = 0.45 * maxf(0.0, 1.0 - _fx_t / 0.30)
		if _fx_t >= 0.55:
			_end_finish_fx()
			return

	var c := _flash.color
	_flash.color = Color(c.r, c.g, c.b, flash_alpha)


func _end_finish_fx() -> void:
	_fx_seq = ""
	_flash.color = Color(_flash.color.r, _flash.color.g, _flash.color.b, 0.0)
	_banner_wrap.visible = false
	_banner_wrap.scale = Vector2.ONE
	_show_result()


func _clear_fx() -> void:
	_fx_seq = ""
	_fx_t = 0.0
	_shake_t = 0.0
	position = Vector2.ZERO
	if _flash != null:
		_flash.color = Color(_flash.color.r, _flash.color.g, _flash.color.b, 0.0)
	if _banner_wrap != null:
		_banner_wrap.visible = false
		_banner_wrap.scale = Vector2.ONE


## 猫被撞飞（被狗吃掉）：**螺旋起飞** —— 往上飞、绕两圈、缩小淡出。
## 用的是猫自己那张贴图的副本，所以换美术不用改这里；残影只是视觉，不参与任何规则运算。
## 参数偏"夸张"是故意的：小贴图 + 1 秒的位移在手机上很容易看漏。
func _spawn_takeoff(source: Node2D, cell: Vector2i) -> void:
	if source == null or not (source is Sprite2D):
		return
	var sprite := source as Sprite2D
	if sprite.texture == null:
		return

	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.scale = sprite.scale * 1.35      # 起手放大一下，像被撞飞
	ghost.modulate = sprite.modulate
	ghost.z_index = 40                     # 飞在天上，压在其它单位上面
	ghost.position = _cell_center(cell)

	var host: Node = _level_root if _level_root != null else self
	host.add_child(ghost)

	var base := ghost.position
	var base_scale := sprite.scale * 1.35
	var tween := create_tween()
	tween.tween_method(_tick_takeoff.bind(ghost, base, base_scale), 0.0, 1.0, 1.5)
	tween.tween_callback(ghost.queue_free)


## 螺旋轨迹：x 绕两圈摆（半径 36），y 一路升 200px，边转边缩，后半程淡出。
func _tick_takeoff(p: float, ghost: Sprite2D, base: Vector2, base_scale: Vector2) -> void:
	if not is_instance_valid(ghost):
		return
	var turn := p * TAU * 2.0
	ghost.position = base + Vector2(cos(turn) * 36.0, -p * 200.0)
	ghost.rotation = turn
	ghost.scale = base_scale * (1.0 - 0.78 * p)
	ghost.modulate.a = 1.0 - clampf((p - 0.55) / 0.45, 0.0, 1.0)


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


## 屏幕按钮：**手机上没键盘**，悔棋/重开必须点到。
## 贴右上角（锚点跟着视口走），focus_mode=NONE 免得键盘焦点被按钮吃掉。
func _build_ui_layer() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 6
	add_child(_ui_layer)

	_undo_btn = _make_hud_button("UNDO", 1)
	_undo_btn.pressed.connect(func() -> void:
		_sfx("click")
		controller.undo()
		_selected = -1
		_bump_version()
		_update_hint()
		_hide_result()
		_sync_units()
		queue_redraw())

	_restart_btn = _make_hud_button("RESTART", 0)
	_restart_btn.pressed.connect(func() -> void:
		_sfx("click")
		_start_level(_level_index))

	_refresh_buttons()


## slot 0 = 最靠右，slot 1 = 它左边一个
func _make_hud_button(text: String, slot: int) -> Button:
	var b := Button.new()
	b.text = text
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -136.0 - 140.0 * slot
	b.offset_right = -16.0 - 140.0 * slot
	b.offset_top = 10.0
	b.offset_bottom = 44.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	_ui_layer.add_child(b)
	return b


func _refresh_buttons() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = controller == null or not controller.can_undo()


# ---------------------------------------------------------------- 音效 ----

func _build_audio() -> void:
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.volume_db = -5.0
		add_child(p)
		_sfx_players.append(p)


## 播一个音效。手机浏览器要等玩家第一次点击才解锁音频，标题页那一下点击就是手势。
func _sfx(key: String) -> void:
	if _sfx_players.is_empty() or not SFX.has(key):
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = SFX[key]
	p.play()


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
			prompt = "tap or press any key for the next level"
		else:
			prompt = "all levels cleared - tap to replay"
	_result_prompt.text = prompt
	_result_layer.visible = true


func _hide_result() -> void:
	if _result_layer != null:
		_result_layer.visible = false


## 结算页之后：赢了进下一关（最后一关则从头再来），输了重开本关。
## 手机上就是"点一下屏幕"，键盘上就是"任意键"。
func _advance_after_result() -> void:
	if not controller.finished:
		return
	if controller.won:
		_start_level(_level_index + 1 if _has_next_level() else 0)
	else:
		_start_level(_level_index)


# ---------------------------------------------------------------- 输入 ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _point_to_cell(get_global_mouse_position())
		if hovered != _hover:
			_hover = hovered
			queue_redraw()
		return

	# 结算页：任意键 / 点屏幕都继续（手机上没有键盘）
	if controller.finished:
		if event is InputEventKey and event.pressed and not event.echo:
			_advance_after_result()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_advance_after_result()
		elif event is InputEventScreenTouch and event.pressed:
			_advance_after_result()
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
			KEY_ESCAPE:
				_selected = -1
		queue_redraw()
		return

	# 触摸：手机上没有鼠标，用 ScreenTouch 走同一套逻辑
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(_point_to_cell(event.position))
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_handle_tap(_point_to_cell(get_global_mouse_position()))


## 棋盘上的一次点击/触摸：点高亮格 = 走（狗立刻行动）；点猫 = 选中；点别处 = 取消
func _handle_tap(cell: Vector2i) -> void:
	if cell.x < 0:
		return
	_reset_idle()

	if _selected >= 0 and MoveRules.legal_moves(controller.state, _selected).has(cell):
		_apply_move(_selected, cell)
		return

	_selected = controller.state.cat_at(cell)
	queue_redraw()


## 走一步：走完狗立刻行动，顺便播反馈。
## 全靠"动手前后对比 state"判断发生了什么，不需要 Core 额外回报。
func _apply_move(cat_index: int, to: Vector2i) -> void:
	var before_dog: Vector2i = controller.state.dog["pos"]
	var before_cells: Array = []
	for c in controller.state.cats:
		before_cells.append(c["pos"])

	controller.move_cat(cat_index, to)

	var eaten := false

	# 狗吃到肉 => 红光 + 震屏（结算演出接着上）
	if controller.result_reason == "meat_eaten":
		_punch_meat()
		_shake(0.3, 8.0)
	# 有猫被吃掉 => 螺旋起飞残影
	# ⚠️ 必须跳过玩家刚走的那只猫 —— 它的位置也变了，但那是自己走的，不是被吃
	for i in controller.state.cats.size():
		if i >= before_cells.size():
			break
		if i == cat_index:
			continue
		if controller.state.cats[i]["pos"] != before_cells[i]:
			_spawn_takeoff(_cat_nodes[i] if i < _cat_nodes.size() else null, before_cells[i])
			_hit_cell = before_cells[i]      # 命中环：飞出去了也还剩这一下
			_hit_t = 0.45
			_shake(0.2, 5.0)
			eaten = true
	# 狗自己挪了窝 => 轻震一下
	if controller.state.dog["pos"] != before_dog:
		_shake(0.15, 3.0)

	# 一次行动只播一个音效：吃子 > 低吼 > 挪动（吃肉的音效交给结算页的 lose）
	if eaten:
		_sfx("flick")
	elif controller.result_reason != "meat_eaten":
		_sfx("growl" if controller.state.growling else "move")

	_selected = -1
	_bump_version()
	_update_hint()
	_sync_units()
	queue_redraw()


func _on_game_over(is_win: bool, _reason: String) -> void:
	_selected = -1
	if not is_win:
		_fail_count += 1
	_sfx("win" if is_win else "lose")
	_start_finish_fx(is_win)      # 先播演出，演完 _end_finish_fx 才弹结算
	queue_redraw()


# ---------------------------------------------------------------- 工具 ----

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(board_origin + cell * cell_size), Vector2(cell_size, cell_size))


## 屏幕坐标 -> 格子。棋盘外返回 (-1, -1)。
## ⚠️ 先 to_local：震屏时 board 整体在平移，直接拿 global 坐标比会错位。
func _point_to_cell(p: Vector2) -> Vector2i:
	var local := to_local(p) - Vector2(board_origin)
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
