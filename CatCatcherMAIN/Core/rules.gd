class_name Rules
extends RefCounted
## 一个回合的完整结算，**纯静态函数**：给状态 + 玩家动作，原地推进。
##
## 为什么单独抽出来：GameController（实战）、tests/solvecheck.gd（关卡设计搜索）、
## Core/solver.gd（启动校验 + 提示）三边必须是**同一套结算逻辑**。
## 各写一份的下场是搜索说"这关有解"、实战却赢不了。
##
## 本轮规则（定稿，别翻案）：
##   · 没有血量：**狗进入（空的）肉格 = 玩家输**
##   · 狗贴肉必须先低吼一回合（前摇），低吼后再进才算吃到
##   · 肉格上有猫 => 狗吃掉那只猫（站肉格的猫永不受保护），狗停在原地、低吼清零
##   · 撞飞 = 吃子：狗吃掉相邻未受保护的猫并移动到那一格
##   · 胜利 = 狗没有任何合法动作（见 Encircle.legal_actions）

const ONGOING := "ongoing"
const WON := "won"
const LOST := "lost"


## 玩家走一步 + 狗行动。求解器 / 关卡搜索 / 实战共用这一份。
## 返回 { "outcome": ONGOING/WON/LOST, "reason": String }
## reason 是语言无关的 code，屏幕文案由表现层映射（ARCHITECTURE 9.5）。
static func apply_turn(state: GameState, config: Dictionary, cat_index: int, to: Vector2i) -> Dictionary:
	if cat_index >= 0 and cat_index < state.cats.size():
		state.cats[cat_index]["pos"] = to
	state.turn += 1
	return apply_dog_turn(state, config)


## 狗行动 + 回合结算。控制器在「结束回合」时调这个。
static func apply_dog_turn(state: GameState, config: Dictionary) -> Dictionary:
	# ① 玩家刚走完就把狗堵死了 => 直接赢，别让狗再动
	if Encircle.is_encircled(state):
		return { "outcome": WON, "reason": "encircled" }

	# ② 狗行动
	var action := DogAI.plan(state)
	match String(action["kind"]):
		"eat":
			return { "outcome": LOST, "reason": "meat_eaten" }
		"growl":
			state.growling = true
		"flee":
			# 脚下被控制 => 自己跑到安全格。逃跑也算它的动作，低吼清零
			state.dog["pos"] = action["to"]
			state.growling = false
		"move":
			state.dog["pos"] = action["to"]
			state.growling = false
		"flick":
			var victim: int = int(action["cat"])
			var cell: Vector2i = action["to"]
			if cell != state.meat_pos:
				state.dog["pos"] = cell          # 吃子 = 走到那一格
			# 肉格上的猫被吃掉后狗进不去，低吼清零 —— 玩家又争取到一回合
			state.cats[victim]["pos"] = Respawn.pick_cell(state)
			state.growling = false
			# cat_lost = 这一回合送掉了一只猫（靠 Respawn 复活到出生点）。
			# 只有求解器读它：提示优先给不送子的路线（见 Solver.find_line）。
			var flicked := settle(state, config)
			flicked["cat_lost"] = true
			return flicked
		_:
			return { "outcome": WON, "reason": "encircled" }

	# ③ 狗自己把自己走死了也算赢；④ 回合上限
	return settle(state, config)


## 胜负判定（不含狗的行动）：围死 => 赢；回合用尽 => 输。
static func settle(state: GameState, config: Dictionary) -> Dictionary:
	if Encircle.is_encircled(state):
		return { "outcome": WON, "reason": "encircled" }
	if state.max_turns > 0 and state.turn >= state.max_turns:
		return { "outcome": LOST, "reason": "timeout" }
	return { "outcome": ONGOING, "reason": "" }


static func cfg_int(config: Dictionary, section: String, key: String, fallback: int) -> int:
	var s: Dictionary = config.get(section, {})
	return int(s.get(key, fallback))
