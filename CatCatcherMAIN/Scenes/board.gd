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

## ---- 字体 ----
## 得意黑（Smiley Sans，斜体标题字）：大字、数字、棋盘上的警告标签。
## 霞鹜文楷（LXGW WenKai，正文字）：HUD 说明文字、结算说明。
## ⚠️ 用的是 **subset/** 里的子集字体（ASCII + 屏幕文案里出现的汉字），合计几十 KB。
##    改过中文文案后要重跑 tools/subset_font.gd 再 --import，否则新加的字会缺字形。
const FONT_DISPLAY := preload("res://CatCatcherMAIN/Fonts/subset/display.ttf")
const FONT_BODY := preload("res://CatCatcherMAIN/Fonts/subset/body.ttf")

## 单位平移的时长。原来是 0.16，改成"我方猫先动、狗后动"两拍后**速度翻倍**（各 0.08，
## 总时长还是 0.16）—— 狗那一拍正好接在猫滑完的瞬间。
const SLIDE_SECONDS := 0.08

## 警告文字那一层的脚本（画在单位/障碍上面，见 _build_warn_layer）
const WARN_LAYER := preload("res://CatCatcherMAIN/Scenes/warn_layer.gd")

## ---- 美术：狗的三个状态 + 提示笔刷 ----
## 狗的场景默认是待机图；低吼 / 撕咬 / 困毙在 _sync_units() 里换贴图（换美术只改这几张图）。
const TEX_DOG_IDLE := preload("res://CatCatcherMAIN/Graphics/Dog/art_dog_idle.png")
const TEX_DOG_GROWL := preload("res://CatCatcherMAIN/Graphics/Dog/art_dog_growl.png")
const TEX_DOG_BITE := preload("res://CatCatcherMAIN/Graphics/Dog/art_dog_bite.png")
const TEX_DOG_TRAPPED := preload("res://CatCatcherMAIN/Graphics/Dog/art_dog_trapped.png")
## 提示箭头（蓝）= 尾巴（横线，沿长度方向拉伸）+ 头（默认朝左，按方向旋转）+ 落点圈
const TEX_TIP_TAIL := preload("res://CatCatcherMAIN/Graphics/Tips/art_arrow_tail.png")
const TEX_TIP_HEAD := preload("res://CatCatcherMAIN/Graphics/Tips/art_arrow_head.png")
const TEX_TIP_RING := preload("res://CatCatcherMAIN/Graphics/Tips/art_ring.png")
## 危险/预览箭头（橙）：悬停预览"狗下一步会干什么"用的同一套笔刷
const TEX_WARN_LINE := preload("res://CatCatcherMAIN/Graphics/Tips/art_line_orange.png")
const TEX_WARN_HEAD := preload("res://CatCatcherMAIN/Graphics/Tips/art_arrow_orange.png")
const TEX_WARN_RING := preload("res://CatCatcherMAIN/Graphics/Tips/art_ring_orange.png")
## 控制格（猫能罩住的格）：青色爪印方砖
const TEX_CONTROL_CELL := preload("res://CatCatcherMAIN/Graphics/Grids/art_control_cell.png")
## 右上角三个图标按钮
const TEX_BTN_UNDO := preload("res://CatCatcherMAIN/Graphics/Button/art_btn_undo.png")
const TEX_BTN_RESTART := preload("res://CatCatcherMAIN/Graphics/Button/art_btn_restart.png")
const TEX_BTN_HINT := preload("res://CatCatcherMAIN/Graphics/Button/art_btn_hint.png")

## Core 只给 code，屏幕文案在这里映射成中文（项目里自带 CJK 字体，web 版也能画）。
const REASON_TEXT := {
	"encircled": "狗没路可走了",
	"meat_eaten": "肉被狗吃掉了",
	"timeout": "回合用完了",
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
var _control_alpha: float = 0.3     # 控制格爪印的不透明度（配置 board.control_alpha）

## ---- 屏幕适配（竖屏 / 横屏）----
## 设计坐标永远是 960×540 那一套（格子/原点直接读配置），只按画布算 Camera2D 的 zoom
## （见 layout.gd）。这样单位、障碍、笔刷、线宽全都跟着相机缩放 —— **不会再漏**。
## `_ui_scale` = 相机 zoom，只用于 CanvasLayer 里的 Control（按钮 / 结算文字 / 大标语）：
## CanvasLayer 不受相机影响，不另外放大在手机上就只剩 15px。
const LAYOUT := preload("res://CatCatcherMAIN/Scenes/layout.gd")
const HUD_UNITS := 170.0            # 竖屏取景时棋盘下方 HUD 的高度
const HINT_UNITS := 110.0           # 竖屏取景时棋盘上方给"提示"那三行留的高度
var _portrait: bool = false
var _ui_scale: float = 1.0
var _cam: Camera2D = null

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
var _hint_btn: Button = null

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
var _hint_forced: bool = false    # 玩家按了 "?" —— 这一关就一直给提示

## ---- 警告文字/笔刷层（画在单位/障碍上面）----
## board 的 _draw() 把要写的字、要画的笔刷塞进来，_warn_layer 负责落笔（见 _build_warn_layer）
var warn_texts: Array = []
var warn_draws: Array = []
var _warn_layer: Node2D = null

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

	colors = config["board"]["colors"]
	_control_alpha = float(config["board"].get("control_alpha", 0.62))
	cell_size = int(config["board"]["cell_size"])
	var o: Array = config["board"]["origin"]
	board_origin = Vector2i(int(o[0]), int(o[1]))

	_cam = $Camera                                   # 竖屏/横屏只动这台相机（见 layout.gd）
	_layout_board()
	get_window().size_changed.connect(_on_window_resized)

	controller = GameController.new()
	controller.state_changed.connect(_on_state_changed)
	controller.game_over.connect(_on_game_over)

	RenderingServer.set_default_clear_color(_color("bg"))
	_build_fx_layer()
	_build_result_layer()
	_build_ui_layer()
	_build_warn_layer()
	_build_audio()
	print("[CatCatcher] 点猫选中 / 点高亮格移动（狗立刻行动）/ 悬停看威胁范围 | 右上角按钮或 Z 悔棋、R 重开 | 通关后任意键或点屏幕进下一关")

	# 启动校验：每关都必须有解（求解器真搜，不是读标准答案糊弄）
	# ⚠️ 只在 debug 版跑：8 关在 depth=6 全搜一遍要 1 秒（web 上更久），
	#    玩家一点进棋盘就卡一秒不值当。发布包靠 tests/solvecheck.gd 在开发期守着。
	if OS.is_debug_build():
		var problems := Levels.validate_all(config)
		for p in problems:
			push_error("[关卡校验] " + String(p))
		if problems.is_empty():
			print("[CatCatcher] 关卡校验通过（%d 关全部有解）" % Levels.count())

	# 从编辑器里 F6 单独跑某一关时，关卡场景会先把路径写进 RunRequest
	var start := Levels.index_of_path(RunRequest.level_path)
	RunRequest.level_path = ""
	_start_level(maxi(start, 0))


## 按当前画布算相机取景（横屏 zoom=1 原构图；竖屏把棋盘+HUD 那块铺满画布）。
## 设计坐标不动 —— 这是和隔壁 CameraRig._apply_adaptive_zoom 同一套思路。
func _layout_board() -> void:
	var cols := level.w if level != null else 6
	var rows := level.h if level != null else 6
	var board := Rect2(Vector2(board_origin), Vector2(cols * cell_size, rows * cell_size))
	var fit := LAYOUT.view_fit(get_viewport_rect().size, board, HUD_UNITS, HINT_UNITS)
	_portrait = bool(fit["portrait"])
	_ui_scale = float(fit["zoom"])
	if _cam != null:
		_cam.position = fit["center"]
		_cam.zoom = Vector2(_ui_scale, _ui_scale)
	_apply_ui_scale()


## 转屏 / 拖动窗口大小：重算取景并重画笔（局面不动）。
func _on_window_resized() -> void:
	if config.is_empty():
		return
	_layout_board()
	queue_redraw()


## CanvasLayer 里的 Control 不吃相机缩放，所以按钮/结算字/大标语得自己按 _ui_scale 放大。
## 位置和字号都按 _ui_scale 一起乘 —— 只乘字号会导致结算那几行文字**叠在一起**。
func _apply_ui_scale() -> void:
	var k := _ui_scale
	for b in [_undo_btn, _restart_btn, _hint_btn]:
		if b == null:
			continue
		var slot := int(b.get_meta("slot", 0))
		b.offset_left = (-60.0 - 62.0 * slot) * k
		b.offset_right = (-8.0 - 62.0 * slot) * k
		b.offset_top = 8.0 * k
		b.offset_bottom = 48.0 * k
		b.add_theme_constant_override("icon_max_width", int(round(38.0 * k)))
	for l in [_result_title, _result_reason, _result_prompt]:
		if l != null:
			_place_result_label(l)
	if _banner != null:
		_banner.add_theme_font_size_override("font_size", int(round(52.0 * k)))


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

	# 单位贴图是按 64px 的格子画的：设计坐标不动，位置由相机缩放（不需要改 scale）
	if level == null:
		push_error("关卡加载失败: index %d" % _level_index)
		return

	controller.setup(level, config)
	_layout_board()          # 关卡的 w/h 到这时候才知道
	_selected = -1
	_hover = Vector2i(-1, -1)
	_fail_count = 0
	_hint_forced = false       # 换关/重开就忘掉上一关按过的 "?"
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
		_sync_dog_face()


## 狗的样子：围死（赢）=> 困毙；这回合要咬猫 => 撕咬；低吼中 => 低吼；其它 => 待机。
## 只有一个来源：Core 的 state / DogAI.plan，别在这里自行判断"它看起来像要咬人了"。
func _sync_dog_face() -> void:
	if not (_dog_node is Sprite2D):
		return
	var sprite := _dog_node as Sprite2D
	var act := "" if controller.finished else String(controller.preview_dog_action().get("kind", ""))
	if controller.finished and controller.won:
		sprite.texture = TEX_DOG_TRAPPED
	elif act == "flick":
		sprite.texture = TEX_DOG_BITE
	elif controller.state.growling:
		sprite.texture = TEX_DOG_GROWL
	else:
		sprite.texture = TEX_DOG_IDLE


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(board_origin) + Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5


## 平移小动画：把节点摆回 from 再滑到 to。位置真相永远是 _sync_units() 摆好的那个，
## 这里只补最后一跳的观感（同一帧内先摆回原位，看不出跳变）。
## ponytail: 不做 tween 去重 —— 两条 tween 抢同一个 position 时后建的每帧最后写，视觉上不会抖。
func _slide_unit(node: Node2D, from: Vector2, to: Vector2) -> void:
	if node == null or from.is_equal_approx(to):
		return
	node.position = from
	create_tween().bind_node(node).tween_property(node, "position", to, SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- 提示 ----

## 警告文字独立成一层：单位和障碍是 board 的子节点，永远压在 board 自己的 _draw() 上（9.2），
## 所以棋盘上的字必须由一个**后画的兄弟节点**来画。z_index 要高于撞飞残影（40）。
func _build_warn_layer() -> void:
	_warn_layer = WARN_LAYER.new()
	_warn_layer.name = "WarnLayer"
	_warn_layer.board = self
	_warn_layer.z_index = 60
	add_child(_warn_layer)


func _bump_version() -> void:
	_version += 1


func _hint_cfg(key: String, fallback: float) -> float:
	return float(config.get("hint", {}).get(key, fallback))


## 这一关现在该不该给提示。
func _hint_due() -> bool:
	if controller.finished:
		return false
	if _hint_forced:
		return true                                       # 玩家按了 "?"，这一关一直给
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
	warn_texts.clear()          # 警告文字/笔刷这一帧要重算（由 _warn_layer 落笔）
	warn_draws.clear()
	_draw_cells()

	var controlled := MoveRules.controlled_cells(state)
	_draw_control(controlled)
	_draw_focus_reach()
	_draw_dog_warning(controlled, _preview_labels_dog())
	_draw_preview()
	_draw_selection()
	_draw_hit_burst()
	_draw_hint()
	_draw_hud()
	if _warn_layer != null:
		_warn_layer.queue_redraw()
	# 结算界面不在这里画 —— 单位是场景子节点，会盖住 _draw() 的内容。
	# 结算用 CanvasLayer（永远在最上层），见 _build_result_layer。


func _draw_cells() -> void:
	for y in level.h:
		for x in level.w:
			var cell := Vector2i(x, y)
			var fill: Color = _color("cell") if (x + y) % 2 == 0 else _color("cell_alt")
			draw_rect(_cell_rect(cell), fill)


func _draw_control(controlled: Dictionary) -> void:
	# 控制格 = 猫罩得住的格 = 狗进不去的格。这张爪印方砖就是整个玩法唯一要教的东西。
	# 不透明度走配置（board.control_alpha）：铺满半块盘时全不透明太抢眼。
	var tint := Color(1.0, 1.0, 1.0, _control_alpha)
	for cell in controlled:
		draw_texture_rect(TEX_CONTROL_CELL, _cell_rect(cell), false, tint)


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
## hide_text：悬停预览正在狗头上那一行写字时闭嘴 —— 两者是同一格同一行，都画就是叠字。
func _draw_dog_warning(controlled: Dictionary, hide_text := false) -> void:
	var state := controller.state
	var dog_cell: Vector2i = state.dog["pos"]
	var dog_cfg: Dictionary = config.get("dog", {})
	var width := float(dog_cfg.get("warning_width", 3))
	var red := Color(String(dog_cfg.get("warning_outline", "#e03e3e")))

	# 这回合狗究竟会干什么 —— **整个函数只算一次**，狗头和肉格两边共用同一个答案。
	# 各画各的曾经出过事：狗贴着肉时狗头写 "EATING THE MEAT"、肉格又写 "EAT!"，两行字叠在一起。
	var act := ""
	if not controller.finished:
		act = String(controller.preview_dog_action().get("kind", ""))

	if controlled.has(dog_cell):
		draw_rect(_cell_rect(dog_cell), red, false, width)

		# 罩住了 ≠ 赶得走：念它这回合真正会做的动作（DogAI.plan 是唯一来源）。
		if not hide_text:
			var cx := _cell_rect(dog_cell).get_center().x
			var ty := _cell_rect(dog_cell).position.y - 8.0
			match act:
				"flee":
					_warn_text("逃跑", cx, ty, FONT_SMALL, red)
				"flick":
					_warn_text("先咬猫", cx, ty, FONT_SMALL, _color("selected"))

		# 没被保护的猫任何时候都标出来（"它吃得到谁"这条信息成立，跟它先吃谁无关）
		if not controller.finished:
			var bite := Color("#e07a3e")
			for f in Encircle.flickable_cats(state):
				var r := _cell_rect(f["cell"]).grow(-4)
				draw_rect(r, bite, false, 2.5)
				_warn_text("!", r.get_center().x, r.position.y + 12.0, FONT_SMALL, bite)

	# 肉格：**吃肉预警只画在这一处**（狗头那边不再重复）。
	var d: Vector2i = dog_cell - state.meat_pos
	if absi(d.x) + absi(d.y) == 1:
		var meat_rect := _cell_rect(state.meat_pos)
		var hot := act == "eat" or act == "growl"      # 真要吃 / 马上要吃
		draw_rect(meat_rect, _color("growl"), false, width if hot else 2.0)
		if act == "eat" and not hide_text:
			_warn_text("吃肉!", meat_rect.get_center().x, meat_rect.position.y - 8, FONT_MID, _color("growl"))


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
		_warn_text("围死了!", dog_rect.get_center().x, dog_rect.position.y - 8, FONT_MID, Color("#7fb069"))
		return
	if kind == "none":
		return
	if kind == "growl":
		var growl_rect := _cell_rect(controller.state.dog["pos"])
		_warn_text("低吼", growl_rect.get_center().x, growl_rect.position.y - 8, FONT_MID, warn)
		return
	if kind == "flee":
		# 罩住它站的格 => 它下回合会往安全格跑
		var flee_to := _cell_rect(preview["to"]).get_center()
		var flee_from := _cell_rect(controller.state.dog["pos"]).get_center()
		_draw_warn_arrow(flee_from, flee_to)
		_warn_text("逃跑", flee_from.x, _cell_rect(controller.state.dog["pos"]).position.y - 8, FONT_SMALL, warn)
		return

	var target: Vector2i = preview["to"]
	if kind == "eat":
		target = controller.state.meat_pos
	var from := _cell_rect(controller.state.dog["pos"]).get_center()
	var to := _cell_rect(target).get_center()

	# ① 先画"走到这一格之后，这只猫会控住哪些格"—— 这是玩家最想知道的那件事
	var after_move := controller.state.clone()
	after_move.cats[cat_index]["pos"] = _hover
	# 半透明的爪印（和真正控制格同一张图），加绿边表示"这是走完之后才会有的控制"
	var ghost_tint := Color(1.0, 1.0, 1.0, 0.45)
	var hyp_edge := Color(0.60, 0.86, 0.44, 0.9)
	for cell in MoveRules.reach_cells(after_move, cat_index):
		draw_texture_rect(TEX_CONTROL_CELL, _cell_rect(cell), false, ghost_tint)
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

	# ③ 箭头和落点画在最上面（手绘橙色笔刷，和蓝色提示箭头同一套画法）
	_draw_warn_arrow(from, to)


## 橙色笔刷箭头：尾巴 + 头 + 落点圈。悬停预览用（狗这回合会做什么 / 会逃到哪）。
func _draw_warn_arrow(from: Vector2, to: Vector2) -> void:
	var d := to - from
	if d.length() < 1.0:
		return
	var dir := d.normalized()
	var ring_px := cell_size * 0.40
	_draw_brush_center(TEX_WARN_RING, to, ring_px)
	_draw_brush_tail(TEX_WARN_LINE, from + dir * cell_size * 0.18, to - dir * ring_px * 0.42)
	_draw_brush_head(TEX_WARN_HEAD, to - dir * ring_px * 0.42, dir, cell_size * 0.34)


## 悬停预览会不会在狗头上那一行写字（FLEE / GROWL / ENCIRCLED）。
## 会和"当前局面"的 FLEE / WILL BITE 撞同一行 —— 谁在预览，静态那行就让位。
func _preview_labels_dog() -> bool:
	if controller.finished:
		return false
	var cat_index := _preview_cat_index()
	if cat_index < 0:
		return false
	var preview := controller.preview_after(cat_index, _hover)
	if preview.is_empty():
		return false
	return String(preview["kind"]) in ["flee", "growl", "encircled"]


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


## 引导：一条从"该动的那只猫"指向目标格的手绘箭头 + 落点圈，外加猫头顶上下浮动的小箭头
## （"点这一只"）。全部用 Tips/ 里的三张笔刷贴图画，不再自己拼多边形。
## 方向来源是求解器，见 _update_hint。
func _draw_hint() -> void:
	if _hint_step.is_empty() or controller.finished:
		return

	var from := _cell_rect(_hint_cell(_hint_step["cat"])).get_center()
	var to := _cell_rect(_hint_cell(_hint_step["to"])).get_center()
	var d := to - from
	if d.length() < 1.0:
		return
	var dir := d.normalized()

	# 一步之遥时格子之间本来就没多少空地，圈和箭头都得缩小，否则挤成一坨
	var near := d.length() < cell_size * 1.45
	var ring_px := cell_size * (0.50 if near else 0.70)

	# 落点圈（画最下层，箭头压在它上面）
	_draw_brush_center(TEX_TIP_RING, to, ring_px)
	# 尾巴：从猫那一格的边缘拉到圈的外侧
	var start := from + dir * cell_size * 0.22
	var tip := to - dir * (ring_px * 0.42)
	_draw_brush_tail(TEX_TIP_TAIL, start, tip)
	# 箭头：笔刷默认朝左，按方向转过去，并把"笔尖"对准 tip
	_draw_brush_head(TEX_TIP_HEAD, tip, dir, cell_size * (0.36 if near else 0.46))

	# 猫头顶浮动的小箭头：同一个笔刷缩小、朝下
	var bob := sin(_hint_time * 4.5) * cell_size * 0.07
	_draw_brush_head(TEX_TIP_HEAD, Vector2(from.x, from.y - cell_size * 0.50 + bob), Vector2.DOWN, cell_size * 0.26)


## 把一张笔刷贴图按"可见区域"居中画在 at 处，可见直径约 want_px。
## 200×200 的画布里图形只占一部分，所以按实测的不透明包围盒换算，不然会画小一圈。
## （蓝/橙两套笔刷的包围盒一致，所以共用这一份换算。）
## ⚠️ 笔刷和警告文字一样会被单位贴图盖住，所以这里只登记，交给 _warn_layer 画。
func _draw_brush_center(tex: Texture2D, at: Vector2, want_px: float) -> void:
	var k := want_px / 179.0                      # 圈的不透明宽度 = 179
	var side := 200.0 * k
	# ⚠️ rect 必须是**相对 pivot 的本地坐标**：_warn_layer 会先 draw_set_transform(at, ...)
	_brush_draw(tex, at, 0.0, Rect2(-Vector2(side, side) * 0.5, Vector2(side, side)))


## 尾巴：一条横线笔刷，沿 from→to 拉伸（粗细不变）。不透明区域 y=81..120 => 中心 y=100.5、粗 40。
func _draw_brush_tail(tex: Texture2D, from: Vector2, to: Vector2) -> void:
	var d := to - from
	var length := d.length()
	if length < 6.0:
		return
	var want_thick := cell_size * 0.16
	var k := want_thick / 40.0                    # 画布里线宽 40px
	_brush_draw(tex, from, d.angle(), Rect2(0.0, -100.5 * k, length, 200.0 * k))


## 箭头：笔刷默认朝左（笔尖在不透明区域的 x=4）；转过去并让笔尖落在 tip 上。
func _draw_brush_head(tex: Texture2D, tip: Vector2, dir: Vector2, want_len: float) -> void:
	var k := want_len / 196.0                     # 不透明区域宽 196
	_brush_draw(tex, tip, dir.angle() - PI, Rect2(-4.0 * k, -101.5 * k, 200.0 * k, 200.0 * k))


## 记一次笔刷绘制：绕 pivot 转 rot 度画 rect（rect 是相对 pivot 的本地坐标）。
func _brush_draw(tex: Texture2D, pivot: Vector2, rot: float, rect: Rect2) -> void:
	warn_draws.append({ "tex": tex, "pivot": pivot, "rot": rot, "rect": rect })


func _hint_cell(arr: Array) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))


func _draw_hud() -> void:
	var state := controller.state
	var bar_w := level.w * cell_size
	var bar_pos := Vector2(board_origin.x, board_origin.y + level.h * cell_size + 14)

	_text("回合 %d / %d" % [state.turn, level.max_turns], bar_pos, FONT_MID,
		Color(0.9, 0.87, 0.8), FONT_DISPLAY)
	_text("关卡 %d / %d" % [_level_index + 1, Levels.count()],
		bar_pos + Vector2(bar_w - 96, 0), FONT_MID, Color(0.9, 0.87, 0.8), FONT_DISPLAY)

	# 回合流程：点猫 -> 点高亮格 => 走完狗立刻行动
	if not controller.finished:
		_text("点一只猫，再点高亮格",
			bar_pos + Vector2(0, 26), FONT_SMALL, Color(0.78, 0.74, 0.66))
		# 顺序有讲究：**罩住了会跑**优先于"它在低吼" —— 逃跑会打断低吼，这时喊"快去垫肉"反而是错的。
		if Encircle.can_flee(state):
			_text("罩住狗那格，它自己会跑 —— 把它赶进角落",
				bar_pos + Vector2(0, 46), FONT_SMALL, _color("selected"))
		elif MoveRules.controlled_cells(state).has(state.dog["pos"]):
			# 罩住了 ≠ 赶得走。直接念它这回合真正会做的动作（DogAI.plan 是唯一来源），
			# 别在这儿另猜一套条件 —— "低吼时罩住它为什么不动"的答案就在这两行字里。
			var act := String(controller.preview_dog_action().get("kind", ""))
			if act == "flick":
				_text("它先去咬没人罩的猫",
					bar_pos + Vector2(0, 46), FONT_SMALL, Color("#e07a3e"))
			elif act == "eat":
				_text("它要吃肉了 —— 把猫垫到肉格上",
					bar_pos + Vector2(0, 46), FONT_SMALL, _color("growl"))
			else:
				_text("它动不了，但还够得着肉",
					bar_pos + Vector2(0, 46), FONT_SMALL, Color("#e07a3e"))
		elif state.growling:
			# 狗已经低吼过 => 下一回合就吃肉了，这是最后的警告
			_text("狗在低吼 —— 快垫肉！",
				bar_pos + Vector2(0, 46), FONT_SMALL, _color("growl"))

	# 手机上没有键盘，这两行提示只在横屏（有键盘的设备）画
	if not _portrait:
		_text("Z 悔棋     R 重开", bar_pos + Vector2(0, 84), FONT_SMALL, Color(0.62, 0.58, 0.5))

	# 提示放棋盘右边（横屏）；竖屏棋盘把宽度占满了，改放棋盘上方那片空白
	if not _hint_step.is_empty() and not controller.finished:
		var cat_cell := _hint_cell(_hint_step["cat"])
		var to_cell := _hint_cell(_hint_step["to"])
		var hint_pos := bar_pos + Vector2(bar_w + 24, 6)
		if _portrait:
			hint_pos = Vector2(board_origin.x, board_origin.y - 96)
		_text("提示", hint_pos, FONT_SMALL, _color("hint"), FONT_DISPLAY)
		_text("(%d,%d)" % [cat_cell.x, cat_cell.y], hint_pos + Vector2(0, 20), FONT_SMALL, Color(0.85, 0.82, 0.76), FONT_DISPLAY)
		_text("→ (%d,%d)" % [to_cell.x, to_cell.y], hint_pos + Vector2(0, 38), FONT_SMALL, Color(0.85, 0.82, 0.76), FONT_DISPLAY)


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
	_banner.add_theme_font_override("font", FONT_DISPLAY)
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
		_banner.text = "围死了！"
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


## 猫被撞飞（被狗吃掉）：**原地疯狂旋转 + 朝一个方向直飞出去**。
## 用的是猫自己那张贴图的副本，所以换美术不用改这里；残影只是视觉，不参与任何规则运算。
## 参数偏"夸张"是故意的：小贴图 + 一秒的位移在手机上很容易看漏。
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
	# 飞出去的方向 = **背离狗**（被撞飞的方向感）。同一格理论上不会发生，兜底朝右上。
	var dir := base - _cell_center(controller.state.dog["pos"])
	if dir.length() < 1.0:
		dir = Vector2(0.6, -1.0)
	var tween := create_tween()
	tween.tween_method(_tick_takeoff.bind(ghost, base, base_scale, dir.normalized()), 0.0, 1.0, 1.2)
	tween.tween_callback(ghost.queue_free)


## 撞飞轨迹：Sprite2D 的 rotation 就是绕**自身原点**转，所以"原地疯狂旋转"和"朝一个方向平移"
## 直接叠加即可 —— 1.2 秒转 6 圈、直线飞 320px、边飞边缩、后半程淡出。
func _tick_takeoff(p: float, ghost: Sprite2D, base: Vector2, base_scale: Vector2, dir: Vector2) -> void:
	if not is_instance_valid(ghost):
		return
	ghost.rotation = p * TAU * 6.0
	ghost.position = base + dir * (320.0 * p)
	ghost.scale = base_scale * (1.0 - 0.55 * p)
	ghost.modulate.a = 1.0 - clampf((p - 0.5) / 0.5, 0.0, 1.0)


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

	_undo_btn = _make_icon_button(TEX_BTN_UNDO, 1, "悔棋 (Z)")
	_undo_btn.pressed.connect(func() -> void:
		_sfx("click")
		controller.undo()
		_selected = -1
		_bump_version()
		_update_hint()
		_hide_result()
		_sync_units()
		queue_redraw())

	_restart_btn = _make_icon_button(TEX_BTN_RESTART, 0, "重开 (R)")
	_restart_btn.pressed.connect(func() -> void:
		_sfx("click")
		_start_level(_level_index))

	# "?" = 主动要提示：和第一关那种常驻引导**长得一样**（同一个 _hint_step 渲染路径），
	# 只是把"该不该给"的判断短路掉，这一关后面就一直给
	_hint_btn = _make_icon_button(TEX_BTN_HINT, 2, "提示")
	_hint_btn.pressed.connect(func() -> void:
		_sfx("click")
		_hint_forced = true
		_hint_version = -1        # 强制重算（之前可能因为"不该给提示"被判成空）
		_update_hint()
		queue_redraw())

	_refresh_buttons()
	_apply_ui_scale()        # 按钮尺寸跟着 _ui_scale（竖屏要大一圈才点得到）


## 右上角的图标按钮（美术：Graphics/Button/）。slot 0 = 最靠右，slot 1/2 依次往左。
## flat = true：**不要默认那层深色面板**，手绘笔刷直接落在页面底色上。
## 悬停/按下靠 modulate 反馈（没有底框时不给反馈就像贴纸，点不动）。
func _make_icon_button(tex: Texture2D, slot: int, tip: String) -> Button:
	var b := Button.new()
	b.icon = tex
	b.flat = true
	b.set_meta("slot", slot)          # _apply_ui_scale 按 slot 重算偏移（竖屏按钮要放大）
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -60.0 - 62.0 * slot
	b.offset_right = -8.0 - 62.0 * slot
	b.offset_top = 8.0
	b.offset_bottom = 48.0
	b.focus_mode = Control.FOCUS_NONE
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 38)
	# 没有底框了，用图标本身的明暗变化表示悬停/按下
	b.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("icon_hover_color", Color(1, 1, 1, 1.0))
	b.add_theme_color_override("icon_pressed_color", Color(1, 1, 1, 0.65))
	b.tooltip_text = tip
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
## 大标题（size >= FONT_MID 那档）用得意黑，说明文字用文楷。
func _make_result_label(top: int, height: int, size: int, tint: Color) -> Label:
	var l := Label.new()
	l.set_meta("top", top)
	l.set_meta("height", height)
	l.set_meta("size", size)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	# 竖向锚在**画布正中**：竖屏画布能高达 2000+ 单位，固定 y=215 会让结算字跑到屏幕上方去。
	l.anchor_top = 0.5
	l.anchor_bottom = 0.5
	l.offset_left = 0.0
	l.offset_right = 0.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT_DISPLAY if size >= FONT_MID else FONT_BODY)
	l.add_theme_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(l)
	_place_result_label(l)
	return l


## 结算三行文字的**位置和字号都乘 _ui_scale**（只乘字号会让它们叠在一起）。
## 270 = 540/2，所以横屏（zoom=1）下和以前的位置一模一样。
func _place_result_label(l: Label) -> void:
	var k := _ui_scale
	var top := float(l.get_meta("top", FONT_MID)) - 270.0
	l.offset_top = top * k
	l.offset_bottom = (top + float(l.get_meta("height", FONT_MID))) * k
	l.add_theme_font_size_override("font_size", _font_px(int(l.get_meta("size", FONT_MID))))


func _show_result() -> void:
	if _result_layer == null:
		return
	_result_title.text = "赢了！" if controller.won else "输了…"
	_result_title.add_theme_color_override("font_color",
		Color("#8fd17a") if controller.won else Color("#e0705e"))
	_result_reason.text = String(REASON_TEXT.get(controller.result_reason, controller.result_reason))

	var prompt := "按 R 重开"
	if controller.won:
		if _has_next_level():
			prompt = "点屏幕或按任意键，进入下一关"
		else:
			prompt = "全部通关！点屏幕重玩"
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

## 手机上一次点击会**同时**收到 InputEventScreenTouch 和模拟出来的 InputEventMouseButton
## （项目默认 `emulate_mouse_from_touch` 是开的），不挡的话一次点会走两遍 —— 典型症状：
## 走到围死那一步，同一根手指顺带把结算页的"按任意键继续"点掉，玩家没看见胜负就进了下一关。
## ponytail: 时间窗去重够用（模拟事件和触摸几乎同时到达）；要更严格就改成按事件序列配对。
const TAP_GUARD_MS := 150
var _last_tap_ms: int = -10000


## 这一次是不是"一次新的点击/触摸按下"（合并手机上那两种表示，并去重）。
func _tap_pressed(event: InputEvent) -> bool:
	var is_tap: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not is_tap:
		return false
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < TAP_GUARD_MS:
		return false
	_last_tap_ms = now
	return true


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
		elif _tap_pressed(event) and _result_layer != null and _result_layer.visible:
			# ⚠️ 要等结算界面**真的画出来**才认这一下：赢的那一刻手指还在屏幕上，
			#    同一根手指的模拟鼠标事件会把还没看见的结算页点掉（演出要 1 秒才出结算）。
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
			KEY_F1:
				_debug_dump_dog()               # debug 版：打印狗为什么跑/不跑
			KEY_ESCAPE:
				_selected = -1
		queue_redraw()
		return

	# 触摸 / 点击：手机上一次点击会来 ScreenTouch + 模拟 MouseButton 两个事件，靠 _tap_pressed 去重
	if not _tap_pressed(event):
		return
	var at := get_global_mouse_position()
	if event is InputEventScreenTouch:
		# ⚠️ 有相机之后 event.position 是**画布**坐标，不是世界坐标：先反变换回世界再判格子
		at = get_viewport().get_canvas_transform().affine_inverse() * event.position
	_handle_tap(_point_to_cell(at))


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
##
## 【演出是异步的两拍】我方猫先滑过去，**狗那一拍等猫滑完才动**（撞飞残影、震屏、音效都算狗那一拍）：
## 同时动的话看不出"我走了一步，它才反应"，而且猫被打飞的因果读不出来。
func _apply_move(cat_index: int, to: Vector2i) -> void:
	var before_dog: Vector2i = controller.state.dog["pos"]
	var before_cells: Array = []
	for c in controller.state.cats:
		before_cells.append(c["pos"])

	controller.move_cat(cat_index, to)

	# 狗吃到肉 => 红光 + 震屏（结算演出接着上）
	var meat_eaten := controller.result_reason == "meat_eaten"
	if meat_eaten:
		_punch_meat()
		_shake(0.3, 8.0)

	# 哪几只猫被吃掉了（撞飞残影留到狗那一拍再播）
	# ⚠️ 不能一律跳过玩家刚走的那只：**垫在肉格上的猫正是它刚走上去的那只**，狗吃了它但进不了肉格。
	#    所以比的是"这一回合它该在哪"：自己走 => to，别的猫 => 原地；对不上就是被吃了。
	var victims: Array = []
	for i in controller.state.cats.size():
		if i >= before_cells.size():
			break
		var expected: Vector2i = to if i == cat_index else before_cells[i]
		if controller.state.cats[i]["pos"] != expected:
			victims.append({ "index": i, "cell": expected })

	_selected = -1
	_bump_version()
	_sync_units()
	queue_redraw()

	# ---- 第一拍：我方猫滑过去（被吃掉的猫不滑，交给残影）----
	var version := _version
	if cat_index < _cat_nodes.size() and cat_index < controller.state.cats.size() \
			and controller.state.cats[cat_index]["pos"] == to:
		_slide_unit(_cat_nodes[cat_index], _cell_center(before_cells[cat_index]), _cell_center(to))
	# 狗先钉回旧格（_sync_units 已经把它摆到新格了，不钉住就会"先跳一下再滑回去"）
	if _dog_node != null:
		_dog_node.position = _cell_center(before_dog)

	await get_tree().create_timer(SLIDE_SECONDS).timeout
	if not is_inside_tree() or version != _version:
		return      # 这期间重开 / 悔棋 / 又走了一步 => 这一拍作废，别去动新的节点
	# ---- 第二拍：狗动 ----
	_play_dog_turn(victims, before_dog, meat_eaten)


func _play_dog_turn(victims: Array, before_dog: Vector2i, meat_eaten: bool) -> void:
	for v in victims:
		_spawn_takeoff(_cat_nodes[v["index"]] if v["index"] < _cat_nodes.size() else null, v["cell"])
		_hit_cell = v["cell"]              # 命中环：飞出去了也还剩这一下
		_hit_t = 0.45
		_shake(0.2, 5.0)
	if controller.state.dog["pos"] != before_dog:
		_shake(0.15, 3.0)                  # 狗自己挪了窝 => 轻震一下

	# 一次行动只播一个音效：吃子 > 低吼 > 挪动（吃肉的音效交给结算页的 lose）
	if not victims.is_empty():
		_sfx("flick")
	elif not meat_eaten:
		_sfx("growl" if controller.state.growling else "move")

	_slide_unit(_dog_node, _cell_center(before_dog), _cell_center(controller.state.dog["pos"]))
	queue_redraw()

	# 提示要走一遍求解器（几十~几百毫秒，纯主线程，会吃掉一整帧的 delta，让 tween 直接跳到终点）。
	# 所以**等狗滑完再算**：不然它会把上面这一滑动"卡掉"，看起来像瞬移。
	await get_tree().create_timer(SLIDE_SECONDS).timeout
	if is_inside_tree():
		_update_hint()
		queue_redraw()


## 调试用（F1，只在 debug 构建里生效）：把"狗为什么跑 / 为什么跑不掉"逐条打出来。
## 逃跑三条件任何一条不满足，狗就不会动 —— 而不是随机。
func _debug_dump_dog() -> void:
	if not OS.is_debug_build():
		return
	var st := controller.state
	if st == null:
		return
	var dog: Vector2i = st.dog["pos"]
	print("---- 狗 @ 格%s | 低吼中=%s ----" % [str(dog), str(st.growling)])
	print("① 脚下那格被控制: %s" % str(MoveRules.controlled_cells(st).has(dog)))
	print("② 可走格 %d 个: %s" % [Encircle.movable_cells(st).size(), str(Encircle.movable_cells(st))])
	var flicks := Encircle.flickable_cats(st)
	print("③ 能吃掉的猫 %d 只: %s" % [flicks.size(), str(flicks)])
	for f in flicks:
		var idx: int = f["cat"]
		print("   - 格%s 上的猫 #%d 没被保护（走到那儿=吃子）" % [str(f["cell"]), idx])
	print("=> can_flee=%s | 这回合它会做: %s" % [str(Encircle.can_flee(st)), str(DogAI.plan(st))])
	print("   （③ 非空时不跑：吃子优先于逃跑）")


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


## HUD / 说明文字用正文字体（霞鹜文楷）
## 字号不用乘任何系数：世界里的东西统一由 Camera2D 缩放（见 _layout_board）。
func _text(txt: String, pos: Vector2, size: int, tint: Color, font: Font = FONT_BODY) -> void:
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)


## 设计字号 -> Control 的实际字号（CanvasLayer 不吃相机缩放，只有控件用得上）
func _font_px(size: int) -> int:
	return int(round(float(size) * _ui_scale))


## 警告文字**不能**直接 draw_string：单位和障碍是 board 的子节点，永远压在 board 自己的
## _draw() 之上（ARCHITECTURE 9.2），写在格子上的字会被障碍物盖住。
## 所以这里只把字收集进 warn_texts，由 _warn_layer（z_index 更高、后画）落笔。
func _warn_text(txt: String, cx: float, cy: float, size: int, tint: Color) -> void:
	var font := FONT_DISPLAY          # 棋盘上的标签用得意黑，粗一点更好认
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var ascent := font.get_ascent(size)
	var descent := font.get_descent(size)
	warn_texts.append({
		"txt": txt, "size": size, "tint": tint, "font": font,
		"at": Vector2(cx - w * 0.5, cy + (ascent - descent) * 0.5),
	})


func _text_centered(txt: String, cx: float, cy: float, size: int, tint: Color,
		font: Font = FONT_BODY) -> void:
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var ascent := font.get_ascent(size)
	var descent := font.get_descent(size)
	draw_string(font, Vector2(cx - w * 0.5, cy + (ascent - descent) * 0.5), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)
