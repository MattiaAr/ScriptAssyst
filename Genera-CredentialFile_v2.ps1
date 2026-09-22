[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$DomainNetBIOS
)

Write-Host "Inserire le credenziali dell'utenza tecnica AD." -ForegroundColor Cyan
Write-Host "Formato richiesto: $DomainNetBIOS\nomeutente oppure nomeutente@dominio" -ForegroundColor Yellow

do {
    $cred = Get-Credential -Message "Credenziali utenza tecnica AD"
    $usernameOk = $cred.UserName -match '\\' -or $cred.UserName -match '@'
    if (-not $usernameOk) { Write-Host "[ERRORE] Specificare dominio\utente o UPN." -ForegroundColor Red }
} while (-not $usernameOk)

$cred | Export-Clixml -Path $OutputPath
Write-Host "File salvato: $OutputPath" -ForegroundColor Green

$DCServer = Read-Host "IP/nome DC per test (ENTER per saltare)"
if (-not [string]::IsNullOrWhiteSpace($DCServer)) {
    try {
        $domain = Get-ADDomain -Server $DCServer -Credential $cred -ErrorAction Stop
        Write-Host "[OK] Autenticazione riuscita: $($domain.DNSRoot)" -ForegroundColor Green
    } catch {
        Write-Host "[FALLITO] $($_.Exception.Message)" -ForegroundColor Red
    }
}
