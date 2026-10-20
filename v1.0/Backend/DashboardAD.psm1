$script:DashboardADAvailableGroupsCache = $null
$script:DashboardADAvailableGroupsCacheAt = [datetime]::MinValue

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DashboardADStatus {
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
        application = 'DashboardAD'
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

function Get-DashboardADUsers {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $escaped = $Query.Replace("'", "''")
    $filter = if ([string]::IsNullOrWhiteSpace($Query)) { '*' } else { "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*' -or Description -like '*$escaped*'" }
    @(Get-ADUser -Filter $filter -Properties GivenName,Surname,DisplayName,UserPrincipalName,Description,Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut -ErrorAction Stop |
        Sort-Object Name |
        Select-Object Name,SamAccountName,GivenName,Surname,DisplayName,UserPrincipalName,Description,Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut)
}

function Get-DashboardADGroups {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $escaped=$Query.Replace("'","''")
    $filter=if([string]::IsNullOrWhiteSpace($Query)){'*'}else{"Name -like '*$escaped*' -or SamAccountName -like '*$escaped*' -or Description -like '*$escaped*'"}
    $all=@(Get-ADGroup -Filter $filter -Properties GroupCategory,GroupScope,Description,DistinguishedName,Member,SID -ErrorAction Stop)
    @(foreach($g in $all | Sort-Object Name){$type=if(Test-DashboardADDefaultGroup $g){'Predefinito'}else{'Personalizzato'};[pscustomobject]@{Name=$g.Name;SamAccountName=$g.SamAccountName;GroupCategory=$g.GroupCategory;GroupScope=$g.GroupScope;Description=$g.Description;DistinguishedName=$g.DistinguishedName;MemberCount=@($g.Member).Count;DashboardADGroupType=$type}})
}

function Get-DashboardADOUContents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 1024) {
        throw 'Identità OU non valida.'
    }
    $ou = Get-ADOrganizationalUnit -Identity $Identity -Properties DistinguishedName -ErrorAction Stop
    $objects = @(
        Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -LDAPFilter '(objectClass=*)' -Properties Description,DistinguishedName,ObjectClass -ErrorAction Stop |
        Select-Object Name,DistinguishedName,Description,@{Name='ObjectClass';Expression={ if ($_.ObjectClass -contains 'organizationalUnit') { 'organizationalUnit' } elseif ($_.ObjectClass -contains 'group') { 'group' } elseif ($_.ObjectClass -contains 'user') { 'user' } else { [string]($_.ObjectClass | Select-Object -Last 1) } }}
    )
    [pscustomobject]@{ ou=$ou.DistinguishedName; objects=$objects }
}

function Get-DashboardADOUs {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $escaped = $Query.Replace("'", "''")
    $filter = if ([string]::IsNullOrWhiteSpace($Query)) { '*' } else { "Name -like '*$escaped*'" }
    @(Get-ADOrganizationalUnit -Filter $filter -Properties Description,DistinguishedName,ProtectedFromAccidentalDeletion -ErrorAction Stop |
        Sort-Object DistinguishedName |
        Select-Object Name,Description,DistinguishedName,ProtectedFromAccidentalDeletion)
}

function New-DashboardADOU {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,[string]$Path='',[string]$Description='',[bool]$ProtectedFromAccidentalDeletion=$true)
    Import-Module ActiveDirectory -ErrorAction Stop
    $nameValue=$Name.Trim()
    if ([string]::IsNullOrWhiteSpace($nameValue) -or $nameValue.Length -gt 64 -or $nameValue -match '[,+"\\<>;=]') { throw 'Nome OU non valido (massimo 64 caratteri; evitare , + " \ < > ; =).' }
    if ([string]::IsNullOrWhiteSpace($Path)) { $parent=(Get-ADDomain -ErrorAction Stop).DistinguishedName }
    else { $parent=(Get-ADOrganizationalUnit -Identity $Path -ErrorAction Stop).DistinguishedName }
    $escaped=$nameValue.Replace("'","''")
    if (Get-ADOrganizationalUnit -SearchBase $parent -SearchScope OneLevel -Filter "Name -eq '$escaped'" -ErrorAction Stop) { throw "Esiste già una OU chiamata '$nameValue' in questa posizione." }
    $created=New-ADOrganizationalUnit -Name $nameValue -Path $parent -Description $Description -ProtectedFromAccidentalDeletion:$ProtectedFromAccidentalDeletion -PassThru -ErrorAction Stop
    [pscustomobject]@{message="OU '$nameValue' creata con protezione dall'eliminazione accidentale $([string]$ProtectedFromAccidentalDeletion.ToString().ToLowerInvariant()).";ou=$created.DistinguishedName;protectedFromAccidentalDeletion=$ProtectedFromAccidentalDeletion}
}
function Update-DashboardADOU {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[Parameter(Mandatory)][string]$Name,[string]$Description='')
    Import-Module ActiveDirectory -ErrorAction Stop
    $ou=Get-ADOrganizationalUnit -Identity $Identity -Properties Description,ProtectedFromAccidentalDeletion -ErrorAction Stop
    $nameValue=$Name.Trim()
    if ([string]::IsNullOrWhiteSpace($nameValue) -or $nameValue.Length -gt 64 -or $nameValue -match '[,+"\\<>;=]') { throw 'Nome OU non valido (massimo 64 caratteri; evitare , + " \ < > ; =).' }
    $parentDn=($ou.DistinguishedName -split ',',2)[1]
    $escaped=$nameValue.Replace("'","''")
    $siblings=@(Get-ADOrganizationalUnit -SearchBase $parentDn -SearchScope OneLevel -Filter "Name -eq '$escaped'" -ErrorAction Stop | Where-Object { $_.DistinguishedName -ine $ou.DistinguishedName })
    if ($siblings.Count) { throw "Esiste già una OU chiamata '$nameValue' nella stessa posizione." }
    Set-ADOrganizationalUnit -Identity $ou.DistinguishedName -Description $Description -ErrorAction Stop
    if ($ou.Name -cne $nameValue) { Rename-ADObject -Identity $ou.DistinguishedName -NewName $nameValue -ErrorAction Stop }
    $updatedDn=if($ou.Name -cne $nameValue){"OU=$nameValue,$parentDn"}else{$ou.DistinguishedName}
    $updated=Get-ADOrganizationalUnit -Identity $updatedDn -ErrorAction Stop
    [pscustomobject]@{message="OU '$nameValue' aggiornata.";ou=$updated.DistinguishedName}
}
function Remove-DashboardADOU {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $ou=Get-ADOrganizationalUnit -Identity $Identity -Properties ProtectedFromAccidentalDeletion -ErrorAction Stop
    if ($ou.ProtectedFromAccidentalDeletion) { throw "La OU '$($ou.Name)' è protetta dall'eliminazione. Disattiva prima la protezione in Active Directory." }
    $children=@(Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -LDAPFilter '(objectClass=*)' -ErrorAction Stop)
    if ($children.Count) { throw "La OU '$($ou.Name)' non è vuota. Sposta o elimina prima gli oggetti e le sotto-OU contenuti." }
    Remove-ADOrganizationalUnit -Identity $ou.DistinguishedName -Confirm:$false -ErrorAction Stop
    [pscustomobject]@{message="OU '$($ou.Name)' eliminata."}
}

function Get-DashboardADGpos {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module GroupPolicy -ErrorAction Stop
    $all = @(Get-GPO -All -ErrorAction Stop)
    if (-not [string]::IsNullOrWhiteSpace($Query)) { $all = @($all | Where-Object { $_.DisplayName -like "*$Query*" }) }
    @($all | Sort-Object DisplayName | Select-Object DisplayName,Id,GpoStatus,CreationTime,ModificationTime,Owner,Description)
}

function Get-DashboardADScheduledTasks {
    [CmdletBinding()]
    param([string]$Query = '')
    $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })
    if (-not [string]::IsNullOrWhiteSpace($Query)) { $tasks = @($tasks | Where-Object { $_.TaskName -like "*$Query*" -or $_.TaskPath -like "*$Query*" }) }
    @($tasks | Sort-Object TaskPath,TaskName | Select-Object TaskName,TaskPath,State,Author,Description)
}

function Get-DashboardADDashboard {
    [CmdletBinding()]
    param()
    $status = Get-DashboardADStatus
    if (-not $status.adConnected) { return [pscustomobject]@{ status=$status; metrics=$null; message='Metriche non disponibili: Active Directory non raggiungibile.' } }
    Import-Module ActiveDirectory -ErrorAction Stop
    $users = @(Get-ADUser -Filter * -ErrorAction Stop).Count
    $groups = @(Get-ADGroup -Filter * -ErrorAction Stop).Count
    $ous = @(Get-ADOrganizationalUnit -Filter * -ErrorAction Stop).Count
    $gpos = $null
    if ($status.groupPolicyModule) { Import-Module GroupPolicy -ErrorAction Stop; $gpos = @(Get-GPO -All -ErrorAction Stop).Count }
    [pscustomobject]@{ status=$status; metrics=[pscustomobject]@{ users=$users; groups=$groups; ous=$ous; gpos=$gpos } }
}

function Invoke-DashboardADUserAction {
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
    $user = Get-ADUser -Identity $Identity -Properties Enabled,DistinguishedName,SamAccountName,LockedOut,PasswordLastSet -ErrorAction Stop
    $sourceOU = ($user.DistinguishedName -split ',',2)[1]
    $destinationOuDn = $null
    $mutationApplied = $false
    $passwordReset = $false
    $actionError = $null
    $message = ''

    try {
        switch ($Operation) {
            'disableUser' {
                if (-not $user.Enabled) { throw 'L’account è già disabilitato.' }
                Disable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
                $mutationApplied = $true
                $message = "Account $($user.SamAccountName) disabilitato."
            }
            'enableUser' {
                if ($user.Enabled) { throw 'L’account è già abilitato. Usa Reset password per modificare la password.' }
                if ([string]::IsNullOrEmpty($Password)) { throw 'Per abilitare e sbloccare l’account è obbligatorio impostare una nuova password.' }
                $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
                Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword $securePassword -ErrorAction Stop
                $mutationApplied = $true
                $passwordReset = $true
                if ($ChangePasswordAtLogon) { Set-ADUser -Identity $user.DistinguishedName -ChangePasswordAtLogon $true -ErrorAction Stop }
                Enable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
                Unlock-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
                $message = "Password reimpostata; account $($user.SamAccountName) abilitato e sbloccato."
            }
            'moveUser' {
                if ([string]::IsNullOrWhiteSpace($DestinationOU) -or $DestinationOU.Length -gt 1024) { throw 'Specificare il Distinguished Name della OU di destinazione.' }
                $ou = Get-ADOrganizationalUnit -Identity $DestinationOU -ErrorAction Stop
                if ($sourceOU -ieq $ou.DistinguishedName) { throw 'L’utente si trova già nella OU di destinazione.' }
                $destinationOuDn = $ou.DistinguishedName
                Move-ADObject -Identity $user.DistinguishedName -TargetPath $destinationOuDn -Confirm:$false -ErrorAction Stop
                $mutationApplied = $true
                $message = "Account $($user.SamAccountName) spostato in $destinationOuDn."
            }
            'resetPassword' {
                if (-not $user.Enabled) { throw 'Per sicurezza, il reset password è consentito solo agli account abilitati.' }
                if ([string]::IsNullOrEmpty($Password)) { throw 'La nuova password è obbligatoria.' }
                $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
                Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword $securePassword -ErrorAction Stop
                $mutationApplied = $true
                $passwordReset = $true
                if ($ChangePasswordAtLogon) { Set-ADUser -Identity $user.DistinguishedName -ChangePasswordAtLogon $true -ErrorAction Stop }
                $message = "Password reimpostata per $($user.SamAccountName)."
            }
        }
    } catch {
        $actionError = $_.Exception.Message
    } finally {
        $Password = $null
    }

    $updated = $null
    try {
        $updated = Get-ADUser -Identity $user.SamAccountName -Properties Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut,PasswordLastSet -ErrorAction Stop |
            Select-Object Name,SamAccountName,Department,Title,Enabled,DistinguishedName,Mail,LastLogonDate,LockedOut,PasswordLastSet
    } catch {
        if ([string]::IsNullOrWhiteSpace($actionError)) { $actionError = "Verifica dello stato finale non riuscita: $($_.Exception.Message)" }
        else { $actionError += " Verifica dello stato finale non riuscita: $($_.Exception.Message)" }
    }

    $verified = $false
    if ($updated) {
        switch ($Operation) {
            'disableUser' { $verified = ($updated.Enabled -eq $false) }
            'enableUser' { $verified = ($updated.Enabled -eq $true -and $updated.LockedOut -eq $false) }
            'moveUser' { $verified = (($updated.DistinguishedName -split ',',2)[1] -ieq $destinationOuDn) }
            'resetPassword' { $verified = ($passwordReset -and $updated.PasswordLastSet -and $updated.PasswordLastSet -ne $user.PasswordLastSet) }
        }
    }

    if (-not $mutationApplied) {
        if (-not [string]::IsNullOrWhiteSpace($actionError)) { throw $actionError }
        throw 'L’operazione non è stata applicata.'
    }

    $operationStatus = if ([string]::IsNullOrWhiteSpace($actionError) -and $verified) { 'success' } else { 'partial' }
    if (-not $verified -and [string]::IsNullOrWhiteSpace($actionError)) {
        $actionError = 'Il comando di modifica è stato eseguito, ma la verifica dello stato finale non ha confermato completamente il risultato. Controllare Active Directory.'
    }
    if ($operationStatus -eq 'partial') {
        $message = "Operazione $Operation applicata almeno in parte per $($user.SamAccountName); verificare lo stato finale in Active Directory."
    }

    $audit = [ordered]@{ passwordReset = $passwordReset }
    if ($Operation -eq 'moveUser') {
        $audit.sourceOU = $sourceOU
        $audit.destinationOU = $destinationOuDn
    }
    [pscustomobject]@{
        message = $message
        operationStatus = $operationStatus
        error = $actionError
        user = $updated
        audit = $audit
    }
}

function Test-DashboardADDefaultGroup {
    param([Parameter(Mandatory)]$Group)
    $sid=[string]$Group.SID.Value
    $builtin=[string]$Group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,'
    $rid=if($sid -match '-(\d+)$'){[int]$Matches[1]}else{-1}
    return ($builtin -or (@(498,499,500,501,502,512,513,514,515,516,517,518,519,520,521,522,525,526,527,553,571,572) -contains $rid))
}
function Search-DashboardADDirectoryMembers {
    [CmdletBinding()]
    param([string]$Query = '')
    Import-Module ActiveDirectory -ErrorAction Stop
    $term = ([string]$Query).Trim()
    if ([string]::IsNullOrWhiteSpace($term) -or $term.Length -lt 2) { return @() }

    # Use the AD PowerShell provider's filter parser instead of constructing an LDAP filter.
    # Escape single quotes so names/account fragments cannot break the filter expression.
    $escaped = $term.Replace("'", "''")
    $filter = "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*'"
    $results = @(
        Get-ADUser -Filter $filter -Properties SamAccountName,DistinguishedName -ResultSetSize 30 -ErrorAction Stop |
        Select-Object Name,SamAccountName,DistinguishedName,@{Name='ObjectClass';Expression={'user'}}
    )
    @($results | Sort-Object Name | Select-Object -First 30)
}

function Get-DashboardADGroupMembers {
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $g=Get-ADGroup -Identity $Identity -Properties Name,DistinguishedName -ErrorAction Stop
    $members=@(Get-ADGroupMember -Identity $g.DistinguishedName -Recursive:$false -ErrorAction Stop | Sort-Object Name | Select-Object Name,SamAccountName,DistinguishedName,ObjectClass)
    [pscustomobject]@{group=$g.DistinguishedName;name=$g.Name;members=$members}
}
function Update-DashboardADGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Members=@())
    Import-Module ActiveDirectory -ErrorAction Stop
    $g=Get-ADGroup -Identity $Identity -Properties SID,DistinguishedName,Name -ErrorAction Stop
    if(Test-DashboardADDefaultGroup $g){throw 'I membri dei gruppi predefiniti non possono essere modificati da questa schermata.'}
    $current=@(Get-ADGroupMember -Identity $g.DistinguishedName -Recursive:$false -ErrorAction Stop)
    $desired=@{}
    foreach($entry in @($Members)){
        if([string]::IsNullOrWhiteSpace([string]$entry)){continue}
        $obj=$null
        try{$obj=Get-ADObject -Identity ([string]$entry) -Properties Name,DistinguishedName,ObjectClass -ErrorAction Stop}
        catch{
            $escaped=([string]$entry).Replace("'","''")
            $obj=Get-ADObject -Filter "Name -eq '$escaped' -or SamAccountName -eq '$escaped'" -Properties Name,DistinguishedName,ObjectClass -ErrorAction Stop | Select-Object -First 1
        }
        if(-not $obj){throw "Membro non trovato: '$entry'."}
        $desired[$obj.DistinguishedName.ToLowerInvariant()]=$obj
    }

    $operationErrors=[System.Collections.Generic.List[string]]::new()
    foreach($m in $current){
        if(-not $desired.ContainsKey($m.DistinguishedName.ToLowerInvariant())){
            try{Remove-ADGroupMember -Identity $g.DistinguishedName -Members $m.DistinguishedName -Confirm:$false -ErrorAction Stop}
            catch{$operationErrors.Add("Rimozione di '$($m.Name)': $($_.Exception.Message)")}
        }
    }
    foreach($key in $desired.Keys){
        $member=$desired[$key]
        if(-not ($current | Where-Object {$_.DistinguishedName -ieq $member.DistinguishedName})){
            try{Add-ADGroupMember -Identity $g.DistinguishedName -Members $member.DistinguishedName -ErrorAction Stop}
            catch{$operationErrors.Add("Aggiunta di '$($member.Name)': $($_.Exception.Message)")}
        }
    }

    $final=@(Get-ADGroupMember -Identity $g.DistinguishedName -Recursive:$false -ErrorAction Stop)
    $finalDns=@($final | ForEach-Object {[string]$_.DistinguishedName})
    foreach($key in $desired.Keys){
        if($finalDns -notcontains $desired[$key].DistinguishedName){$operationErrors.Add("Verifica finale: membro atteso non presente ($($desired[$key].Name)).")}
    }
    foreach($m in $final){
        if(-not $desired.ContainsKey($m.DistinguishedName.ToLowerInvariant())){$operationErrors.Add("Verifica finale: membro non previsto ancora presente ($($m.Name)).")}
    }

    $added=[System.Collections.Generic.List[string]]::new()
    $removed=[System.Collections.Generic.List[string]]::new()
    foreach($m in $final){
        if(-not ($current | Where-Object {$_.DistinguishedName -ieq $m.DistinguishedName})){$added.Add($m.Name)}
    }
    foreach($m in $current){
        if(-not ($final | Where-Object {$_.DistinguishedName -ieq $m.DistinguishedName})){$removed.Add($m.Name)}
    }
    $operationStatus=if($operationErrors.Count){'partial'}else{'success'}
    [pscustomobject]@{
        message="Membri verificati in Active Directory per '$($g.Name)'. Aggiunti: $($added.Count); rimossi: $($removed.Count)."
        operationStatus=$operationStatus
        error=if($operationErrors.Count){$operationErrors -join '; '}else{$null}
        added=@($added)
        removed=@($removed)
        currentMembers=@($final | Select-Object Name,SamAccountName,DistinguishedName,ObjectClass)
    }
}

function New-DashboardADGroup {
    param([Parameter(Mandatory)][string]$GroupName,[Parameter(Mandatory)][string]$Path,[string]$Description='',[ValidateSet('Security','Distribution')][string]$GroupCategory='Security',[ValidateSet('Global','Universal','DomainLocal')][string]$GroupScope='Global')
    Import-Module ActiveDirectory -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($GroupName) -or $GroupName.Length -gt 256){throw 'Nome gruppo non valido.'}
    $ou=Get-ADOrganizationalUnit -Identity $Path -ErrorAction Stop;$escaped=$GroupName.Replace("'","''")
    if(Get-ADGroup -Filter "Name -eq '$escaped'" -ErrorAction Stop){throw "Esiste già un gruppo con nome '$GroupName'."}
    New-ADGroup -Name $GroupName -Path $ou.DistinguishedName -GroupCategory $GroupCategory -GroupScope $GroupScope -Description $Description -ErrorAction Stop
    [pscustomobject]@{message="Gruppo '$GroupName' creato nella OU '$($ou.Name)'."}
}
function Update-DashboardADGroup {
    param([Parameter(Mandatory)][string]$Identity,[Parameter(Mandatory)][string]$GroupName,[string]$Description='')
    Import-Module ActiveDirectory -ErrorAction Stop;$g=Get-ADGroup -Identity $Identity -Properties SID -ErrorAction Stop
    if(Test-DashboardADDefaultGroup $g){throw 'I gruppi predefiniti non possono essere modificati da questa schermata.'}
    $name=$GroupName.Trim()
    if([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 256 -or $name -match '[\\/\[\]:;|=,+*?<>"\\]'){throw 'Nome gruppo non valido (massimo 256 caratteri; contiene caratteri non consentiti).'}
    $escaped=$name.Replace("'","''")
    $duplicates=@(Get-ADGroup -Filter "Name -eq '$escaped' -or SamAccountName -eq '$escaped'" -ErrorAction Stop | Where-Object {$_.DistinguishedName -ine $g.DistinguishedName})
    if($duplicates.Count){throw "Esiste già un gruppo con nome o account '$name'."}
    Set-ADGroup -Identity $g.DistinguishedName -SamAccountName $name -Description $Description -ErrorAction Stop
    Rename-ADObject -Identity $g.DistinguishedName -NewName $name -ErrorAction Stop
    [pscustomobject]@{message="Gruppo aggiornato: '$name'."}
}
function Get-DashboardADGroupDeletePreview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    $group=Get-ADGroup -Identity $Identity -Properties Name,DistinguishedName,SID -ErrorAction Stop
    if(Test-DashboardADDefaultGroup $group){throw 'I gruppi predefiniti non possono essere eliminati.'}
    $users=@(Get-ADGroupMember -Identity $group.DistinguishedName -Recursive -ErrorAction Stop |
        Where-Object { $_.ObjectClass -eq 'user' } |
        Sort-Object DistinguishedName -Unique |
        Select-Object Name,SamAccountName,DistinguishedName)
    [pscustomobject]@{name=$group.Name;identity=$group.DistinguishedName;users=$users;userCount=$users.Count}
}
function Remove-DashboardADGroup {
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop;$g=Get-ADGroup -Identity $Identity -Properties SID -ErrorAction Stop
    if(Test-DashboardADDefaultGroup $g){throw 'I gruppi predefiniti non possono essere eliminati.'}
    Remove-ADGroup -Identity $g.DistinguishedName -Confirm:$false -ErrorAction Stop
    [pscustomobject]@{message="Gruppo '$($g.Name)' eliminato."}
}

function Get-DashboardADAvailableGroups {
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
            @{Name='DashboardADGroupType';Expression={'Personalizzato'}}
    )
}

function Get-DashboardADUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 512) {
        throw 'Identità utente non valida.'
    }
    $user = Get-ADUser -Identity $Identity -Properties GivenName,Surname,DisplayName,UserPrincipalName,Department,Title,Enabled,WhenCreated,WhenChanged,LastLogonDate,PasswordLastSet,BadPwdCount,LastBadPasswordAttempt,LockedOut,Mail,Description,DistinguishedName,SamAccountName,memberOf -ErrorAction Stop
    $details = $user | Select-Object Name,SamAccountName,GivenName,Surname,DisplayName,UserPrincipalName,Department,Title,Enabled,WhenCreated,WhenChanged,LastLogonDate,PasswordLastSet,BadPwdCount,LastBadPasswordAttempt,LockedOut,Mail,Description,DistinguishedName
    $groups = @(
        foreach ($groupDn in @($user.memberOf)) {
            $group = Get-ADGroup -Identity $groupDn -Properties DistinguishedName -ErrorAction Stop
            [pscustomobject]@{ Name=$group.Name; DistinguishedName=$group.DistinguishedName }
        }
    )
    # Keep user details fast: load the selectable group catalogue separately after the modal opens.
    [pscustomobject]@{ user=$details; groups=$groups; availableGroups=@() }
}

function Set-DashboardADUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string]$GivenName='',[string]$Surname='',[string]$DisplayName='',[string]$UserPrincipalName='',[string]$Department='',[string]$Title='',[string]$Email='',[string]$Description='',[string[]]$Groups=@(),[bool]$GroupsSpecified=$false)
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 512) { throw 'Identità utente non valida.' }
    $user=Get-ADUser -Identity $Identity -Properties SID,SamAccountName,DistinguishedName,GivenName,Surname,DisplayName,UserPrincipalName,Department,Title,mail,Description,MemberOf -ErrorAction Stop
    $rid=[string]$user.SID.Value.Split('-')[-1]
    if ($rid -in @('500','501','502')) { throw 'Non è consentito modificare gli account amministratore, guest o krbtgt predefiniti.' }
    $set=@{Identity=$user.DistinguishedName;ErrorAction='Stop'}
    $clear=[System.Collections.Generic.List[string]]::new()
    foreach($field in @(
        @{Key='GivenName';Value=$GivenName;Attribute='givenName'},
        @{Key='Surname';Value=$Surname;Attribute='sn'},
        @{Key='DisplayName';Value=$DisplayName;Attribute='displayName'},
        @{Key='Department';Value=$Department;Attribute='department'},
        @{Key='Title';Value=$Title;Attribute='title'},
        @{Key='EmailAddress';Value=$Email;Attribute='mail'},
        @{Key='Description';Value=$Description;Attribute='description'}
    )){
        if([string]::IsNullOrWhiteSpace([string]$field.Value)){$clear.Add([string]$field.Attribute)}else{$set[[string]$field.Key]=[string]$field.Value}
    }
    if (-not [string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        if ($UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+$') {
            throw 'User Principal Name non valido. Usa il formato nome@dominio.'
        }
        $set.UserPrincipalName = $UserPrincipalName
    }

    $fieldErrors = [System.Collections.Generic.List[string]]::new()
    Set-ADUser @set
    if ($clear.Count -gt 0) {
        try { Set-ADUser -Identity $user.DistinguishedName -Clear $clear.ToArray() -ErrorAction Stop }
        catch { $fieldErrors.Add("Pulizia attributi: $($_.Exception.Message)") }
    }

    $groupChanges = $null
    $groupError = $null
    if ($GroupsSpecified) {
        # Un array esplicitamente vuoto significa rimuovere tutte le appartenenze dirette modificabili.
        # Le appartenenze protette e il gruppo primario sono esclusi dalla funzione di aggiornamento.
        try {
            $groupChanges = Update-DashboardADUserGroups -Identity $user.DistinguishedName -Groups $Groups
            if ($groupChanges.operationStatus -eq 'partial') { $groupError = [string]$groupChanges.error }
        } catch { $groupError = $_.Exception.Message }
    }

    $updatedUser = Get-ADUser -Identity $user.DistinguishedName -Properties GivenName,Surname,DisplayName,UserPrincipalName,Department,Title,mail,Description,Enabled,MemberOf -ErrorAction Stop
    $changedFields = [System.Collections.Generic.List[string]]::new()
    foreach ($field in @(
        @{Name='givenName';Before=$user.GivenName;After=$updatedUser.GivenName},
        @{Name='sn';Before=$user.Surname;After=$updatedUser.Surname},
        @{Name='displayName';Before=$user.DisplayName;After=$updatedUser.DisplayName},
        @{Name='department';Before=$user.Department;After=$updatedUser.Department},
        @{Name='title';Before=$user.Title;After=$updatedUser.Title},
        @{Name='mail';Before=$user.mail;After=$updatedUser.mail},
        @{Name='description';Before=$user.Description;After=$updatedUser.Description}
    )) {
        if ([string]$field.Before -cne [string]$field.After) { $changedFields.Add([string]$field.Name) }
    }
    if (-not [string]::IsNullOrWhiteSpace($UserPrincipalName) -and [string]$user.UserPrincipalName -cne [string]$updatedUser.UserPrincipalName) {
        $changedFields.Add('userPrincipalName')
    }
    $groupsAdded = [System.Collections.Generic.List[string]]::new()
    $groupsRemoved = [System.Collections.Generic.List[string]]::new()
    $beforeDns = @($user.MemberOf | ForEach-Object { [string]$_ })
    $afterDns = @($updatedUser.MemberOf | ForEach-Object { [string]$_ })
    foreach ($dn in $afterDns) {
        if ($beforeDns -notcontains $dn) {
            try { $groupsAdded.Add((Get-ADGroup -Identity $dn -ErrorAction Stop).Name) } catch { $groupsAdded.Add($dn) }
        }
    }
    foreach ($dn in $beforeDns) {
        if ($afterDns -notcontains $dn) {
            try { $groupsRemoved.Add((Get-ADGroup -Identity $dn -ErrorAction Stop).Name) } catch { $groupsRemoved.Add($dn) }
        }
    }
    $auditErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $fieldErrors) { $auditErrors.Add($item) }
    if (-not [string]::IsNullOrWhiteSpace($groupError)) { $auditErrors.Add("Appartenenze gruppi: $groupError") }
    $auditStatus = if ($auditErrors.Count) { 'partial' } else { 'success' }
    $audit = [ordered]@{ operationStatus = $auditStatus; error = if ($auditErrors.Count) { $auditErrors -join '; ' } else { $null }; changedFields = @($changedFields); groupsAdded = @($groupsAdded); groupsRemoved = @($groupsRemoved) }
    if ($groupChanges) { $updatedUser | Add-Member -NotePropertyName DashboardADGroupChanges -NotePropertyValue $groupChanges -Force }
    $updatedUser | Add-Member -NotePropertyName DashboardADAudit -NotePropertyValue $audit -Force
    $updatedUser
}

function New-DashboardADUser {
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

    # Validate the default domain policy before creating any directory object.
    $passwordPolicy = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop
    if ($Password.Length -lt [int]$passwordPolicy.MinPasswordLength) {
        throw "Password non conforme: la policy del dominio richiede almeno $($passwordPolicy.MinPasswordLength) caratteri. L'utente non è stato creato."
    }
    if ($passwordPolicy.ComplexityEnabled) {
        $categories = 0
        if ($Password -cmatch '[A-Z]') { $categories++ }
        if ($Password -cmatch '[a-z]') { $categories++ }
        if ($Password -match '[0-9]') { $categories++ }
        if ($Password -match '[^a-zA-Z0-9]') { $categories++ }
        if ($categories -lt 3) {
            throw "Password non conforme: la policy del dominio richiede almeno 3 categorie tra maiuscole, minuscole, numeri e simboli. L'utente non è stato creato."
        }
    }
    if ($Password.IndexOf($Identity, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Password non conforme: non può contenere il nome account. L'utente non è stato creato."
    }
    $nameParts = @("$GivenName $Surname $DisplayName" -split '[^\p{L}\p{Nd}]+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique)
    foreach ($part in $nameParts) {
        if ($Password.IndexOf($part, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Password non conforme: non può contenere parti del nome o cognome. L'utente non è stato creato."
        }
    }

    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        $upnSuffix = [string]$global:DashboardADConfig.ActiveDirectory.UPNSuffix
        if ([string]::IsNullOrWhiteSpace($upnSuffix)) {
            $domain = Get-ADDomain -ErrorAction Stop
            $upnSuffix = [string]$domain.DNSRoot
        }
        $UserPrincipalName = "$Identity@$upnSuffix"
    }
    if ($UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+$') { throw 'User Principal Name non valido. Usa il formato nome@dominio.' }
    $ou = Get-ADOrganizationalUnit -Identity $DestinationOU -ErrorAction Stop
    $escapedIdentity = $Identity.Replace("'", "''")
    if (Get-ADUser -Filter "SamAccountName -eq '$escapedIdentity'" -ErrorAction Stop) { throw "Esiste già un account con nome '$Identity'." }

    $accountName = if ($DisplayName) { $DisplayName } else { (($GivenName + ' ' + $Surname).Trim()) }
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = $Identity }
    $params = @{
        Name = $accountName
        SamAccountName = $Identity
        Path = $ou.DistinguishedName
        Enabled = $false
        PassThru = $true
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

    $created = New-ADUser @params
    try {
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        Set-ADAccountPassword -Identity $created.DistinguishedName -Reset -NewPassword $securePassword -ErrorAction Stop
        Set-ADUser -Identity $created.DistinguishedName -ChangePasswordAtLogon $ChangePasswordAtLogon -ErrorAction Stop
        Enable-ADAccount -Identity $created.DistinguishedName -ErrorAction Stop
    } catch {
        $passwordError = $_.Exception.Message
        try {
            Remove-ADUser -Identity $created.DistinguishedName -Confirm:$false -ErrorAction Stop
        } catch {
            throw "Active Directory ha rifiutato la password e non è stato possibile rimuovere automaticamente l'account rimasto disabilitato. Errore password: $passwordError. Errore rimozione: $($_.Exception.Message)"
        }
        throw "Active Directory ha rifiutato la password (ad esempio per cronologia o policy specifiche). L'account temporaneo è stato rimosso e l'utente non è stato creato. Dettaglio: $passwordError"
    }

    $created = Get-ADUser -Identity $created.DistinguishedName -Properties DistinguishedName,primaryGroupID -ErrorAction Stop
    $added = [System.Collections.Generic.List[string]]::new()
    $groupWarnings = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Groups)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry)) { continue }
        $groupIdentity = [string]$entry
        try {
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
        } catch {
            $groupWarnings.Add("$($groupIdentity): $($_.Exception.Message)")
        }
    }
    $message = "Utente '$Identity' creato e abilitato nella OU '$($ou.Name)'. Gruppi assegnati: $($added.Count)."
    if ($groupWarnings.Count) { $message += " ATTENZIONE: l'account esiste, ma non è stato possibile assegnare alcuni gruppi: " + ($groupWarnings -join '; ') }
    [pscustomobject]@{ message = $message; operationStatus = $(if ($groupWarnings.Count) { 'partial' } else { 'success' }); error = $(if ($groupWarnings.Count) { $groupWarnings -join '; ' } else { $null }); user = $created; groups = @($added); groupWarnings = @($groupWarnings) }
}

function Update-DashboardADUserGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity,[string[]]$Groups = @())
    Import-Module ActiveDirectory -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 512) { throw 'Identità utente non valida.' }
    $user = Get-ADUser -Identity $Identity -Properties memberOf,primaryGroupID,DistinguishedName,SamAccountName -ErrorAction Stop
    $currentDns = @($user.memberOf | ForEach-Object { [string]$_ })
    $desired = @{}
    foreach ($entry in @($Groups)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry)) { continue }
        $group = $null
        try { $group = Get-ADGroup -Identity ([string]$entry) -Properties SID,DistinguishedName -ErrorAction Stop }
        catch {
            $escapedGroup = ([string]$entry).Replace("'", "''")
            $matches = @(Get-ADGroup -Filter "Name -eq '$escapedGroup' -or SamAccountName -eq '$escapedGroup'" -Properties SID,DistinguishedName -ErrorAction Stop)
            if ($matches.Count -gt 1) { throw "Il gruppo '$entry' non è univoco. Specifica il Distinguished Name completo." }
            if (-not $matches.Count) { throw "Gruppo non trovato: '$entry'." }
            $group = $matches[0]
        }
        $sidText = [string]$group.SID.Value
        $protected = $group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,' -or
            $sidText -match '-(498|499|500|501|502|503|504|505|506|507|508|509|510|511|512|513|514|515|516|517|518|519|520|521|522|525|526|527|553|571|572)$'
        if ($protected) {
            if ($currentDns -contains $group.DistinguishedName) { continue }
            throw "Il gruppo di sistema '$($group.Name)' non può essere aggiunto da questa schermata."
        }
        $desired[$group.DistinguishedName.ToLowerInvariant()] = $group
    }

    $operationErrors = [System.Collections.Generic.List[string]]::new()
    $protectedDns = @{}
    foreach ($dn in $currentDns) {
        $group = Get-ADGroup -Identity $dn -Properties SID,DistinguishedName -ErrorAction Stop
        $sidText = [string]$group.SID.Value
        $protected = $group.DistinguishedName -match '(?i)^CN=[^,]+,CN=Builtin,' -or
            $sidText -match '-(498|499|500|501|502|503|504|505|506|507|508|509|510|511|512|513|514|515|516|517|518|519|520|521|522|525|526|527|553|571|572)$'
        if ($protected) {
            $protectedDns[$dn.ToLowerInvariant()] = $dn
            continue
        }
        if ($desired.ContainsKey($dn.ToLowerInvariant())) { continue }
        try { Remove-ADGroupMember -Identity $group.DistinguishedName -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop }
        catch { $operationErrors.Add("Rimozione da '$($group.Name)': $($_.Exception.Message)") }
    }

    foreach ($key in @($desired.Keys)) {
        $group = $desired[$key]
        if ($currentDns -notcontains $group.DistinguishedName) {
            try { Add-ADGroupMember -Identity $group.DistinguishedName -Members $user.DistinguishedName -ErrorAction Stop }
            catch { $operationErrors.Add("Aggiunta a '$($group.Name)': $($_.Exception.Message)") }
        }
    }

    $finalUser = Get-ADUser -Identity $user.DistinguishedName -Properties memberOf,DistinguishedName -ErrorAction Stop
    $finalDns = @($finalUser.MemberOf | ForEach-Object { [string]$_ })
    $expectedDns = @{}
    foreach ($key in $desired.Keys) { $expectedDns[$key] = $desired[$key].DistinguishedName }
    foreach ($key in $protectedDns.Keys) { $expectedDns[$key] = $protectedDns[$key] }
    foreach ($key in $expectedDns.Keys) {
        if ($finalDns -notcontains $expectedDns[$key]) { $operationErrors.Add("Verifica finale: appartenenza attesa non presente ($($expectedDns[$key])).") }
    }
    foreach ($dn in $finalDns) {
        if (-not $expectedDns.ContainsKey($dn.ToLowerInvariant())) {
            $operationErrors.Add("Verifica finale: appartenenza non prevista ancora presente ($dn).")
        }
    }

    $added = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($dn in $finalDns) {
        if ($currentDns -notcontains $dn) {
            try { $added.Add((Get-ADGroup -Identity $dn -ErrorAction Stop).Name) } catch { $added.Add($dn) }
        }
    }
    foreach ($dn in $currentDns) {
        if ($finalDns -notcontains $dn) {
            try { $removed.Add((Get-ADGroup -Identity $dn -ErrorAction Stop).Name) } catch { $removed.Add($dn) }
        }
    }
    $operationStatus = if ($operationErrors.Count) { 'partial' } else { 'success' }
    [pscustomobject]@{
        message = "Appartenenze verificate in Active Directory. Aggiunti: $($added.Count); rimossi: $($removed.Count)."
        operationStatus = $operationStatus
        error = if ($operationErrors.Count) { $operationErrors -join '; ' } else { $null }
        added = @($added)
        removed = @($removed)
        currentMemberships = @($finalDns)
    }
}

function Invoke-DashboardADRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('status','dashboard','users','groups','ous','createOU','updateOU','deleteOU','ouContents','gpos','tasks','disableUser','enableUser','moveUser','resetPassword','userDetails','updateUserGroups','createUser','updateUser','copyUser','availableGroups','groupMembers','searchDirectoryMembers','updateGroupMembers','createGroup','updateGroup','groupDeletePreview','deleteGroup')]
        [string]$Operation,
        [ValidateLength(0,128)][string]$Query = '',
        [string]$Identity = '',
        [string]$DestinationOU = '',
        [string]$Password = '',
        [bool]$ChangePasswordAtLogon = $false,
        [string[]]$Groups = @(),
        [bool]$GroupsSpecified = $false,
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
    try {
        $data = switch ($Operation) {
            'status' { Get-DashboardADStatus }
            'dashboard' { Get-DashboardADDashboard }
            'users' { Get-DashboardADUsers -Query $Query }
            'userDetails' { Get-DashboardADUserDetails -Identity $Identity }
            'availableGroups' { Get-DashboardADAvailableGroups }
            'createUser' { New-DashboardADUser -Identity $Identity -DestinationOU $Path -Password $Password -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Groups $Groups -ChangePasswordAtLogon $ChangePasswordAtLogon }
            'updateUser' { Set-DashboardADUser -Identity $Identity -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Groups $Groups -GroupsSpecified $GroupsSpecified }
            'copyUser' { New-DashboardADUser -Identity $GroupName -DestinationOU $Path -Password $Password -GivenName $GivenName -Surname $Surname -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName -Department $Department -Title $Title -Email $Email -Description $Description -Groups $Groups -ChangePasswordAtLogon $ChangePasswordAtLogon }
            'updateUserGroups' { Update-DashboardADUserGroups -Identity $Identity -Groups $Groups }
            'groupMembers' { Get-DashboardADGroupMembers -Identity $Identity }
            'searchDirectoryMembers' { Search-DashboardADDirectoryMembers -Query $Query }
            'updateGroupMembers' { Update-DashboardADGroupMembers -Identity $Identity -Members $Members }
            'createGroup' { New-DashboardADGroup -GroupName $GroupName -Path $Path -Description $Description -GroupCategory $GroupCategory -GroupScope $GroupScope }
            'updateGroup' { Update-DashboardADGroup -Identity $Identity -GroupName $GroupName -Description $Description }
            'groupDeletePreview' { Get-DashboardADGroupDeletePreview -Identity $Identity }
            'deleteGroup' { Remove-DashboardADGroup -Identity $Identity }
            'groups' { Get-DashboardADGroups -Query $Query }
            'ouContents' { Get-DashboardADOUContents -Identity $Identity }
            'createOU' { New-DashboardADOU -Name $GroupName -Path $Path -Description $Description -ProtectedFromAccidentalDeletion $ProtectedFromAccidentalDeletion }
            'updateOU' { Update-DashboardADOU -Identity $Identity -Name $GroupName -Description $Description }
            'deleteOU' { Remove-DashboardADOU -Identity $Identity }
            'ous' { Get-DashboardADOUs -Query $Query }
            'gpos' { Get-DashboardADGpos -Query $Query }
            'tasks' { Get-DashboardADScheduledTasks -Query $Query }
            'disableUser' { Invoke-DashboardADUserAction -Operation $Operation -Identity $Identity }
            'enableUser' { Invoke-DashboardADUserAction -Operation $Operation -Identity $Identity -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon }
            'moveUser' { Invoke-DashboardADUserAction -Operation $Operation -Identity $Identity -DestinationOU $DestinationOU }
            'resetPassword' { Invoke-DashboardADUserAction -Operation $Operation -Identity $Identity -Password $Password -ChangePasswordAtLogon $ChangePasswordAtLogon }
        }
        $status = 'success'
        $responseError = $null
        if ($data -and $data.PSObject.Properties['DashboardADAudit'] -and $data.DashboardADAudit.operationStatus -eq 'partial') {
            $status = 'partial'
            $responseError = [string]$data.DashboardADAudit.error
        } elseif ($data -and $data.PSObject.Properties['operationStatus'] -and $data.operationStatus -eq 'partial') {
            $status = 'partial'
            $responseError = [string]$data.error
        }
        [pscustomobject]@{ success=($status -eq 'success'); status=$status; operation=$Operation; query=$Query; data=$data; error=$responseError }
    } catch {
        [pscustomobject]@{ success=$false; status='failed'; operation=$Operation; query=$Query; data=$null; error=$_.Exception.Message }
    } finally {
        if ($Password) { $Password = $null }
    }
}

Export-ModuleMember -Function Get-DashboardADStatus, Invoke-DashboardADRequest
