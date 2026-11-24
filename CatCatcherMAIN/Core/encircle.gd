class_name Encircle
extends RefCounted
## 狗的所有合法动作 + 围死判定。纯计算，不碰节点。
##
## 【核心机制，定稿】控制 = 硬阻挡：狗**不能**走进被任意一只猫控制的格。
## 于是「封死它的所有去路」是字面意思：
##   围死 = 合法动作为空 = 相邻没有空格 且 相邻没有猫。

## 枚举狗这一回合的所有合法动作。
## 返回：[{ "kind": "move" | "flick", "to": Vector2i, "cat": int }]
##   move  走到 to（空格、未被控制）
##   flick 撞飞 cat（相邻的猫），本回合不移动
static func legal_actions(state: GameState) -> Array:
	assert(false, "TODO(M1): Encircle.legal_actions")
	return []


## 围死判定。独立成函数是硬要求 —— 求解器（M3）要直接调它。
static func is_encircled(state: GameState) -> bool:
	return legal_actions(state).is_empty()
