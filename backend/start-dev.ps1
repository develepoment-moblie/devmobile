$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
. "$PSScriptRoot/node-runtime.ps1"
$env:JWT_PUBLIC_KEY = '.dev/public.pem'
$env:JWT_ISSUER = 'nova-local-dev'
$env:JWT_AUDIENCE = 'nova-housekeeping'
$env:CORS_ORIGINS = 'http://127.0.0.1:8085,http://localhost:8085'
& $script:NodeRuntime server.mjs
