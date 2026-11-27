# CatCatcher

> 一只狗冲过来抢肉，你指挥一群"人脸流浪猫"用象棋走法（车/马/兵/象）把它逼到角落，
> 让它的**任何一个动作都做不出来**就算赢 —— 狗贴着肉格时会先低吼，那是它动手前的最后警告。

网页直接可玩：**https://hoollowbw.github.io/CatCatcher/**

## 跑起来

```powershell
# 导出 web 版 + 起本地服务 + 开浏览器
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1
```

之后改完游戏再跑一次，浏览器按 <kbd>F5</kbd> 刷新即可，服务不用重启。

> Godot 的 `.wasm` / `.pck` 是 `fetch()` 加载的，**直接双击 `index.html` 打不开**（file:// 不行），必须走 http。
> ⚠️ `Data/game_config.json` 里的数值是**烧进 pck** 的，改完必须重新导出，不然本地预览还是旧值。

## 操作

| 动作 | 电脑 | 手机 |
|---|---|---|
| 选猫 → 落子 | 点猫，再点高亮格（**走完狗立刻行动**） | 点猫，再点高亮格 |
| 悔棋（撤一整个回合） | <kbd>Z</kbd> 或右上角悔棋图标 | 右上角悔棋图标 |
| 重开本关 | <kbd>R</kbd> 或右上角重开图标 | 右上角重开图标 |
| 要提示 | 右上角 `?` 图标（和第一关的常驻引导同一个样子） | 同上 |
| 取消选中 | <kbd>Esc</kbd> / 点空地 | 点空地 |
| 通关后进下一关 | 任意键 | 点屏幕任意处 |
| 调试：狗为什么跑/不跑 | **F1**（仅 debug 版，打印控制台） | — |

**看懂棋盘**：青色爪印 = 猫的控制范围（狗进不去）；橙块 = 狗下一步的威胁；橙箭头 = 狗这回合的动作；
狗脚下被控制时会显示 `逃跑`（它会跑）或 `先咬猫` + 橙框 `!`（它会先吃掉那只没人罩的猫）；
肉的颜色随时间变暗变黄绿 = 在腐烂。

前 3 关常驻引导（多邻国式箭头）；之后要连续失败 2 次或挂机 60 秒才会给下一步。

**单独测某一关**：在 Godot 里打开那个 `Levels/level_XX.tscn`，按 <kbd>F6</kbd> 就直接从这一关开打。

## 结构

```
CatCatcherMAIN/
  Core/            纯逻辑层（规则、状态、求解器）—— 不碰节点
  Characters/      单位场景：Cats/（车/马/兵/象）Dogs/ Meat/ Objects/
  Levels/          关卡场景：level_01…09.tscn + levels.gd；做新关直接复制
  Scenes/          标题页 title.tscn（主场景）+ 棋盘 board.tscn
                   + warn_layer.gd（画在单位上面的警告文字/笔刷）+ bgm.gd（音乐 autoload）
  Graphics/        手绘素材：Cats/ Dog/ Objects/ Tips/ Grids/ Button/ Title/（文件名全 ASCII）
  Fonts/           原字体（排包外）+ subset/（实际随包的子集字体，~140 KB）
  Audio/           6 个音效 + bgm_rest.mp3
  Data/            全局数值 game_config.json
docs/              GitHub Pages 发布目录（tools/deploy.ps1 生成，要入库）
tests/             selftest.gd（规则自检 131 条）/ solvecheck.gd（量关卡难度）
tools/dev.ps1      一键导出 + 本地预览
tools/deploy.ps1   生成 docs/（wasm 预压 gzip + 解压 shim + pck 破缓存）
tools/serve.ps1    本地静态服务器（dev.ps1 会自己调）
tools/subset_font.gd  字体子集化（改了中文文案要重跑）
export_presets.cfg web 导出配置
build/web/         导出产物（gitignore + .gdignore，不入库）
Ruler/             笔试题与要求
```

**动手前先读 [`ARCHITECTURE.md`](ARCHITECTURE.md)** —— 分层铁律、核心规则（含狗的行动优先级）、
命名、数据规范、17 条踩坑都在里面。

## 验证

改完 `Core/` 或数据层，跑这几条：

```powershell
# 规则层自检（退出码 0 = 全过）
godot --headless --path . --script res://tests/selftest.gd

# 关卡尺子：量每关最短几步能赢（1/2/3/3/3/3/4/4/6），设计新关时用
godot --headless --path . --script res://tests/solvecheck.gd -- 6

# 主场景（标题页）能启动 —— 改了规则一定要跑，标题页有 assert 会炸
godot --headless --path . --quit

# 直接跑棋盘场景（抓表现层错误，顺便验 9 关全部有解）
godot --headless --path . --quit res://CatCatcherMAIN/Scenes/board.tscn

# 从导出的 pck 运行 —— web 版真实的数据加载路径（FileAccess 在这里会失效）
godot --headless --main-pack build\web\index.pck --quit

# 不开编辑器也能看画面：Godot 自带 movie writer 会写出 PNG 序列
godot --path . --write-movie "$env:TEMP\shot\f.png" --fixed-fps 30 --quit-after 8
```

## 字体（中文的坑）

屏幕上的中文全靠项目自带字体，web 版没有系统字体回退。为了不把 17 MB 的 CJK 字体塞进包里，
`Fonts/subset/` 里放的是**子集字体**（只含 ASCII + 屏幕文案里出现的汉字，合计 ~140 KB），
原字体只当子集化的输入、已排到导出包外。

**改了任何屏幕文案（新增汉字）就要重跑：**

```powershell
godot --headless --path . --script res://tools/subset_font.gd -- `
  res://CatCatcherMAIN/Fonts/DeYiHei/SmileySans-Oblique-2.ttf res://CatCatcherMAIN/Fonts/subset/display.ttf
godot --headless --path . --script res://tools/subset_font.gd -- `
  res://CatCatcherMAIN/Fonts/LXGWWenKai-Regular/LXGWWenKai-Medium.ttf res://CatCatcherMAIN/Fonts/subset/body.ttf
godot --headless --path . --import
```

## 部署（GitHub Pages）

```powershell
# 1. 导出（产物在 build\web，本地预览也用它）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1

# 2. 生成发布目录 docs\（wasm 预压成 gzip 内容：37.7MB -> 9.65MB）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy.ps1

# 3. 提交并推送（推送由本人手动做）
git add -A ; git commit -m "deploy: ..." ; git push
```

仓库 Settings → Pages → Source: `main` / `/docs`。推完约一分钟重建。

> **为什么 wasm 要预压**：GitHub Pages 不会替你压 `application/wasm`，而且引擎本体 37.7MB
> （游戏内容 pck 才约 2.6MB —— 换美术/换字体不会让它变小）。`docs/index.wasm` 里存的是 gzip 内容，
> `docs/wasm-gzip.js` 用 `DecompressionStream` 在浏览器里**边下边解**，页面底部显示
> `engine 42% 4.1/9.65MB 118KB/s`，弱网也能分清"在下"和"坏了"。这套不依赖任何托管平台
> 的自定义响应头，换托管不用改代码。
>
> **缓存**：Pages 给所有文件发 `max-age=600`。`index.pck` 已带时间戳破缓存，改完游戏普通刷新就是新版；
> 但如果改了 `index.html` / `wasm-gzip.js`，浏览器仍可能拿十分钟内的旧副本 → 强刷或等一会儿。
> 线上自检：`curl -I https://hoollowbw.github.io/CatCatcher/index.pck` 看体积变没变。

## 做关卡

关卡就是场景，用 Godot 编辑器本身编辑：

1. 打开 `CatCatcherMAIN/Levels/level_01.tscn`
2. 把 `Characters/` 里的单位场景拖进来，随便往格子上扔 —— 会自动吸到格心
3. 做下一关：FileSystem 里右键那个 `.tscn` → 复制，改名，挪几个单位
4. 新关在 `Levels/levels.gd` 的 `SCENES` 里加一行

⚠️ **播放顺序看 `levels.gd` 的数组，不是文件名编号**（`level_07` 是第 3 关）。
⚠️ 单位类型是从**场景路径**认的（`Cats/cat_rook.tscn` → 车猫），别随手重命名文件或挪文件夹。

设计关卡的两条硬约束（都是规则逼出来的）：
- **围死必须发生在狗离肉 ≥2 格时** —— 狗贴着肉格就永远有动作（低吼/吃肉/吃垫肉的猫）
- **别把贴身的猫白送** —— 狗会咬没人罩的猫；想让它跑，得用车/象/马隔空罩

跑一次 `solvecheck` 量难度，启动时也会自动校验每关有解（debug 版）。

## 进度与待办

玩法、9 关、美术、字体、中文、音效、音乐、GitHub Pages 部署全部完成。
**交付清单、下一步优先级、已知粗糙处见 [`TODO.md`](TODO.md)**，改过什么、为什么是现在这样见 [`CHANGELOG.md`](CHANGELOG.md)。

## 技术

Godot 4.7（GL Compatibility）→ Web 导出，`thread_support=false`（不需要 COOP/COEP 响应头，任意静态托管即可）。
