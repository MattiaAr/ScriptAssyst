[CmdletBinding()]
param([ValidateSet('status','dashboard')][string]$Operation='status')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ScriptAssyst.psm1') -Force
Invoke-ScriptAssystRequest -Operation $Operation | ConvertTo-Json -Depth 5 -Compress
