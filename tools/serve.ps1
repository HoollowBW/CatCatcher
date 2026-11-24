# serve.ps1 - minimal static server for the Godot web build.
# Godot loads .wasm / .pck via fetch(), so opening CatCatcher.html from file:// never
# works. It has to be served over http.
# Usually started by dev.ps1; standalone:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\serve.ps1 [-Port 8099] [-Root D:\Bulid\CatCatcher]
# NOTE: ASCII-only on purpose (Windows PowerShell 5.1 + UTF-8 without BOM = broken script).
param(
  [int]$Port = 8099,
  [string]$Root = ''             # default: <project>/build/web
)

$root = $Root
if ([string]::IsNullOrEmpty($root)) { $root = Join-Path (Split-Path -Parent $PSScriptRoot) 'build\web' }
if (-not (Test-Path $root)) {
  Write-Host "export dir not found: $root  (run dev.ps1 first)"
  exit 1
}

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'text/javascript'
  '.wasm' = 'application/wasm'
  '.pck'  = 'application/octet-stream'
  '.png'  = 'image/png'
  '.svg'  = 'image/svg+xml'
  '.json' = 'application/json'
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "Serving $root"
Write-Host "Open http://localhost:$Port/"

while ($true) {
  $client = $listener.AcceptTcpClient()
  $client.ReceiveTimeout = 5000
  try {
    $stream = $client.GetStream()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrEmpty($requestLine)) { $client.Close(); continue }
    while ($true) {
      $line = $reader.ReadLine()
      if ([string]::IsNullOrEmpty($line)) { break }
    }

    $rel = ($requestLine -split ' ')[1]
    $rel = ($rel -split '\?')[0].TrimStart('/')
    if ($rel -eq '') { $rel = 'index.html' }
    $rel = [System.Uri]::UnescapeDataString($rel)
    $file = Join-Path $root $rel

    if (Test-Path $file -PathType Leaf) {
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      $type = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $head = "HTTP/1.1 200 OK`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
      $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($headBytes, 0, $headBytes.Length)
      $stream.Write($bytes, 0, $bytes.Length)
      Write-Host "200 $rel ($($bytes.Length))"
    } else {
      $body = [System.Text.Encoding]::UTF8.GetBytes("404 $rel")
      $head = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
      $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($headBytes, 0, $headBytes.Length)
      $stream.Write($body, 0, $body.Length)
      Write-Host "404 $rel"
    }
    $stream.Flush()
  } catch {
    Write-Host "ERR $($_.Exception.Message)"
  } finally {
    $client.Close()
  }
}
