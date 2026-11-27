# TODO

> 这是**笔试题**的交付项目，不是长期产品。时间是硬约束，先交得上，再谈打磨。
> 规则和分层约束见 `ARCHITECTURE.md`；改完 `Core/` 必须跑 `tests/selftest.gd`。

## 0. 交付清单（题目硬性要求，先对着这条检查）

| 要交的 | 状态 |
|---|---|
| 可游玩链接（打开即玩，评审期 2 周有效） | ✅ **https://hoollowbw.github.io/CatCatcher/**（GitHub Pages，`docs/` 目录发布） |
| GitHub 公开仓库 | ✅ https://github.com/HoollowBW/CatCatcher （public，匿名可访问） |
| 设计文档（1500–3000 字） | ❌ 未写 ——**唯一的大块缺口** |
| AI 对话完整记录 | ❌ 未整理（导出各会话 + 去掉无关闲聊即可，不必润色） |

设计文档题目要求覆盖：一句话介绍 / 设计思路 / AI 协作方式 / 试玩迭代 / 复盘。
素材直接对应取：规则定稿过程（`ARCHITECTURE` 第 5 节含"撞猫优先"那条）、
每次"看起来是规则问题其实是实现漏了"的排查（`CHANGELOG`）、难度梯度（`solvecheck` 1/2/3/3/3/3/4/4/6）。

## 1. 立刻该做的（按优先级）

1. **设计文档**（1500–3000 字）：
   - 一句话：用象棋走法把抢肉的狗逼到无招可出
   - 设计思路：为什么"控制=硬阻挡"、为什么删掉 HP 改成"进肉即输+低吼前摇"、
     为什么胜利条件是"狗没有任何合法动作"、为什么最后把"撞猫"提到"吃肉"之上
   - AI 协作：规则先定稿再让 AI 实现；每轮改动都跑自检；AI 犯过的错比成功更值得写
   - 试玩迭代：3 关 → 6 关 → 9 关；难度梯度用求解器量出来而不是拍脑袋；
     第 9 关（6 步）是拿第 7 关几何加障碍"逼"出来的
   - 复盘：早期债（HP 系统、撞飞保护机制）、web 独有的坑（字体子集、JSON 烧进 pck、wasm 体积）
2. **AI 对话记录整理**（照着"一条需求 → 一次验证 → 一次修正"的方式挑选）。
3. **手机实测**（唯一没被真机验证过的环节）：点猫 → 点高亮格 → 狗立刻行动；
   右上角三个图标按钮；通关点屏幕继续；音效/音乐是否正常（首次点击后解锁音频）。
4. **手感/平衡**：`max_turns` 从没按实玩调过。

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

- `board.gd` **约 1280 行**，远超 500 行上限。下次大改应该把演出（震屏/闪白/撞飞/HUD/按钮/音效）拆出去。
- **手机没有悬停预览**：威胁范围靠鼠标 hover 触发，手机上点完猫看不到"走这里狗会怎么动"。
  可选方案：选中猫时列出各候选落点的威胁 / 手机上点高亮格先预览、再点一次才落子。
- 叠放（多只猫同格）只在 `Respawn` 满盘兜底时出现，渲染没特殊处理，会完全重叠。
- 提示阈值（前 3 关常驻、之后失败 2 次或挂机 60 秒）没实测过。
- 没有关卡选择界面，只能从头打到尾，`R`/RESTART 只重开当前关。
- 浏览器窗口**不是 16:9 时棋盘会贴左边**（`aspect="expand"`：多出来的宽度全加在右侧）。
  手机上尤其明显 —— 竖屏时棋盘偏上偏左。要修就改成居中补偿或用黑边。
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
