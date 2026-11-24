class_name RunRequest
extends RefCounted
## 编辑器里对某一关按 F6 时，关卡场景把自己的路径写在这儿；棋盘读完就清空。
##
## ⚠️ 为什么单独开一个类，而不是直接用一个 `Levels.pending_index`：
##   levels.gd --preload--> level_XX.tscn --ext_resource--> level.gd --引用--> Levels
##   这样就成了环，Godot 会报 `Parse Error: Busy` / `referenced non-existent resource`。
##   本类**不 preload 任何东西**，是打断这个环的最小代价。
##   所以：**level.gd 永远不许引用 Levels**。

static var level_path: String = ""
