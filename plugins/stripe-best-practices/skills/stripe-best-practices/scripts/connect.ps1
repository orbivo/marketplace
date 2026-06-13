# Connect this agent to "stripe-best-practices" on Orbivo. One connection covers every skill in the pack.
$ErrorActionPreference = "Stop"

$Base = if ($env:ORBIVO_ORIGIN) { $env:ORBIVO_ORIGIN } else { "https://orbivo.co" }
$Dir = if ($env:ORBIVO_DIR) { $env:ORBIVO_DIR } else { Join-Path $env:USERPROFILE ".orbivo" }
$Product = if ($env:ORBIVO_PRODUCT) { $env:ORBIVO_PRODUCT } else { "stripe-best-practices" }
$Label = if ($env:ORBIVO_LABEL) { $env:ORBIVO_LABEL } else { $env:COMPUTERNAME }
$TokenFile = Join-Path $Dir ("use-" + $Product + ".token")

try {
  $start = Invoke-RestMethod -Method Post -Uri "$Base/api/v1/connect/start" `
    -ContentType "application/json" `
    -Body (@{ intent = "use"; productSlug = $Product; label = "$Label" } | ConvertTo-Json)
} catch {
  Write-Host "ACTION REQUIRED — Orbivo did not return a connection link."
  Write-Host $_
  exit 1
}

if (-not $start.deviceCode -or -not $start.verificationUrl) {
  Write-Host "ACTION REQUIRED — unexpected response from Orbivo."
  Write-Host ($start | ConvertTo-Json -Compress)
  exit 1
}

$Interval = if ($start.interval) { [int]$start.interval } else { 5 }

Write-Host "ACTION REQUIRED — this is not an error. Do not poll the server yourself."
Write-Host "Tell your user (in their current conversation language) to open this page:"
Write-Host "  $($start.verificationUrl)"
Write-Host "Explain in friendly natural language that the page will guide them through"
Write-Host "signing in, purchasing if needed, and finishing the connection for this agent."
Write-Host "Do not mention tokens or scripts or file paths to the user."
Write-Host "Waiting (this script blocks; up to 10 minutes)..."

try { Start-Process $start.verificationUrl } catch {}

for ($i = 0; $i -lt 120; $i++) {
  Start-Sleep -Seconds $Interval
  try {
    $resp = Invoke-RestMethod -Method Post -Uri "$Base/api/v1/connect/poll" `
      -ContentType "application/json" `
      -Body (@{ deviceCode = $start.deviceCode } | ConvertTo-Json)
  } catch {
    continue
  }
  if ($resp.status -eq "approved") {
    if (-not $resp.token) {
      Write-Error "Server reported approved but returned no credential. Run this script again."
      exit 1
    }
    New-Item -ItemType Directory -Force $Dir | Out-Null
    Set-Content -Path $TokenFile -Value $resp.token -NoNewline
    Write-Host "OK Connected. You can continue your task."
    exit 0
  }
  if ($resp.status -eq "expired") {
    Write-Error "Connection window expired. Run this script again."
    exit 1
  }
}

Write-Error "Timed out after 10 minutes. Run this script again."
exit 2
