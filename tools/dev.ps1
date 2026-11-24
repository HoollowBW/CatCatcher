# dev.ps1 - export web build + start local server + open browser
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1
# Re-run after changing the game, then press F5 in the browser (server keeps running).
# Output goes to <project>/build/web/index.html, which is gitignored.
# NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 reads .ps1 as
# ANSI unless it has a UTF-8 BOM, and a stray UTF-8 char can eat the closing quote.
param(
  [string]$Godot  = 'D:\edge\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe',
  [string]$OutDir = '',          # default: <project>/build/web
  [int]$Port     = 8099
)

$projectDir = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($OutDir)) { $OutDir = Join-Path $projectDir 'build\web' }
$target = Join-Path $OutDir 'index.html'

if (-not (Test-Path $Godot)) {
  Write-Host "[!] Godot not found: $Godot  (pass -Godot <path>)" -ForegroundColor Red
  exit 1
}
New-Item -ItemType Directory $OutDir -Force | Out-Null

# --- 1. export -------------------------------------------------------------
Write-Host '[1/3] exporting web build...' -ForegroundColor Cyan
$log = (& $Godot --headless --path $projectDir --export-release 'Web' $target 2>&1 | Out-String)
$code = $LASTEXITCODE
$log -split "`n" |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -match '^(ERROR|WARNING):' -and $_ -notmatch 'root certificate|editor_settings' } |
  ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
if ($code -ne 0) {
  Write-Host "[x] export failed (exit $code)" -ForegroundColor Red
  exit 1
}
Write-Host "      -> $target" -ForegroundColor DarkGray

# --- 2. make sure the server is up -----------------------------------------
Write-Host '[2/3] checking local server...' -ForegroundColor Cyan
$url = "http://localhost:$Port/"
$up = $false
try { Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 3 | Out-Null; $up = $true } catch { $up = $false }

if ($up) {
  Write-Host '      already running, reusing' -ForegroundColor DarkGray
} else {
  Start-Process powershell -WindowStyle Minimized -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$PSScriptRoot\serve.ps1`"",
    '-Port', $Port, '-Root', "`"$OutDir`""
  )
  for ($i = 0; $i -lt 25 -and -not $up; $i++) {
    Start-Sleep -Milliseconds 300
    try { Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2 | Out-Null; $up = $true } catch {}
  }
  if (-not $up) {
    Write-Host '[x] server failed to start (port in use? try -Port 8100)' -ForegroundColor Red
    exit 1
  }
  Write-Host '      started (minimized window; close it to stop the server)' -ForegroundColor DarkGray
}

# --- 3. open browser -------------------------------------------------------
Write-Host "[3/3] opening $url" -ForegroundColor Cyan
Start-Process $url
