# deploy.ps1 - build the GitHub Pages folder (docs/) from the Godot web export.
#
# WHY THIS EXISTS: Godot's index.wasm is 37.7MB. Shipping it raw means the reviewer
# downloads 37.7MB (GitHub Pages does not gzip application/wasm for you, and it has no
# custom-response-header support at all). Gzipped it is 9.65MB.
#
# HOW THE BROWSER STILL GETS A REAL WASM:
#   1. docs/index.wasm holds GZIP CONTENT (file name stays index.wasm)
#   2. docs/wasm-gzip.js patches window.fetch: when the engine asks for index.wasm it
#      fetches the gzip payload and inflates it with DecompressionStream, then hands the
#      engine a normal application/wasm Response
#   3. docs/index.html gets one <script> tag in <head> so the patch is installed first
# Because decompression happens client-side, this works on ANY static host (no CDN
# header rules, no server config), and it is verifiable locally.
#
# The shim passes non-gzip payloads straight through, so putting a raw wasm there by
# mistake still works - it just costs 37.7MB.
#
# build/web stays raw on purpose - tools/serve.ps1 serves THAT for local play.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy.ps1
# Then: git add docs && git commit && git push  (Pages: branch main, folder /docs)
#
# NOTE: ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM).
param(
  [string]$Src = '',             # default: <project>/build/web
  [string]$Out = ''              # default: <project>/docs   (GitHub Pages source folder)
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($Src)) { $Src = Join-Path $projectDir 'build\web' }
if ([string]::IsNullOrEmpty($Out)) { $Out = Join-Path $projectDir 'docs' }

$wasmSrc = Join-Path $Src 'index.wasm'
$htmlSrc = Join-Path $Src 'index.html'
if (-not (Test-Path $htmlSrc) -or -not (Test-Path $wasmSrc)) {
  Write-Host "[x] no web build in $Src - run tools\dev.ps1 first" -ForegroundColor Red
  exit 1
}

Write-Host "[1/5] copying $Src -> $Out ..." -ForegroundColor Cyan
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory $Out -Force | Out-Null
Get-ChildItem $Src -File | Where-Object { $_.Name -ne 'index.wasm' } |
  ForEach-Object { Copy-Item $_.FullName -Destination $Out }

# Godot must not treat the published copy as project assets (else it packs them into the
# next pck). Same trick as build/.gdignore.
Set-Content -Path (Join-Path $Out '.gdignore') -Value '' -Encoding ASCII

Write-Host '[2/5] gzipping index.wasm...' -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression
$dst = Join-Path $Out 'index.wasm'
$in = [System.IO.File]::OpenRead($wasmSrc)
$outFile = [System.IO.File]::Create($dst)
$gz = New-Object System.IO.Compression.GZipStream($outFile, [System.IO.Compression.CompressionLevel]::Optimal)
$in.CopyTo($gz)
$gz.Dispose(); $outFile.Dispose(); $in.Dispose()

Write-Host '[3/5] writing wasm-gzip.js (client-side inflate + progress)...' -ForegroundColor Cyan
$gzLen = (Get-Item $dst).Length
$shim = @'
// Inflates the gzipped index.wasm the engine fetches. See tools/deploy.ps1 for why.
// Runs before the engine starts (script tag in <head>).
//
// STREAMING on purpose: res.body is piped through DecompressionStream, so the engine
// starts on bytes as they arrive. Buffering all 9.65MB first makes a slow connection
// look frozen at 1% with no feedback.
//
// It also prints the download state on the page ("engine 42% 4.1 / 9.65 MB 118 KB/s")
// because a reviewer on a slow link must be able to tell "still downloading" from
// "broken". Errors are shown in red instead of dying silently in the console.
//
// GZIPPED / GZIP_BYTES are filled in below by deploy.ps1; with GZIPPED=false the
// response passes through untouched, so an uncompressed wasm in this folder still works.
var GZIPPED = true;
var GZIP_BYTES = __GZIP_BYTES__;

(function () {
  if (!GZIPPED) return;

  var box = null, label = null;

  function say(msg, bad) {
    if (!box) {
      box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:0;right:0;bottom:12%;z-index:2147483647;' +
        'text-align:center;pointer-events:none;font:14px/1.5 monospace;' +
        'text-shadow:0 1px 3px #000';
      label = document.createElement('span');
      box.appendChild(label);
      document.body.appendChild(box);
    }
    label.textContent = msg;
    label.style.color = bad ? '#ff6b5e' : '#f5ecd8';
    box.style.display = '';
  }

  function hide() { if (box) { box.style.display = 'none'; } }

  window.addEventListener('error', function (e) {
    say('ENGINE ERROR: ' + (e && e.message ? e.message : 'unknown'), true);
  });

  var raw = window.fetch;
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : ((input && input.url) || '');
    return raw.call(this, input, init).then(function (res) {
      if (!/\/?index\.wasm(\?.*)?$/.test(url) || !res.ok || !res.body) return res;
      if (typeof DecompressionStream === 'undefined') {
        say('ENGINE LOAD FAILED: this browser cannot inflate the engine ' +
            '(DecompressionStream missing)', true);
        throw new Error('wasm-gzip.js: DecompressionStream unavailable');
      }

      var seen = 0;
      var t0 = Date.now();
      say('engine 0%');

      var counter = new TransformStream({
        transform: function (chunk, ctrl) {
          seen += chunk.byteLength;
          var pct = Math.min(100, Math.round(seen * 100 / GZIP_BYTES));
          var secs = (Date.now() - t0) / 1000;
          var kbs = secs > 0.2 ? Math.round(seen / 1024 / secs) : 0;
          say('engine ' + pct + '%   ' + (seen / 1048576).toFixed(2) + ' / ' +
              (GZIP_BYTES / 1048576).toFixed(2) + ' MB   ' + kbs + ' KB/s');
          ctrl.enqueue(chunk);
        },
        flush: function () { setTimeout(hide, 1200); }
      });

      var body = res.body.pipeThrough(counter).pipeThrough(new DecompressionStream('gzip'));
      return new Response(body, {
        status: 200,
        statusText: 'OK',
        headers: { 'Content-Type': 'application/wasm' }
      });
    });
  };
})();
'@
$shim = $shim -replace '__GZIP_BYTES__', [string]$gzLen
Set-Content -Path (Join-Path $Out 'wasm-gzip.js') -Value $shim -Encoding ASCII

Write-Host '[4/5] patching index.html...' -ForegroundColor Cyan
$html = [System.IO.File]::ReadAllText((Join-Path $Out 'index.html'))
# ?v= is a cache buster: GitHub Pages caches for 10 minutes, and a stale shim looks
# exactly like a frozen game. Bump it whenever the shim changes.
$tag = '<script src="wasm-gzip.js?v=3"></script>'
if ($html -notmatch [regex]::Escape($tag)) {
  if ($html -notmatch '</head>') {
    Write-Host '[x] index.html has no </head> - cannot install the shim' -ForegroundColor Red
    exit 1
  }
  $html = $html -replace '</head>', ($tag + "`n</head>")
  [System.IO.File]::WriteAllText((Join-Path $Out 'index.html'), $html, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host '[5/5] verifying...' -ForegroundColor Cyan
# a) the payload must inflate back to the original byte count and start with wasm magic
$rIn = [System.IO.File]::OpenRead($dst)
$rGz = New-Object System.IO.Compression.GZipStream($rIn, [System.IO.Compression.CompressionMode]::Decompress)
$head = New-Object byte[] 4
$read = $rGz.Read($head, 0, 4)
$total = $read
$buf = New-Object byte[] 1048576
while (($n = $rGz.Read($buf, 0, $buf.Length)) -gt 0) { $total += $n }
$rGz.Dispose(); $rIn.Dispose()

$magic = ($read -eq 4 -and $head[0] -eq 0 -and $head[1] -eq 0x61 -and $head[2] -eq 0x73 -and $head[3] -eq 0x6D)
$origLen = (Get-Item $wasmSrc).Length
if (-not $magic -or $total -ne $origLen) {
  Write-Host "[x] gzip verify FAILED (magic ok=$magic, $total vs $origLen bytes)" -ForegroundColor Red
  exit 1
}
# b) the shim must be referenced by the published index.html
$published = [System.IO.File]::ReadAllText((Join-Path $Out 'index.html'))
if ($published -notmatch [regex]::Escape($tag)) {
  Write-Host '[x] index.html patch did not stick' -ForegroundColor Red
  exit 1
}
Write-Host "      ok: inflates to $total bytes, wasm magic present, shim installed" -ForegroundColor DarkGray

Write-Host ''
Write-Host "pages folder ready: $Out" -ForegroundColor Green
Get-ChildItem $Out -File | Where-Object { $_.Name -ne '.gdignore' } | Sort-Object Length -Descending |
  ForEach-Object { "  {0,-34} {1,8:N2} MB" -f $_.Name, ($_.Length/1MB) }
$sum = (Get-ChildItem $Out -File | Measure-Object -Sum Length).Sum
"{0,-36} {1,8:N2} MB" -f 'TOTAL', ($sum/1MB)
Write-Host ''
Write-Host 'Next: git add docs && git commit -m "..." && git push'
Write-Host 'Then GitHub -> Settings -> Pages -> Source: Deploy from a branch / main / /docs'
Write-Host 'Verify locally first:  tools\serve.ps1 -Root <project>\docs   (plain http, no gzip header)'
