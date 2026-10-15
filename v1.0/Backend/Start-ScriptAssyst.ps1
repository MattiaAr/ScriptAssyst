[CmdletBinding()]
param(
    [ValidateSet('status','dashboard','users','groups','ous','createOU','updateOU','deleteOU','ouContents','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','userDetails','updateUserGroups','createUser','availableGroups','groupMembers','searchDirectoryMembers','updateGroupMembers','createGroup','updateGroup','deleteGroup')]
    [string]$Operation = 'status',
    [ValidateLength(0,128)]
    [string]$Query = '',
    [string]$Identity = '',
    [string]$DestinationOU = '',
    [string]$Password = '',
    [bool]$ChangePasswordAtLogon = $false,
    [switch]$ReadRequestFromStdin,
    [string[]]$Groups = @(),
    [string]$GivenName = '',
    [string]$Surname = '',
    [string]$DisplayName = '',
    [string]$UserPrincipalName = '',
    [string]$Department = '',
    [string]$Title = '',
    [string]$Email = '',
    [string]$Description = '',
    [string]$Path = '',
    [string]$GroupName = '',
    [string]$GroupCategory = 'Security',
    [string]$GroupScope = 'Global',
    [string[]]$Members = @()
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
    if ($properties.ContainsKey('groups') -and $null -ne $properties['groups']) { $Groups = @($properties['groups'] | ForEach-Object { [string]$_ }) }
    if ($properties.ContainsKey('givenName') -and $null -ne $properties['givenName']) { $GivenName = [string]$properties['givenName'] }
    if ($properties.ContainsKey('surname') -and $null -ne $properties['surname']) { $Surname = [string]$properties['surname'] }
    if ($properties.ContainsKey('displayName') -and $null -ne $properties['displayName']) { $DisplayName = [string]$properties['displayName'] }
    if ($properties.ContainsKey('userPrincipalName') -and $null -ne $properties['userPrincipalName']) { $UserPrincipalName = [string]$properties['userPrincipalName'] }
    if ($properties.ContainsKey('department') -and $null -ne $properties['department']) { $Department = [string]$properties['department'] }
    if ($properties.ContainsKey('title') -and $null -ne $properties['title']) { $Title = [string]$properties['title'] }
    if ($properties.ContainsKey('email') -and $null -ne $properties['email']) { $Email = [string]$properties['email'] }
    if ($properties.ContainsKey('description') -and $null -ne $properties['description']) { $Description = [string]$properties['description'] }
    if ($properties.ContainsKey('path') -and $null -ne $properties['path']) { $Path = [string]$properties['path'] }
    if ($properties.ContainsKey('groupName') -and $null -ne $properties['groupName']) { $GroupName = [string]$properties['groupName'] }
    if ($properties.ContainsKey('groupCategory') -and $null -ne $properties['groupCategory']) { $GroupCategory = [string]$properties['groupCategory'] }
    if ($properties.ContainsKey('groupScope') -and $null -ne $properties['groupScope']) { $GroupScope = [string]$properties['groupScope'] }
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
    Invoke-ScriptAssystRequest -Operation $Operation -Query $Query -Identity $Identity -DestinationOU $DestinationOU -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon -Groups $Groups -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Path $Path -GroupName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Members $Members | ConvertTo-Json -Depth 8 -Compress
} finally {
    $Password = $null
}
