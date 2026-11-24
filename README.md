# CatCatcher

> 一句话介绍待填（设计文档里那句「好玩在哪」放这儿）

网页直接可玩：**<线上链接待填>**

## 跑起来

```powershell
# 导出 web 版 + 起本地服务 + 开浏览器
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1
```

之后改完游戏再跑一次，浏览器按 <kbd>F5</kbd> 刷新即可，服务不用重启。

> Godot 的 `.wasm` / `.pck` 是 `fetch()` 加载的，**直接双击 `index.html` 打不开**（file:// 协议不行），必须走 http。

## 结构

```
CatCatcherMAIN/
  Core/            纯逻辑层（规则、状态、流程）—— 不碰节点，求解器要复用
  Scenes/          表现层（棋盘渲染、输入）
  Data/            关卡与数值 JSON
tools/dev.ps1      一键导出 + 本地预览
tools/serve.ps1    本地静态服务器（dev.ps1 会自己调）
export_presets.cfg web 导出配置
Ruler/             笔试题与要求
build/web/         导出产物（gitignore + .gdignore，不入库）
```

**动手前先读 [`ARCHITECTURE.md`](ARCHITECTURE.md)** —— 分层铁律、命名、数据规范、里程碑验收都在里面。

导出产物落在 `build/web/index.html`，**内容不进版本库**（一次 wasm 39MB，提交进去仓库会爆）。`build/.gdignore` 要留着 —— 否则 Godot 会把上次的导出产物当成项目资源打进 pck。要改输出位置就 `-OutDir`。

## 验证

改完 Core 或数据层，跑这两个：

```powershell
# 规则层自检（改完 Core/ 或关卡 JSON 必跑），退出码 0 = 全过
godot --headless --path . --script res://tests/selftest.gd

# 关卡尺子：量每关最短几步能围死（迭代加深 DFS），设计新关时用
godot --headless --path . --script res://tests/solvecheck.gd -- 4

# 启动自检：打印关卡加载结果
godot --headless --path . --quit

# 从导出的 pck 运行 —— 这才是 web 版真实的数据加载路径（FileAccess 在这里会失效）
godot --headless --main-pack build\web\index.pck --quit

# 不开编辑器也能看到画面：Godot 自带的 movie writer 会写出 PNG 序列
godot --path . --write-movie "$env:TEMP\shot\f.png" --fixed-fps 30 --quit-after 3
```

## 操作

左键点猫选中 → 悬停可落格看敌方行动预览 → 点格子移动（狗会立刻行动）。
<kbd>Z</kbd> 悔棋（一次撤一整个回合），<kbd>R</kbd> 重开本关，<kbd>Esc</kbd> 取消选中，
通关后 <kbd>Space</kbd> 进下一关。

## 技术

Godot 4.7（GL Compatibility）→ Web 导出，`thread_support=false`（不需要 COOP/COEP 响应头，任意静态托管即可）。
