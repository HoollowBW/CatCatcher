extends RefCounted
## 屏幕适配：**设计坐标永远是 960×540 那一套**（格子 64、原点 288,40），只把 Camera2D 的 zoom
## 按当前画布算出来 —— 和隔壁 hollow-bastion 的 CameraRig._apply_adaptive_zoom 同一套做法。
##
## 为什么不手算 cell_size、到处乘缩放系数：那种写法**每漏一处就出错**（障碍物就是这么跑到棋盘
## 外面的 —— 它们不进 _sync_units，位置没人改）。相机缩放一次，单位 / 障碍 / 笔刷 / 线宽 /
## 字号 / 贴图全都跟着走，设计坐标和编辑器里看到的一模一样。
##
## 横屏：取景框 = 整个 960×540，zoom 恒为 1（和改造前一模一样）。
## 竖屏：取景框 = 棋盘 + 下方 HUD + 上方提示那一块 => 棋盘自然铺满宽度。
##
## 纯函数、不碰节点：board.gd 和 title.gd 共用这一份。

const DESIGN_W := 960.0
const DESIGN_H := 540.0
## 竖屏取景时棋盘左右各留一点（设计单位）：贴到屏幕边上不好点，左侧的"提示"也会被切掉
const PAD_X := 26.0

## canvas：可见画布尺寸（canvas 单位，见 Viewport.get_visible_rect）
## board：棋盘在设计坐标里的矩形
## pad_bottom / pad_top：竖屏取景时棋盘下方 / 上方还要留的空白（设计单位）
## 返回 { "zoom": float, "center": Vector2, "portrait": bool }
static func view_fit(canvas: Vector2, board: Rect2, pad_bottom: float, pad_top: float) -> Dictionary:
	if canvas.y <= canvas.x * 1.05:
		return {
			"zoom": minf(canvas.x / DESIGN_W, canvas.y / DESIGN_H),
			"center": Vector2(DESIGN_W, DESIGN_H) * 0.5,
			"portrait": false,
		}

	var box := Rect2(board.position - Vector2(PAD_X, pad_top),
		board.size + Vector2(PAD_X * 2.0, pad_top + pad_bottom))
	return {
		"zoom": minf(canvas.x / maxf(box.size.x, 1.0), canvas.y / maxf(box.size.y, 1.0)),
		"center": box.get_center(),
		"portrait": true,
	}
