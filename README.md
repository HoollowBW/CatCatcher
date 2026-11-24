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
CatCatcherMAIN/    游戏场景与脚本（源码，入库）
tools/dev.ps1      一键导出 + 本地预览
tools/serve.ps1    本地静态服务器（dev.ps1 会自己调）
export_presets.cfg web 导出配置
Ruler/             笔试题与要求
build/web/         导出产物（gitignore + .gdignore，不入库）
```

导出产物落在 `build/web/index.html`，**内容不进版本库**（一次 wasm 39MB，提交进去仓库会爆）。`build/.gdignore` 要留着 —— 否则 Godot 会把上次的导出产物当成项目资源打进 pck。要改输出位置就 `-OutDir`。

## 技术

Godot 4.7（GL Compatibility）→ Web 导出，`thread_support=false`（不需要 COOP/COEP 响应头，任意静态托管即可）。
