@tool
extends Node2D
## 关卡编辑器用的标记物：往 level_editor.tscn 里拖几个，摆到格子上即可。
## 吸附到格心、以及导出成关卡 JSON 都由 level_editor.gd 负责，这里只管"在编辑器里看得见"。
##
## 运行时什么都不画 —— 真棋盘的样子是 board.gd 的事。

@export_enum("cat", "dog", "meat", "obstacle") var kind: String = "cat":
	set(value):
		kind = value
		queue_redraw()

@export_enum("rook", "horse", "pawn") var cat_type: String = "rook":
	set(value):
		cat_type = value
		queue_redraw()

const MARK_SIZE := 46.0
const FONT_SIZE := 18


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var fill := Color(0.95, 0.66, 0.36)
	match kind:
		"dog":
			fill = Color(0.26, 0.26, 0.28)
		"meat":
			fill = Color(0.78, 0.32, 0.30)
		"obstacle":
			fill = Color(0.55, 0.48, 0.36)

	var half := MARK_SIZE * 0.5
	if kind == "cat" or kind == "dog":
		draw_circle(Vector2.ZERO, half, fill)
	else:
		draw_rect(Rect2(-half, -half, MARK_SIZE, MARK_SIZE), fill)

	var label := ""
	match kind:
		"cat":
			label = cat_type.substr(0, 1).to_upper()
		"dog":
			label = "D"
		"meat":
			label = "M"
		"obstacle":
			label = "X"

	var w := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(ThemeDB.fallback_font, Vector2(-w * 0.5, FONT_SIZE * 0.36), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1))
