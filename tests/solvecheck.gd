extends SceneTree
## 关卡尺子：量每关最短几步能围死，顺便确认不是死局。
##
##   godot --headless --path . --script res://tests/solvecheck.gd [-- 最大深度] [关卡文件...]
##
## 搜索本身在 Core/solver.gd 里 —— 这里只是把它跑一遍打印出来，不另写一份。
## （求解器和实战共用 Rules.apply_turn，所以搜出来的路线实战一定走得通。）

var _config: Dictionary
var _checked := 0


func _initialize() -> void:
	_config = Level.load_config()

	var depth := Solver.DEFAULT_DEPTH
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

	print("---- 检查了 %d 关 ----" % _checked)
	quit(0)


func _check(path: String, max_depth: int) -> void:
	var lv := Level.from_file(path)
	if lv == null:
		print("FAIL %s  读不出来" % path.get_file())
		return

	_checked += 1
	var start := lv.to_state(_config)

	if Encircle.is_encircled(start):
		print("BAD  %s  开局狗已经被围死（这关是白送的）" % path.get_file())
		return

	var t0 := Time.get_ticks_msec()
	var line := Solver.find_line(start, _config, max_depth)
	var ms := Time.get_ticks_msec() - t0

	if line.is_empty():
		print("FAIL %-14s %d 步内无解（%d ms）" % [path.get_file(), max_depth, ms])
		return

	print("OK   %-14s 最短 %d 步（%d ms）" % [path.get_file(), line.size(), ms])
	print("     解法: %s" % JSON.stringify(line))

	if not lv.solution.is_empty() and lv.solution.size() != line.size():
		print("     ⚠️ JSON 里的 solution 是 %d 步，搜索给出 %d 步 —— 有一个是多余的"
			% [lv.solution.size(), line.size()])
