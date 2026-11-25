# CatCatcher 项目规范

> 这份文档是**约束**，不是愿望清单。动手前先看第 4 节分层铁律、第 5 节规则、第 9 节踩过的坑。
> 参考项目：`D:\HBW\hollow-bastion`（同作者隔壁项目，美术/音效占位素材来自那里）。

**当前状态：M0–M5 完成（含玩法重构与三关残局），交付只剩「设计文档」和「AI 对话记录」两项文书。**

---

## 1. 一句话

一只狗冲过来抢肉，你指挥一群"人脸流浪猫"用象棋走法（车/马/兵/象）把它逼进角落，
让它的**任何一个动作都做不出来**就算赢。单局几分钟，关卡制。

## 2. 技术底线（硬性，不许改）

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7 |
| 渲染器 | **Compatibility**（`gl_compatibility`），不要改 |
| 节点类型 | 只用 2D（Node2D / Control / Sprite2D / Polygon2D）。**禁止任何 3D 节点** |
| 基准分辨率 | 960 × 540，`window/stretch/mode="canvas_items"`，`aspect="expand"` |
| Web 导出 | `variant/thread_support=false`（否则要 COOP/COEP 响应头，静态托管配不了） |
| 第三方插件 | **零**。`addons/` 不许出现东西 |
| 数值 | 全部走 `Data/game_config.json`，脚本里不许出现魔法数字 |
| 屏幕文字 | **只许 ASCII**（内置字体没有 CJK 字形，web 版画成方块，见 9.5） |

## 3. 目录与职责

```
CatCatcherMAIN/
  Core/                     纯逻辑层：不许引用任何节点
    game_state.gd           一局的完整可变状态 + 快照/回滚
    level.gd                运行期关卡数据（纯数据）+ 全局配置读取
    rules.gd                一个回合的结算（实战/搜索/求解器共用这一份）
    move_rules.gd           走法 = 控制范围（同一份计算）+ 受保护判定
    encircle.gd             狗的动作表 / 逃跑条件 / 围死判定
    dog_ai.gd               狗的行动决策（实战与预览共用）
    respawn.gd              猫被吃掉后的投放点（确定性）
    solver.gd               求解器：启动校验 + 提示（唯一一份搜索）
    game_controller.gd      回合流程 + 悔棋栈 + 胜负
  Characters/               单位都是场景，用 Godot 编辑器拖放编辑
    Cats/   cat_rook.tscn / cat_horse.tscn / cat_pawn.tscn / cat_bishop.tscn
    Dogs/   dog_stray.tscn（dog_collie.tscn 已废弃，未使用）
    Meat/   meat.tscn
    Objects/ obstacle.tscn
  Levels/                   关卡也是场景
    level.gd                格子向导 + 吸附 + collect + 按路径认单位（@tool）
    levels.gd               关卡顺序 SCENES + 启动校验
    run_request.gd          打断循环引用用的小纸条（见 9.3）
    level_01.tscn … level_06.tscn
  Scenes/
    title.tscn / title.gd   标题页（**主场景**）：纯视觉软引导，点一下进棋盘
    board.tscn / board.gd   格子 + 控制范围 + 预览 + HUD + 演出 + 音效
    dissolve.gdshader       旧撕纸残影用的，现已无人引用（撞飞改成螺旋起飞了）
  Graphics/placeholders/    占位贴图（借自隔壁 hollow-bastion）
  Audio/                    音效 6 个（借自隔壁 Audio/Sound_effect，改成 ASCII 文件名）
  Data/game_config.json     全局数值（配色、格子尺寸、提示阈值、求解器参数）
docs/                       **GitHub Pages 发布目录**（tools/deploy.ps1 生成，必须入库）
tests/
  selftest.gd               规则层自检，115 条断言
  solvecheck.gd             关卡尺子：量每关最短几步
tools/
  dev.ps1                   导出 + 起本地服务 + 开浏览器
  deploy.ps1                build/web → docs/（wasm 预压 gzip + 解压 shim + 破缓存）
  serve.ps1                 本地静态服务器
```

**单位和关卡都是场景，不是数据文件。** 刻意的：Godot 编辑器本身就是最好的关卡编辑器。

## 4. 分层铁律

**`Core/` 里不许出现**：`get_node()` / `$` / `await` / `preload` 场景 / 任何 `Node` 派生类型的参数。
Core 的输入只能是 `GameState` 和基本类型，输出只能是数据。
理由：求解器要在**没有场景树**的情况下跑几十万次试算。

场景层（`Scenes/`、`Levels/*.gd`）只做三件事：读 Core 的结果来画、把输入翻译成 Core 调用、播表现。

**单文件上限 500 行。** `board.gd` 现在 811 行，已超标（见 TODO 第 4 节）。

## 5. 核心规则（当前定稿，别再翻案）

### 棋盘与单位
- 6×6，坐标 `Vector2i(x=列, y=行)`，左上 `(0,0)`
- 猫：`pawn` 邻 1 格（正交）/ `rook` 整行整列遇障碍停 / `horse` 日字可越人 / `bishop` 斜线遇障碍停
- 狗只有一种（`stray`）：贪心朝肉走。**全确定性，没有随机数**
- 肉占一格，**可以站 1 只猫**
- 障碍挡视线（车的线会被截断）

### 控制范围 = 走法范围（铁律，但有一个例外）
同一个 `MoveRules.reach_cells()` 出同一份集合，绝不拆两套。

- ⚠️ 控制范围**不受其他单位阻挡**（纯几何，只有障碍 / 出界能挡）
- ⚠️ **肉格不计入控制范围**，但它不阻挡车 / 象的线（肉不是单位，是地物）
- ⚠️ **站在肉格上的猫，控制范围 = 0** —— 这是"走法=控制"的**唯一例外**：
  它没有控制，但**可以按自己的走法走下来**（玩家能把守肉的猫撤回，见 `MoveRules._geometry`）

### 保护
猫的格子落在**另一只猫**的控制范围内 = 受保护 → 狗**吃不动**它。
⚠️ **站肉格上的猫永远不受保护**（否则"垫肉"会变成无敌防守）。

### 肉格（胜负核心）
- 狗进入**空的**肉格 = **玩家立即输**（`meat_eaten`）
- 狗贴肉必须先**低吼**一回合（前摇）：本回合只低吼、不动
- 低吼之后的下一个狗回合，肉格还是空的 → 它**吃掉肉**
- 狗做了低吼以外的任何动作（走 / 吃子 / 逃跑）→ 低吼清零，前摇要重来
- 肉格上有猫 → 狗**吃掉那只猫、自己停在原地**（进不了肉格），低吼清零 —— 玩家用一只猫换一回合
- 进入肉格**无视控制**（控制挡不住它吃肉）

### 撞飞 = 吃子
狗吃掉相邻的**未被保护**的猫，**并移动到那一格**（吃子即前进）。
例外：吃垫在肉格上的猫时，狗停在原地。

### 逃跑（玩家"驱赶"狗的手段，不是额外操作）
狗**脚下那格被某只猫控制** + **还有空可走** + **吃不到相邻的猫** ⇒ 它自己跑，不朝肉走。

- 逃跑优先级**最高**（高于吃肉前摇）；逃跑也清零低吼
- 落点 = "逃路最多"的安全格（该格周围可走的邻格数最多）；同分取离肉更远的，再按方向表序
- ⚠️ **推论（最容易被误解的一条）**：用**贴身**的猫去罩狗，那只猫自己就在狗嘴边且往往没被保护
  → 狗会**先吃它**（界面显示 `WILL BITE`），不跑。要真赶走它，得**隔空罩**
  （车的行列 / 象的斜线 / 马的日字），或者用另一只猫把那隻贴身的猫罩住。

### 胜负
- **胜利**：狗**没有任何合法动作**（走 / 吃子 / 对肉的动作都算动作）
- **失败**：狗吃到肉；或回合数达到 `max_turns`
- ⚠️ 推论：狗只要**贴着肉格就永远有动作**（低吼 / 吃肉 / 吃垫肉的猫），
  所以**只能在它离肉 ≥2 格时围死**。贴身之后只能靠垫猫拖延。

### 回合流程
- 玩家每回合**只能移动一只猫一次**，走完**狗立刻行动**（自动结束回合，没有"结束回合"键）
- 悔棋 = 撤销**一整个回合**（玩家那步 + 狗那步），可以连撤到开局
- 悔棋是快照，不是反向操作（见 6.1）

## 6. 三条继承 hollow-bastion 的硬规矩

### 6.1 悔棋 = 状态快照，不是逆操作
回合边界拍 `GameState.snapshot()`，悔棋就是 `restore()`。
写"反向操作"的话，每加一个机制就要写一份反向逻辑，漏一处就状态不一致。

### 6.2 预览与实战必须同一个函数
预览 = `DogAI.plan(state.clone())`，实战 = `DogAI.plan(state)`，就这一行差别。

### 6.3 AI 全确定性，禁止随机
掷了随机数预览就对不上实战。要"变化"就用距离、回合数这类确定量去分叉。
**玩家报"AI 有时跑有时不跑"时，先查 `Encircle.can_flee()` 的三个条件，不要怀疑随机。**

## 7. 命名

- 文件 `snake_case.gd`；`class_name` `PascalCase` 且和文件名对应
- 常量 `UPPER_SNAKE`，私有前缀 `_`，信号用过去式
- 坐标一律 `Vector2i`，`(x, y)` = `(列, 行)`
- **音效/贴图文件名一律 ASCII**（中文名在 web 导出里是额外的路径编码风险）

## 8. 数据

**全局数值**在 `CatCatcherMAIN/Data/game_config.json`：格子尺寸/原点/配色、狗的警示样式、
提示触发阈值、求解器深度与节点预算。一次改完，不许每关抄一遍。
（旧的肉 HP / 腐坏 / 啃食已随规则重构删除。）

**关卡内容在场景里**（`Levels/level_XX.tscn`），不是数据文件。见第 10 节。

⚠️ 读 `game_config.json` 只能走 `load()`，不能走 `FileAccess` —— 见 9.1。

## 9. 踩过的坑（别再踩）

### 9.1 JSON 只能 `load()`，不能 `FileAccess`
`include_filter="*.json"` 在 headless 导出里**不生效**。只有被**静态 `preload()`** 的 JSON 才会打包，
而且是**烧进 GDScript 编译块**，pck 里没有独立文件。
所以 `Level.load_config()` 走 `ResourceLoader.exists()` + `load()` + `.data`。
验收：`godot --headless --main-pack build\web\index.pck --quit`（web 版真实的加载路径）。

### 9.2 子节点永远压在父节点的 `_draw()` 之上
单位成了 board 的子节点之后，board 自己 `_draw()` 画的东西会被盖住。
**结算界面必须用 `CanvasLayer`**（+ ColorRect/Label），不能用 `_draw()`。
反过来也用得上：撞飞的飞行残影设 `z_index=40` 才能盖在单位上面。

### 9.3 `levels.gd` ↔ `level.gd` 循环引用
`levels.gd` preload 关卡场景 → 场景 ext_resource `level.gd` → 若 `level.gd` 再引用 `Levels` 就成环。
所以才有 `run_request.gd`。**`level.gd` 永远不许引用 `Levels`。**

### 9.4 关卡坐标要惰性初始化
`Levels.build()` 只 `instantiate()`、不进场景树，`_ready()` 不会跑。
`level.gd` 的 `_ensure_geometry()` 就是为这个。

### 9.5 屏幕上不许出现中文
内置字体是拉丁字面。桌面端靠系统字体回退能画，**web 导出没有这个回退**。
Core 只产语言无关的 code（`encircled` / `meat_eaten` / `timeout`），文案在 `board.gd` 的 `REASON_TEXT`。

### 9.6 判胜有多条入口，别只写一条
`Rules.apply_dog_turn()` 开头就判一次（玩家刚走完可能已经围死），狗行动完再判一次
（狗自己走进死胡同）。只写后半条会让"明明困死了却不结算"重现。

### 9.7 震屏之后点击要 `to_local()`
震屏是平移 board 节点本身，`_point_to_cell()` 必须 `to_local(get_global_mouse_position())`。

### 9.8 车的位置决定关卡会不会一步杀
车的特性是"同行列一步可达"。只要**制胜格和车共行或共列**，这关必然一步杀。
设计新关要么把车放远，要么用障碍切断那条线。**量难度只信 `solvecheck`，别凭感觉。**

### 9.9 wasm 37.7MB，超过各家的上传/压缩上限
引擎本体 37.7MB，游戏内容 pck 才 0.39MB —— **换美术不会让下载变小**。
所以有 `tools/deploy.ps1`：wasm 预压成 gzip（9.65MB）+ `wasm-gzip.js`（客户端 `DecompressionStream`
流式解压 + 页面显示下载进度/报错）。`build/web` 保持原样给本地预览，**上传的永远是 `docs/`**。

### 9.10 改规则必须跑**主场景**，不只跑棋盘
标题页 `title.gd` 里用 `assert(Encircle.is_encircled(演示布局))` 自检演示动画演得对不对。
规则一改（"狗贴肉永远有动作"），这个断言必然失败 → **调试版直接卡死在主场景，进不了第一关**。
所以验收固定三条：`selftest` + **`--quit`（主场景）** + `--quit res://…/board.tscn`。

### 9.11 新资源不 `--import` 会直接 parse error
往 `Graphics/` `Audio/` 里拷新文件后，没有 `.import` 的话 `preload()` 报
`no resource loaders (unrecognized file extension)`。先跑 `godot --headless --path . --import`。

### 9.12 图层：肉要先画
单位是关卡场景的子节点，场景里的节点顺序决定绘制顺序 —— 守肉的猫会**被肉盖住**。
`_sync_units()` 里统一设：肉 `z_index=0`、猫 `2`、狗 `3`。

### 9.13 用"动作前后比对"求发生了什么，必须排除玩家自己动的那只
`_apply_move()` 靠对比 `before_cells` 判断"哪只猫被吃了"。漏掉 `if i == cat_index: continue`
→ **每走一步都播一次撞飞动画**（真出过）。同理音效也会错播成"吃子音"。

### 9.14 GitHub Pages 缓存 600 秒，push 完看到的还是旧版
Pages 给所有文件发 `Cache-Control: max-age=600`，而 `index.pck` 就是游戏逻辑本体。
现在 shim 把 pck 请求改成 `index.pck?t=<时间戳>` 强制取最新（每次多下 0.39MB）。
`index.html` 那一层破不了（Pages 不许自定义响应头），所以**改完 html/shim 仍需等十分钟或强刷**。

## 10. 做关卡：用 Godot 编辑器，不另写编辑器

1. Godot 里打开 `Levels/level_01.tscn`
2. 把 `Characters/` 里的单位场景拖进来，往格子上随便扔 —— `level.gd` 每帧吸到格心
3. 做下一关：FileSystem 里右键那个 `.tscn` → **复制**，改名，挪几个单位
4. 新关在 `Levels/levels.gd` 的 `SCENES` 里加一行
5. **单独跑某一关**：对那个 `.tscn` 按 **F6**

**类型的唯一来源是场景路径**：`Cats/cat_<type>.tscn`（`rook`/`horse`/`pawn`/`bishop`）、
`Dogs/dog_<type>.tscn`、`Meat/*`、`Objects/*`。⚠️ 别重命名单位场景或挪文件夹，那等于改语义。

**关卡不许是死局，也不许是白送**：启动时和 `selftest` 都会跑求解器验一遍。

```powershell
godot --headless --path . --script res://tests/solvecheck.gd -- 6      # 全部关卡（6 = 最大深度）
godot --headless --path . --script res://tests/solvecheck.gd -- 6 4    # 只量第 4 关
```

**当前梯度：1 / 2 / 3 / 3 / 3 / 4**（第 1–3 关是教学，第 4–6 关是国象残局主题）：
`底线杀·石墙`（车+兵+兵+障碍墙）/ `梯子杀`（车+兵+障碍）/ `马象杀`（马+象+障碍）。

设计要领（都是被规则逼出来的）：
- **围死必须发生在狗离肉 ≥2 格时**（贴肉就永远有动作），所以关卡要让狗"走不到肉"或"先被逼偏"
- **边和角最好用**：格子少，需要封的方向少
- **障碍当墙**：能把狗的贪心路线掰弯，也能把车/象的线截断（车线一断，难度立刻上来）
- **别把贴身猫白送**：狗会吃孤儿猫。想让它跑，就得隔空罩
- 量难度只信 `solvecheck`；手摆十有八九会撞出"一步杀"

## 11. 求解器只有一个

`Core/solver.gd` 是唯一的搜索实现（迭代加深 DFS，返回**最短**赢棋路线）：

| 用处 | 调用点 |
|---|---|
| 启动校验每关有解（无解 `push_error`） | `Levels.validate_all()` ← `board._ready()` |
| 提示：从**当前局面**算下一步 | `board._update_hint()` |
| 设计关卡时量难度 | `tests/solvecheck.gd` |

三者都走 `Rules.apply_turn`，所以搜出来的路线实战一定走得通。

⚠️ 搜索必须带 `node_budget`（默认 20 万节点），宁可返回"搜不到"，也不能把浏览器卡死。
⚠️ 状态指纹必须包含 `growling`（低吼状态），否则"低吼过/没低吼过"会被错误剪枝。

## 12. 表现层现状

- **单位**：`Characters/` 里的场景就是全部外观，`board.gd` 只 `position = …` 挪它们
- **预览**：只对**选中的那只猫**生效、且**只在鼠标悬停时**有（手机没有悬停，见 TODO）
- **驱赶提示**：狗脚下被控制时显示 `FLEE`（真会跑）或 `WILL BITE` + 橙框 `!`（会咬那只孤儿猫）
- **肉的腐烂**：按 `turn / max_turns` 从原色 lerp 到暗黄绿（纯 modulate）
- **撞飞**：螺旋起飞（200px / 1.5s，绕两圈、缩小淡出）+ 命中冲击环 + 斩击音
- **音效**：`Audio/` 6 个（点击 / 挪动 / 吃子 / 低吼 / 胜 / 负），3 个播放器轮转
- **结算/闪屏**：`CanvasLayer`，永远在最上层；任意键或点屏幕继续
- **屏幕按钮**：右上角 UNDO / RESTART（手机没键盘，必须点得到）
- **调试**：debug 版按 **F1** 打印狗"为什么跑/为什么不跑"的三条条件

## 13. 明确不做（别自作主张加）

- ❌ 血量 / 伤害 / 攻击力系统（已经删干净了，别加回来）
- ❌ 将军判定（"狗威胁肉"不做单独判定）
- ❌ 自由组队、抽卡、养成、背包
- ❌ 肉鸽、随机地图生成
- ❌ 3D、联网、云存档
- ❌ 动画系统、状态机框架、事件总线

## 14. 待定

1. **第 4、5 关偏软**（都是 3 步，和第 3 关同档）—— 想拉到 4–5 步需要再搜一轮布局
2. **手机没有悬停预览** → 手机上"走这里狗会怎么动"看不见，只有走完才知道
3. `board.gd` 811 行超标，下次大改应该把演出（震屏/闪白/撞飞/HUD）拆出去
4. 平衡数值：`max_turns` 前 3 关 10/12/10、后 3 关 15，从没按手感调过
