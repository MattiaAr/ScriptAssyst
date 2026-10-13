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
    @(Get-ADUser -Filter $filter -Properties Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut,Description,GivenName,Surname,DisplayName,UserPrincipalName -ErrorAction Stop |
        Sort-Object Name |
        Select-Object Name,SamAccountName,Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut)
}

function Get-ScriptAssystGroups {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $escaped = $Query.Replace("'", "''")
    $filter = if ([string]::IsNullOrWhiteSpace($Query)) { '*' } else { "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*' -or Description -like '*$escaped*'" }
    $domainSid = (Get-ADDomain -ErrorAction Stop).DomainSID.Value
    $defaultDomainRids = @(512,513,514,515,516,517,518,519,520,521,522,526,527,553)
    $groups = Get-ADGroup -Filter $filter -Properties GroupCategory,GroupScope,Description,DistinguishedName,Member,SID -ErrorAction Stop |
        Sort-Object Name |
        Select-Object Name,SamAccountName,GroupCategory,GroupScope,Description,DistinguishedName,
            @{Name = 'MemberCount'; Expression = { @($_.Member).Count }},
            @{Name = 'ScriptAssystGroupType'; Expression = {
                $dn = [string]$_.DistinguishedName
                $sid = [string]$_.SID.Value
                $rid = 0
                if ($sid -match '-(\d+)$') { $rid = [int]$Matches[1] }
                if ($dn -match '(?i)^CN=[^,]+,CN=Builtin,') { 'Predefinito' }
                elseif ($sid.StartsWith($domainSid + '-') -and $defaultDomainRids -contains $rid) { 'Predefinito' }
                else { 'Personalizzato' }
            }}
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

function Invoke-ScriptAssystRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','userDetails','createUser','updateUser','copyUser','createGroup','deleteGroup','updateGroup','groupMembers','updateGroupMembers','ouContents')]
        [string]$Operation,
        [ValidateLength(0,128)][string]$Query = '',
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
        [string[]]$Members = @()
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
            'userDetails' { Get-ScriptAssystUserDetails -Identity $Identity }
            'createUser' { New-ScriptAssystUser -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -Identity $Identity -UserPrincipalName $UserPrincipalName -Path $Path -Password $Password -Department $Department -Title $Title -Email $Email -Description $Description -Groups $Groups }
            'updateUser' { Set-ScriptAssystUser -Identity $Identity -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Groups $Groups }
            'copyUser' { Copy-ScriptAssystUser -Identity $Identity -NewSamAccountName $GroupName -NewUserPrincipalName $UserPrincipalName -NewPath $Path -Password $Password -CopyGroups $Groups -CopyDescription ([bool]$ChangePasswordAtLogon) }
            'createGroup' { New-ScriptAssystGroup -GroupName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Path $Path -Description $Description }
            'deleteGroup' { Remove-ScriptAssystGroup -Identity $Identity }
            'updateGroup' { Set-ScriptAssystGroup -Identity $Identity -GroupName $GroupName -Description $Description -GroupCategory $GroupCategory -GroupScope $GroupScope }
            'groupMembers' { Get-ScriptAssystGroupMembers -Identity $Identity }
            'updateGroupMembers' { Set-ScriptAssystGroupMembers -Identity $Identity -Members $Members }
            'ouContents' { Get-ScriptAssystOuContents -Identity $Identity }
        }
        [pscustomobject]@{ success=$true; operation=$Operation; data=$data; error=$null }
    } catch {
        [pscustomobject]@{ success=$false; operation=$Operation; data=$null; error=$_.Exception.Message }
    } finally {
        if ($Password) { $Password = $null }
    }
}



function Get-ScriptAssystUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $user = Get-ADUser -Identity $Identity -Properties * -ErrorAction Stop
    $groups = @(Get-ADPrincipalGroupMembership -Identity $user.DistinguishedName -ErrorAction Stop | Select-Object Name,SamAccountName,DistinguishedName,GroupCategory,GroupScope)
    [pscustomobject]@{
        user = [pscustomobject]@{
            Name=$user.Name; SamAccountName=$user.SamAccountName; GivenName=$user.GivenName; Surname=$user.Surname
            DisplayName=$user.DisplayName; UserPrincipalName=$user.UserPrincipalName; Department=$user.Department
            Title=$user.Title; Mail=$user.Mail; Description=$user.Description; Enabled=$user.Enabled
            DistinguishedName=$user.DistinguishedName; Created=$user.Created; Modified=$user.Modified
            LastLogonDate=$user.LastLogonDate; PasswordLastSet=$user.PasswordLastSet
            BadPwdCount=$user.BadPwdCount; LastBadPasswordAttempt=$user.LastBadPasswordAttempt
            LockedOut=$user.LockedOut; WhenCreated=$user.WhenCreated; WhenChanged=$user.WhenChanged
        }
        groups=$groups
    }
}

function New-ScriptAssystUser {
    [CmdletBinding()]
    param([string]$GivenName,[string]$Surname,[string]$DisplayName,[string]$Identity,[string]$UserPrincipalName,[string]$Path,[string]$Password,[string]$Department,[string]$Title,[string]$Email,[string]$Description,[string[]]$Groups=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'Il nome account (sAMAccountName) è obbligatorio.' }
    if ($Identity.Length -gt 20) { throw 'Il nome account sAMAccountName non può superare 20 caratteri.' }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Selezionare la OU di destinazione.' }
    if ([string]::IsNullOrEmpty($Password)) { throw 'La password iniziale è obbligatoria.' }
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = (@($GivenName,$Surname | Where-Object { $_ }) -join ' ').Trim() }
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $Identity }
    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        $domain = Get-ADDomain -ErrorAction Stop
        $UserPrincipalName = "$Identity@$($domain.DNSRoot)"
    }
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    $args = @{Name=$DisplayName;SamAccountName=$Identity;UserPrincipalName=$UserPrincipalName;Path=$Path;AccountPassword=$secure;Enabled=$true;ErrorAction='Stop'}
    if ($GivenName) {$args.GivenName=$GivenName}; if ($Surname) {$args.Surname=$Surname}
    if ($Department) {$args.Department=$Department}; if ($Title) {$args.Title=$Title}
    if ($Description) {$args.Description=$Description}
    New-ADUser @args
    $created = Get-ADUser -Identity $Identity -ErrorAction Stop
    foreach ($group in @($Groups | Where-Object { $_ })) { Add-ADGroupMember -Identity $group -Members $created -ErrorAction Stop }
    if ($Email) { Set-ADUser -Identity $created -EmailAddress $Email -ErrorAction Stop }
    [pscustomobject]@{message="Utente $Identity creato."; user=(Get-ADUser -Identity $Identity -Properties Mail,Description,Department,Title,Enabled,DistinguishedName -ErrorAction Stop | Select-Object Name,SamAccountName,Mail,Description,Department,Title,Enabled,DistinguishedName)}
}

function Set-ScriptAssystUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string]$GivenName,[string]$Surname,[string]$DisplayName,[string]$UserPrincipalName,[string]$Department,[string]$Title,[string]$Email,[string]$Description,[string[]]$Groups=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    $user=Get-ADUser -Identity $Identity -ErrorAction Stop
    $params=@{Identity=$user.DistinguishedName;ErrorAction='Stop'}
    if ($PSBoundParameters.ContainsKey('GivenName')) {$params.GivenName=$GivenName}
    if ($PSBoundParameters.ContainsKey('Surname')) {$params.Surname=$Surname}
    if ($PSBoundParameters.ContainsKey('DisplayName')) {$params.DisplayName=$DisplayName}
    if ($PSBoundParameters.ContainsKey('UserPrincipalName') -and $UserPrincipalName) {$params.UserPrincipalName=$UserPrincipalName}
    if ($PSBoundParameters.ContainsKey('Department')) {$params.Department=$Department}
    if ($PSBoundParameters.ContainsKey('Title')) {$params.Title=$Title}
    if ($PSBoundParameters.ContainsKey('Description')) {$params.Description=$Description}
    Set-ADUser @params
    if ($PSBoundParameters.ContainsKey('Email')) { Set-ADUser -Identity $user.DistinguishedName -EmailAddress $Email -ErrorAction Stop }
    if ($Groups.Count -gt 0) {
        $current=@(Get-ADPrincipalGroupMembership -Identity $user.DistinguishedName | ForEach-Object DistinguishedName)
        $target=@($Groups | Where-Object { $_ })
        foreach($dn in $current) { if($target -notcontains $dn) { try { Remove-ADGroupMember -Identity $dn -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop } catch {} } }
        foreach($dn in $target) { if($current -notcontains $dn) { Add-ADGroupMember -Identity $dn -Members $user.DistinguishedName -ErrorAction Stop } }
    }
    [pscustomobject]@{message="Utente $($user.SamAccountName) aggiornato."; user=(Get-ADUser -Identity $user.SamAccountName -Properties Mail,Description,Department,Title,Enabled,DistinguishedName -ErrorAction Stop | Select-Object Name,SamAccountName,Mail,Description,Department,Title,Enabled,DistinguishedName)}
}

function Copy-ScriptAssystUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string]$NewSamAccountName,[string]$NewUserPrincipalName,[string]$NewPath,[string]$Password,[string[]]$CopyGroups=@(),[bool]$CopyDescription=$true)
    Import-Module ActiveDirectory -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($NewSamAccountName)){throw 'Specificare il nuovo nome account.'}
    if([string]::IsNullOrWhiteSpace($NewPath)){throw 'Selezionare la OU di destinazione.'}
    if([string]::IsNullOrEmpty($Password)){throw 'Specificare la password iniziale del nuovo account.'}
    $source=Get-ADUser -Identity $Identity -Properties * -ErrorAction Stop
    if(-not $NewUserPrincipalName){$domain=Get-ADDomain; $NewUserPrincipalName="$NewSamAccountName@$($domain.DNSRoot)"}
    $display=$source.DisplayName
    $secure=ConvertTo-SecureString $Password -AsPlainText -Force
    $params=@{Name=$display;SamAccountName=$NewSamAccountName;UserPrincipalName=$NewUserPrincipalName;Path=$NewPath;AccountPassword=$secure;Enabled=$true;ErrorAction='Stop'}
    if($source.GivenName){$params.GivenName=$source.GivenName};if($source.Surname){$params.Surname=$source.Surname}
    if($source.Department){$params.Department=$source.Department};if($source.Title){$params.Title=$source.Title}
    if($CopyDescription -and $source.Description){$params.Description=$source.Description}
    New-ADUser @params
    $new=Get-ADUser -Identity $NewSamAccountName -ErrorAction Stop
    $groupsToCopy=@($CopyGroups | Where-Object { $_ })
    if($groupsToCopy.Count -eq 0) {
        $groupsToCopy=@(Get-ADPrincipalGroupMembership -Identity $source.DistinguishedName -ErrorAction Stop |
            Where-Object { $_.SID.Value -notmatch '-513
}

function New-ScriptAssystGroup {
    [CmdletBinding()]
    param([string]$GroupName,[string]$GroupCategory='Security',[string]$GroupScope='Global',[string]$Path,[string]$Description)
    Import-Module ActiveDirectory -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($GroupName)){throw 'Il nome del gruppo è obbligatorio.'}
    if([string]::IsNullOrWhiteSpace($Path)){throw 'Specificare la OU o il container di destinazione.'}
    New-ADGroup -Name $GroupName -SamAccountName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Path $Path -Description $Description -ErrorAction Stop
    [pscustomobject]@{message="Gruppo $GroupName creato."}
}
function Remove-ScriptAssystGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties SID -ErrorAction Stop
    $sid=[string]$group.SID.Value
    $dn=[string]$group.DistinguishedName
    if($dn -match '(?i)^CN=[^,]+,CN=Builtin,' -or $sid -match '-(512|513|514|515|516|517|518|519|520|521|522|526|527|553)
}
function Set-ScriptAssystGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string]$GroupName,[string]$Description,[string]$GroupCategory,[string]$GroupScope)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Description -ErrorAction Stop
    if($GroupName -and $GroupName -ne $group.Name){Rename-ADObject -Identity $group.DistinguishedName -NewName $GroupName -ErrorAction Stop}
    $setParams=@{Identity=$group.ObjectGUID;Description=$Description;ErrorAction='Stop'}
    if($GroupCategory -in @('Security','Distribution')){$setParams.GroupCategory=$GroupCategory}
    if($GroupScope -in @('Global','Universal','DomainLocal')){$setParams.GroupScope=$GroupScope}
    Set-ADGroup @setParams
    [pscustomobject]@{message="Gruppo aggiornato."}
}
function Get-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Member -ErrorAction Stop
    $members=@(Get-ADGroupMember -Identity $group.DistinguishedName -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{Name=$_.Name;SamAccountName=$_.SamAccountName;DistinguishedName=$_.DistinguishedName;ObjectClass=$_.ObjectClass}
    })
    [pscustomobject]@{group=$group.Name;members=$members}
}
function Set-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Members=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -ErrorAction Stop
    $current=@(Get-ADGroupMember -Identity $group.DistinguishedName | ForEach-Object DistinguishedName)
    $target=@($Members | Where-Object { $_ })
    foreach($dn in $current){if($target -notcontains $dn){Remove-ADGroupMember -Identity $group.DistinguishedName -Members $dn -Confirm:$false -ErrorAction Stop}}
    foreach($dn in $target){if($current -notcontains $dn){Add-ADGroupMember -Identity $group.DistinguishedName -Members $dn -ErrorAction Stop}}
    [pscustomobject]@{message="Membri del gruppo $($group.Name) aggiornati."}
}
function Get-ScriptAssystOuContents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $ou=Get-ADOrganizationalUnit -Identity $Identity -ErrorAction Stop
    $objects=@(Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter * -Properties ObjectClass,Description,DistinguishedName -ErrorAction Stop | Select-Object Name,ObjectClass,Description,DistinguishedName)
    [pscustomobject]@{ou=$ou.DistinguishedName;objects=$objects}
}

Export-ModuleMember -Function Get-ScriptAssystStatus, Invoke-ScriptAssystRequest
 } |
            ForEach-Object { $_.DistinguishedName })
    }
    foreach($group in $groupsToCopy){Add-ADGroupMember -Identity $group -Members $new -ErrorAction Stop}
    [pscustomobject]@{message="Creato $NewSamAccountName a partire da $($source.SamAccountName)."; user=(Get-ADUser -Identity $NewSamAccountName -Properties Description,Department,Title,Enabled,DistinguishedName -ErrorAction Stop | Select-Object Name,SamAccountName,Description,Department,Title,Enabled,DistinguishedName)}
}

function New-ScriptAssystGroup {
    [CmdletBinding()]
    param([string]$GroupName,[string]$GroupCategory='Security',[string]$GroupScope='Global',[string]$Path,[string]$Description)
    Import-Module ActiveDirectory -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($GroupName)){throw 'Il nome del gruppo è obbligatorio.'}
    if([string]::IsNullOrWhiteSpace($Path)){throw 'Specificare la OU o il container di destinazione.'}
    New-ADGroup -Name $GroupName -SamAccountName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Path $Path -Description $Description -ErrorAction Stop
    [pscustomobject]@{message="Gruppo $GroupName creato."}
}
function Remove-ScriptAssystGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -ErrorAction Stop
    Remove-ADGroup -Identity $group.DistinguishedName -Confirm:$false -ErrorAction Stop
    [pscustomobject]@{message="Gruppo $($group.Name) eliminato."}
}
function Set-ScriptAssystGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string]$GroupName,[string]$Description,[string]$GroupCategory,[string]$GroupScope)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Description -ErrorAction Stop
    if($GroupName -and $GroupName -ne $group.Name){Rename-ADObject -Identity $group.DistinguishedName -NewName $GroupName -ErrorAction Stop}
    $setParams=@{Identity=$group.ObjectGUID;Description=$Description;ErrorAction='Stop'}
    if($GroupCategory -in @('Security','Distribution')){$setParams.GroupCategory=$GroupCategory}
    if($GroupScope -in @('Global','Universal','DomainLocal')){$setParams.GroupScope=$GroupScope}
    Set-ADGroup @setParams
    [pscustomobject]@{message="Gruppo aggiornato."}
}
function Get-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Member -ErrorAction Stop
    $members=@(Get-ADGroupMember -Identity $group.DistinguishedName -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{Name=$_.Name;SamAccountName=$_.SamAccountName;DistinguishedName=$_.DistinguishedName;ObjectClass=$_.ObjectClass}
    })
    [pscustomobject]@{group=$group.Name;members=$members}
}
function Set-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Members=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -ErrorAction Stop
    $current=@(Get-ADGroupMember -Identity $group.DistinguishedName | ForEach-Object DistinguishedName)
    $target=@($Members | Where-Object { $_ })
    foreach($dn in $current){if($target -notcontains $dn){Remove-ADGroupMember -Identity $group.DistinguishedName -Members $dn -Confirm:$false -ErrorAction Stop}}
    foreach($dn in $target){if($current -notcontains $dn){Add-ADGroupMember -Identity $group.DistinguishedName -Members $dn -ErrorAction Stop}}
    [pscustomobject]@{message="Membri del gruppo $($group.Name) aggiornati."}
}
function Get-ScriptAssystOuContents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $ou=Get-ADOrganizationalUnit -Identity $Identity -ErrorAction Stop
    $objects=@(Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter * -Properties ObjectClass,Description,DistinguishedName -ErrorAction Stop | Select-Object Name,ObjectClass,Description,DistinguishedName)
    [pscustomobject]@{ou=$ou.DistinguishedName;objects=$objects}
}

Export-ModuleMember -Function Get-ScriptAssystStatus, Invoke-ScriptAssystRequest
) {
        throw 'Per sicurezza non è consentito eliminare un gruppo Builtin o un gruppo predefinito del dominio.'
    }
    Remove-ADGroup -Identity $group.DistinguishedName -Confirm:$false -ErrorAction Stop
    [pscustomobject]@{message="Gruppo $($group.Name) eliminato."}
}
function Set-ScriptAssystGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string]$GroupName,[string]$Description,[string]$GroupCategory,[string]$GroupScope)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Description -ErrorAction Stop
    if($GroupName -and $GroupName -ne $group.Name){Rename-ADObject -Identity $group.DistinguishedName -NewName $GroupName -ErrorAction Stop}
    $setParams=@{Identity=$group.ObjectGUID;Description=$Description;ErrorAction='Stop'}
    if($GroupCategory -in @('Security','Distribution')){$setParams.GroupCategory=$GroupCategory}
    if($GroupScope -in @('Global','Universal','DomainLocal')){$setParams.GroupScope=$GroupScope}
    Set-ADGroup @setParams
    [pscustomobject]@{message="Gruppo aggiornato."}
}
function Get-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Member -ErrorAction Stop
    $members=@(Get-ADGroupMember -Identity $group.DistinguishedName -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{Name=$_.Name;SamAccountName=$_.SamAccountName;DistinguishedName=$_.DistinguishedName;ObjectClass=$_.ObjectClass}
    })
    [pscustomobject]@{group=$group.Name;members=$members}
}
function Set-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Members=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -ErrorAction Stop
    $current=@(Get-ADGroupMember -Identity $group.DistinguishedName | ForEach-Object DistinguishedName)
    $target=@($Members | Where-Object { $_ })
    foreach($dn in $current){if($target -notcontains $dn){Remove-ADGroupMember -Identity $group.DistinguishedName -Members $dn -Confirm:$false -ErrorAction Stop}}
    foreach($dn in $target){if($current -notcontains $dn){Add-ADGroupMember -Identity $group.DistinguishedName -Members $dn -ErrorAction Stop}}
    [pscustomobject]@{message="Membri del gruppo $($group.Name) aggiornati."}
}
function Get-ScriptAssystOuContents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $ou=Get-ADOrganizationalUnit -Identity $Identity -ErrorAction Stop
    $objects=@(Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter * -Properties ObjectClass,Description,DistinguishedName -ErrorAction Stop | Select-Object Name,ObjectClass,Description,DistinguishedName)
    [pscustomobject]@{ou=$ou.DistinguishedName;objects=$objects}
}

Export-ModuleMember -Function Get-ScriptAssystStatus, Invoke-ScriptAssystRequest
 } |
            ForEach-Object { $_.DistinguishedName })
    }
    foreach($group in $groupsToCopy){Add-ADGroupMember -Identity $group -Members $new -ErrorAction Stop}
    [pscustomobject]@{message="Creato $NewSamAccountName a partire da $($source.SamAccountName)."; user=(Get-ADUser -Identity $NewSamAccountName -Properties Description,Department,Title,Enabled,DistinguishedName -ErrorAction Stop | Select-Object Name,SamAccountName,Description,Department,Title,Enabled,DistinguishedName)}
}

function New-ScriptAssystGroup {
    [CmdletBinding()]
    param([string]$GroupName,[string]$GroupCategory='Security',[string]$GroupScope='Global',[string]$Path,[string]$Description)
    Import-Module ActiveDirectory -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($GroupName)){throw 'Il nome del gruppo è obbligatorio.'}
    if([string]::IsNullOrWhiteSpace($Path)){throw 'Specificare la OU o il container di destinazione.'}
    New-ADGroup -Name $GroupName -SamAccountName $GroupName -GroupCategory $GroupCategory -GroupScope $GroupScope -Path $Path -Description $Description -ErrorAction Stop
    [pscustomobject]@{message="Gruppo $GroupName creato."}
}
function Remove-ScriptAssystGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -ErrorAction Stop
    Remove-ADGroup -Identity $group.DistinguishedName -Confirm:$false -ErrorAction Stop
    [pscustomobject]@{message="Gruppo $($group.Name) eliminato."}
}
function Set-ScriptAssystGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string]$GroupName,[string]$Description,[string]$GroupCategory,[string]$GroupScope)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Description -ErrorAction Stop
    if($GroupName -and $GroupName -ne $group.Name){Rename-ADObject -Identity $group.DistinguishedName -NewName $GroupName -ErrorAction Stop}
    $setParams=@{Identity=$group.ObjectGUID;Description=$Description;ErrorAction='Stop'}
    if($GroupCategory -in @('Security','Distribution')){$setParams.GroupCategory=$GroupCategory}
    if($GroupScope -in @('Global','Universal','DomainLocal')){$setParams.GroupScope=$GroupScope}
    Set-ADGroup @setParams
    [pscustomobject]@{message="Gruppo aggiornato."}
}
function Get-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Member -ErrorAction Stop
    $members=@(Get-ADGroupMember -Identity $group.DistinguishedName -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{Name=$_.Name;SamAccountName=$_.SamAccountName;DistinguishedName=$_.DistinguishedName;ObjectClass=$_.ObjectClass}
    })
    [pscustomobject]@{group=$group.Name;members=$members}
}
function Set-ScriptAssystGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Members=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -ErrorAction Stop
    $current=@(Get-ADGroupMember -Identity $group.DistinguishedName | ForEach-Object DistinguishedName)
    $target=@($Members | Where-Object { $_ })
    foreach($dn in $current){if($target -notcontains $dn){Remove-ADGroupMember -Identity $group.DistinguishedName -Members $dn -Confirm:$false -ErrorAction Stop}}
    foreach($dn in $target){if($current -notcontains $dn){Add-ADGroupMember -Identity $group.DistinguishedName -Members $dn -ErrorAction Stop}}
    [pscustomobject]@{message="Membri del gruppo $($group.Name) aggiornati."}
}
function Get-ScriptAssystOuContents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $ou=Get-ADOrganizationalUnit -Identity $Identity -ErrorAction Stop
    $objects=@(Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter * -Properties ObjectClass,Description,DistinguishedName -ErrorAction Stop | Select-Object Name,ObjectClass,Description,DistinguishedName)
    [pscustomobject]@{ou=$ou.DistinguishedName;objects=$objects}
}

Export-ModuleMember -Function Get-ScriptAssystStatus, Invoke-ScriptAssystRequest
