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
    level.gd                关卡数据 + JSON 加载
    move_rules.gd           走法 = 控制范围（同一份计算）
    encircle.gd             狗的所有合法动作 + 围死判定
    dog_ai.gd               狗的行动决策（实战与预览共用）
    game_controller.gd      回合流程 + 悔棋栈 + 胜负
  Scenes/                   表现层：节点、渲染、输入
    board.tscn / board.gd   棋盘渲染 + 点击选格 + 控制范围 + 预览 + HUD
  Graphics/placeholders/    占位贴图（借自隔壁 hollow-bastion，M4 整体替换）
  Data/
    game_config.json        全局数值（肉的 HP、腐坏、啃食、格子尺寸……）
    levels/level_01.json    关卡数据
tests/selftest.gd           规则层自检（`--script` 直接跑）
tools/                      导出与本地预览脚本（不入库产物）
```

后面 M1 加 `Scenes/unit.tscn`、`Scenes/hud.tscn`；M4 加 `Graphics/`。**没用到就别建空目录。**

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
| M2 | 从 JSON 读 6 关、通关进下一关 | |
| M3 | 求解器能验证关卡有解（启动时跑）、能给提示 | |
| M4 | 视觉替换（便利贴、人脸猫、dissolve、总攻击、开场动画） | |
| M5 | Web 导出 + 部署 | |

### 8.2 屏幕文案不许写在 Core 里

Godot 内置字体**没有 CJK 字形**，`draw_string` 画中文在 web 版是空白/方块。
所以 Core 只产出语言无关的 code（`encircled` / `meat_gone` / `timeout`），
显示文字由表现层的 `REASON_TEXT` 映射。Core 一旦开始拼屏幕句子，就等着在 web 版看空白吧。

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
- `hint` 元素 = `{"cat": [x,y], "to": [x,y]}`
