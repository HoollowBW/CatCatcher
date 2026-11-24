# CatCatcher 项目规范

> 这份文档是**约束**，不是愿望清单。写代码前先对照第 4 节的分层铁律。
> 参考项目：`D:\HBW\hollow-bastion`（同类棋盘战术游戏，规范从它提炼，坑也从它绕开）。

当前阶段：**搭框架，只做 M0 / M1**。框架里所有玩法函数都是 `assert(false, "TODO")` 的空壳，
故意让它一跑就炸 —— 空壳静默返回 `false`/`[]` 比报错更危险。

---

## 1. 一句话

一只狗冲过来抢肉，你指挥一群"人脸流浪猫"用象棋走法封死它的所有去路，达成"围死"触发总攻击。

## 2. 技术底线（硬性，不许改）

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7 |
| 渲染器 | **Compatibility**（`gl_compatibility`），不要改 |
| 节点类型 | 只用 2D（Node2D / Control / Sprite2D）。**禁止任何 3D 节点** |
| 基准分辨率 | 960 × 540，`window/stretch/mode="canvas_items"` |
| Web 导出 | `variant/thread_support=false`（否则需要 COOP/COEP 响应头，静态托管配不了） |
| 第三方插件 | **零**。`addons/` 不许出现东西 |
| 数值 | 全部走 `Data/*.json`，脚本里不许出现魔法数字 |

## 3. 目录与职责

```
CatCatcherMAIN/
  Core/                     纯逻辑层：可以 import，但不许引用任何节点路径
    game_state.gd           一局的完整可变状态 + 快照/回滚
    level.gd                运行期关卡数据（纯数据）+ 全局配置读取
    rules.gd                一个回合的结算（实战/搜索/求解器共用这一份）
    move_rules.gd           走法 = 控制范围（同一份计算）
    encircle.gd             狗的所有合法动作 + 围死判定
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
    level_01.tscn …         一关一个场景，做新关直接复制
  Scenes/                   棋盘主场景
    board.tscn / board.gd   格子 + 控制范围 + 预览 + HUD；单位由关卡场景提供
  Graphics/placeholders/    占位贴图（借自隔壁 hollow-bastion，M4 整体替换）
  Data/game_config.json     全局数值（肉的 HP、腐坏、啃食、格子尺寸、求解器参数……）
tests/                      selftest.gd（规则自检）/ solvecheck.gd（关卡尺子）
tools/                      导出与本地预览脚本（不入库产物）
```

**单位和关卡都是场景，不是数据文件。** 这是刻意的：Godot 编辑器本身就是最好的关卡编辑器
（拖放、吸附、复制关卡、可视化摆位），自己再写一套编辑器是重复造轮子。

## 4. 分层铁律

**Core/ 里不许出现这些东西**：`get_node()` / `$` / `await` / `preload` 场景 / 任何 `Node` 派生类型的参数。
Core 的输入只能是 `GameState` 和基本类型，输出只能是数据。理由：求解器（M3）要在**没有场景树**的情况下
跑几十万次试算，Core 一旦绑了节点就永远搬不进求解器。

场景层（`Scenes/`）只做三件事：读 Core 的结果来画、把玩家输入翻译成 Core 的函数调用、播表现。

**单文件上限 500 行。** 隔壁 `main.gd` 有 466KB —— 这就是不设上限的下场，没人在凌晨三点读得懂它。

## 5. 三条从 hollow-bastion 继承的硬规矩

### 5.1 悔棋 = 状态快照，不是逆操作
在**回合边界**拍快照（`GameState.snapshot()`），悔棋就是 `restore()` 回去。
邻居踩过的坑：写"反向操作"来撤销，结果每加一个机制就要写一份反向逻辑，漏一处就状态不一致。
状态只有一份，快照就是一坨字典，`duplicate(true)` 就完事。

### 5.2 预览与实战必须同一个函数
敌方行动预览**不许**另写一套"预测逻辑"。预览 = `DogAI.plan(state.clone())`，
实战 = `DogAI.plan(state)`，同一行代码。隔壁的原话：「预告与实战只有一个来源」。

### 5.3 AI 全确定性，禁止随机
一旦掷了随机数，预览就对不上实战，玩家会觉得游戏在骗人。
需要"变化"就用状态里的确定量（回合数、距离）去分叉。

## 6. 命名

- 文件：`snake_case.gd`（**不跟隔壁混用 PascalCase 文件名**，那边 `MoveRules.gd` 和 `gridmanager.gd` 是混着的）
- `class_name`：`PascalCase`，且**和文件名对应**
- 常量：`UPPER_SNAKE`
- 私有成员/函数：前缀 `_`
- 信号：过去式（`turn_ended`、`game_over`）
- 坐标一律 `Vector2i`，`(x, y)` = `(列, 行)`，左上角 `(0,0)`

## 7. 数据

所有可调数值进 `Data/game_config.json`；关卡进 `Data/levels/`。

关卡 JSON 结构见 `level_01.json`。字段含义：

| 字段 | 说明 |
|---|---|
| `grid` | 棋盘尺寸 |
| `meat` | 肉的坐标 `[x, y]` |
| `dog` | `{pos, type}`，type ∈ `stray` / `collie` |
| `cats` | `[{pos, type}]`，type ∈ `pawn` / `rook` / `horse` |
| `obstacles` | 障碍格坐标数组 |
| `hint` | 手工提示序列，元素 `{"cat": [x,y], "to": [x,y]}` = 把 `cat` 那格的猫走到 `to`。只给前几关教学用；空数组 = 交给求解器（M3） |
| `solution` | 参考解法，格式同 `hint`。**只给自检/求解器验收，不展示给玩家**（见 8.3） |
| `max_turns` | 回合上限（肉每回合腐坏，间接就是计时器） |

**撞飞 / 马路扫中的猫不回"出生点"，而是动态投放到离主战场最远的格。** 见 8.1。

**肉的 HP / 每回合腐坏 / 啃食伤害不在关卡里**，在 `game_config.json` —— 那是全局数值，
改平衡要能一处改完，不许每关抄一遍。

### ⚠️ 7.1 读 JSON 只能走 `load()`，不能走 `FileAccess`

这是踩过的坑，别再重走：

1. `export_presets.cfg` 里的 `include_filter="*.json"` 在 headless 导出里**不生效**
   （实测连放一个 `*.txt` 进去也不进 pck）。
2. 只有被**静态 `preload()`** 的 JSON 才会被打包，而且它是**烧进 GDScript 编译块**的，
   pck 里并不会留下一个 `res://.../x.json` 文件。
3. 所以 `FileAccess.get_file_as_string("res://...json")` 在 web 版**必然读不到**，
   编辑器里却完全正常 —— 这种"只在导出后才炸"的 bug 最难查。

结论：`Level.read_json()` 走 `ResourceLoader.exists()` + `load()` + `.data`；
新增关卡必须在 `Level._EXPORT_DEPS` 里补一行 preload，否则 web 版读不到那一关。

**验收方式**（改完数据层必跑）：

```powershell
# 直接从导出的 pck 运行 —— 这才是 web 版真实的数据加载路径
godot --headless --main-pack build\web\index.pck --quit
```

## 8. 里程碑验收

每个里程碑都必须**单独可验收**，验收标准写在下面，做完自查：

| 里程碑 | 验收标准 | 状态 |
|---|---|---|
| **M0** | 棋盘画出来、点格子有选中反馈、单位以占位方块 + 类型文字显示在正确格 | ✅ |
| **M1** | 猫能动、控制范围实时显示、狗按规则行动、围死能判赢、肉 HP 归零能判负、能重开、能悔棋、能预览狗的行动 | ✅ |
| M2 | 从 JSON 读多关、通关进下一关 | ✅ |
| M3 | 求解器能验证关卡有解（启动时跑）、能给提示 | ✅ |
| M4 | 视觉替换（便利贴、人脸猫、dissolve、总攻击、开场动画） | |
| M5 | Web 导出 + 部署 | |

### 8.3 关卡不许是死局，也不许是白送

关卡改成场景之后**不再有"标准答案"字段**，改由求解器验（启动时 + selftest 各跑一遍）：

- 每关必须：能构建、至少一只猫、有狗有肉、开局不是已经被围死、`Solver` 在
  `solver.validate_depth` 步内搜得到解。
- 任一条不满足就 `push_error` 点名是哪关。

设计新关时用 `tests/solvecheck.gd` 量难度（迭代加深，报**最短**步数）：

```powershell
godot --headless --path . --script res://tests/solvecheck.gd -- 4      # 全部关卡
godot --headless --path . --script res://tests/solvecheck.gd -- 4 2    # 只量第 2 关
```

⚠️ 别指望 4 步以上：狗是确定性的，分支只来自玩家一侧，但深度一上去节点数还是爆炸。

⚠️ **空地 + 两只车 = 一步赢**。任何一只车都能一步滑进狗的所在行/列，两只车夹住就完事了。
所以关卡必须有障碍切断车的直线，或者只给兵/马这种慢单位，否则一律是一步送。

### 8.2 屏幕文案不许写在 Core 里

Godot 内置字体是拉丁字面，**中文上屏是有风险的**：桌面端能画出来，是因为引擎回退到了
Windows 系统字体；web 导出没有这个回退，同一段文字很可能变成空白或方块。
所以：

- Core 只产出语言无关的 code（`encircled` / `meat_gone` / `timeout`），
  显示文字由表现层的 `REASON_TEXT` 映射。
- **屏幕上不出现中文**。关卡 `name` 是中文，但它只给文档和日志用，不上屏 ——
  真要在 web 上显示中文，得在 M4 自带一个中文字体文件（参考项目里就有思源黑体）。

`tests/selftest.gd` 是规则层的验收闸门，改完 `Core/` 必须跑：

```powershell
godot --headless --path . --script res://tests/selftest.gd   # 退出码 0 = 全过
```

### 8.1 撞飞/扫中后猫去哪：动态投放（已定稿）

猫**没有固定出生点**。被撞飞或被马路扫中时，投放到「离主战场最远」的格子：

1. 候选格 = 非墙、非狗所在格的空格
2. 每格算一个分数 = 到 `{狗, 肉}` 的最小曼哈顿距离，取分数最高的那个
3. 同分按固定顺序（先 y 后 x）取，保证**确定性** —— 随机的话预览和实战会对不上（5.3）
4. **候选格为空（棋盘满了）时允许堆叠**：挑当前猫最少的格子塞进去，不报错、不阻塞回合

堆叠是这条规则带出来的例外，所以 `GameState` 里同一格可以有多只猫。
`cat_at()` 只返回其中一只，需要枚举时要遍历 `cats`。这是 v1 唯一的叠放场景，
玩家自己操作**仍然不允许**把猫走到有猫的格上。

### 8.4 求解器只有一个，三处共用

`Core/solver.gd` 是唯一的搜索实现（迭代加深 DFS，返回**最短**赢棋路线）：

| 用处 | 调用点 |
|---|---|
| 启动校验每关有解（无解 `push_error`） | `Level.validate_all()` ← `board._ready()` |
| 提示：从**当前局面**算下一步 | `board._update_hint()` |
| 设计关卡时量难度 | `tests/solvecheck.gd` |

三者都走 `Rules.apply_turn`，所以搜出来的路线实战一定走得通。
**别在别处另写搜索** —— 一份逻辑改一处，三份逻辑改成三处、漏两处。

⚠️ 搜索必须带 `node_budget`（默认 20 万节点）。深度一上去就是指数爆炸，
宁可返回"搜不到"，也不能把浏览器卡死。深度和预算在 `game_config.json` 的 `solver` 段。

### 8.5 做关卡：用 Godot 编辑器，不另写编辑器

照隔壁 HollowBastion 那套搬的 —— **关卡就是场景**：

1. Godot 里打开 `Levels/level_01.tscn`
2. 把 `Characters/` 里的单位场景拖进来
3. 往格子上随便扔 —— `Levels/level.gd` 每帧把单位吸到格心
4. 做下一关：FileSystem 里右键这个 `.tscn` → **复制**，改名，挪几个单位
5. 新关在 `Levels/levels.gd` 的 `SCENES` 里加一行

**类型的唯一来源是场景路径**，不是导出属性（和隔壁按 `Heros/` `Enemys/` 判阵营同一路数）：

| 路径 | 含义 |
|---|---|
| `Characters/Cats/cat_<type>.tscn` | 猫，type = `rook` / `horse` / `pawn` |
| `Characters/Dogs/dog_<type>.tscn` | 狗，type = `stray` / `collie` |
| `Characters/Meat/*` | 肉 |
| `Characters/Objects/*` | 障碍 |

⚠️ 所以**别随手重命名单位场景或挪文件夹** —— 那等于改掉它的语义。

⚠️ **坐标原点靠惰性初始化**：`Levels.build()` 只 `instantiate()`、不进场景树，`_ready()` 不会跑。
`Levels/level.gd` 的 `_ensure_geometry()` 就是为了这个 —— 直接相信 `_ready()` 会让所有单位整体偏掉
（这个坑真踩过：三关坐标全错，第 2、3 关直接变成"开局白送"）。

### 8.6 单位的视觉是场景，不是 board 画的

`Characters/` 里的场景就是单位的全部外观（`Sprite2D` / `Polygon2D`）。`board.gd` **不画单位**，
只按 Core 算出的格子坐标去 `position = ...` 挪它们（`_sync_units()`）。
换美术 = 改 `Characters/` 里的场景，一行 board 代码都不用动。

### 8.7 层级：子节点永远压在父节点的 `_draw()` 之上

单位成了 board 的子节点之后有一串连带后果，踩过一次别再踩：

- **结算界面不能用 `_draw()` 画** —— 遮罩会被障碍物和猫盖住。用 `CanvasLayer`（永远在最上层）
  + `ColorRect` / `Label`，见 `_build_result_layer()`。
- 什么时候单独跑某一关：在编辑器里对 `Levels/level_XX.tscn` 按 **F6**。关卡场景在 `_ready`
  发现 `current_scene == self` 就把路径写进 `RunRequest` 再切到棋盘，棋盘据此决定从第几关开始。
- ⚠️ **`level.gd` 不许引用 `Levels`**：`levels.gd` preload 关卡场景、场景 ext_resource 了
  `level.gd`，`level.gd` 再引用 `Levels` 就成环，Godot 报 `Parse Error: Busy` /
  `referenced non-existent resource`。所以才有那个什么也不 preload 的 `RunRequest`。

### 8.8 威胁范围预览

鼠标停在一个**可走的格子**上时（选中了猫就用选中的；没选中时如果只有一只猫能走到那就自动用它，
多只都能走到就不猜），显示两段信息：

- 橙箭头 + 橙圈 = 狗**这一回合**会做什么（`preview_after` → `DogAI.plan`）
- 橙色块 = **威胁范围**：把这一步真的 `Rules.apply_turn` 走一遍，再取 `Encircle.legal_actions`
  —— 也就是狗下回合能碰到哪些格

全是 Core 的现成函数，没有第二套预测逻辑。

## 9. 明确不做（别自作主张加）
- ❌ 血量 / 伤害 / 攻击力系统（肉的 HP 是倒计时，不是战斗）
- ❌ 自由组队、抽卡、养成、背包
- ❌ 肉鸽、随机地图生成
- ❌ 3D、联网、云存档
- ❌ 动画系统、状态机框架、事件总线 —— 需要时再说，别提前搭

## 10. 待定（做之前先问）

1. 求解器的搜索深度到底取几层（设计写 3–5 层），要等 M1 的分支因子实测出来才知道。

已定，不再是待定项（留档，别再翻案）：
- 控制范围**不被其他单位阻挡**（纯几何，只有障碍和出界能挡）
- 控制 = 硬阻挡，围死 = 相邻无空格且相邻无猫
- 撞飞/扫中 = 动态投放，棋盘满则堆叠（见 8.1）
- 单位和关卡都是**场景**，不是 JSON（见 8.5 / 8.6）
