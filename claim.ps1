$resumePath = $args[0]
$resume = Get-Content -LiteralPath $resumePath -Raw | ConvertFrom-Json
if (-not $resume.ports -or $null -eq $resume.ports.nextFree) { Write-Output 'NO-LEDGER'; exit 1 }
Start-Sleep -Seconds 3  # WINDOW-WIDENER (not in production code) - forces the read/incr/write interleave
$Port = [int]$resume.ports.nextFree
$resume.ports.nextFree = $Port + 1
$resume | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resumePath -Encoding utf8
Write-Output "CLAIMED=$Port"
