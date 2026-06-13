# Fetch a streamed file of the "stripe-best-practices" skill (pack "stripe-best-practices") from Orbivo.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run.ps1 <path>
$ErrorActionPreference = "Stop"

if ($args.Count -lt 1) { Write-Error "usage: run.ps1 <path>"; exit 1 }
$PathArg = $args[0]

$Base = if ($env:ORBIVO_ORIGIN) { $env:ORBIVO_ORIGIN } else { "https://orbivo.co" }
$Dir = if ($env:ORBIVO_DIR) { $env:ORBIVO_DIR } else { Join-Path $env:USERPROFILE ".orbivo" }
$Product = if ($env:ORBIVO_PRODUCT) { $env:ORBIVO_PRODUCT } else { "stripe-best-practices" }
$Skill = if ($env:ORBIVO_SKILL) { $env:ORBIVO_SKILL } else { "stripe-best-practices" }
$TokenFile = Join-Path $Dir ("use-" + $Product + ".token")
$ScriptDir = $PSScriptRoot

function Invoke-Fetch {
  $headers = @{}
  $ua = "orbivo-loader/1"
  if ($env:CLAUDECODE -or $env:CLAUDE_CODE_ENTRYPOINT) { $ua = "claude-code orbivo-loader/1" }
  elseif ($env:CODEX_SANDBOX -or $env:CODEX_HOME -or $env:CODEX_SANDBOX_NETWORK_DISABLED) { $ua = "codex orbivo-loader/1" }
  elseif ($env:CURSOR_TRACE_ID -or $env:CURSOR_AGENT) { $ua = "cursor orbivo-loader/1" }
  if (Test-Path $TokenFile) {
    $headers["Authorization"] = "Bearer " + (Get-Content $TokenFile -Raw).Trim()
  }
  if ($env:ORBIVO_PASSWORD) { $headers["X-Orbivo-Password"] = $env:ORBIVO_PASSWORD }
  try {
    $resp = Invoke-WebRequest -Method Get -Uri "$Base/api/v1/s/$Product/$Skill/$PathArg" `
      -Headers $headers -UserAgent $ua -UseBasicParsing
    return @{ Status = [int]$resp.StatusCode; Body = $resp.Content }
  } catch {
    if ($_.Exception.Response) {
      $code = [int]$_.Exception.Response.StatusCode
      $stream = $_.Exception.Response.GetResponseStream()
      $body = ""
      if ($stream) { $body = (New-Object System.IO.StreamReader($stream)).ReadToEnd() }
      return @{ Status = $code; Body = $body }
    }
    throw
  }
}

$result = Invoke-Fetch
if ($result.Status -in 401, 402, 403) {
  if (Test-Path $TokenFile) { Remove-Item $TokenFile -Force -ErrorAction SilentlyContinue }
  $env:ORBIVO_PRODUCT = $Product
  & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "connect.ps1")
  if ($LASTEXITCODE -ne 0) { exit 1 }
  $result = Invoke-Fetch
}

Write-Output $result.Body
if ($result.Status -ge 400) { exit 1 }
exit 0
