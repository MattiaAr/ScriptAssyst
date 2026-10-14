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
            Unlock-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
            $message = "Account $($user.SamAccountName) abilitato e sbloccato."
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

function Get-ScriptAssystUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 512) {
        throw 'Identità utente non valida.'
    }
    $user = Get-ADUser -Identity $Identity -Properties WhenCreated,WhenChanged,LastLogonDate,PasswordLastSet,BadPwdCount,LastBadPasswordAttempt,LockedOut,Mail,Description,DistinguishedName,SamAccountName,memberOf -ErrorAction Stop
    $details = $user | Select-Object Name,SamAccountName,WhenCreated,WhenChanged,LastLogonDate,PasswordLastSet,BadPwdCount,LastBadPasswordAttempt,LockedOut,Mail,Description,DistinguishedName
    $groups = @(
        foreach ($groupDn in @($user.memberOf)) {
            $group = Get-ADGroup -Identity $groupDn -Properties DistinguishedName -ErrorAction Stop
            [pscustomobject]@{ Name=$group.Name; DistinguishedName=$group.DistinguishedName }
        }
    )
    $availableGroups = @(
        Get-ADGroup -Filter * -Properties Description,DistinguishedName,SID,GroupCategory,GroupScope -ErrorAction Stop |
        Where-Object {
            $_.DistinguishedName -notmatch '(?i)^CN=[^,]+,CN=Builtin,' -and
            [string]$_.SID.Value -notmatch '-(500|501|502|512|513|514|515|516|517|518|519|520|521|522|525|526|527|544|545|546|547|548|549|550|551|552|553|554|555|556|557|558|559|560|561|562|568|569|571|572)$'
        } |
        Sort-Object Name |
        Select-Object Name,SamAccountName,Description,DistinguishedName,GroupCategory,GroupScope,
            @{Name='ScriptAssystGroupType';Expression={'Personalizzato'}}
    )
    [pscustomobject]@{ user=$details; groups=$groups; availableGroups=$availableGroups }
}

function Update-ScriptAssystUserGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identity,
        [string[]]$Groups = @()
    )
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 512) {
        throw 'Identità utente non valida.'
    }
    $user = Get-ADUser -Identity $Identity -Properties memberOf,primaryGroupID,DistinguishedName,SamAccountName -ErrorAction Stop
    $currentDns = @($user.memberOf | ForEach-Object { [string]$_ })
    $desired = @{}
    foreach ($entry in @($Groups)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry)) { continue }
        $group = Get-ADGroup -Identity ([string]$entry) -Properties SID,DistinguishedName -ErrorAction Stop
        $sidText = [string]$group.SID.Value
        $protected = $group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,' -or
            $sidText -match '-(500|501|502|512|513|514|515|516|517|518|519|520|521|522|525|526|527|544|545|546|547|548|549|550|551|552|553|554|555|556|557|558|559|560|561|562|568|569|571|572)$'
        if ($protected) { throw "Il gruppo di sistema '$($group.Name)' non può essere modificato da questa schermata." }
        $desired[$group.DistinguishedName.ToLowerInvariant()] = $group
    }
    $added = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($dn in $currentDns) {
        $group = Get-ADGroup -Identity $dn -Properties SID,DistinguishedName -ErrorAction Stop
        $sidText = [string]$group.SID.Value
        $protected = $group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,' -or
            $sidText -match '-(500|501|502|512|513|514|515|516|517|518|519|520|521|522|525|526|527|544|545|546|547|548|549|550|551|552|553|554|555|556|557|558|559|560|561|562|568|569|571|572)$'
        if ($protected -or $desired.ContainsKey($dn.ToLowerInvariant())) { continue }
        Remove-ADGroupMember -Identity $group.DistinguishedName -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop
        $removed.Add($group.Name)
    }
    foreach ($key in @($desired.Keys)) {
        $group = $desired[$key]
        if ($currentDns -notcontains $group.DistinguishedName) {
            Add-ADGroupMember -Identity $group.DistinguishedName -Members $user.DistinguishedName -ErrorAction Stop
            $added.Add($group.Name)
        }
    }
    [pscustomobject]@{
        message = "Appartenenze aggiornate per $($user.SamAccountName). Aggiunti: $($added.Count); rimossi: $($removed.Count)."
        added = @($added)
        removed = @($removed)
    }
}

function Invoke-ScriptAssystRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','userDetails','updateUserGroups')]
        [string]$Operation,
        [ValidateLength(0,128)][string]$Query = '',
        [string]$Identity = '',
        [string]$DestinationOU = '',
        [string]$Password = '',
        [bool]$ChangePasswordAtLogon = $false,
        [string[]]$Groups = @()
    )
    try {
        $data = switch ($Operation) {
            'status' { Get-ScriptAssystStatus }
            'dashboard' { Get-ScriptAssystDashboard }
            'users' { Get-ScriptAssystUsers -Query $Query }
            'userDetails' { Get-ScriptAssystUserDetails -Identity $Identity }
            'updateUserGroups' { Update-ScriptAssystUserGroups -Identity $Identity -Groups $Groups }
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
