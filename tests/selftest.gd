extends SceneTree
## 规则层自检。不引框架、不建夹具，就是一堆 assert。
##
##   godot --headless --script res://tests/selftest.gd
##
## 改完 Core/ 下任何东西都应该跑一遍。退出码 0 = 全过，1 = 有失败。
##
## 本轮规则（见 ARCHITECTURE 第 5 节）：没有 HP，狗进（空的）肉格玩家就输；
## 狗贴肉要先低吼一回合；肉格可站一只猫（控制为 0、永不受保护），狗吃猫停在原地；
## 撞飞 = 吃子，狗移动到那格；胜利 = 狗没有任何合法动作。

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("== CatCatcher selftest ==")
	_test_move_rules()
	_test_meat_cell()
	_test_protection()
	_test_dog_actions()
	_test_dog_ai()
	_test_flee()
	_test_rules()
	_test_controller()
	_test_respawn()
	_test_levels()

	print("---- %d passed, %d failed ----" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ------------------------------------------------------------- 用例数据 ----

## 造局面。opts 里可给 meat / obstacles / growling / max_turns
func _mk(dog_cell: Vector2i, cats: Array, opts := {}) -> GameState:
	var s := GameState.new()
	s.w = int(opts.get("w", 6))
	s.h = int(opts.get("h", 6))
	s.meat_pos = opts.get("meat", Vector2i(5, 5))
	s.max_turns = int(opts.get("max_turns", 12))
	s.obstacles = opts.get("obstacles", [])
	s.growling = bool(opts.get("growling", false))
	s.dog = { "type": "stray", "pos": dog_cell }
	s.cats = []
	for c in cats:
		s.cats.append({ "type": String(c["type"]), "pos": c["pos"] })
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

	var gc := GameController.new()
	gc.setup(lv, {})
	return gc


# ---------------------------------------------------------------- 用例 ----

func _test_move_rules() -> void:
	var s := _mk(Vector2i(0, 5), [{ "type": "rook", "pos": Vector2i(4, 4) }], { "meat": Vector2i(2, 1) })
	_eq(MoveRules.reach_cells(s, 0).size(), 10, "车猫控制 10 格（4 行 + 4 列）")
	_ok(MoveRules.reach_cells(s, 0).has(Vector2i(0, 4)), "车猫控制到行首")
	_ok(not MoveRules.reach_cells(s, 0).has(s.meat_pos), "肉格不在控制范围里")

	# 障碍挡住：车看不见后面的格
	var blocked := _mk(Vector2i(0, 5), [{ "type": "rook", "pos": Vector2i(4, 4) }],
		{ "meat": Vector2i(2, 1), "obstacles": [Vector2i(2, 4)] })
	_ok(not MoveRules.reach_cells(blocked, 0).has(Vector2i(2, 4)), "车不控制障碍格")
	_ok(not MoveRules.reach_cells(blocked, 0).has(Vector2i(1, 4)), "障碍后面也不控制")

	# 象：斜线；8 格（从 (2,2) 出发 4 条对角线共 8 格可达）
	var bishop := _mk(Vector2i(0, 5), [{ "type": "bishop", "pos": Vector2i(2, 2) }], { "meat": Vector2i(5, 5) })
	_ok(MoveRules.reach_cells(bishop, 0).has(Vector2i(0, 0)), "象控制到对角")
	_ok(not MoveRules.reach_cells(bishop, 0).has(Vector2i(2, 3)), "象不控制正交格")

	# 马：8 个日字，出界丢弃
	var horse := _mk(Vector2i(0, 5), [{ "type": "horse", "pos": Vector2i(2, 2) }], { "meat": Vector2i(5, 5) })
	_eq(MoveRules.reach_cells(horse, 0).size(), 8, "马在中间控制 8 格")

	# 可走格要排掉其它猫和狗
	var crowded := _mk(Vector2i(3, 4), [
		{ "type": "rook", "pos": Vector2i(4, 4) },
		{ "type": "pawn", "pos": Vector2i(4, 5) },
	], { "meat": Vector2i(2, 1) })
	_ok(not MoveRules.legal_moves(crowded, 1).has(Vector2i(4, 4)), "兵不能走到车上")
	_ok(not MoveRules.legal_moves(crowded, 0).has(Vector2i(3, 4)), "车不能走到狗身上")


## 肉格的专属规则
func _test_meat_cell() -> void:
	# 1) 空的肉格是"走法可落点"，但不算控制格
	var s := _mk(Vector2i(5, 5), [{ "type": "pawn", "pos": Vector2i(1, 1) }], { "meat": Vector2i(1, 0) })
	_eq(MoveRules.reach_cells(s, 0).size(), 3, "兵的控制范围不含肉格（3 格）")
	_ok(MoveRules.legal_moves(s, 0).has(Vector2i(1, 0)), "兵可以走进空的肉格")
	_eq(MoveRules.legal_moves(s, 0).size(), 4, "兵的走法含肉格（4 格）")

	# 2) 车能"看穿"肉格，只是肉格自己不算控制
	var through := _mk(Vector2i(5, 5), [{ "type": "rook", "pos": Vector2i(0, 0) }], { "meat": Vector2i(2, 0) })
	_ok(not MoveRules.reach_cells(through, 0).has(Vector2i(2, 0)), "肉格不进控制范围")
	_ok(MoveRules.reach_cells(through, 0).has(Vector2i(3, 0)), "车能看穿肉格控制后面的格")

	# 3) 站在肉格上的猫：控制为 0，但**可以撤下来**（规则里明写的例外）
	var on_meat := _mk(Vector2i(5, 5), [
		{ "type": "rook", "pos": Vector2i(2, 0) },
		{ "type": "pawn", "pos": Vector2i(0, 4) },
	], { "meat": Vector2i(2, 0) })
	_eq(MoveRules.reach_cells(on_meat, 0).size(), 0, "站肉格的车控制为 0")
	_ok(MoveRules.legal_moves(on_meat, 0).has(Vector2i(2, 1)), "站肉格的猫可以撤下来")
	_eq(MoveRules.legal_moves(on_meat, 0).size(), 10, "站肉格的车按自己的走法撤离（10 格）")

	# 4) 肉格已经有猫时，别的猫不能再踩上去
	var taken := _mk(Vector2i(5, 5), [
		{ "type": "pawn", "pos": Vector2i(2, 0) },
		{ "type": "pawn", "pos": Vector2i(1, 1) },
	], { "meat": Vector2i(2, 0) })
	_ok(not MoveRules.legal_moves(taken, 1).has(Vector2i(2, 0)), "肉格只让站一只猫")


## 受保护的猫吃不动；但站肉格的猫永远吃得到
func _test_protection() -> void:
	var s := _mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(2, 3) },
		{ "type": "rook", "pos": Vector2i(4, 3) },
	])
	_ok(MoveRules.is_protected(s, 0), "同一行上的车保护彼此")
	_eq(Encircle.flickable_cats(s).size(), 0, "受保护的猫一只都吃不到")

	var lone := _mk(Vector2i(2, 2), [
		{ "type": "pawn", "pos": Vector2i(2, 3) },
		{ "type": "pawn", "pos": Vector2i(0, 5) },
	], { "meat": Vector2i(0, 4) })
	_ok(not MoveRules.is_protected(lone, 0), "落单的猫不算受保护")
	_ok(Encircle.is_flickable(lone, 0), "落单的猫吃得掉")

	# 站肉格的猫：即使有车罩着肉格，它也不算受保护
	var meat_cat := _mk(Vector2i(4, 4), [
		{ "type": "pawn", "pos": Vector2i(5, 4) },
		{ "type": "rook", "pos": Vector2i(5, 0) },
	], { "meat": Vector2i(5, 4) })
	_ok(not MoveRules.is_protected(meat_cat, 0), "站肉格的猫永不受保护")
	_ok(Encircle.is_flickable(meat_cat, 0), "站肉格的猫永远吃得到")


## 狗的动作表 = 围死判定的依据
func _test_dog_actions() -> void:
	# ① 四邻全被控制、旁边没猫、肉也不贴 => 围死
	var mated := _mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(2, 0) },
		{ "type": "rook", "pos": Vector2i(0, 2) },
	], { "meat": Vector2i(5, 5) })
	_eq(Encircle.movable_cells(mated).size(), 0, "四邻全被控制时没有可走格")
	_ok(Encircle.is_encircled(mated), "四邻全被控制 + 无猫可吃 => 围死")
	_ok(Encircle.legal_actions(mated).is_empty(), "围死时动作表为空")

	# ② 贴着空肉格 => 有动作（低吼），不算围死
	var near_meat := _mk(Vector2i(4, 4), [{ "type": "rook", "pos": Vector2i(2, 0) }], { "meat": Vector2i(5, 4) })
	_eq(String(Encircle.meat_action(near_meat)["kind"]), "growl", "贴肉且没低吼 => 低吼")
	_ok(not Encircle.is_encircled(near_meat), "贴肉的狗永远不算围死")

	near_meat.growling = true
	_eq(String(Encircle.meat_action(near_meat)["kind"]), "eat", "贴肉 + 已低吼 => 吃肉")

	# ③ 肉格上有猫 => 吃掉那只猫（于是永远有动作）
	var plugged := _mk(Vector2i(4, 4), [
		{ "type": "rook", "pos": Vector2i(2, 0) },
		{ "type": "pawn", "pos": Vector2i(5, 4) },
	], { "meat": Vector2i(5, 4) })
	var act := Encircle.meat_action(plugged)
	_eq(String(act["kind"]), "flick", "肉格有猫 => 吃掉它")
	_eq(int(act["cat"]), 1, "吃的是垫在肉上的那只")
	_ok(not Encircle.is_encircled(plugged), "肉格有猫时也不算围死")

	# ④ 旁边蹲着吃得掉的猫 => 仍有动作
	# ⚠️ 注意别让挡路的猫落进另一只猫的控制范围（那就受保护了）：
	#    车(0,2) 控住 (1,2)/(3,2)，兵(2,0) 只控 (2,1)，(2,3) 上的兵没被谁罩着。
	var edible := _mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(0, 2) },
		{ "type": "pawn", "pos": Vector2i(2, 0) },
		{ "type": "pawn", "pos": Vector2i(2, 3) },
	], { "meat": Vector2i(5, 5) })
	_ok(not Encircle.is_encircled(edible), "旁边有吃得掉的猫 => 不是围死")


func _test_dog_ai() -> void:
	# 朝肉走：狗(2,2) 离肉(5,5) 是 6，(2,3) 才是 5（(2,1) 反而更远 7）
	var s := _mk(Vector2i(2, 2), [{ "type": "rook", "pos": Vector2i(0, 0) }], { "meat": Vector2i(5, 5) })
	var p := DogAI.plan(s)
	_eq(String(p["kind"]), "move", "狗贪心朝肉走")
	_eq(p["to"], Vector2i(2, 3), "走向离肉更近的那格")

	# 贴肉：低吼 -> 吃肉
	var g := _mk(Vector2i(4, 4), [], { "meat": Vector2i(5, 4) })
	_eq(String(DogAI.plan(g)["kind"]), "growl", "贴肉先低吼")
	g.growling = true
	_eq(String(DogAI.plan(g)["kind"]), "eat", "低吼之后吃肉")

	# 肉格有猫：先吃猫
	var plugged := _mk(Vector2i(4, 4), [{ "type": "pawn", "pos": Vector2i(5, 4) }], { "meat": Vector2i(5, 4) })
	_eq(String(DogAI.plan(plugged)["kind"]), "flick", "肉格有猫时先吃猫")

	# 撞无保护猫**优先于吃肉**：狗贴着肉、已经低吼过（下一口就是肉），但嘴边挂着只没人罩的猫
	var distracted := _mk(Vector2i(4, 4), [{ "type": "pawn", "pos": Vector2i(4, 5) }],
		{ "meat": Vector2i(5, 4), "growling": true })
	var pd := DogAI.plan(distracted)
	_eq(String(pd["kind"]), "flick", "吃得掉的猫优先于吃肉")
	_eq(pd["to"], Vector2i(4, 5), "咬的是那只没人罩的猫")
	# 反过来：那只猫被罩住了就吃不掉。
	# ⚠️ 注意这条规则推论：贴身猫的控制范围一定覆盖狗那格（猫控制自己的四邻格），
	#    所以"贴身猫被罩住 => 狗那格也就被罩住 => 它多半会跑"。要让它真去吃肉，
	#    得把它其余出口也堵上（下面用两块障碍），否则测的是逃跑而不是优先级。
	var shielded := _mk(Vector2i(4, 4), [
		{ "type": "pawn", "pos": Vector2i(4, 5) },
		{ "type": "rook", "pos": Vector2i(0, 5) },
	], { "meat": Vector2i(5, 4), "growling": true,
		"obstacles": [Vector2i(3, 4), Vector2i(4, 3)] })
	_ok(not Encircle.can_flee(shielded), "（前提）它没地方可跑")
	_eq(String(DogAI.plan(shielded)["kind"]), "eat", "猫被罩住吃不动 => 照旧吃肉")

	# 朝肉方向被吃得掉的猫挡住：吃掉它（挡在狗真正想走的 (2,3) 上）
	var blocker := _mk(Vector2i(2, 2), [{ "type": "pawn", "pos": Vector2i(2, 3) }], { "meat": Vector2i(5, 5) })
	var p2 := DogAI.plan(blocker)
	_eq(String(p2["kind"]), "flick", "朝肉方向被落单的猫挡住 => 吃掉它")
	_eq(p2["to"], Vector2i(2, 3), "吃的是挡路那只")

	# 围死 => none
	var mated := _mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(2, 0) },
		{ "type": "rook", "pos": Vector2i(0, 2) },
	], { "meat": Vector2i(5, 5) })
	_eq(String(DogAI.plan(mated)["kind"]), "none", "被围死时狗没有动作")


## 逃跑：狗脚下那格被控制时**自己**跑，不需要玩家操作（驱赶 = 用控制范围逼它走）
func _test_flee() -> void:
	# 车(2,0) 控住狗的格子 (2,2)，狗还有 (1,2)/(3,2) 可走，旁边没猫 => 会跑
	var s := _mk(Vector2i(2, 2), [{ "type": "rook", "pos": Vector2i(2, 0) }], { "meat": Vector2i(5, 5) })
	_ok(Encircle.can_flee(s), "狗脚下被控制 + 有路可走 => 会逃跑")
	var p := DogAI.plan(s)
	_eq(String(p["kind"]), "flee", "被罩住时狗的动作是逃跑")

	# 落点必须是它本来就能走的格，而且确定性
	var target: Vector2i = p["to"]
	_ok(Encircle.movable_cells(s).has(target), "逃跑落点是狗的合法走法")
	_eq(Encircle.flee_target(s), Encircle.flee_target(s), "逃跑落点确定性")

	# 逃跑优先于吃肉前摇：贴肉但被罩住 => 先跑，低吼清零
	var near := _mk(Vector2i(2, 2), [{ "type": "rook", "pos": Vector2i(2, 0) }],
		{ "meat": Vector2i(2, 3), "growling": true })
	_eq(String(DogAI.plan(near)["kind"]), "flee", "低吼中的狗被罩住也先跑")
	var r := Rules.apply_dog_turn(near, {})
	_ok(near.dog["pos"] != Vector2i(2, 2), "逃跑把狗挪走了")
	_ok(not near.growling, "逃跑清零低吼")
	_eq(String(r["outcome"]), Rules.ONGOING, "逃跑本身不结束对局")

	# 旁边蹲着吃得掉的猫 => 先吃，不跑
	var armed := _mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(2, 0) },
		{ "type": "pawn", "pos": Vector2i(1, 2) },
	], { "meat": Vector2i(5, 5) })
	_ok(not Encircle.can_flee(armed), "旁边有吃得掉的猫时它先吃，不跑")

	# 没罩住狗 => 不跑，照常朝肉走
	var free := _mk(Vector2i(2, 2), [{ "type": "rook", "pos": Vector2i(5, 0) }], { "meat": Vector2i(0, 0) })
	_ok(not Encircle.can_flee(free), "没控制住狗所在格时它不会跑")
	_eq(String(DogAI.plan(free)["kind"]), "move", "没被罩住的狗照常朝肉走")

	# 整局流程：走一步猫 => 狗立刻行动（如果是被罩住，它自己跑掉，玩家不点狗）
	var gc := _controller_for(s)
	var before: Vector2i = gc.state.dog["pos"]
	_ok(gc.move_cat(0, Vector2i(2, 1)), "玩家把车挪到狗那一列")
	_ok(gc.state.dog["pos"] != before, "狗自己跑掉了，不需要点它")
	_eq(gc.state.turn, 1, "推进一回合")


## 一个回合的结算
func _test_rules() -> void:
	var cfg := {}

	# 低吼：不动、growling 置真
	var s := _mk(Vector2i(4, 4), [{ "type": "rook", "pos": Vector2i(0, 0) }], { "meat": Vector2i(5, 4) })
	var r := Rules.apply_dog_turn(s, cfg)
	_eq(String(r["outcome"]), Rules.ONGOING, "低吼不结束对局")
	_ok(s.growling, "低吼后进入前摇状态")
	_eq(s.dog["pos"], Vector2i(4, 4), "低吼那回合狗不动")

	# 前摇完成 => 吃到肉 => 玩家输
	s.growling = true
	r = Rules.apply_dog_turn(s, cfg)
	_eq(String(r["outcome"]), Rules.LOST, "贴肉 + 已低吼 => 玩家输")
	_eq(String(r["reason"]), "meat_eaten", "失败原因是吃到肉")

	# 撞飞 = 吃子：狗移动到那一格
	var eatcat := _mk(Vector2i(2, 2), [{ "type": "pawn", "pos": Vector2i(2, 3) }], { "meat": Vector2i(5, 5) })
	var victim_pos := Vector2i(2, 3)
	r = Rules.apply_dog_turn(eatcat, cfg)
	_eq(String(r["outcome"]), Rules.ONGOING, "吃子不结束对局")
	_eq(eatcat.dog["pos"], Vector2i(2, 3), "吃子后狗站在被吃掉的猫那格")
	_ok(eatcat.cats[0]["pos"] != victim_pos, "被吃掉的猫被投放到远处")

	# 吃垫在肉上的猫：狗停在原地，低吼清零
	var plug := _mk(Vector2i(4, 4), [{ "type": "pawn", "pos": Vector2i(5, 4) }],
		{ "meat": Vector2i(5, 4), "growling": true })
	r = Rules.apply_dog_turn(plug, cfg)
	_eq(String(r["outcome"]), Rules.ONGOING, "吃掉垫肉的猫不算吃到肉")
	_eq(plug.dog["pos"], Vector2i(4, 4), "吃垫肉的猫后狗停在原地")
	_ok(not plug.growling, "吃掉垫肉的猫后低吼清零")
	_ok(plug.cat_at(Vector2i(5, 4)) == -1, "肉格空出来了")

	# 玩家走完就把狗堵死 => 直接赢
	var win_state := _mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(2, 0) },
		{ "type": "rook", "pos": Vector2i(0, 3) },
	], { "meat": Vector2i(5, 5) })
	# 车 (0,3) -> (0,2) 之后控制 (1,2)/(3,2)... 用围死局面直接验 apply_dog_turn 的入口判定
	var mated := _mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(2, 0) },
		{ "type": "rook", "pos": Vector2i(0, 2) },
	], { "meat": Vector2i(5, 5) })
	r = Rules.apply_dog_turn(mated, cfg)
	_eq(String(r["outcome"]), Rules.WON, "已经围死 => 直接判赢")
	_eq(String(r["reason"]), "encircled", "胜利原因 encircled")
	_ok(win_state.cats.size() == 2, "（构造用例健康）")

	# 回合上限
	var late := _mk(Vector2i(4, 4), [{ "type": "rook", "pos": Vector2i(5, 0) }],
		{ "meat": Vector2i(0, 0), "max_turns": 1 })
	r = Rules.apply_turn(late, cfg, 0, Vector2i(5, 1))
	_eq(String(r["outcome"]), Rules.LOST, "回合数用尽 => 玩家输")
	_eq(String(r["reason"]), "timeout", "失败原因 timeout")


func _test_controller() -> void:
	var gc := _controller_for(_mk(Vector2i(2, 2), [
		{ "type": "rook", "pos": Vector2i(4, 4) },
	], { "meat": Vector2i(0, 0) }))

	_eq(gc.state.turn, 0, "开局回合 0")
	# 非法走法不改状态（车在 (4,4)，(0,5) 不在它的行列上）
	if not gc.move_cat(0, Vector2i(0, 5)):
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: 非法走法应返回 false")
	_eq(gc.state.turn, 0, "非法走法不推进回合")

	# 合法走法：走完**立刻**轮狗行动（没有"先摆再提交"了）
	_ok(gc.move_cat(0, Vector2i(4, 3)), "合法走法返回 true")
	_eq(gc.state.turn, 1, "走一步就推进到回合 1")
	_eq(gc.state.dog["pos"], Vector2i(2, 1), "狗立刻朝肉走了一格")

	# 悔棋 = 回到上一步（玩家那一步 + 狗那一步一起撤）
	_ok(gc.can_undo(), "有可悔的回合")
	_ok(gc.undo(), "悔棋成功")
	_eq(gc.state.turn, 0, "悔棋回到回合 0")
	_eq(gc.state.cats[0]["pos"], Vector2i(4, 4), "悔棋把车放回原位")
	_eq(gc.state.dog["pos"], Vector2i(2, 2), "悔棋把狗放回原位")
	if not gc.can_undo():
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: 悔到底后不该还能悔")

	# 预览：这一步之后狗会做什么
	var preview := gc.preview_after(0, Vector2i(4, 2))
	_ok(preview.has("kind"), "预览返回了动作")


func _test_respawn() -> void:
	var s := _mk(Vector2i(3, 4), [
		{ "type": "rook", "pos": Vector2i(4, 4) },
	], { "meat": Vector2i(2, 1) })
	var cell := Respawn.pick_cell(s)
	_ok(cell != s.dog["pos"], "投放点不在狗身上")
	_ok(cell != s.meat_pos, "投放点不在肉格上")
	_eq(cell, Respawn.pick_cell(s), "投放点确定性")


## 每关都必须：能构建、开局不是白送、求解器搜得到解。
func _test_levels() -> void:
	var cfg := Level.load_config()
	_ok(Levels.count() > 0, "至少有一关")

	var depth := int(cfg.get("solver", {}).get("validate_depth", Solver.DEFAULT_DEPTH))

	for i in Levels.count():
		var lv := Levels.build(i)
		if lv == null:
			_fail += 1
			printerr("  FAIL: 关卡 %d 构建不出来" % (i + 1))
			continue

		var gc := GameController.new()
		gc.setup(lv, cfg)

		_ok(gc.state.cats.size() > 0, "关卡 %d 至少有一只猫" % (i + 1))
		_ok(not gc.state.dog.is_empty(), "关卡 %d 有狗" % (i + 1))
		_ok(lv.meat_pos.x >= 0, "关卡 %d 有肉" % (i + 1))

		if Encircle.is_encircled(gc.state):
			_fail += 1
			printerr("  FAIL: 关卡 %d 开局就是围死（白送）" % (i + 1))
			continue

		_ok(Solver.is_solvable(gc.state, cfg, depth), "关卡 %d 有解" % (i + 1))


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
