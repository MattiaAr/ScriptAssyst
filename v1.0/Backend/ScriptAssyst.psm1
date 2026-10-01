Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ScriptAssystCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

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
        }
        catch {
            $errorMessage = $_.Exception.Message
        }
    }
    else {
        $errorMessage = 'Modulo ActiveDirectory non disponibile. Installare RSAT o il componente AD PowerShell.'
    }

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
    @(Get-ADGroup -Filter $filter -Properties GroupCategory,GroupScope,Description,DistinguishedName,Member -ErrorAction Stop |
        Sort-Object Name |
        Select-Object Name,SamAccountName,GroupCategory,GroupScope,Description,DistinguishedName,@{Name='MemberCount';Expression={ @($_.Member).Count }})
    )
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
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $all = @($all | Where-Object { $_.DisplayName -like "*$Query*" })
    }
    @($all | Sort-Object DisplayName | Select-Object DisplayName,Id,GpoStatus,CreationTime,ModificationTime,Owner,Description)
}

function Get-ScriptAssystScheduledTasks {
    [CmdletBinding()]
    param([string]$Query = '')
    $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $tasks = @($tasks | Where-Object { $_.TaskName -like "*$Query*" -or $_.TaskPath -like "*$Query*" })
    }
    @($tasks | Sort-Object TaskPath,TaskName | Select-Object TaskName,TaskPath,State,Author,Description)
}

function Get-ScriptAssystDashboard {
    [CmdletBinding()]
    param()
    $status = Get-ScriptAssystStatus
    if (-not $status.adConnected) {
        return [pscustomobject]@{ status=$status; metrics=$null; message='Metriche non disponibili: Active Directory non raggiungibile.' }
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    $users = @(Get-ADUser -Filter * -ErrorAction Stop).Count
    $groups = @(Get-ADGroup -Filter * -ErrorAction Stop).Count
    $ous = @(Get-ADOrganizationalUnit -Filter * -ErrorAction Stop).Count
    $gpos = $null
    if ($status.groupPolicyModule) {
        Import-Module GroupPolicy -ErrorAction Stop
        $gpos = @(Get-GPO -All -ErrorAction Stop).Count
    }
    [pscustomobject]@{ status=$status; metrics=[pscustomobject]@{ users=$users; groups=$groups; ous=$ous; gpos=$gpos } }
}

function Invoke-ScriptAssystRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('status','dashboard','users','groups','ous','gpos','tasks')]
        [string]$Operation,
        [ValidateLength(0,128)]
        [string]$Query = ''
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
        }
        [pscustomobject]@{ success=$true; operation=$Operation; data=$data; error=$null }
    }
    catch {
        [pscustomobject]@{ success=$false; operation=$Operation; data=$null; error=$_.Exception.Message }
    }
}

Export-ModuleMember -Function Get-ScriptAssystStatus, Invoke-ScriptAssystRequest