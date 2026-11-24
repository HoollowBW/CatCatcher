extends SceneTree
## 关卡尺子：量每关最短几步能围死，顺便确认不是死局。
##
##   godot --headless --path . --script res://tests/solvecheck.gd [-- 最大深度] [关卡序号...]
##
## 第一个数字参数是最大深度（不给就用 Solver.DEFAULT_DEPTH），后面的是关卡序号（从 1 起，不给就全跑）。
## 搜索本身在 Core/solver.gd 里 —— 这里只是把它跑一遍打印出来，不另写一份。

var _config: Dictionary


func _initialize() -> void:
	_config = Level.load_config()

	var depth := Solver.DEFAULT_DEPTH
	var wanted: Array = []
	var first := true
	for arg in OS.get_cmdline_user_args():
		if not arg.is_valid_int():
			continue
		if first:
			depth = int(arg)
			first = false
		else:
			wanted.append(int(arg) - 1)

	print("== solvecheck: 最大深度 %d ==" % depth)
	for i in Levels.count():
		if not wanted.is_empty() and not wanted.has(i):
			continue
		_check(i, depth)

	quit(0)


func _check(index: int, max_depth: int) -> void:
	var lv := Levels.build(index)
	if lv == null:
		print("FAIL 关卡 %d  构建失败" % (index + 1))
		return

	var start := lv.to_state(_config)
	var label := "%d %s" % [index + 1, lv.display_name]

	if Encircle.is_encircled(start):
		print("BAD  %-18s 开局狗已经被围死（这关是白送的）" % label)
		return

	var t0 := Time.get_ticks_msec()
	var line := Solver.find_line(start, _config, max_depth)
	var ms := Time.get_ticks_msec() - t0

	if line.is_empty():
		print("FAIL %-18s %d 步内无解（%d ms）" % [label, max_depth, ms])
		return

	print("OK   %-18s 最短 %d 步（%d ms）" % [label, line.size(), ms])
	print("     解法: %s" % JSON.stringify(line))
