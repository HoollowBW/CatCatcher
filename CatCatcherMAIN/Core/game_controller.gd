class_name GameController
extends RefCounted
## 回合流程：玩家动 1 只猫 -> 狗立刻行动 -> 回合结算（腐坏 / 啃食 / 胜负）。
##
## 悔棋 = 快照（ARCHITECTURE 5.1）。每回合边界往 _undo 里压一份 state.snapshot()，
## 悔棋就是 restore 回来。不许写"反向操作"。

signal state_changed
signal game_over(won: bool, reason: String)

var level: Level
var config: Dictionary
var state: GameState

var _undo: Array = []
var _finished := false


func setup(lv: Level, cfg: Dictionary) -> void:
	level = lv
	config = cfg
	state = lv.to_state(cfg)
	_undo.clear()
	_finished = false
	state_changed.emit()


## 玩家把第 cat_index 只猫走到 to。走完立刻推进狗的行动并结算。
## 非法走法返回 false，不改任何状态。
func try_move_cat(cat_index: int, to: Vector2i) -> bool:
	if _finished or state == null:
		return false
	assert(false, "TODO(M1): GameController.try_move_cat")
	return false


## 敌方行动预览：在副本上跑同一个 DogAI.plan，绝不动真身。
func preview_dog_action() -> Dictionary:
	if state == null:
		return {}
	return DogAI.plan(state.clone())


func can_undo() -> bool:
	return not _undo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	state.restore(_undo.pop_back())
	_finished = false
	state_changed.emit()
	return true


func restart() -> void:
	if level == null:
		return
	state = level.to_state(config)
	_undo.clear()
	_finished = false
	state_changed.emit()


## 一回合的结算：腐坏、啃食、胜负、回合数上限。try_move_cat 末尾调它。
func _resolve_turn() -> void:
	assert(false, "TODO(M1): GameController._resolve_turn")
