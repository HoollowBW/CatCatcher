# CatCatcher 项目规范

> 这份文档是**约束**，不是愿望清单。动手前先看第 4 节分层铁律和第 9 节「踩过的坑」。
> 参考项目：`D:\HBW\hollow-bastion`（同类棋盘战术游戏，规范从它提炼，坑也从它绕开）。

**当前状态：M0–M3 完成，M4 做了一半（不需要美术的部分做完了），M5 未开始。**

---

## 1. 一句话

一只狗冲过来抢肉，你指挥一群"人脸流浪猫"用象棋走法封死它的所有去路，达成"围死"触发总攻击。
单局 3–6 分钟，关卡制。

## 2. 技术底线（硬性，不许改）

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7 |
| 渲染器 | **Compatibility**（`gl_compatibility`），不要改 |
| 节点类型 | 只用 2D（Node2D / Control / Sprite2D / Polygon2D）。**禁止任何 3D 节点** |
| 基准分辨率 | 960 × 540，`window/stretch/mode="canvas_items"` |
| Web 导出 | `variant/thread_support=false`（否则要 COOP/COEP 响应头，静态托管配不了） |
| 第三方插件 | **零**。`addons/` 不许出现东西 |
| 数值 | 全部走 `Data/game_config.json`，脚本里不许出现魔法数字 |

## 3. 目录与职责

```
CatCatcherMAIN/
  Core/                     纯逻辑层：不许引用任何节点
    game_state.gd           一局的完整可变状态 + 快照/回滚
    level.gd                运行期关卡数据（纯数据）+ 全局配置读取
    rules.gd                一个回合的结算（实战/搜索/求解器共用这一份）
    move_rules.gd           走法 = 控制范围（同一份计算）+ 受保护判定
    encircle.gd             狗的去路 / 撞飞候选 / 围死判定
    dog_ai.gd               狗的行动决策（实战与预览共用）
    respawn.gd              撞飞后猫的投放点（确定性）
    solver.gd               求解器：启动校验 + 提示（唯一一份搜索）
    game_controller.gd      回合流程 + 悔棋栈 + 胜负
  Characters/               单位都是场景，用 Godot 编辑器拖放编辑
    Cats/   cat_rook.tscn / cat_horse.tscn / cat_pawn.tscn
    Dogs/   dog_stray.tscn / dog_collie.tscn
    Meat/   meat.tscn
    Objects/ obstacle.tscn
  Levels/                   关卡也是场景
    level.gd                格子向导 + 吸附 + collect + 按路径认单位（@tool）
    levels.gd               关卡顺序 SCENES + 启动校验
    run_request.gd          打断循环引用用的小纸条（见 9.3）
    level_01.tscn …         一关一个场景，做新关直接复制
  Scenes/
    board.tscn / board.gd   格子 + 控制范围 + 预览 + HUD + 演出
    dissolve.gdshader       撕纸消散（M4，不需要美术）
  Graphics/placeholders/    占位贴图（借自隔壁 hollow-bastion，M4 换真美术时替换）
  Data/game_config.json     全局数值（肉的 HP、腐坏、啃食、格子尺寸、求解器/提示参数）
tests/
  selftest.gd               规则层自检，73 条断言
  solvecheck.gd             关卡尺子：量每关最短几步
tools/                      dev.ps1 / serve.ps1（导出与本地预览，产物不入库）
```

**单位和关卡都是场景，不是数据文件。** 刻意的：Godot 编辑器本身就是最好的关卡编辑器
（拖放、吸附、复制关卡、可视化摆位），自己再写一套是重复造轮子。

## 4. 分层铁律

**`Core/` 里不许出现**：`get_node()` / `$` / `await` / `preload` 场景 / 任何 `Node` 派生类型的参数。
Core 的输入只能是 `GameState` 和基本类型，输出只能是数据。
理由：求解器要在**没有场景树**的情况下跑几十万次试算，Core 一旦绑了节点就永远搬不进求解器。

场景层（`Scenes/`、`Levels/*.gd`）只做三件事：读 Core 的结果来画、把输入翻译成 Core 调用、播表现。

**单文件上限 500 行。** 隔壁 `main.gd` 有 466KB —— 这就是不设上限的下场。
（当前最大的是 `board.gd`，约 850 行，已经超标，下次大改应该拆出表现层的演出/HUD。）

## 5. 核心规则（当前定稿，别再翻案）

### 棋盘与单位
- 6×6，坐标 `Vector2i(x=列, y=行)`，左上 `(0,0)`
- 猫：`pawn` 邻 1 格 / `rook` 整行+整列遇障碍停 / `horse` 走日字可越人
- 狗：只能正交走 1 格。`stray` 贪心朝肉走，`collie` BFS 绕障碍
- 肉占一格，谁都站不上去

### 控制范围 = 走法范围
同一个 `MoveRules.reach_cells()` 出同一份集合，绝不拆两套。

⚠️ **控制范围不受其他单位阻挡**（纯几何，只有障碍/出界/肉的格能挡）。
理由：棋盘上的色块必须稳定，不能因为自家猫站位变化而忽长忽短。

### 控制 = 硬阻挡
狗**不能**走进被任意一只猫控制的格。

### 围死 = 没有可走的空格
`Encircle.is_encircled()` 只看 `movable_cells()`（空 + 未被控制 + 不是肉）。

⚠️ **相邻的猫不算逃生路。** 早先写成"没有空格且相邻没有猫"，结果四邻被猫围住时
狗还能一直撞飞苟着，玩家看着明明困死了却不结算 —— 那不是玩家该去理解的东西，是规则没写对。

### 撞飞
- 只有「朝肉方向那一格蹲着猫」时才会撞，且**撞完本回合不移动**
- ⚠️ **被队友保护的猫撞不动**（国际象棋那套）：猫的格子落在**另一只猫**的控制范围内 = 受保护。
  所以站成一排互相罩着的车，狗一只都拍不飞；撞飞只对落单的猫有效。
- 被撞飞的猫**没有固定出生点**，动态投放到离 `{狗, 肉}` 最远（曼哈顿）的格；
  同分按先 y 后 x 取，保证确定性；棋盘满了允许堆叠

### 胜负
- **胜利**：玩家行动后 `is_encircled()`，**或狗自己走完之后** `is_encircled()`
  （漏了后半条会让"困死了却不结算"重现，见 9.6）
- **失败**：肉 HP ≤ 0（每回合腐坏 -1，狗贴着肉啃 -3），或回合数到 `max_turns`

## 6. 三条从 hollow-bastion 继承的硬规矩

### 6.1 悔棋 = 状态快照，不是逆操作
回合边界拍 `GameState.snapshot()`，悔棋就是 `restore()`。
写"反向操作"的话，每加一个机制就要写一份反向逻辑，漏一处就状态不一致。

### 6.2 预览与实战必须同一个函数
预览 = `DogAI.plan(state.clone())`，实战 = `DogAI.plan(state)`，就这一行差别。
另写一套预测逻辑，玩家迟早发现"预览说会撞飞，实际没撞"。

### 6.3 AI 全确定性，禁止随机
掷了随机数预览就对不上实战。要"变化"就用回合数、距离这类确定量去分叉。

## 7. 命名

- 文件 `snake_case.gd`（**不跟隔壁混用 PascalCase 文件名**）
- `class_name` `PascalCase` 且和文件名对应
- 常量 `UPPER_SNAKE`，私有前缀 `_`，信号用过去式
- 坐标一律 `Vector2i`，`(x, y)` = `(列, 行)`

## 8. 数据

**全局数值**在 `CatCatcherMAIN/Data/game_config.json`：格子尺寸/原点/配色、
肉的 HP/腐坏/啃食、狗的警示样式、提示触发阈值、求解器深度与节点预算。
一次改完，不许每关抄一遍。

**关卡内容在场景里**（`Levels/level_XX.tscn`），不是数据文件。见 10。

⚠️ 读 `game_config.json` 只能走 `load()`，不能走 `FileAccess` —— 见 9.1。

## 9. 踩过的坑（按被坑次数排序，别再踩）

### 9.1 JSON 只能 `load()`，不能 `FileAccess`
`include_filter="*.json"` 在 headless 导出里**不生效**（塞个 `.txt` 也不进 pck）。
只有被**静态 `preload()`** 的 JSON 才会打包，而且是**烧进 GDScript 编译块**，pck 里没有独立文件。
所以 `FileAccess.get_file_as_string("res://…json")` 在 web 版**必然读不到**，编辑器里却完全正常。

结论：`Level.load_config()` 走 `ResourceLoader.exists()` + `load()` + `.data`。

验收：`godot --headless --main-pack build\web\index.pck --quit`（这才是 web 版真实的加载路径）。

### 9.2 子节点永远压在父节点的 `_draw()` 之上
单位成了 board 的子节点之后，board 自己 `_draw()` 画的东西会被盖住。
**结算界面必须用 `CanvasLayer`**（+ ColorRect/Label），不能用 `_draw()`。

### 9.3 `levels.gd` ↔ `level.gd` 循环引用
`levels.gd` preload 关卡场景 → 场景 ext_resource `level.gd` → 若 `level.gd` 再引用 `Levels` 就成环，
Godot 报 `Parse Error: Busy` / `referenced non-existent resource`。
所以才有 `run_request.gd`（什么也不 preload 的小纸条）。
**`level.gd` 永远不许引用 `Levels`。**

### 9.4 关卡坐标要惰性初始化
`Levels.build()` 只 `instantiate()`、不进场景树，`_ready()` 不会跑。
`Levels/level.gd` 的 `_ensure_geometry()` 就是为这个 —— 直接信 `_ready()` 会让所有单位整体偏掉
（真踩过：三关坐标全错，第 2、3 关直接变成"开局白送"）。

### 9.5 屏幕上不许出现中文
Godot 内置字体是拉丁字面。桌面端能画中文是因为回退到 Windows 系统字体，
**web 导出没有这个回退**，同一段文字会变空白或方块。
Core 只产语言无关的 code（`encircled` / `meat_gone` / `timeout`），文案由 `board.gd` 的
`REASON_TEXT` 映射。关卡 `name` 是中文，但只给文档和日志用，不上屏。
真要在 web 上显示中文，得自带字体文件（隔壁有思源黑体）。

### 9.6 判胜有两条路径，别只写一条
玩家行动后要判，**狗自己走完之后也要判**。只写前半条 = "狗拐进死胡同却不结算，
玩家必须再瞎走一步才赢"（这个 bug 真出过，第 2 关因此多了一步无用操作）。

### 9.7 震屏之后点击要 `to_local()`
震屏是平移 board 节点本身，`_point_to_cell()` 必须
`to_local(get_global_mouse_position())`，否则震屏那零点几秒里点击会错位。

### 9.8 车的位置决定关卡会不会一步杀
车的特性是"同行列一步可达"。只要**制胜格和车共行或共列**，这关必然一步杀。
第 2 关就栽在这：车在 (5,4)、制胜格 (4,4) 同一行。把车挪到 (5,1) 才变回两步。
设计新关要么把车放离制胜线远一点，要么用障碍切断那条线。

## 10. 做关卡：用 Godot 编辑器，不另写编辑器

1. Godot 里打开 `Levels/level_01.tscn`
2. 把 `Characters/` 里的单位场景拖进来，往格子上随便扔 —— `Levels/level.gd` 每帧吸到格心
3. 做下一关：FileSystem 里右键那个 `.tscn` → **复制**，改名，挪几个单位
4. 新关在 `Levels/levels.gd` 的 `SCENES` 里加一行
5. **单独跑某一关**：对那个 `.tscn` 按 **F6**

**类型的唯一来源是场景路径**，不是导出属性：

| 路径 | 含义 |
|---|---|
| `Characters/Cats/cat_<type>.tscn` | 猫，type = `rook` / `horse` / `pawn` |
| `Characters/Dogs/dog_<type>.tscn` | 狗，type = `stray` / `collie` |
| `Characters/Meat/*` | 肉 |
| `Characters/Objects/*` | 障碍 |

⚠️ **别随手重命名单位场景或挪文件夹** —— 那等于改掉它的语义。

**关卡不许是死局，也不许是白送。** 启动时和 `selftest` 都会跑求解器验一遍。
量难度用 `tests/solvecheck.gd`（迭代加深，报**最短**步数）：

```powershell
godot --headless --path . --script res://tests/solvecheck.gd -- 4      # 全部关卡
godot --headless --path . --script res://tests/solvecheck.gd -- 4 2    # 只量第 2 关
```

当前梯度：第 1 关 1 步、第 2 关 2 步、第 3 关 3 步。

## 11. 求解器只有一个

`Core/solver.gd` 是唯一的搜索实现（迭代加深 DFS，返回**最短**赢棋路线）：

| 用处 | 调用点 |
|---|---|
| 启动校验每关有解（无解 `push_error`） | `Levels.validate_all()` ← `board._ready()` |
| 提示：从**当前局面**算下一步 | `board._update_hint()` |
| 设计关卡时量难度 | `tests/solvecheck.gd` |

三者都走 `Rules.apply_turn`，所以搜出来的路线实战一定走得通。
**别在别处另写搜索** —— 一份逻辑改一处，三份逻辑改成三处、漏两处。

⚠️ 搜索必须带 `node_budget`（默认 20 万节点）。深度上去就是指数爆炸，
宁可返回"搜不到"，也不能把浏览器卡死。

## 12. 表现层现状

- **单位**：`Characters/` 里的场景就是全部外观，`board.gd` 不画单位，只 `position = …` 挪它们
- **预览**：只对**选中的那只猫**生效。悬停可落格 → 绿=走到这格后的控制范围 /
  橙块=狗下回合威胁 / 橙箭头=狗这回合动作
- **引导**：多邻国式箭头（长距离画箭头，一格距离改短指示三角 + 缩小落点圈）
- **演出（M4 已完成的无美术部分）**：屏幕震动、闪白/闪红 + `ENCIRCLED!` 弹入、
  围死后延迟弹结算、猫被撞飞的撕纸 dissolve 残影（`dissolve.gdshader`，纯程序化）
- **结算/闪屏**：`CanvasLayer`，永远在最上层

## 13. 明确不做（别自作主张加）

- ❌ 血量 / 伤害 / 攻击力系统（肉的 HP 是倒计时，不是战斗）
- ❌ 自由组队、抽卡、养成、背包
- ❌ 肉鸽、随机地图生成
- ❌ 3D、联网、云存档
- ❌ 动画系统、状态机框架、事件总线 —— 需要时再说，别提前搭

## 14. 待定

1. 第 5、6 关的**马路机关**（每 3 回合整排被扫过）还没做，`Core/` 里没有任何实现
2. 第 4 关用边牧（`dog_collie.tscn` 已存在但没关卡用），BFS 绕障逻辑没被实际关卡验证过
3. `game_config.json` 里的平衡数值（HP 20 / 腐坏 1 / 啃食 3 / `max_turns`）从没调过

已定，别再翻案：控制范围纯几何不阻挡、控制=硬阻挡、围死=没有可走格、
受保护的猫撞不动、撞飞=动态投放、单位与关卡都是场景。
