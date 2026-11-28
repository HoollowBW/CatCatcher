# TODO

> 这是**笔试题**的交付项目，不是长期产品。时间是硬约束，先交得上，再谈打磨。
> 规则和分层约束见 `ARCHITECTURE.md`；改完 `Core/` 必须跑 `tests/selftest.gd`。

## 0. 交付清单（题目硬性要求，先对着这条检查）

| 要交的 | 状态 |
|---|---|
| 可游玩链接（打开即玩，评审期 2 周有效） | ✅ **https://hoollowbw.github.io/CatCatcher/**（GitHub Pages，`docs/` 目录发布） |
| GitHub 公开仓库 | ✅ https://github.com/HoollowBW/CatCatcher （public，匿名可访问） |
| 设计文档（1500–3000 字） | ✅ `DESIGN.md`（2,682 汉字，含题目要求的 5 节） |
| AI 对话完整记录 | ✅ `ai-log/`（4 个会话 / 69 轮 / 索引 + 原始日志 `raw/`） |

> 四样都齐了。提交前只需重跑一次 `tools/export_ai_log.mjs` 把最新的对话补进去。

## 1. 如果再有一周（按优先级）

1. **竖屏做真正的竖版布局**：现在竖屏是把横版画面用相机缩放铺满（棋盘够大了），HUD 仍是一条横带。
2. **手感/平衡**：`max_turns` 从没按实玩调过，建议拿"求解器最短步数 × 1.5"当基准重定。
3. **关卡生产工具化**：写"给定主题 + 目标步数，自动搜布局"的脚本（修第 7 关时已验证思路可行）。
4. **手机补两条**：没有悬停预览（改成点两下：先预览再落子）；竖屏边缘格子离屏幕太近，需要更大触摸安全区。
5. **代码债**：`board.gd` 约 1250 行，把演出层拆出去。

## 2. 玩法缺口

- [ ] **第 3 关「守肉」不再演示垫肉**：`DogAI` 改成"撞猫优先于吃肉"后，最短解里没有垫肉那一步了
      （现在是"封住它去肉的路 + 收网"，还是能教守肉，但少了"牺牲抢回合"这层）。
      想恢复得放宽到 4–5 步重搜布局。
- [ ] **第 5、6 关的马路机关**（每 3 回合整排被"车"扫过）从未实现，规则重构后更难自洽，建议放弃。
- [ ] **关卡数量**：9 关现在大约 5–6 分钟通关，符合题目"单局 3–6 分钟"。
- [ ] **BGM 已接**（`Audio/bgm_rest.mp3`，1.4 MB，循环，走 autoload）。想换曲子只改一张图/一个文件。
- [x] ~~音效~~ 6 个（点击/挪动/吃子/低吼/胜/负）。
- [x] ~~第 4 关边牧~~ 按"不做别的狗了"废弃，`dog_collie.tscn` 保留但没人用。
- [x] ~~美术~~ 手绘素材全部接好（猫 4 种 / 狗 4 态 / 肉 / 障碍 / 提示笔刷 / 按钮 / 标题）。

## 3. 已知粗糙处

- `board.gd` **约 1250 行**，远超 500 行上限。下次大改应该把演出（震屏/闪白/撞飞/HUD/按钮/音效）拆出去。
- **手机没有悬停预览**：威胁范围靠鼠标 hover 触发，手机上点完猫看不到"走这里狗会怎么动"。
  可选方案：选中猫时列出各候选落点的威胁 / 手机上点高亮格先预览、再点一次才落子。
- **第 8 关「护肉」的提示仍含送子**：那是它的教学意图（狗会咬你没罩住的猫），干净路线在 8 步内不存在。
- 叠放（多只猫同格）只在 `Respawn` 满盘兜底时出现，渲染没特殊处理，会完全重叠。
- 提示阈值（前 3 关常驻、之后失败 2 次或挂机 60 秒）没实测过。
- 没有关卡选择界面，只能从头打到尾，`R`/RESTART 只重开当前关。
- 竖屏是把横版画面用相机缩放铺满（棋盘够大），但 HUD 仍是一条横带、上下留白偏多。
- `Scenes/dissolve.gdshader` 没有任何文件引用，可以直接删。

## 4. 部署 / 交付操作（每次改完游戏都要做）

```powershell
# 1. 如果动过中文文案：重跑字体子集（否则新字没字形），再 --import
godot --headless --path . --script res://tools/subset_font.gd -- `
  res://CatCatcherMAIN/Fonts/DeYiHei/SmileySans-Oblique-2.ttf res://CatCatcherMAIN/Fonts/subset/display.ttf
godot --headless --path . --script res://tools/subset_font.gd -- `
  res://CatCatcherMAIN/Fonts/LXGWWenKai-Regular/LXGWWenKai-Medium.ttf res://CatCatcherMAIN/Fonts/subset/body.ttf
godot --headless --path . --import

# 2. 生成发布目录（导出 + wasm 预压 + 解压 shim + 破缓存）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy.ps1

# 3. 本地先跑三条验收
godot --headless --path . --script res://tests/selftest.gd          # 规则自检（131 条）
godot --headless --path . --script res://tests/solvecheck.gd -- 6   # 难度梯度 1/2/3/3/3/3/4/4/6
godot --headless --path . --quit                                    # 主场景（标题页）能启动
godot --headless --path . --quit res://CatCatcherMAIN/Scenes/board.tscn   # 棋盘场景 + 9 关校验

# 3.5 重导 AI 对话记录（新开过会话就要跑）
"D:\DSH\node.exe" tools\export_ai_log.mjs

# 4. 提交 + 推送（推送由本人手动做）
git add -A ; git commit -m "..." ; git push
```

⚠️ **改了 `Data/game_config.json` 必须重新导出**：配置是烧进 pck 的（`ARCHITECTURE` 9.1），
不重导出的话本地看 `build/web` 或线上都还是旧值。

Pages 一分钟左右重建。**改动只涉及 pck 时**打开就是新版（pck 已带时间戳破缓存）；
**改了 `index.html` / `wasm-gzip.js` 时**仍有最多 10 分钟浏览器缓存，需要强刷或等一会儿。

线上验收：`curl -I https://hoollowbw.github.io/CatCatcher/index.pck` 看体积是否变了
（现在约 2.6 MB；变了说明 Pages 已经换了新包，剩下的就是本地缓存问题）。

## 5. 别做的事

见 `ARCHITECTURE.md` 第 13 节。尤其：**不要把血量/伤害系统加回来、不做将军判定、
不要做随机地图、不要提前搭动画框架或事件总线**。
