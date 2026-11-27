class_name Levels
extends RefCounted
## 关卡注册表 + 启动校验。这里是唯一知道「关卡是场景」的那一层，
## Core/ 保持纯净（Level 只管数据，不碰节点）。
##
## 做新关卡：FileSystem 里复制一个 Levels/level_XX.tscn → 改名 → 在下面 SCENES 里加一行。

## ⚠️ **播放顺序 = 这个数组的顺序**，不是文件名编号（level_07「守肉」是第 3 关）。
## 新关按主题插进来就行，别去重命名已有文件。
const SCENES := [
	preload("res://CatCatcherMAIN/Levels/level_01.tscn"),
	preload("res://CatCatcherMAIN/Levels/level_02.tscn"),
	preload("res://CatCatcherMAIN/Levels/level_07.tscn"),      # 教学 · 守肉
	preload("res://CatCatcherMAIN/Levels/level_03.tscn"),
	preload("res://CatCatcherMAIN/Levels/level_04.tscn"),
	preload("res://CatCatcherMAIN/Levels/level_05.tscn"),
	preload("res://CatCatcherMAIN/Levels/level_06.tscn"),
	preload("res://CatCatcherMAIN/Levels/level_08.tscn"),      # 实践 · 护肉
	preload("res://CatCatcherMAIN/Levels/level_09.tscn"),      # 终局 · 铁闸（6 步）
]

## 在编辑器里 F6 单独跑某一关时，关卡场景会先把路径写进 RunRequest（见 run_request.gd），
## 棋盘用 index_of_path() 换算成下标。默认 -1 = 从第 1 关开始。


static func count() -> int:
	return SCENES.size()


## 场景路径 -> 关卡下标，找不到返回 -1
static func index_of_path(path: String) -> int:
	for i in SCENES.size():
		if SCENES[i] != null and SCENES[i].resource_path == path:
			return i
	return -1


## 实例化一关、收数据、把节点扔掉。只想要数据时用它。
static func build(index: int) -> Level:
	if index < 0 or index >= SCENES.size():
		return null
	var node: Node = SCENES[index].instantiate()
	var data: Dictionary = node.collect()
	node.free()
	return Level.from_dict(data)


## 启动时把关卡全验一遍：每关必须有解，而且开局不能已经是围死（那是白送）。
## 返回问题描述数组，空 = 全部正常。用 Solver 真搜，不是读标准答案糊弄。
static func validate_all(config: Dictionary) -> Array:
	var problems: Array = []
	var depth := int(config.get("solver", {}).get("validate_depth", Solver.DEFAULT_DEPTH))

	for i in count():
		var lv := build(i)
		if lv == null:
			problems.append("关卡 %d 构建失败" % (i + 1))
			continue

		var st := lv.to_state(config)
		if Encircle.is_encircled(st):
			problems.append("关卡 %d「%s」开局就是围死，等于白送" % [i + 1, lv.display_name])
			continue
		if not Solver.is_solvable(st, config, depth):
			problems.append("关卡 %d「%s」在 %d 步内搜不到解" % [i + 1, lv.display_name, depth])

	return problems
