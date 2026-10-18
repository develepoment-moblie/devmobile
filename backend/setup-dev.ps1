$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
. "$PSScriptRoot/node-runtime.ps1"
& $script:NodeRuntime dev-setup.mjs
