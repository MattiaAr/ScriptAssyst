$script:ScriptAssystAvailableGroupsCache = $null
$script:ScriptAssystAvailableGroupsCacheAt = [datetime]::MinValue

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
    $escaped=$Query.Replace("'","''")
    $filter=if([string]::IsNullOrWhiteSpace($Query)){'*'}else{"Name -like '*$escaped*' -or SamAccountName -like '*$escaped*' -or Description -like '*$escaped*'"}
    $all=@(Get-ADGroup -Filter $filter -Properties GroupCategory,GroupScope,Description,DistinguishedName,Member,SID -ErrorAction Stop)
    @(foreach($g in $all | Sort-Object Name){$type=if(Test-ScriptAssystDefaultGroup $g){'Predefinito'}else{'Personalizzato'};[pscustomobject]@{Name=$g.Name;SamAccountName=$g.SamAccountName;GroupCategory=$g.GroupCategory;GroupScope=$g.GroupScope;Description=$g.Description;DistinguishedName=$g.DistinguishedName;MemberCount=@($g.Member).Count;ScriptAssystGroupType=$type}})
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

function Test-ScriptAssystDefaultGroup {
    param([Parameter(Mandatory)]$Group)
    $sid=[string]$Group.SID.Value
    $builtin=[string]$Group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,'
    $rid=if($sid -match '-(\d+)$'){[int]$Matches[1]}else{-1}
    return ($builtin -or (@(498,499,500,501,502,512,513,514,515,516,517,518,519,520,521,522,525,526,527,553,571,572) -contains $rid))
}
function Search-ScriptAssystDirectoryMembers {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Query) -or $Query.Trim().Length -lt 2) { return @() }
    $escaped=$Query.Trim().Replace("'","''")
    $users=@(Get-ADUser -Filter "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*'" -Properties DistinguishedName,SamAccountName -ResultSetSize 20 -ErrorAction Stop | Select-Object Name,SamAccountName,DistinguishedName,@{Name='ObjectClass';Expression={'user'}})
    $groups=@(Get-ADGroup -Filter "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*'" -Properties DistinguishedName,SamAccountName -ResultSetSize 20 -ErrorAction Stop | Select-Object Name,SamAccountName,DistinguishedName,@{Name='ObjectClass';Expression={'group'}})
    @($users + $groups | Sort-Object Name | Select-Object -First 30)
}

function Get-ScriptAssystGroupMembers {
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $g=Get-ADGroup -Identity $Identity -Properties Name,DistinguishedName -ErrorAction Stop
    $members=@(Get-ADGroupMember -Identity $g.DistinguishedName -Recursive:$false -ErrorAction Stop | Sort-Object Name | Select-Object Name,SamAccountName,DistinguishedName,ObjectClass)
    [pscustomobject]@{group=$g.DistinguishedName;name=$g.Name;members=$members}
}
function Update-ScriptAssystGroupMembers {
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Members=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    $g=Get-ADGroup -Identity $Identity -Properties SID -ErrorAction Stop
    if(Test-ScriptAssystDefaultGroup $g){throw 'I membri dei gruppi predefiniti non possono essere modificati da questa schermata.'}
    $current=@(Get-ADGroupMember -Identity $g.DistinguishedName -Recursive:$false -ErrorAction Stop);$desired=@{}
    foreach($entry in @($Members)){
        if([string]::IsNullOrWhiteSpace([string]$entry)){continue}
        $obj=$null
        try{$obj=Get-ADObject -Identity ([string]$entry) -Properties Name,DistinguishedName,ObjectClass -ErrorAction Stop}catch{$escaped=([string]$entry).Replace("'","''");$obj=Get-ADObject -Filter "Name -eq '$escaped' -or SamAccountName -eq '$escaped'" -Properties Name,DistinguishedName,ObjectClass -ErrorAction Stop | Select-Object -First 1}
        if(-not $obj){throw "Membro non trovato: '$entry'."};$desired[$obj.DistinguishedName.ToLowerInvariant()]=$obj
    }
    $added=[System.Collections.Generic.List[string]]::new();$removed=[System.Collections.Generic.List[string]]::new()
    foreach($m in $current){if(-not $desired.ContainsKey($m.DistinguishedName.ToLowerInvariant())){Remove-ADGroupMember -Identity $g.DistinguishedName -Members $m.DistinguishedName -Confirm:$false -ErrorAction Stop;$removed.Add($m.Name)}}
    foreach($key in $desired.Keys){if(-not ($current | Where-Object {$_.DistinguishedName -ieq $desired[$key].DistinguishedName})){Add-ADGroupMember -Identity $g.DistinguishedName -Members $desired[$key].DistinguishedName -ErrorAction Stop;$added.Add($desired[$key].Name)}}
    [pscustomobject]@{message="Membri aggiornati per '$($g.Name)'. Aggiunti: $($added.Count); rimossi: $($removed.Count).";added=@($added);removed=@($removed)}
}
function New-ScriptAssystGroup {
    param([Parameter(Mandatory)][string]$GroupName,[Parameter(Mandatory)][string]$Path,[string]$Description='',[ValidateSet('Security','Distribution')][string]$GroupCategory='Security',[ValidateSet('Global','Universal','DomainLocal')][string]$GroupScope='Global')
    Import-Module ActiveDirectory -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($GroupName) -or $GroupName.Length -gt 256){throw 'Nome gruppo non valido.'}
    $ou=Get-ADOrganizationalUnit -Identity $Path -ErrorAction Stop;$escaped=$GroupName.Replace("'","''")
    if(Get-ADGroup -Filter "Name -eq '$escaped'" -ErrorAction Stop){throw "Esiste già un gruppo con nome '$GroupName'."}
    New-ADGroup -Name $GroupName -Path $ou.DistinguishedName -GroupCategory $GroupCategory -GroupScope $GroupScope -Description $Description -ErrorAction Stop
    [pscustomobject]@{message="Gruppo '$GroupName' creato nella OU '$($ou.Name)'."}
}
function Update-ScriptAssystGroup {
    param([Parameter(Mandatory)][string]$Identity,[Parameter(Mandatory)][string]$GroupName,[string]$Description='')
    Import-Module ActiveDirectory -ErrorAction Stop;$g=Get-ADGroup -Identity $Identity -Properties SID -ErrorAction Stop
    if(Test-ScriptAssystDefaultGroup $g){throw 'I gruppi predefiniti non possono essere modificati da questa schermata.'}
    Set-ADGroup -Identity $g.DistinguishedName -SamAccountName $GroupName -Description $Description -ErrorAction Stop
    Rename-ADObject -Identity $g.DistinguishedName -NewName $GroupName -ErrorAction Stop
    [pscustomobject]@{message="Gruppo aggiornato: '$GroupName'."}
}
function Remove-ScriptAssystGroup {
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop;$g=Get-ADGroup -Identity $Identity -Properties SID -ErrorAction Stop
    if(Test-ScriptAssystDefaultGroup $g){throw 'I gruppi predefiniti non possono essere eliminati.'}
    Remove-ADGroup -Identity $g.DistinguishedName -Confirm:$false -ErrorAction Stop
    [pscustomobject]@{message="Gruppo '$($g.Name)' eliminato."}
}

function Get-ScriptAssystAvailableGroups {
    [CmdletBinding()]
    param()
    Import-Module ActiveDirectory -ErrorAction Stop
    @(
        Get-ADGroup -Filter * -Properties Description,DistinguishedName,SID,GroupCategory,GroupScope -ErrorAction Stop |
        Where-Object {
            $sid = [string]$_.SID.Value
            $isBuiltinContainer = $_.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,'
            $isDefaultDomainObject = $sid -match '-(498|499|500|501|502|503|504|505|506|507|508|509|510|511|512|513|514|515|516|517|518|519|520|521|522|525|526|527|553|571|572)$'
            -not ($isBuiltinContainer -or $isDefaultDomainObject)
        } |
        Sort-Object Name |
        Select-Object Name,SamAccountName,Description,DistinguishedName,GroupCategory,GroupScope,
            @{Name='ScriptAssystGroupType';Expression={'Personalizzato'}}
    )
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
    $cacheValid = $null -ne $script:ScriptAssystAvailableGroupsCache -and ((Get-Date) - $script:ScriptAssystAvailableGroupsCacheAt).TotalSeconds -lt 60
    if ($cacheValid) {
        $availableGroups = @($script:ScriptAssystAvailableGroupsCache)
    } else {
        $availableGroups = @(
            Get-ADGroup -Filter * -Properties Description,DistinguishedName,SID,GroupCategory,GroupScope -ErrorAction Stop |
            Where-Object {
                $sid = [string]$_.SID.Value
                $isBuiltinContainer = $_.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,'
                $isDefaultDomainObject = $sid -match '-(498|499|500|501|502|503|504|505|506|507|508|509|510|511|512|513|514|515|516|517|518|519|520|521|522|525|526|527|553|571|572)$'
                -not ($isBuiltinContainer -or $isDefaultDomainObject)
            } |
            Sort-Object Name |
            Select-Object Name,SamAccountName,Description,DistinguishedName,GroupCategory,GroupScope,
                @{Name='ScriptAssystGroupType';Expression={'Personalizzato'}}
        )
        $script:ScriptAssystAvailableGroupsCache = @($availableGroups)
        $script:ScriptAssystAvailableGroupsCacheAt = Get-Date
    }
    [pscustomobject]@{ user=$details; groups=$groups; availableGroups=$availableGroups }
}

function New-ScriptAssystUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$DestinationOU,
        [Parameter(Mandatory)][string]$Password,
        [string]$GivenName = '',
        [string]$Surname = '',
        [string]$DisplayName = '',
        [string]$UserPrincipalName = '',
        [string]$Department = '',
        [string]$Title = '',
        [string]$Email = '',
        [string]$Description = '',
        [string[]]$Groups = @(),
        [bool]$ChangePasswordAtLogon = $true
    )
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 128) { throw 'Nome account non valido.' }
    if ([string]::IsNullOrWhiteSpace($DestinationOU) -or $DestinationOU.Length -gt 1024) { throw 'Selezionare una OU valida.' }
    if ([string]::IsNullOrEmpty($Password)) { throw 'La password iniziale è obbligatoria.' }
    $ou = Get-ADOrganizationalUnit -Identity $DestinationOU -ErrorAction Stop
    $escapedIdentity = $Identity.Replace("'", "''")
    if (Get-ADUser -Filter "SamAccountName -eq '$escapedIdentity'" -ErrorAction Stop) { throw "Esiste già un account con nome '$Identity'." }
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $accountName = if ($DisplayName) { $DisplayName } else { (($GivenName + ' ' + $Surname).Trim()) }
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = $Identity }
    $params = @{
        Name = $accountName
        SamAccountName = $Identity
        Path = $ou.DistinguishedName
        AccountPassword = $securePassword
        Enabled = $true
        ChangePasswordAtLogon = $ChangePasswordAtLogon
        ErrorAction = 'Stop'
    }
    if ($GivenName) { $params.GivenName = $GivenName }
    if ($Surname) { $params.Surname = $Surname }
    if ($DisplayName) { $params.DisplayName = $DisplayName }
    if ($UserPrincipalName) { $params.UserPrincipalName = $UserPrincipalName }
    if ($Department) { $params.Department = $Department }
    if ($Title) { $params.Title = $Title }
    if ($Email) { $params.EmailAddress = $Email }
    if ($Description) { $params.Description = $Description }
    New-ADUser @params
    $created = Get-ADUser -Identity $Identity -Properties DistinguishedName,primaryGroupID -ErrorAction Stop
    $added = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Groups)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry)) { continue }
        $groupIdentity = [string]$entry
        try {
            $group = Get-ADGroup -Identity $groupIdentity -Properties SID,DistinguishedName -ErrorAction Stop
        } catch {
            $escapedGroup = $groupIdentity.Replace("'", "''")
            $group = Get-ADGroup -Filter "Name -eq '$escapedGroup' -or SamAccountName -eq '$escapedGroup'" -Properties SID,DistinguishedName -ErrorAction Stop | Select-Object -First 1
            if (-not $group) { throw "Gruppo non trovato: '$groupIdentity'." }
        }
        $primaryRid = [string]$created.primaryGroupID
        if ([string]$group.SID.Value.Split('-')[-1] -eq $primaryRid) { continue }
        $alreadyMember = Get-ADGroupMember -Identity $group.DistinguishedName -Recursive:$false -ErrorAction Stop |
            Where-Object { $_.DistinguishedName -eq $created.DistinguishedName }
        if ($alreadyMember) { continue }
        Add-ADGroupMember -Identity $group.DistinguishedName -Members $created.DistinguishedName -ErrorAction Stop
        $added.Add($group.Name)
    }
    [pscustomobject]@{ message = "Utente '$Identity' creato nella OU '$($ou.Name)'. Gruppi assegnati: $($added.Count)."; user = $created; groups = @($added) }
}

function Update-ScriptAssystUserGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Groups = @())
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 512) { throw 'Identità utente non valida.' }
    $user = Get-ADUser -Identity $Identity -Properties memberOf,primaryGroupID,DistinguishedName,SamAccountName -ErrorAction Stop
    $currentDns = @($user.memberOf | ForEach-Object { [string]$_ })
    $desired = @{}
    foreach ($entry in @($Groups)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry)) { continue }
        $group = Get-ADGroup -Identity ([string]$entry) -Properties SID,DistinguishedName -ErrorAction Stop
        $sidText = [string]$group.SID.Value
        $protected = $group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,' -or
            $sidText -match '-(498|499|500|501|502|503|504|505|506|507|508|509|510|511|512|513|514|515|516|517|518|519|520|521|522|525|526|527|553|571|572)$'
        if ($protected) { throw "Il gruppo di sistema '$($group.Name)' non può essere modificato da questa schermata." }
        $desired[$group.DistinguishedName.ToLowerInvariant()] = $group
    }
    $added = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($dn in $currentDns) {
        $group = Get-ADGroup -Identity $dn -Properties SID,DistinguishedName -ErrorAction Stop
        $sidText = [string]$group.SID.Value
        $protected = $group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,' -or
            $sidText -match '-(498|499|500|501|502|503|504|505|506|507|508|509|510|511|512|513|514|515|516|517|518|519|520|521|522|525|526|527|553|571|572)$'
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
        [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','userDetails','updateUserGroups','createUser','availableGroups','groupMembers','searchDirectoryMembers','updateGroupMembers','createGroup','updateGroup','deleteGroup')]
        [string]$Operation,
        [ValidateLength(0,128)][string]$Query = '',
        [string]$Identity = '',
        [string]$DestinationOU = '',
        [string]$Password = '',
        [bool]$ChangePasswordAtLogon = $false,
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
    try {
        $data = switch ($Operation) {
            'status' { Get-ScriptAssystStatus }
            'dashboard' { Get-ScriptAssystDashboard }
            'users' { Get-ScriptAssystUsers -Query $Query }
            'userDetails' { Get-ScriptAssystUserDetails -Identity $Identity }
            'availableGroups' { Get-ScriptAssystAvailableGroups }
            'createUser' { New-ScriptAssystUser -Identity $Identity -DestinationOU $Path -Password $Password -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Groups $Groups -ChangePasswordAtLogon $ChangePasswordAtLogon }
            'updateUserGroups' { Update-ScriptAssystUserGroups -Identity $Identity -Groups $Groups }
            'groupMembers' { Get-ScriptAssystGroupMembers -Identity $Identity }
            'searchDirectoryMembers' { Search-ScriptAssystDirectoryMembers -Query $Query }
            'updateGroupMembers' { Update-ScriptAssystGroupMembers -Identity $Identity -Members $Members }
            'createGroup' { New-ScriptAssystGroup -GroupName $GroupName -Path $Path -Description $Description -GroupCategory $GroupCategory -GroupScope $GroupScope }
            'updateGroup' { Update-ScriptAssystGroup -Identity $Identity -GroupName $GroupName -Description $Description }
            'deleteGroup' { Remove-ScriptAssystGroup -Identity $Identity }
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
