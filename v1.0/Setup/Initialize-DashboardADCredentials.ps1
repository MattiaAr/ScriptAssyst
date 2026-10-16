[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'DashboardAD.config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "File di configurazione non trovato: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$credentialPath = [string]$config.ActiveDirectory.AdminCredentialPath
if ([string]::IsNullOrWhiteSpace($credentialPath)) { throw 'AdminCredentialPath non è configurato.' }
$directory = Split-Path -Parent $credentialPath
if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }

$expectedUser = [string]$config.ActiveDirectory.ExpectedAdminUsername
if ([string]::IsNullOrWhiteSpace($expectedUser)) {
    $credential = Get-Credential -Message 'Inserisci le credenziali amministrative Active Directory'
} else {
    $credential = Get-Credential -UserName $expectedUser -Message 'Inserisci la password per l’account amministrativo configurato'
}
if (-not $credential) { throw 'Operazione annullata: credenziali non inserite.' }
if (-not [string]::IsNullOrWhiteSpace($expectedUser) -and $credential.UserName -ne $expectedUser) {
    throw "L'account inserito ($($credential.UserName)) non corrisponde a ExpectedAdminUsername ($expectedUser)."
}

$credential | Export-Clixml -LiteralPath $credentialPath -Force
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $directory /inheritance:r /grant:r "$($currentIdentity):(OI)(CI)F" 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $credentialPath -Force -ErrorAction SilentlyContinue
    throw "Impossibile applicare i permessi di sicurezza alla cartella: $directory"
}
Write-Host "Credenziali salvate nel file protetto: $credentialPath"
Write-Host "Il file è decifrabile soltanto dallo stesso account Windows e sullo stesso computer."
Write-Host "Account Windows che deve eseguire DashboardAD: $currentIdentity"
