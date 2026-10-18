$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
. "$PSScriptRoot/node-runtime.ps1"
& $script:NodeRuntime --test test/api.test.mjs
exit $LASTEXITCODE
