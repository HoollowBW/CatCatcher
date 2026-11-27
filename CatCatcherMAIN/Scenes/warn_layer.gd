extends Node2D

## 只画"必须压在单位/障碍上面"的警告文字（FLEE / WILL BITE / EAT! / GROWL / ENCIRCLED / !）。
##
## 为什么单独一个节点：单位（猫/狗/肉/障碍）是关卡场景的子节点，**子节点永远画在
## board 自己 _draw() 之后**（ARCHITECTURE 9.2）——所以这些字写在 board 的 _draw() 里
## 会被障碍物挡住。放到 board 之后的兄弟节点、并且 z_index 更高，就压在上面了。
##
## 内容不在这里算：board 的 _draw() 先跑，把要写的字填进 warn_texts，这里只负责落笔。
var board: Node = null


func _draw() -> void:
	if board == null:
		return
	# 先画笔刷（箭头/圈），再画文字，字压在笔刷上
	for d in board.warn_draws:
		draw_set_transform(d["pivot"], float(d["rot"]), Vector2.ONE)
		draw_texture_rect(d["tex"], d["rect"], false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for t in board.warn_texts:
		draw_string(t["font"], t["at"], String(t["txt"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(t["size"]), t["tint"])
