class_name DogAI
extends RefCounted
## 狗每回合的行为决策。纯计算，不碰节点。
##
## 【硬规矩 1】实战和「敌方行动预览」必须调**同一个函数**（ARCHITECTURE 5.2）。
##   预览 = DogAI.plan(state.clone())，实战 = DogAI.plan(state)，就这一行差别。
##   另写一套预测逻辑的下场：预览和实战对不上，玩家觉得游戏在骗人。
## 【硬规矩 2】全确定性，不许掷随机（5.3）。要变化就用回合数、距离这类确定量去分叉。
##
## 返回 { "kind": String, "to": Vector2i, "cat": int }
##   "eat"   相邻啃肉（优先于移动），to = 肉所在格，cat = -1
##   "move"  朝肉推进一格，to = 目标格，cat = -1
##   "flick" 前进方向被猫挡住 -> 撞飞它（回出生点），本回合不移动，cat = 猫下标
##   "none"  围死，无动作
##
## 狗类型：
##   stray  野狗，贪心走法（哪条轴离肉近就走哪条）
##   collie 边牧，BFS 寻路会绕障碍
static func plan(state: GameState) -> Dictionary:
	assert(false, "TODO(M1): DogAI.plan")
	return { "kind": "none", "to": Vector2i.ZERO, "cat": -1 }
