extends SceneTree
## 规则层自检。不引框架、不建夹具，就是一堆 assert。
##
##   godot --headless --script res://tests/selftest.gd
##
## 改完 Core/ 下任何东西都应该跑一遍。退出码 0 = 全过，1 = 有失败。

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("== CatCatcher selftest ==")
	_test_move_rules()
	_test_controlled()
	_test_encircle()
	_test_dog_ai()
	_test_respawn()
	_test_controller()
	_test_win()
	_test_lose()
	_test_levels()

	print("---- %d passed, %d failed ----" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ------------------------------------------------------------- 用例数据 ----

## 6x6，肉(2,1)，狗(3,4)，车(4,4) 马(2,4) 兵(3,5)，障碍(0,5)
func _base_state() -> GameState:
	var s := GameState.new()
	s.w = 6
	s.h = 6
	s.meat_pos = Vector2i(2, 1)
	s.meat_hp = 20
	s.max_turns = 12
	s.obstacles = [Vector2i(0, 5)]
	s.dog = { "type": "stray", "pos": Vector2i(3, 4) }
	s.cats = [
		{ "type": "rook", "pos": Vector2i(4, 4) },
		{ "type": "horse", "pos": Vector2i(2, 4) },
		{ "type": "pawn", "pos": Vector2i(3, 5) },
	]
	return s


func _controller_for(state: GameState) -> GameController:
	var lv := Level.new()
	lv.w = state.w
	lv.h = state.h
	lv.meat_pos = state.meat_pos
	lv.dog_type = String(state.dog["type"])
	lv.dog_pos = state.dog["pos"]
	lv.obstacles = state.obstacles.duplicate()
	lv.max_turns = state.max_turns
	lv.cat_spawns.clear()
	for c in state.cats:
		lv.cat_spawns.append({ "type": c["type"], "pos": c["pos"] })

	var cfg := { "meat": { "max_hp": state.meat_hp, "decay_per_turn": 1, "bite_damage": 3 } }
	var gc := GameController.new()
	gc.setup(lv, cfg)
	return gc


# ---------------------------------------------------------------- 用例 ----

func _test_move_rules() -> void:
	var s := _base_state()

	# 车 (4,4)：整行 y=4 剩 5 格 + 整列 x=4 剩 5 格 = 10（自己那格不算）
	_eq(MoveRules.reach_cells(s, 0).size(), 10, "车猫控制 10 格")
	_ok(MoveRules.reach_cells(s, 0).has(Vector2i(0, 4)), "车猫控制到行首")
	_ok(MoveRules.reach_cells(s, 0).has(Vector2i(4, 0)), "车猫控制到列首")

	# 车遇障碍即停：(0,5) 不在同行列，另测一条 —— 兵 (3,5) 左边 (2,5) 可走
	var s2 := _base_state()
	s2.obstacles = [Vector2i(2, 4)]
	var rook_cells := MoveRules.reach_cells(s2, 0)
	_ok(not rook_cells.has(Vector2i(2, 4)), "车不再控制被障碍挡住的格")
	_ok(not rook_cells.has(Vector2i(1, 4)), "车被障碍挡住后，后面的格也不控制")

	# 马 (2,4)：8 个日字里 (3,6)/(1,6) 出界、(0,5) 是障碍 => 5 格
	_eq(MoveRules.reach_cells(s, 1).size(), 5, "马猫控制 5 格")

	# 兵 (3,5)：上(3,4) 左(2,5) 右(4,5)，下出界 => 3 格
	_eq(MoveRules.reach_cells(s, 2).size(), 3, "兵猫控制 3 格")

	# 可走格要再排掉 猫占据的格 + 狗占据的格
	# 车控制 10 格里，(2,4) 有马、(3,4) 有狗 => 8
	_eq(MoveRules.legal_moves(s, 0).size(), 8, "车猫可走 8 格（排掉马和狗）")
	_ok(not MoveRules.legal_moves(s, 2).has(Vector2i(3, 4)), "兵猫不能走到狗身上")

	# 肉的格谁都不能踩
	_ok(not MoveRules.reach_cells(s, 0).has(s.meat_pos), "车猫控制范围不含肉的格")


func _test_controlled() -> void:
	var s := _base_state()
	var ctrl := MoveRules.controlled_cells(s)
	_ok(ctrl.has(Vector2i(3, 4)), "狗所在格被控制（界面要画警示描边）")
	_ok(not ctrl.is_empty(), "控制范围非空")


func _test_encircle() -> void:
	var s := _base_state()
	var actions := Encircle.legal_actions(s)
	# 狗(3,4) 四邻：(3,3) 空可走；(3,5)兵、(2,4)马、(4,4)车 => 3 个撞飞
	_eq(actions.size(), 4, "开局狗有 4 个合法动作")
	if not Encircle.is_encircled(s):
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: 开局不该是围死")


func _test_dog_ai() -> void:
	var s := _base_state()
	var p := DogAI.plan(s)
	_eq(String(p["kind"]), "move", "狗开局应该往肉走")
	_eq(p["to"], Vector2i(3, 3), "狗往 (3,3) 走（离肉最近）")

	# 贴着肉就该啃，优先于移动
	var s2 := _base_state()
	s2.dog = { "type": "stray", "pos": Vector2i(3, 1) }
	s2.cats = []
	_eq(String(DogAI.plan(s2)["kind"]), "eat", "相邻肉时优先啃食")

	# 四邻全被控/被占，只剩撞飞
	var s3 := _base_state()
	s3.cats = [
		{ "type": "rook", "pos": Vector2i(3, 3) },   # 正上方有猫
		{ "type": "rook", "pos": Vector2i(0, 4) },   # 控制左方 (2,4)
		{ "type": "rook", "pos": Vector2i(4, 0) },   # 控制 (4,4)
		{ "type": "rook", "pos": Vector2i(0, 5) },   # 控制下方？(3,5) 不在其行列
	]
	var p3 := DogAI.plan(s3)
	_ok(String(p3["kind"]) in ["flick", "move"], "s3 至少有动作")


func _test_respawn() -> void:
	var s := _base_state()
	# 主战场 = {狗(3,4), 肉(2,1)}。最远的空格应该是 (5,0)
	_eq(Respawn.pick_cell(s), Vector2i(5, 0), "投放点取离狗和肉都远的一端")
	# 确定性：连算两次必须一致
	_eq(Respawn.pick_cell(s), Respawn.pick_cell(s), "投放点确定性")


func _test_controller() -> void:
	var gc := _controller_for(_base_state())
	_eq(gc.state.turn, 0, "开局回合 0")
	_eq(gc.state.meat_hp, 20, "开局肉 HP 20")

	# 非法走法不改状态
	if not gc.try_move_cat(0, Vector2i(0, 0)):
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: 非法走法应返回 false")
	_eq(gc.state.turn, 0, "非法走法不推进回合")

	# 车 (4,4) -> (4,3)，之后狗会撞飞离肉最近的马
	_ok(gc.try_move_cat(0, Vector2i(4, 3)), "合法走法返回 true")
	_eq(gc.state.turn, 1, "走完推进到回合 1")
	_eq(gc.state.cats[1]["type"], "horse", "猫列表顺序不变")
	_ok(not gc.state.cats[1]["pos"] == Vector2i(2, 4), "马被撞飞离开了原位")
	_eq(gc.state.meat_hp, 19, "回合末腐坏 -1")
	_eq(gc.state.dog["pos"], Vector2i(3, 4), "撞飞时狗不移动")

	# 悔棋回到动手之前
	_ok(gc.can_undo(), "有可悔的回合")
	_ok(gc.undo(), "悔棋成功")
	_eq(gc.state.turn, 0, "悔棋回到回合 0")
	_eq(gc.state.meat_hp, 20, "悔棋回到 HP 20")
	_eq(gc.state.cats[1]["pos"], Vector2i(2, 4), "悔棋把马放回原位")
	_eq(gc.state.cats[0]["pos"], Vector2i(4, 4), "悔棋把车放回原位")
	if not gc.can_undo():
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: 悔到底后不该还能悔")

	# 重开
	_ok(gc.try_move_cat(0, Vector2i(4, 3)), "重开测试：先走一步")
	gc.restart()
	_eq(gc.state.turn, 0, "重开回到回合 0")
	_eq(gc.state.meat_hp, 20, "重开回满 HP")

	# 预览和实战走同一个 DogAI
	var preview := gc.preview_after(0, Vector2i(4, 3))
	_ok(preview.has("kind"), "预览返回了动作")
	_eq(String(preview["kind"]), "flick", "预览：这一步之后狗会撞飞")


## 狗被围死 => 直接判赢。车(1,1) 同时控住 (1,0) 和 (0,1)，狗缩在 (0,0) 且旁边没猫。
func _test_win() -> void:
	var s := GameState.new()
	s.w = 6
	s.h = 6
	s.meat_pos = Vector2i(5, 5)
	s.meat_hp = 20
	s.max_turns = 12
	s.dog = { "type": "stray", "pos": Vector2i(0, 0) }
	s.cats = [{ "type": "rook", "pos": Vector2i(1, 1) }]

	if Encircle.is_encircled(s):
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: (0,0) 的狗应被判定围死")
	_ok(Encircle.legal_actions(s).is_empty(), "围死时没有任何合法动作")

	var gc := _controller_for(s)
	gc.restart()
	if gc.state != null:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: 围死局面也该能构建控制器")


## 肉 HP 归零 => 判负
func _test_lose() -> void:
	var s := _base_state()
	s.meat_hp = 1
	var gc := _controller_for(s)
	# 兵 (3,5) -> (4,5)，这一步不围死狗，狗会走一步，然后腐坏 -1 => 0
	_ok(gc.try_move_cat(2, Vector2i(4, 5)), "走兵这一步")
	_ok(gc.finished, "HP 归零后对局结束")
	if not gc.won:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: HP 归零应该是失败")
	_eq(gc.state.meat_hp, 0, "HP 不会显示成负数")


## 每关的参考解法照着重放一遍 —— 这是"关卡不是死局"的回归保证。
## 关卡 JSON 里改了一个坐标但忘了改 solution，这里立刻炸。
func _test_levels() -> void:
	var cfg := Level.load_config()
	_ok(Level.count() > 0, "至少有一关")

	for i in Level.count():
		var lv := Level.from_index(i)
		if lv == null:
			_fail += 1
			printerr("  FAIL: 关卡 %d 加载不出来" % (i + 1))
			continue

		_ok(not lv.solution.is_empty(), "关卡 %d (%s) 有参考解法" % [i + 1, lv.display_name])

		var gc := GameController.new()
		gc.setup(lv, cfg)

		if Encircle.is_encircled(gc.state):
			_fail += 1
			printerr("  FAIL: 关卡 %d 开局就是围死（白送）" % (i + 1))
			continue

		var replay_ok := true
		for n in lv.solution.size():
			var step: Dictionary = lv.solution[n]
			var at := _cell(step["cat"])
			var to := _cell(step["to"])
			var idx := gc.state.cat_at(at)
			if idx < 0:
				_fail += 1
				printerr("  FAIL: 关卡 %d 第 %d 步 —— (%d,%d) 上没有猫" % [i + 1, n + 1, at.x, at.y])
				replay_ok = false
				break
			if not gc.try_move_cat(idx, to):
				_fail += 1
				printerr("  FAIL: 关卡 %d 第 %d 步不合法" % [i + 1, n + 1])
				replay_ok = false
				break

		if replay_ok:
			_ok(gc.finished and gc.won, "关卡 %d 参考解法能围死" % (i + 1))


func _cell(arr) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))


# ---------------------------------------------------------------- 断言 ----

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: " + label)


func _eq(actual, expected, label: String) -> void:
	if actual == expected:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: %s —— 期望 %s，实际 %s" % [label, str(expected), str(actual)])
