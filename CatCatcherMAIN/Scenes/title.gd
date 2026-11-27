extends Node2D
## 标题页（占位版，之后换成特色标题页）：纯视觉软引导，玩法说明一个字的都没有。
##
## 循环演一遍核心循环：狗沿着一排走向肉 → 两只猫落到它的去路上、控制格变绿 → 狗无路可走
## → 白闪 + ENCIRCLED! → 清盘重播。看一遍就能推出「用猫堵死狗」，点一下（或任意键）进游戏。
##
## ⚠️ 规则不在这里重写：绿块来自 MoveRules.controlled_cells()、围死判定来自 Encircle.is_encircled()，
## 和实战同一份函数 —— 演示里看到的绿块，进游戏后语义一定一致（ARCHITECTURE 第 5 节）。
## 换美术只改 title.tscn 里的单位实例和 _draw_title()，时间轴不用动。
##
## 屏幕上只有 ASCII 文字（Godot 内置字体没有 CJK 字形，中文在 web 版会画成方块）。

const BOARD_SCENE := "res://CatCatcherMAIN/Scenes/board.tscn"

## 时间轴（秒）：想调节奏只动这四个数
const STEP_TIME := 0.42      # 狗走一格
const POP_TIME := 0.35       # 一只猫落地
const HOLD_TIME := 1.5       # 围死定格
const BLANK_TIME := 0.35     # 清盘，重播下一轮

## 演示局面 —— 和任何真关卡无关，只把规则演一遍。
## 改坐标后 _ready 里的 assert 会立刻告诉你还围不围得住狗（调试版启动即报错）。
## ⚠️ 新规则下"狗贴着肉就永远有动作"，所以演示必须让狗**停在离肉 ≥2 格**处被围死。
const W := 6
const H := 6
const MEAT_CELL := Vector2i(5, 2)
const DOG_CELLS := [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]  # 狗从左边一格一格走向肉
const CAT_CELLS := [Vector2i(2, 0), Vector2i(0, 2)]                  # 车封上下两格、车封左右两格
const CAT_TYPES := ["rook", "rook"]

const TITLE_LINES := ["CAT", "CATCHER"]
const FONT_TITLE := 34

## 手绘标题图（1024×768，不透明区域 x=26..997 / y=225..555）
const TEX_TITLE := preload("res://CatCatcherMAIN/Graphics/Title/art_title.png")
## 狗的三个样子（待机 / 低吼 / 困毙）—— 演示到"围死"那一刻换成困毙
const TEX_DOG_IDLE := preload("res://CatCatcherMAIN/Graphics/Dog/art_dog_idle.png")
const TEX_DOG_TRAPPED := preload("res://CatCatcherMAIN/Graphics/Dog/art_dog_trapped.png")

## 点一下开始的那声"嗒"（占位素材借自隔壁 hollow-bastion）
const SFX_CLICK := preload("res://CatCatcherMAIN/Audio/sfx_click.mp3")

var config: Dictionary = {}
var cell_size: int = 64
var board_origin := Vector2i.ZERO
var colors: Dictionary = {}
var _control_alpha: float = 0.62     # 和 board 同一个配置项

var _dog_node: Node2D = null
var _meat_node: Node2D = null
var _cat_nodes: Array = []
var _base_scale: Array = []
var _flash: ColorRect = null
var _banner: Label = null

## 标题字用得意黑（和棋盘上的大字同一套；用 subset 里的子集字体）
const FONT_DISPLAY := preload("res://CatCatcherMAIN/Fonts/subset/display.ttf")
## 控制格爪印（和棋盘同一张图、同一个不透明度，演示里看到的规则图 = 进游戏后的样子）
const TEX_CONTROL_CELL := preload("res://CatCatcherMAIN/Graphics/Grids/art_control_cell.png")

var _t: float = 0.0
var _landed: int = -1            # 已落地的猫数量（局面只在它变化时重算）
var _controlled: Dictionary = {}
var _trapped: bool = false
var _walk_end: float = 0.0
var _pop_end: float = 0.0
var _hold_end: float = 0.0
var _total: float = 1.0
var _started: bool = false
var _click_player: AudioStreamPlayer = null


func _ready() -> void:
	config = Level.load_config()
	if config.is_empty():
		push_error("配置加载失败 —— 框架没跑通")
		return

	cell_size = int(config["board"]["cell_size"])
	var o: Array = config["board"]["origin"]
	board_origin = Vector2i(int(o[0]), int(o[1]))
	colors = config["board"]["colors"]
	_control_alpha = float(config["board"].get("control_alpha", 0.62))
	RenderingServer.set_default_clear_color(Color(String(colors["bg"])))

	_dog_node = $Units/Dog
	_meat_node = $Units/Meat
	_flash = $FxLayer/Flash
	_banner = $FxLayer/Banner
	_banner.add_theme_font_override("font", FONT_DISPLAY)
	_cat_nodes = [$Units/CatRook, $Units/CatRook2]
	for n in _cat_nodes:
		_base_scale.append(n.scale)
		n.visible = false
	_meat_node.position = _cell_center(MEAT_CELL)

	_click_player = AudioStreamPlayer.new()
	_click_player.stream = SFX_CLICK
	_click_player.volume_db = -5.0
	add_child(_click_player)

	_walk_end = float((DOG_CELLS.size() - 1) * STEP_TIME)
	_pop_end = _walk_end + float(CAT_CELLS.size() * POP_TIME)
	_hold_end = _pop_end + HOLD_TIME
	_total = _hold_end + BLANK_TIME

	# 演示布局必须真能围死狗 —— 改坏了当场炸，别等玩家发现"演了一遍没围住"
	assert(Encircle.is_encircled(_state_at(CAT_CELLS.size())), "标题页演示布局围不死狗，改 CAT_CELLS")
	print("[CatCatcher] 标题页：点一下或按任意键开始")


func _input(event: InputEvent) -> void:
	if _started:
		return
	var go: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventScreenTouch and event.pressed)
	if not go:
		return
	_started = true
	# 先出个点击声：这一下点击同时是手机浏览器解锁音频的手势，得在切场景前播
	_click_player.play()
	# 等一小会儿再切，否则标题页被 freed 会把声音掐掉
	get_tree().create_timer(0.15).timeout.connect(
		func() -> void: get_tree().change_scene_to_file(BOARD_SCENE))


func _process(delta: float) -> void:
	_t = fmod(_t + delta, _total)

	var landed := _landed_count()
	if landed != _landed:
		_landed = landed
		var st := _state_at(landed)
		_controlled = MoveRules.controlled_cells(st)
		_trapped = Encircle.is_encircled(st)

	_update_units()
	_update_fx()
	queue_redraw()


# ---------------------------------------------------------------- 时间轴 ----

## 已落地的猫数量。由时间推出来，不存状态机。
func _landed_count() -> int:
	if _t < _walk_end:
		return 0
	return clampi(int((_t - _walk_end) / POP_TIME) + 1, 0, CAT_CELLS.size())


## 演示局面。只喂给 Core 的纯函数（不参与玩法、不进求解器）。
func _state_at(landed: int) -> GameState:
	var st := GameState.new()
	st.w = W
	st.h = H
	st.meat_pos = MEAT_CELL
	st.dog = { "type": "stray", "pos": DOG_CELLS[DOG_CELLS.size() - 1] }
	for i in landed:
		st.cats.append({ "type": CAT_TYPES[i], "pos": CAT_CELLS[i], "home": CAT_CELLS[i] })
	return st


func _update_units() -> void:
	var demo := _t < _hold_end          # 定格之后清盘，下一轮重来

	# 狗：沿 DOG_CELLS 一格一格滑过去
	var seg := clampi(int(_t / STEP_TIME), 0, DOG_CELLS.size() - 2)
	var frac := clampf(_t / STEP_TIME - float(seg), 0.0, 1.0)
	var pos: Vector2 = _cell_center(DOG_CELLS[seg]).lerp(_cell_center(DOG_CELLS[seg + 1]), frac)
	if _t >= _walk_end:
		pos = _cell_center(DOG_CELLS[DOG_CELLS.size() - 1])
		if _trapped and demo:
			pos.x += sin(_t * 40.0) * 2.0      # 走不掉了，原地挣扎
	_dog_node.position = pos
	_dog_node.visible = demo
	# 围死那一刻换成"困毙"姿势，和实战里赢了之后的样子一致
	if _dog_node is Sprite2D:
		var sprite := _dog_node as Sprite2D
		sprite.texture = TEX_DOG_TRAPPED if (_trapped and demo) else TEX_DOG_IDLE

	# 猫：依次落地（缩放从 0.35 长到 1），绿格随 _landed 增长自动多出来
	for i in _cat_nodes.size():
		var pop := clampf((_t - _walk_end - float(i) * POP_TIME) / POP_TIME, 0.0, 1.0)
		var node: Node2D = _cat_nodes[i]
		node.visible = demo and pop > 0.0
		node.position = _cell_center(CAT_CELLS[i])
		node.scale = _base_scale[i] * (0.35 + 0.65 * pop)


func _update_fx() -> void:
	var show := _trapped and _t >= _pop_end and _t < _hold_end

	var flash_a := 0.0
	if show:
		flash_a = clampf(1.0 - (_t - _pop_end) / 0.30, 0.0, 1.0) * 0.85
	_flash.color = Color(1.0, 1.0, 1.0, flash_a)

	_banner.visible = show
	if show:
		var fade_out := clampf((_hold_end - _t) / 0.25, 0.0, 1.0)
		_banner.modulate.a = clampf((_t - _pop_end) / 0.12, 0.0, 1.0) * fade_out


# ---------------------------------------------------------------- 绘制 ----

func _draw() -> void:
	if colors.is_empty():
		return
	for y in H:
		for x in W:
			var fill: Color = _color("cell") if (x + y) % 2 == 0 else _color("cell_alt")
			draw_rect(_cell_rect(Vector2i(x, y)), fill)

	# 控制格 = 狗走不进去的格。这一层爪印就是整个玩法唯一要教的东西。
	if _t < _hold_end:
		var tint := Color(1.0, 1.0, 1.0, _control_alpha)
		for cell in _controlled:
			draw_texture_rect(TEX_CONTROL_CELL, _cell_rect(cell), false, tint)

	_draw_title()
	_draw_click_cue()


func _draw_title() -> void:
	# 手绘标题图：不透明区域宽 972px，按 ~250px 显示 => k = 250/972
	var want_w := 250.0
	var k := want_w / 972.0
	var center := Vector2(float(board_origin.x) * 0.5, 232.0)   # 棋盘左栏的中心
	var size := Vector2(1024.0, 768.0) * k
	# 不透明区域中心 (511.5, 390) 对齐到 center
	var top_left := center - Vector2(511.5, 390.0) * k
	draw_texture_rect(TEX_TITLE, Rect2(top_left, size), false)


## 「点一下开始」：光标箭头 + 一圈圈扩散的涟漪。不用文字。
func _draw_click_cue() -> void:
	var tip := Vector2(480.0, 462.0 + sin(_t * 3.2) * 3.0)
	var ink := _color("cell")
	for i in 3:
		var k := fmod(_t + float(i) * 0.45, 1.35) / 1.35
		draw_arc(tip, 8.0 + k * 26.0, 0.0, TAU, 28, Color(ink, 0.5 * (1.0 - k)), 2.0)
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(0, 0), tip + Vector2(0, 26), tip + Vector2(7, 19), tip + Vector2(11, 28),
		tip + Vector2(16, 26), tip + Vector2(12, 17), tip + Vector2(20, 17),
	]), ink)


# ---------------------------------------------------------------- 工具 ----

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(board_origin + cell * cell_size), Vector2(cell_size, cell_size))


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(board_origin) + Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5


func _color(key: String) -> Color:
	return Color(String(colors.get(key, "#ffffff")))
