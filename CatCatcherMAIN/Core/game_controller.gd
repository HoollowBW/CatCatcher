class_name GameController
extends RefCounted
## 回合流程：玩家动 1 只猫 -> 狗立刻行动 -> 回合结算（腐坏 / 胜负）。
##
## 悔棋 = 快照（ARCHITECTURE 5.1）。**每次玩家行动前**压一份 state.snapshot()，
## 所以一次悔棋撤销的是"玩家这一步 + 狗那一步"的整个回合。不许写反向操作。

signal state_changed
signal game_over(won: bool, reason: String)

var level: Level
var config: Dictionary
var state: GameState

var finished := false
var won := false
var result_reason := ""

var _undo: Array = []


func setup(lv: Level, cfg: Dictionary) -> void:
	level = lv
	config = cfg
	restart()


func restart() -> void:
	if level == null:
		return
	state = level.to_state(config)
	_undo.clear()
	finished = false
	won = false
	result_reason = ""
	state_changed.emit()


# ------------------------------------------------------------ 玩家行动 ----

## 玩家把第 cat_index 只猫走到 to。走完立刻推进狗的行动并结算。
## 非法走法返回 false，且不改任何状态。
func try_move_cat(cat_index: int, to: Vector2i) -> bool:
	if finished or state == null:
		return false
	if cat_index < 0 or cat_index >= state.cats.size():
		return false
	if not MoveRules.legal_moves(state, cat_index).has(to):
		return false

	# 悔棋快照必须在动手之前拍
	_undo.append(state.snapshot())

	# 结算逻辑在 Rules 里，和关卡搜索/求解器共用同一份（别在这儿再抄一遍）
	var result := Rules.apply_turn(state, config, cat_index, to)
	var outcome := String(result["outcome"])
	if outcome == Rules.ONGOING:
		state_changed.emit()
	else:
		_finish(outcome == Rules.WON, String(result["reason"]))
	return true


func _finish(is_win: bool, reason: String) -> void:
	finished = true
	won = is_win
	result_reason = reason      # 语言无关的 code（encircled / meat_gone / timeout），
	                            # 显示文字由表现层映射 —— Core 不产屏幕文案
	state_changed.emit()
	game_over.emit(is_win, reason)


# ---------------------------------------------------------------- 预览 ----

## 当前局面狗会做什么（调试 / 自检用）
func preview_dog_action() -> Dictionary:
	if state == null:
		return {}
	return DogAI.plan(state.clone())


## 「如果这只猫走到 to，狗会怎么动」—— 界面上的敌方行动预览。
## 走的是同一个 DogAI.plan，只是喂给它的是一份改过一步的副本。
## 和 try_move_cat 保持同样的顺序：先判围死，再问狗。
func preview_after(cat_index: int, to: Vector2i) -> Dictionary:
	if state == null or cat_index < 0 or cat_index >= state.cats.size():
		return {}
	var sim := state.clone()
	sim.cats[cat_index]["pos"] = to
	sim.turn += 1
	if Encircle.is_encircled(sim):
		return { "kind": "encircled", "to": Vector2i.ZERO, "cat": -1 }
	return DogAI.plan(sim)


# ---------------------------------------------------------------- 悔棋 ----

func can_undo() -> bool:
	return not _undo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	state.restore(_undo.pop_back())
	finished = false
	won = false
	result_reason = ""
	state_changed.emit()
	return true
