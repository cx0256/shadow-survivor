# Run this script yourself when you want a visible game window.
# Validation during office work uses the separate headless QA command.
$ErrorActionPreference = 'Stop'
$makerEntry = Join-Path $env:USERPROFILE '.taptap-maker\mcp-runtime\0.0.37\dist\maker.js'
$codexNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
if (-not (Test-Path -LiteralPath $makerEntry)) { throw 'Maker 0.0.37 runtime is missing. Install Maker MCP first.' }
if (Test-Path -LiteralPath $codexNode) { $gameNode = $codexNode }
else { $gameNode = (Get-Command node -ErrorAction Stop).Source }
$statusText = & $gameNode $makerEntry preview status --target-dir $PSScriptRoot --json
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the local preview.' }
$status = $statusText | ConvertFrom-Json
if ($status.process_alive) {
    Write-Host 'The game is already running. Close its window before starting another session.'
    exit 0
}
& $gameNode $makerEntry preview start --target-dir $PSScriptRoot --json
exit $LASTEXITCODE
