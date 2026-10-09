Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ScriptAssystStatus {
    [CmdletBinding()]
    param()
    $adModule = [bool](Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1)
    $gpModule = [bool](Get-Module -ListAvailable -Name GroupPolicy | Select-Object -First 1)
    $domain = $null
    $connected = $false
    $errorMessage = $null
    if ($adModule) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            $domain = Get-ADDomain -ErrorAction Stop
            $connected = $true
        } catch { $errorMessage = $_.Exception.Message }
    } else { $errorMessage = 'Modulo ActiveDirectory non disponibile. Installare RSAT o il componente AD PowerShell.' }
    [pscustomobject]@{
        application = 'ScriptAssyst'
        version = '1.0.0'
        mode = if ($connected) { 'active-directory' } else { 'offline' }
        adConnected = $connected
        domain = if ($domain) { $domain.DNSRoot } else { $null }
        domainController = if ($domain) { $domain.PDCEmulator } else { $null }
        activeDirectoryModule = $adModule
        groupPolicyModule = $gpModule
        operator = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        message = if ($connected) { 'Connessione ad Active Directory verificata.' } else { $errorMessage }
    }
}

function Get-ScriptAssystUsers {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $escaped = $Query.Replace("'", "''")
    $filter = if ([string]::IsNullOrWhiteSpace($Query)) { '*' } else { "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*' -or Department -like '*$escaped*'" }
    @(Get-ADUser -Filter $filter -Properties Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut -ErrorAction Stop |
        Sort-Object Name |
        Select-Object Name,SamAccountName,Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut)
}

function Get-ScriptAssystGroups {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $escaped = $Query.Replace("'", "''")
    $filter = if ([string]::IsNullOrWhiteSpace($Query)) { '*' } else { "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*' -or Description -like '*$escaped*'" }
    $groups = Get-ADGroup -Filter $filter -Properties GroupCategory,GroupScope,Description,DistinguishedName,Member -ErrorAction Stop |
        Sort-Object Name |
        Select-Object Name,SamAccountName,GroupCategory,GroupScope,Description,DistinguishedName,
            @{Name = 'MemberCount'; Expression = { @($_.Member).Count }}
    return @($groups)
}

function Get-ScriptAssystOUs {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $escaped = $Query.Replace("'", "''")
    $filter = if ([string]::IsNullOrWhiteSpace($Query)) { '*' } else { "Name -like '*$escaped*'" }
    @(Get-ADOrganizationalUnit -Filter $filter -Properties Description,DistinguishedName,ProtectedFromAccidentalDeletion -ErrorAction Stop |
        Sort-Object DistinguishedName |
        Select-Object Name,Description,DistinguishedName,ProtectedFromAccidentalDeletion)
}

function Get-ScriptAssystGpos {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module GroupPolicy -ErrorAction Stop
    $all = @(Get-GPO -All -ErrorAction Stop)
    if (-not [string]::IsNullOrWhiteSpace($Query)) { $all = @($all | Where-Object { $_.DisplayName -like "*$Query*" }) }
    @($all | Sort-Object DisplayName | Select-Object DisplayName,Id,GpoStatus,CreationTime,ModificationTime,Owner,Description)
}

function Get-ScriptAssystScheduledTasks {
    [CmdletBinding()]
    param([string]$Query = '')
    $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })
    if (-not [string]::IsNullOrWhiteSpace($Query)) { $tasks = @($tasks | Where-Object { $_.TaskName -like "*$Query*" -or $_.TaskPath -like "*$Query*" }) }
    @($tasks | Sort-Object TaskPath,TaskName | Select-Object TaskName,TaskPath,State,Author,Description)
}

function Get-ScriptAssystDashboard {
    [CmdletBinding()]
    param()
    $status = Get-ScriptAssystStatus
    if (-not $status.adConnected) { return [pscustomobject]@{ status=$status; metrics=$null; message='Metriche non disponibili: Active Directory non raggiungibile.' } }
    Import-Module ActiveDirectory -ErrorAction Stop
    $users = @(Get-ADUser -Filter * -ErrorAction Stop).Count
    $groups = @(Get-ADGroup -Filter * -ErrorAction Stop).Count
    $ous = @(Get-ADOrganizationalUnit -Filter * -ErrorAction Stop).Count
    $gpos = $null
    if ($status.groupPolicyModule) { Import-Module GroupPolicy -ErrorAction Stop; $gpos = @(Get-GPO -All -ErrorAction Stop).Count }
    [pscustomobject]@{ status=$status; metrics=[pscustomobject]@{ users=$users; groups=$groups; ous=$ous; gpos=$gpos } }
}

function Invoke-ScriptAssystUserAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('disableUser','enableUser','moveUser','resetPassword')][string]$Operation,
        [Parameter(Mandatory)][string]$Identity,
        [string]$DestinationOU = '',
        [string]$Password = '',
        [bool]$ChangePasswordAtLogon = $false
    )
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 512) { throw 'Identità utente non valida.' }
    $user = Get-ADUser -Identity $Identity -Properties Enabled,DistinguishedName,SamAccountName -ErrorAction Stop
    switch ($Operation) {
        'disableUser' {
            if (-not $user.Enabled) { throw 'L’account è già disabilitato.' }
            Disable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
            $message = "Account $($user.SamAccountName) disabilitato."
        }
        'enableUser' {
            if ($user.Enabled) { throw 'L’account è già abilitato.' }
            Enable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
            $message = "Account $($user.SamAccountName) abilitato."
        }
        'moveUser' {
            if ([string]::IsNullOrWhiteSpace($DestinationOU) -or $DestinationOU.Length -gt 1024) { throw 'Specificare il Distinguished Name della OU di destinazione.' }
            $ou = Get-ADOrganizationalUnit -Identity $DestinationOU -ErrorAction Stop
            if (($user.DistinguishedName -split ',',2)[1] -ieq $ou.DistinguishedName) { throw 'L’utente si trova già nella OU di destinazione.' }
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $ou.DistinguishedName -Confirm:$false -ErrorAction Stop
            $message = "Account $($user.SamAccountName) spostato in $($ou.DistinguishedName)."
        }
        'resetPassword' {
            if (-not $user.Enabled) { throw 'Per sicurezza, il reset password è consentito solo agli account abilitati.' }
            if ([string]::IsNullOrEmpty($Password)) { throw 'La nuova password è obbligatoria.' }
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword $securePassword -ErrorAction Stop
            if ($ChangePasswordAtLogon) { Set-ADUser -Identity $user.DistinguishedName -ChangePasswordAtLogon $true -ErrorAction Stop }
            $message = "Password reimpostata per $($user.SamAccountName)."
        }
    }
    $updated = Get-ADUser -Identity $user.SamAccountName -Properties Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut -ErrorAction Stop |
        Select-Object Name,SamAccountName,Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut
    [pscustomobject]@{ message=$message; user=$updated }
}

function Invoke-ScriptAssystRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks','disableUser','enableUser','moveUser','resetPassword')]
        [string]$Operation,
        [ValidateLength(0,128)][string]$Query = '',
        [string]$Identity = '',
        [string]$DestinationOU = '',
        [string]$Password = '',
        [bool]$ChangePasswordAtLogon = $false
    )
    try {
        $data = switch ($Operation) {
            'status' { Get-ScriptAssystStatus }
            'dashboard' { Get-ScriptAssystDashboard }
            'users' { Get-ScriptAssystUsers -Query $Query }
            'groups' { Get-ScriptAssystGroups -Query $Query }
            'ous' { Get-ScriptAssystOUs -Query $Query }
            'gpos' { Get-ScriptAssystGpos -Query $Query }
            'tasks' { Get-ScriptAssystScheduledTasks -Query $Query }
            'disableUser' { Invoke-ScriptAssystUserAction -Operation $Operation -Identity $Identity }
            'enableUser' { Invoke-ScriptAssystUserAction -Operation $Operation -Identity $Identity }
            'moveUser' { Invoke-ScriptAssystUserAction -Operation $Operation -Identity $Identity -DestinationOU $DestinationOU }
            'resetPassword' { Invoke-ScriptAssystUserAction -Operation $Operation -Identity $Identity -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon }
        }
        [pscustomobject]@{ success=$true; operation=$Operation; data=$data; error=$null }
    } catch {
        [pscustomobject]@{ success=$false; operation=$Operation; data=$null; error=$_.Exception.Message }
    } finally {
        if ($Password) { $Password = $null }
    }
}

Export-ModuleMember -Function Get-ScriptAssystStatus, Invoke-ScriptAssystRequest
