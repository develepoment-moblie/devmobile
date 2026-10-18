$ErrorActionPreference = 'Stop'
# Prefer an installed Node 24+. Codex's bundled runtime is a local fallback.
$script:NodeRuntime = (Get-Command node -ErrorAction SilentlyContinue).Source
if ($script:NodeRuntime) {
    $major = [int]((& $script:NodeRuntime --version).TrimStart('v').Split('.')[0])
    if ($major -lt 24) { $script:NodeRuntime = $null }
}
if (-not $script:NodeRuntime) {
    $bundled = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
    if (Test-Path -LiteralPath $bundled) { $script:NodeRuntime = $bundled }
}
if (-not $script:NodeRuntime) { throw 'Install Node.js 24 or newer, then retry.' }
