class_name Rules
extends RefCounted
## 一个回合的完整结算，**纯静态函数**：给状态 + 玩家动作，原地推进整回合。
##
## 为什么单独抽出来：GameController（实战）、tests/solvecheck.gd（关卡设计搜索）、
## 以后 M3 的求解器，三边必须是**同一套结算逻辑**。各写一份的下场是搜索说"这关有解"、
## 实战却赢不了。
##
## 调用方负责：① 先确认这一步合法（MoveRules.legal_moves）；② 需要回滚就自己先 snapshot()。

const ONGOING := "ongoing"
const WON := "won"
const LOST := "lost"


## 玩家走一步 -> 狗立刻行动 -> 回合末腐坏 -> 结算。
## 返回 { "outcome": ONGOING/WON/LOST, "reason": String }
## reason 是语言无关的 code，屏幕文案由表现层映射（ARCHITECTURE 8.2）。
static func apply_turn(state: GameState, config: Dictionary, cat_index: int, to: Vector2i) -> Dictionary:
	state.cats[cat_index]["pos"] = to
	state.turn += 1

	# ① 玩家这一步可能直接把狗围死了
	if Encircle.is_encircled(state):
		return { "outcome": WON, "reason": "encircled" }

	# ② 狗行动
	var action := DogAI.plan(state)
	match String(action["kind"]):
		"eat":
			state.meat_hp -= cfg_int(config, "meat", "bite_damage", 3)
		"move":
			state.dog["pos"] = action["to"]
		"flick":
			var victim: int = action["cat"]
			state.cats[victim]["pos"] = Respawn.pick_cell(state)
		_:
			# DogAI 说没动作 = 围死
			return { "outcome": WON, "reason": "encircled" }

	# ③ 狗自己把自己走死了也算赢，别等玩家再瞎走一步才结算
	if Encircle.is_encircled(state):
		return { "outcome": WON, "reason": "encircled" }

	# ④ 回合末自然腐坏
	state.meat_hp -= cfg_int(config, "meat", "decay_per_turn", 1)

	# ⑤ 胜负
	if state.meat_hp <= 0:
		state.meat_hp = 0
		return { "outcome": LOST, "reason": "meat_gone" }
	if state.turn >= state.max_turns:
		return { "outcome": LOST, "reason": "timeout" }

	return { "outcome": ONGOING, "reason": "" }


static func cfg_int(config: Dictionary, section: String, key: String, fallback: int) -> int:
	var s: Dictionary = config.get(section, {})
	return int(s.get(key, fallback))
