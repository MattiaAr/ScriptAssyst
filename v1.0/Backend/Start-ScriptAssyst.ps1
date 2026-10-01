[CmdletBinding()]
param(
    [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks')]
    [string]$Operation = 'status',
    [ValidateLength(0,128)]
    [string]$Query = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ScriptAssyst.psm1') -Force
Invoke-ScriptAssystRequest -Operation $Operation -Query $Query | ConvertTo-Json -Depth 8 -Compress