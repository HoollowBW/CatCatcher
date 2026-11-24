extends SceneTree
## 关卡尺子：迭代加深 DFS，找一条能在 N 步内围死狗的路线。
##
##   godot --headless --path . --script res://tests/solvecheck.gd [-- 最大深度] [关卡文件...]
##
## 用来设计关卡和确认"这关不是死局"。**不是** M3 的正式求解器（那个要带启发式和剪枝），
## 但两者共用 Rules.apply_turn，所以搜出来的路线实战一定走得通。
##
## 注意：狗是确定性的，所以每个局面只有玩家一侧分支。分支因子 ≈ 每只猫的可走格数之和。

const DEFAULT_MAX_DEPTH := 4

var _config: Dictionary
var _best_depth := {}   # 状态指纹 -> 到达它时剩余的最大步数（避免重复展开）
var _nodes := 0
var _checked := 0


func _initialize() -> void:
	_config = Level.load_config()

	var depth := DEFAULT_MAX_DEPTH
	var paths: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			depth = int(arg)
		else:
			paths.append(arg)
	if paths.is_empty():
		paths = Level.LEVEL_PATHS

	print("== solvecheck: 最大深度 %d ==" % depth)
	for p in paths:
		_check(String(p), depth)

	print("---- 检查了 %d 关，展开 %d 个节点 ----" % [_checked, _nodes])
	quit(0)


func _check(path: String, max_depth: int) -> void:
	var lv := Level.from_file(path)
	if lv == null:
		print("FAIL %s  读不出来" % path.get_file())
		return

	_checked += 1
	var start := lv.to_state(_config)
	var t0 := Time.get_ticks_msec()

	# 开局就是围死 => 数据错了
	if Encircle.is_encircled(start):
		print("BAD  %s  开局狗已经被围死（关卡是白送的）" % path.get_file())
		return

	var line: Array = []
	var found := -1
	for d in range(1, max_depth + 1):
		_best_depth.clear()
		line = _search(start.clone(), d)
		if not line.is_empty():
			found = d
			break

	var ms := Time.get_ticks_msec() - t0
	if found > 0:
		print("OK   %-14s 最短 %d 步（%d ms）" % [path.get_file(), found, ms])
		print("     解法: %s" % JSON.stringify(line))
	else:
		print("FAIL %-14s %d 步内无解（%d ms）" % [path.get_file(), max_depth, ms])


func _search(state: GameState, depth: int) -> Array:
	if depth <= 0:
		return []

	for i in state.cats.size():
		var from: Vector2i = state.cats[i]["pos"]
		for cell in MoveRules.legal_moves(state, i):
			_nodes += 1
			var sim := state.clone()
			var result := Rules.apply_turn(sim, _config, i, cell)
			var outcome := String(result["outcome"])

			var step := { "cat": [from.x, from.y], "to": [cell.x, cell.y] }
			if outcome == Rules.WON:
				return [step]
			if outcome == Rules.LOST:
				continue

			var key := _fingerprint(sim)
			if _best_depth.has(key) and int(_best_depth[key]) >= depth - 1:
				continue
			_best_depth[key] = depth - 1

			var tail := _search(sim, depth - 1)
			if not tail.is_empty():
				return ([step] + tail)

	return []


## 状态指纹。猫按顺序取位置（叠放时能区分），外加狗、肉 HP、回合数。
func _fingerprint(state: GameState) -> String:
	var parts := PackedStringArray()
	for c in state.cats:
		var p: Vector2i = c["pos"]
		parts.append("%d,%d" % [p.x, p.y])
	parts.append("d%d,%d" % [state.dog["pos"].x, state.dog["pos"].y])
	parts.append("h%d" % state.meat_hp)
	parts.append("t%d" % state.turn)
	return "|".join(parts)
