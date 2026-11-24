class_name GameController
extends RefCounted
## 回合流程：玩家挑一只猫走一步（这一回合内可以无限撤销）-> 结束回合 -> 狗行动 -> 结算。
##
## 【每回合只能移动一只猫一次】但**提交前随便撤**：state 里的那一步是"试探性"的，
## 按「结束回合」才把狗放出来。悔棋 = 快照（ARCHITECTURE 6.1），不写反向操作。

signal state_changed
signal game_over(won: bool, reason: String)

var level: Level
var config: Dictionary
var state: GameState

var finished := false
var won := false
var result_reason := ""

## 每回合开始前的快照，撤销一次 = 退回上一个已提交回合
var _undo: Array = []
## 本回合玩家是否已经走过一步
var _moved := false


func setup(lv: Level, cfg: Dictionary) -> void:
	level = lv
	config = cfg
	restart()


func restart() -> void:
	if level == null:
		return
	state = level.to_state(config)
	_undo.clear()
	_moved = false
	finished = false
	won = false
	result_reason = ""
	state_changed.emit()


# ------------------------------------------------------------ 玩家阶段 ----

## 试探性走一步：**不推进狗**，玩家还能撤销。本回合只能走一次。
func move_cat(cat_index: int, to: Vector2i) -> bool:
	if finished or state == null or _moved:
		return false
	if cat_index < 0 or cat_index >= state.cats.size():
		return false
	if not MoveRules.legal_moves(state, cat_index).has(to):
		return false

	_undo.append(state.snapshot())
	state.cats[cat_index]["pos"] = to
	_moved = true
	state_changed.emit()
	return true


func has_moved() -> bool:
	return _moved


## 撤销这一步（可以连撤，一直退回开局）
func undo() -> bool:
	if _undo.is_empty():
		return false
	state.restore(_undo.pop_back())
	_moved = false
	finished = false
	won = false
	result_reason = ""
	state_changed.emit()
	return true


## 提交本回合：狗行动 + 结算。
func end_turn() -> bool:
	if finished or state == null or not _moved:
		return false

	state.turn += 1
	var result := Rules.apply_dog_turn(state, config)
	_moved = false

	var outcome := String(result["outcome"])
	if outcome == Rules.ONGOING:
		state_changed.emit()
	else:
		_finish(outcome == Rules.WON, String(result["reason"]))
	return true


func _finish(is_win: bool, reason: String) -> void:
	finished = true
	won = is_win
	result_reason = reason      # 语言无关的 code（encircled / meat_eaten / timeout）
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
func preview_after(cat_index: int, to: Vector2i) -> Dictionary:
	if state == null or cat_index < 0 or cat_index >= state.cats.size():
		return {}
	var sim := state.clone()
	sim.cats[cat_index]["pos"] = to
	sim.turn += 1
	if Encircle.is_encircled(sim):
		return { "kind": "encircled", "to": Vector2i.ZERO, "cat": -1 }
	return DogAI.plan(sim)
