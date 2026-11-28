// 把 DSH（DeepSeek Harness）的会话日志导出成可读的 Markdown 对话记录，并附带原始日志备份。
//
// 用法（在仓库根目录）：
//   "D:\DSH\node.exe" tools/export_ai_log.mjs
//   "D:\DSH\node.exe" tools/export_ai_log.mjs --project D:\HBW\CatCatcher --out D:\HBW\CatCatcher\ai-log
//
// 产物：
//   <out>/README.md                     索引（每个会话的轮次目录）
//   <out>/NN-YYYY-MM-DD-<会话id前8位>.md  每个会话一份，按时间排序
//   <out>/raw/session-<id>.jsonl.zstd   原始会话日志（多帧 zstd），保住"不加工"的那一份
//
// 为什么要这份脚本：DSH 的会话文件是多帧 zstd（每次 append 一帧），
// node 的 zstdDecompressSync / createZstdDecompress 都只吃第一帧，
// 所以这里按帧头魔数切开逐帧解压。整理规则见下面 KEEP 与截断策略：
// 只留用户原话、助手正式回复、工具调用与结果开头；丢掉流式增量块（text-chunks 等）与内部思考块。
//
// ⚠️ user/message 记录里**没有** data.turn 字段，必须靠 turn/start 标记分段，否则所有用户输入都会归到第 0 轮。
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import os from 'node:os';

const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);          // zstd 帧头
const KEEP = new Set(['turn/start', 'user/message', 'assistant/message', 'tool/call', 'tool/result']);
const MSG_CLIP = 6000;
const ARG_CLIP = 500;
const RESULT_CLIP = 400;

// ---------------------------------------------------------------- 参数 ----
const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const projectDir = path.resolve(opt('project', path.resolve(import.meta.dirname, '..')));
const outDir = path.resolve(opt('out', path.join(projectDir, 'ai-log')));
const keepRaw = !args.includes('--no-raw');

// DSH 按 cwd 给会话分目录：D:\HBW\CatCatcher -> --D-HBW-CatCatcher--
const sessionsRoot = process.env.DSH_SESSIONS_DIR
  ?? path.join(process.env.DSH_ROOT ?? 'D:\\DSH', 'data', 'sessions');
const wsDirName = `--${projectDir.replace(/^([A-Za-z]):/, '$1').replace(/[\\/]+/g, '-')}--`;
const wsDir = path.join(sessionsRoot, wsDirName);

if (!fs.existsSync(wsDir)) {
  console.error(`[x] 找不到会话目录：${wsDir}`);
  console.error('    会话是不是记在别的 harness 目录下？可用 DSH_SESSIONS_DIR 指定。');
  process.exit(1);
}

// ---------------------------------------------------------------- 解码 ----
function decodeAll(buf) {
  const offs = [];
  let i = buf.indexOf(MAGIC, 0);
  while (i !== -1) { offs.push(i); i = buf.indexOf(MAGIC, i + 4); }
  const chunks = [];
  let bad = 0;
  let k = 0;
  while (k < offs.length) {
    let ok = false;
    for (let e = k + 1; e <= offs.length; e++) {
      const end = e < offs.length ? offs[e] : buf.length;
      let out;
      try { out = zlib.zstdDecompressSync(buf.subarray(offs[k], end)); } catch { continue; }
      // 干净的帧边界：JSONL 一定以换行结尾（最后一帧可能还在写，允许没有）
      if (out.length > 0 && out[out.length - 1] !== 0x0a && e < offs.length) continue;
      chunks.push(out);
      k = e;
      ok = true;
      break;
    }
    if (!ok) { bad++; k++; }
  }
  return { buf: Buffer.concat(chunks), bad };
}

// ---------------------------------------------------------------- 小工具 ----
const clip = (s, n) => (s.length <= n ? s : `${s.slice(0, n)} …（截断，共 ${s.length} 字）`);
const oneLine = (s, n) => clip(String(s).replace(/\r/g, '').replace(/\n+/g, ' ⏎ ').trim(), n);
const ts = (ms) => new Date(ms).toLocaleString('zh-CN', { hour12: false });
const day = (ms) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter((c) => c.type === 'text' && c.text).map((c) => c.text).join('\n');
}

function resultText(message) {
  const parts = [];
  const walk = (node) => {
    if (!node) return;
    if (Array.isArray(node)) { node.forEach(walk); return; }
    if (node.type === 'text' && node.text) parts.push(node.text);
    else if (node.content) walk(node.content);
  };
  walk(message?.content);
  return parts.join('\n');
}

// ---------------------------------------------------------------- 解码全部 ----
const parsed = [];
const sessionDirs = fs.readdirSync(wsDir).filter((n) => n.startsWith('session-'));
for (const dirName of sessionDirs) {
  const logPath = path.join(wsDir, dirName, 'session.jsonl.zstd');
  if (!fs.existsSync(logPath)) continue;
  const { buf, bad } = decodeAll(fs.readFileSync(logPath));
  const recs = [];
  let header = null;
  for (const l of buf.toString('utf8').split('\n')) {
    if (l.trim() === '') continue;
    let o;
    try { o = JSON.parse(l); } catch { continue; }
    if (o.type === 'session') { header = o; continue; }
    if (KEEP.has(o.type)) recs.push(o);
  }
  if (!recs.length) continue;
  parsed.push({ header, recs, bad, logPath, from: recs[0].time, to: recs[recs.length - 1].time });
}
parsed.sort((a, b) => a.from - b.from);
if (!parsed.length) {
  console.error('[x] 没读到任何对话记录');
  process.exit(1);
}

fs.mkdirSync(outDir, { recursive: true });
if (keepRaw) {
  fs.mkdirSync(path.join(outDir, 'raw'), { recursive: true });
  for (const s of parsed) {
    fs.copyFileSync(s.logPath, path.join(outDir, 'raw', `${path.basename(path.dirname(s.logPath))}.jsonl.zstd`));
  }
}

// ---------------------------------------------------------------- 逐会话导出 ----
const index = [];
let seq = 0;
for (const s of parsed) {
  seq += 1;
  const shortId = (s.header?.id ?? '').replace('session-', '').slice(0, 8) || `s${seq}`;
  const outName = `${String(seq).padStart(2, '0')}-${day(s.from)}-${shortId}.md`;

  const turns = new Map();
  let curTurn = 0;
  for (const r of s.recs) {
    if (r.type === 'turn/start') { curTurn = r.data?.turn ?? curTurn; continue; }
    const t = r.data?.turn ?? curTurn;
    if (!turns.has(t)) turns.set(t, []);
    turns.get(t).push(r);
  }
  const turnList = [...turns.entries()].sort((a, b) => a[0] - b[0]);

  const catalogue = [];
  for (const [turn, items] of turnList) {
    const u = items.find((r) => r.type === 'user/message');
    const first = u ? textOf(u.data?.content).trim().split('\n')[0].slice(0, 70) : '（无用户输入）';
    catalogue.push({ turn, first, time: items[0].time });
  }

  const toolCount = new Map();
  const md = [];
  md.push(`# CatCatcher · AI 对话记录 · 会话 ${seq}（${shortId}）`);
  md.push('');
  md.push(`- 时间：${ts(s.from)} → ${ts(s.to)}（${turnList.length} 轮）`);
  md.push(`- 会话 id：\`${s.header?.id ?? '?'}\`　工作目录：\`${s.header?.cwd ?? '?'}\``);
  md.push(`- 整理方式：取自 DSH 原始会话日志（多帧 zstd JSONL，原文在 \`raw/\`）。去掉流式增量块与内部思考块，**保留用户原话、助手正式回复、每次工具调用及其结果开头**；工具结果截断 ${RESULT_CLIP} 字、双方消息截断 ${MSG_CLIP} 字，并标注"截断"。`);
  md.push('');
  md.push('## 轮次目录');
  md.push('');
  md.push('| # | 时间 | 用户这一轮要什么 |');
  md.push('|---|---|---|');
  for (const c of catalogue) md.push(`| ${c.turn} | ${ts(c.time)} | ${c.first.replace(/\|/g, '\\|')} |`);
  md.push('');
  md.push('---');
  md.push('');

  const pendingCalls = new Map();
  for (const [turn, items] of turnList) {
    md.push(`## 第 ${turn} 轮`);
    md.push('');
    for (const r of items) {
      if (r.type === 'user/message') {
        const txt = textOf(r.data?.content).trim();
        if (!txt) continue;
        md.push(`**用户**（${ts(r.time)}）：`);
        md.push('');
        md.push(clip(txt, MSG_CLIP));
        md.push('');
      } else if (r.type === 'assistant/message') {
        const content = r.data?.message?.content ?? [];
        const texts = content.filter((c) => c.type === 'text' && c.text).map((c) => c.text);
        if (texts.length) {
          md.push('**助手**：');
          md.push('');
          md.push(clip(texts.join('\n'), MSG_CLIP));
          md.push('');
        }
        for (const c of content) {
          if (c.type === 'tool-call') pendingCalls.set(c.id, { name: c.name });
        }
      } else if (r.type === 'tool/call') {
        const name = r.data?.name ?? '?';
        toolCount.set(name, (toolCount.get(name) ?? 0) + 1);
        md.push(`- 🔧 \`${name}\` ${oneLine(r.data?.arguments ?? '', ARG_CLIP)}`);
        pendingCalls.set(r.data?.callId, { name });
      } else if (r.type === 'tool/result') {
        const call = pendingCalls.get(r.data?.message?.source?.callId);
        md.push(`  - ↳ ${call ? call.name : '结果'}：${oneLine(resultText(r.data?.message), RESULT_CLIP)}`);
      }
    }
    md.push('');
  }

  fs.writeFileSync(path.join(outDir, outName), md.join('\n'), 'utf8');
  index.push({
    seq, file: outName, id: shortId, from: ts(s.from), to: ts(s.to),
    turns: turnList.length, badFrames: s.bad,
    tools: [...toolCount.entries()].sort((a, b) => b[1] - a[1]),
    bytes: fs.statSync(path.join(outDir, outName)).size,
    catalogue,
  });
  console.log(`导出 ${outName}（${turnList.length} 轮，${s.bad} 坏帧，${(fs.statSync(path.join(outDir, outName)).size / 1024).toFixed(0)} KB）`);
}

// ---------------------------------------------------------------- 索引 README ----
const totalTurns = index.reduce((a, s) => a + s.turns, 0);
const totalTools = new Map();
for (const s of index) for (const [n, c] of s.tools) totalTools.set(n, (totalTools.get(n) ?? 0) + c);

const readme = [];
readme.push('# AI 对话记录（CatCatcher）');
readme.push('');
readme.push('笔试题交付项之一。全部会话按时间顺序导出成 Markdown：');
readme.push('');
readme.push('- 工具：**DeepSeek Harness**（全程同一个工具；先定规则文档，再让 AI 实现与验证）');
readme.push(`- 覆盖：${index[0].from.split(' ')[0]} → ${index[index.length - 1].to.split(' ')[0]}，共 **${totalTurns} 轮**对话、${index.length} 个会话`);
readme.push(`- 工具调用：${[...totalTools.entries()].sort((a, b) => b[1] - a[1]).map(([n, c]) => `${n} ×${c}`).join('、')}`);
if (keepRaw) readme.push(`- 原始日志：\`raw/\`（DSH 的 \`session.jsonl.zstd\`，多帧 zstd 原文，未经任何加工）`);
readme.push('- 重新导出：`"D:\\DSH\\node.exe" tools/export_ai_log.mjs`（新开了会话就再跑一次）');
readme.push('');
readme.push('## 会话索引');
readme.push('');
for (const s of index) {
  readme.push(`### 会话 ${s.seq} · ${s.file}`);
  readme.push('');
  readme.push(`时间：${s.from} → ${s.to}　轮数：${s.turns}　体积：${(s.bytes / 1024).toFixed(0)} KB`);
  readme.push('');
  readme.push('| # | 用户这一轮要什么 |');
  readme.push('|---|---|');
  for (const c of s.catalogue) readme.push(`| ${c.turn} | ${c.first.replace(/\|/g, '\\|')} |`);
  readme.push('');
}
readme.push('## 怎么读这份记录');
readme.push('');
readme.push('每一轮都是同一条链路：**用户提需求 → 助手先说改哪几个文件 → 改 → 跑验证（selftest / solvecheck / 真机渲染）→ 贴结果**。重点看三类地方：');
readme.push('');
readme.push('1. **规则先定稿再实现**：涉及玩法的回合里，助手先改 `ARCHITECTURE.md` 第 5 节，再动 `Core/`。');
readme.push('2. **验证卡退出码**：`selftest` 131 条断言、`solvecheck` 量关卡难度，工具结果的结尾常能看到 `passed, 0 failed` 与难度梯度。');
readme.push('3. **探针定位**：凡是"看起来是手感问题"的回合，都是先写 `tests/_xxx.gd` 喂真实输入复现，改完再删。');
readme.push('');
readme.push('> 内部思考（reasoning）与流式增量块没有导出；其余（含每次失败、重试、被否决的改法）都在。原始日志见 `raw/`。');
fs.writeFileSync(path.join(outDir, 'README.md'), readme.join('\n'), 'utf8');
console.log(`\n索引已写：${path.join(outDir, 'README.md')}（共 ${totalTurns} 轮 / ${index.length} 个会话）`);
if (keepRaw) console.log(`原始日志已备份：${path.join(outDir, 'raw')}`);
