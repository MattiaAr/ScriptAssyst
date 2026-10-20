[CmdletBinding()]
param(
    [ValidateSet('status','dashboard','users','groups','ous','createOU','updateOU','deleteOU','ouContents','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','userDetails','updateUserGroups','createUser','updateUser','copyUser','availableGroups','groupMembers','searchDirectoryMembers','updateGroupMembers','createGroup','updateGroup','groupDeletePreview','deleteGroup')]
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
    [string[]]$Members = @(),
    [bool]$ProtectedFromAccidentalDeletion = $true
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
    if ($properties.ContainsKey('groups')) {
        $groupsSpecified = $true
        $Groups = if ($null -eq $properties['groups']) { @() } else { @($properties['groups'] | ForEach-Object { [string]$_ }) }
    }
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
    if ($properties.ContainsKey('protectedFromAccidentalDeletion') -and $null -ne $properties['protectedFromAccidentalDeletion']) { $ProtectedFromAccidentalDeletion = [bool]$properties['protectedFromAccidentalDeletion'] }
    if ($properties.ContainsKey('password')) { $properties['password'] = $null }
    $properties.Clear()
    $json = $null
    $request = $null
    $json = $null
    $request = $null
}
$configPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'DashboardAD.config.json'
$selectedDC = $null
$config = $null
$credential = $null
$groupsSpecified = $false
$script:DashboardADMutationOperations = @(
    'createOU','updateOU','deleteOU','disableUser','enableUser','moveUser','resetPassword',
    'updateUserGroups','createUser','updateUser','copyUser','updateGroupMembers',
    'createGroup','updateGroup','deleteGroup'
)
function Write-DashboardADLog {
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Target = '',
        [bool]$Success = $true,
        [string]$ErrorMessage = '',
        [string]$Controller = '',
        [string]$AdminAccount = '',
        [string]$EventType = 'ad_operation'
    )
    try {
        $logPath = if (-not [string]::IsNullOrWhiteSpace($env:DASHBOARDAD_SESSION_LOG_PATH)) {
            $env:DASHBOARDAD_SESSION_LOG_PATH
        } else {
            [Environment]::ExpandEnvironmentVariables([string]$config.Logging.Path)
        }
        if ([string]::IsNullOrWhiteSpace($logPath)) { return }
        $directory = Split-Path -Parent $logPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $maxMb = 2
        if ($null -ne $config.Logging.MaxLogSizeMB -and [int]$config.Logging.MaxLogSizeMB -gt 0) { $maxMb = [int]$config.Logging.MaxLogSizeMB }
        $maxBytes = [long]$maxMb * 1MB
        $line = [ordered]@{
            timestamp = [DateTimeOffset]::UtcNow.ToString('o')
            eventType = $EventType
            sessionId = $(if (-not [string]::IsNullOrWhiteSpace($env:DASHBOARDAD_SESSION_ID)) { $env:DASHBOARDAD_SESSION_ID } else { $null })
            operator = $(if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { [string]$env:USERNAME })
            adminAccount = $AdminAccount
            sourceComputer = [string]$env:COMPUTERNAME
            domainController = $Controller
            action = $Action
            target = $Target
            success = $Success
            error = $(if ($Success -or [string]::IsNullOrWhiteSpace($ErrorMessage)) { $null } else { $ErrorMessage })
            ticket = $null
        } | ConvertTo-Json -Compress -Depth 5
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($line + [Environment]::NewLine)
        # Il file dedicato alla sessione non si ruota: start, operazioni e chiusura devono restare nello stesso file.
        if ([string]::IsNullOrWhiteSpace($env:DASHBOARDAD_SESSION_LOG_PATH) -and (Test-Path -LiteralPath $logPath -PathType Leaf) -and ((Get-Item -LiteralPath $logPath).Length + $bytes -gt $maxBytes)) {
            $parent = Split-Path -Parent $logPath
            $stem = [IO.Path]::GetFileNameWithoutExtension($logPath)
            $ext = [IO.Path]::GetExtension($logPath)
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
            $rotated = Join-Path $parent "$stem-$stamp$ext"
            $suffix = 1
            while (Test-Path -LiteralPath $rotated) {
                $rotated = Join-Path $parent "$stem-$stamp-$suffix$ext"
                $suffix++
            }
            Move-Item -LiteralPath $logPath -Destination $rotated
        }
        [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}
function Test-DashboardADTcpPort {
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
    if (-not (Test-Path -LiteralPath $config.ActiveDirectory.AdminCredentialPath -PathType Leaf)) { throw "File credenziali non trovato: $($config.ActiveDirectory.AdminCredentialPath). Esegui Setup\Credential-Setup.ps1." }
    $credential = Import-Clixml -LiteralPath $config.ActiveDirectory.AdminCredentialPath -ErrorAction Stop
    if ($credential -isnot [System.Management.Automation.PSCredential]) { throw 'Il file credenziali non contiene un oggetto PSCredential valido.' }
    $expectedUser = [string]$config.ActiveDirectory.ExpectedAdminUsername
    if (-not [string]::IsNullOrWhiteSpace($expectedUser) -and $credential.UserName -ne $expectedUser) { throw "L'account nel file credenziali ($($credential.UserName)) non corrisponde a ExpectedAdminUsername ($expectedUser)." }
    # Prova prima il nome DNS (preferibile per Kerberos); usa l'IP opzionale solo se il nome non risponde.
    $dcCandidates = @(
        [pscustomobject]@{ Name = [string]$config.ActiveDirectory.PrimaryDC; IP = [string]$config.ActiveDirectory.PrimaryDCIP },
        [pscustomobject]@{ Name = [string]$config.ActiveDirectory.SecondaryDC; IP = [string]$config.ActiveDirectory.SecondaryDCIP }
    )
    foreach ($dc in $dcCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($dc.Name) -and (Test-DashboardADTcpPort -Server $dc.Name -Port 9389)) {
            $selectedDC = $dc.Name
            break
        }
        if (-not [string]::IsNullOrWhiteSpace($dc.IP) -and (Test-DashboardADTcpPort -Server $dc.IP -Port 9389)) {
            $selectedDC = $dc.IP
            break
        }
    }
    if (-not $selectedDC) {
        $candidates = @($dcCandidates | ForEach-Object { @($_.Name, $_.IP) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        throw "Nessun controller configurato risponde sulla porta AD Web Services (9389): $($candidates -join ', ')."
    }
    $global:DashboardADConfig = $config
    $global:DashboardADSelectedDC = $selectedDC
    $global:PSDefaultParameterValues['*-AD*:Server'] = $selectedDC
    $global:PSDefaultParameterValues['*-AD*:Credential'] = $credential
    Import-Module (Join-Path $PSScriptRoot 'DashboardAD.psm1') -Force
    $result = Invoke-DashboardADRequest -Operation $Operation -Query $Query -Identity $Identity -DestinationOU $DestinationOU -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon -Groups $Groups -GroupsSpecified $groupsSpecified -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Path $Path -GroupName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Members $Members -ProtectedFromAccidentalDeletion $ProtectedFromAccidentalDeletion
    if ($Operation -in $script:DashboardADMutationOperations) {
        $target = switch ($Operation) {
            { $_ -in @('createOU','createGroup') } { if ($GroupName) { $GroupName } else { $Path }; break }
            { $_ -in @('updateOU','deleteOU','disableUser','enableUser','moveUser','resetPassword','updateUser','updateUserGroups','updateGroup','updateGroupMembers') } { $Identity; break }
            { $_ -in @('createUser','copyUser') } { if ($Identity) { $Identity } elseif ($UserPrincipalName) { $UserPrincipalName } else { $DisplayName }; break }
            default { if ($GroupName) { $GroupName } else { $Identity } }
        }
        $safeError = [string]$result.error
        if ($Password) { $safeError = $safeError.Replace($Password, '[REDACTED]') }
        Write-DashboardADLog -Action $Operation -Target $target -Success ([bool]$result.success) -ErrorMessage $safeError -Controller $selectedDC -AdminAccount $credential.UserName
    }
    $result | ConvertTo-Json -Depth 8 -Compress
} catch {
    if ($Operation -in $script:DashboardADMutationOperations) {
        $target = if ($Identity) { $Identity } elseif ($GroupName) { $GroupName } elseif ($UserPrincipalName) { $UserPrincipalName } else { $DisplayName }
        $safeError = [string]$_.Exception.Message
        if ($Password) { $safeError = $safeError.Replace($Password, '[REDACTED]') }
        Write-DashboardADLog -Action $Operation -Target $target -Success $false -ErrorMessage $safeError -Controller ([string]$selectedDC) -AdminAccount $(if ($credential) { $credential.UserName } else { '' })
    }
    [pscustomobject]@{ success=$false; operation=$Operation; query=$Query; data=$null; error=$_.Exception.Message } | ConvertTo-Json -Depth 8 -Compress
} finally {
    $Password = $null
    if ($credential) { $credential = $null }
}
