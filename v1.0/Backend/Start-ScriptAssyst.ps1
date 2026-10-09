[CmdletBinding()]
param(
    [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks','disableUser','enableUser','moveUser','resetPassword')]
    [string]$Operation = 'status',
    [ValidateLength(0,128)]
    [string]$Query = '',
    [string]$Identity = '',
    [string]$DestinationOU = '',
    [string]$Password = '',
    [bool]$ChangePasswordAtLogon = $false,
    [switch]$ReadRequestFromStdin
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($ReadRequestFromStdin) {
    $json = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($json)) { throw 'Richiesta JSON mancante sullo standard input.' }
    $request = $json | ConvertFrom-Json -ErrorAction Stop
    $Operation = [string]$request.operation
    if ($null -ne $request.query) { $Query = [string]$request.query }
    if ($null -ne $request.identity) { $Identity = [string]$request.identity }
    if ($null -ne $request.destinationOU) { $DestinationOU = [string]$request.destinationOU }
    if ($null -ne $request.password) { $Password = [string]$request.password }
    if ($null -ne $request.changePasswordAtLogon) { $ChangePasswordAtLogon = [bool]$request.changePasswordAtLogon }
}
Import-Module (Join-Path $PSScriptRoot 'ScriptAssyst.psm1') -Force
try {
    Invoke-ScriptAssystRequest -Operation $Operation -Query $Query -Identity $Identity -DestinationOU $DestinationOU -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon | ConvertTo-Json -Depth 8 -Compress
} finally {
    $Password = $null
}
