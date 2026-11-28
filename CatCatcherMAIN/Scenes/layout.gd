extends RefCounted
## 屏幕适配：把「960×540 横屏构图」换算成当前可见画布里的棋盘尺寸和原点。
##
## 为什么需要它：`aspect="expand"` 下画布**宽度永远是 960 单位**，多出来的空间全加在高度上。
## 竖屏手机（390×844）算出来就是一块 960×2079 的瘦长画布，而棋盘只占其中 384 宽、还贴在左上
## —— 于是"点进去只有很小一块"。光靠缩放救不回来（板子只占 40% 宽），只能重排：
## 竖屏让棋盘铺满宽度、整块画面居中、字号和单位贴图一起放大。
##
## 纯函数、不碰节点：board.gd 和 title.gd 共用这一份，别两边各算一套。

const DESIGN_H := 540.0      # 横屏构图的设计高度

## canvas：可见画布尺寸（canvas 单位，见 Viewport.get_visible_rect）
## cfg_cell / cfg_origin：Data/game_config.json 里那套横屏布局（960 宽下的值）
## hud_h：棋盘下方 HUD 预留高度（canvas 单位），竖屏居中时算进去
## 返回 { "cell": int, "origin": Vector2i, "portrait": bool, "scale": float }
static func board_box(canvas: Vector2, cols: int, rows: int, cfg_cell: int, cfg_origin: Vector2i, hud_h: float) -> Dictionary:
	if canvas.y <= canvas.x * 1.05:
		# 横屏：格子尺寸不动，只在多余空间里居中（正好 16:9 时和配置值一模一样）
		var ox := (canvas.x - float(cfg_cell * cols)) * 0.5
		var oy := float(cfg_origin.y) + (canvas.y - DESIGN_H) * 0.5
		return { "cell": cfg_cell, "origin": Vector2i(int(ox), int(oy)), "portrait": false, "scale": 1.0 }

	# 竖屏：宽度铺满（两侧各留 3%），高度最多占 58%，取小的那个
	var cell := maxi(cfg_cell, int(floor(minf(canvas.x * 0.94, canvas.y * 0.58) / float(cols))))
	# 顶部至少留 96：右上角那三个图标按钮是锚在视口顶端的，别被棋盘压住
	var top := maxf(96.0, (canvas.y - (float(cell * rows) + hud_h)) * 0.5)
	return {
		"cell": cell,
		"origin": Vector2i(int((canvas.x - float(cell * cols)) * 0.5), int(top)),
		"portrait": true,
		"scale": float(cell) / float(cfg_cell),
	}
