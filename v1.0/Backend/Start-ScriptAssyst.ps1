[CmdletBinding()]
param(
    [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','userDetails','createUser','updateUser','copyUser','createGroup','deleteGroup','updateGroup','groupMembers','updateGroupMembers','ouContents')]
    [string]$Operation = 'status',
    [ValidateLength(0,128)]
    [string]$Query = '',
    [string]$Identity = '',
    [string]$DestinationOU = '',
    [string]$Password = '',
    [bool]$ChangePasswordAtLogon = $false,
    [string]$GivenName = '',
    [string]$Surname = '',
    [string]$DisplayName = '',
    [string]$UserPrincipalName = '',
    [string]$Path = '',
    [string]$Department = '',
    [string]$Title = '',
    [string]$Email = '',
    [string]$Description = '',
    [string]$GroupName = '',
    [string]$GroupCategory = 'Security',
    [string]$GroupScope = 'Global',
    [string[]]$Groups = @(),
    [string[]]$Members = @(),
    [switch]$ReadRequestFromStdin
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($ReadRequestFromStdin) {
    $json = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($json)) { throw 'Richiesta JSON mancante sullo standard input.' }
    $request = $json | ConvertFrom-Json -ErrorAction Stop
    $properties = @{}
    foreach ($property in $request.PSObject.Properties) { $properties[$property.Name] = $property.Value }
    if ($properties.ContainsKey('operation') -and $properties['operation']) { $Operation = [string]$properties['operation'] }
    if ($properties.ContainsKey('query') -and $null -ne $properties['query']) { $Query = [string]$properties['query'] }
    if ($properties.ContainsKey('identity') -and $null -ne $properties['identity']) { $Identity = [string]$properties['identity'] }
    if ($properties.ContainsKey('destinationOU') -and $null -ne $properties['destinationOU']) { $DestinationOU = [string]$properties['destinationOU'] }
    if ($properties.ContainsKey('password') -and $null -ne $properties['password']) { $Password = [string]$properties['password'] }
    if ($properties.ContainsKey('changePasswordAtLogon') -and $null -ne $properties['changePasswordAtLogon']) { $ChangePasswordAtLogon = [bool]$properties['changePasswordAtLogon'] }
    foreach ($name in @('GivenName','Surname','DisplayName','UserPrincipalName','Path','Department','Title','Email','Description','GroupName','GroupCategory','GroupScope')) {
        $key = $name.Substring(0,1).ToLowerInvariant() + $name.Substring(1)
        if ($properties.ContainsKey($key) -and $null -ne $properties[$key]) { Set-Variable -Name $name -Value ([string]$properties[$key]) }
    }
    if ($properties.ContainsKey('groups') -and $null -ne $properties['groups']) { $Groups = @($properties['groups'] | ForEach-Object { [string]$_ }) }
    if ($properties.ContainsKey('members') -and $null -ne $properties['members']) { $Members = @($properties['members'] | ForEach-Object { [string]$_ }) }
    if ($properties.ContainsKey('password')) { $properties['password'] = $null }
    $properties.Clear()
    $json = $null
    $request = $null
    $json = $null
    $request = $null
}
Import-Module (Join-Path $PSScriptRoot 'ScriptAssyst.psm1') -Force
try {
    Invoke-ScriptAssystRequest -Operation $Operation -Query $Query -Identity $Identity -DestinationOU $DestinationOU -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Path $Path -Department $Department -Title $Title -Email $Email -Description $Description -GroupName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Groups $Groups -Members $Members | ConvertTo-Json -Depth 8 -Compress
} finally {
    $Password = $null
}
