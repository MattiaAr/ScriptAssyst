[CmdletBinding()]
param(
    [ValidateSet('status','dashboard','users','groups','ous','createOU','updateOU','deleteOU','ouContents','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','deleteUser','userDetails','updateUserGroups','createUser','availableGroups','groupMembers','searchDirectoryMembers','updateGroupMembers','createGroup','updateGroup','groupDeletePreview','deleteGroup')]
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
$configPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'ScriptAssyst.config.json'
$selectedDC = $null
$config = $null
$credential = $null
function Write-ScriptAssystLog {
    param([string]$Message)
    try {
        $logPath = [string]$config.Logging.Path
        if ([string]::IsNullOrWhiteSpace($logPath)) { return }
        $directory = Split-Path -Parent $logPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        Add-Content -LiteralPath $logPath -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }
}
function Test-ScriptAssystTcpPort {
    param([Parameter(Mandatory)][string]$Server,[int]$Port=9389,[int]$TimeoutMilliseconds=1500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($Server,$Port,$null,$null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds,$false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false }
    finally { $client.Close() }
}
try {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "File di configurazione mancante: $configPath" }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$config.ActiveDirectory.PrimaryDC)) { throw 'PrimaryDC non configurato.' }
    if ([string]::IsNullOrWhiteSpace([string]$config.ActiveDirectory.UPNSuffix)) { throw 'UPNSuffix non configurato.' }
    if ([string]::IsNullOrWhiteSpace([string]$config.ActiveDirectory.AdminCredentialPath)) { throw 'AdminCredentialPath non configurato.' }
    if (-not (Test-Path -LiteralPath $config.ActiveDirectory.AdminCredentialPath -PathType Leaf)) { throw "File credenziali non trovato: $($config.ActiveDirectory.AdminCredentialPath). Esegui Initialize-ScriptAssystCredentials.ps1." }
    $credential = Import-Clixml -LiteralPath $config.ActiveDirectory.AdminCredentialPath -ErrorAction Stop
    if ($credential -isnot [System.Management.Automation.PSCredential]) { throw 'Il file credenziali non contiene un oggetto PSCredential valido.' }
    $expectedUser = [string]$config.ActiveDirectory.ExpectedAdminUsername
    if (-not [string]::IsNullOrWhiteSpace($expectedUser) -and $credential.UserName -ne $expectedUser) { throw "L'account nel file credenziali ($($credential.UserName)) non corrisponde a ExpectedAdminUsername ($expectedUser)." }
    $candidates = @([string]$config.ActiveDirectory.PrimaryDC)
    if (-not [string]::IsNullOrWhiteSpace([string]$config.ActiveDirectory.SecondaryDC)) { $candidates += [string]$config.ActiveDirectory.SecondaryDC }
    foreach ($candidate in $candidates) {
        if (Test-ScriptAssystTcpPort -Server $candidate -Port 9389) { $selectedDC = $candidate; break }
    }
    if (-not $selectedDC) { throw "Nessun controller configurato risponde sulla porta AD Web Services (9389): $($candidates -join ', ')." }
    $global:ScriptAssystConfig = $config
    $global:ScriptAssystSelectedDC = $selectedDC
    $global:PSDefaultParameterValues['*-AD*:Server'] = $selectedDC
    $global:PSDefaultParameterValues['*-AD*:Credential'] = $credential
    Write-ScriptAssystLog "INFO operation=$Operation dc=$selectedDC account=$($credential.UserName)"
    Import-Module (Join-Path $PSScriptRoot 'ScriptAssyst.psm1') -Force
    $result = Invoke-ScriptAssystRequest -Operation $Operation -Query $Query -Identity $Identity -DestinationOU $DestinationOU -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon -Groups $Groups -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Path $Path -GroupName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Members $Members
    Write-ScriptAssystLog ("{0} operation={1} dc={2}{3}" -f $(if ($result.success) {'INFO'} else {'ERROR'}), $Operation, $selectedDC, $(if ($result.error) {" error=$($result.error)"} else {''}))
    $result | ConvertTo-Json -Depth 8 -Compress
} catch {
    Write-ScriptAssystLog "ERROR operation=$Operation error=$($_.Exception.Message)"
    [pscustomobject]@{ success=$false; operation=$Operation; query=$Query; data=$null; error=$_.Exception.Message } | ConvertTo-Json -Depth 8 -Compress
} finally {
    $Password = $null
    if ($credential) { $credential = $null }
}
