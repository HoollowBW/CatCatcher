extends Node2D
## M0：棋盘渲染 + 点击选格 + 单位占位显示。
##
## 表现层只做三件事：读 Core 的结果来画、把玩家输入翻译成 Core 的函数调用、播表现。
## 规则一律不写在这里 —— 写进来就没法给求解器复用了。

const LEVEL_PATH := "res://CatCatcherMAIN/Data/levels/level_01.json"

var config: Dictionary
var level: Level
var controller: GameController


func _ready() -> void:
	config = Level.load_config()
	level = Level.from_file(LEVEL_PATH)
	if level == null or config.is_empty():
		push_error("关卡或配置加载失败 —— 框架没跑通")
		return

	controller = GameController.new()
	controller.setup(level, config)

	# 底色。做棋盘时可以删掉；现在它是"框架已启动"的唯一视觉证据。
	RenderingServer.set_default_clear_color(
		Color(String(config["board"]["colors"]["bg"]))
	)

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

	_build_board()


## TODO(M0)：按 config.board 的 cell_size / origin 画出 6x6 格子 + 点击选中的高亮框
## TODO(M1)：控制范围半透明色块、单位占位方块 + 类型文字、肉 HP 条、狗的红色警示描边
func _build_board() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	# TODO(M0)：鼠标点格 -> 选中猫 / 取消选中
	# TODO(M1)：Z 悔棋、R 重开
	pass
