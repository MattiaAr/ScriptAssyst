Get-ADUser -Identity "MartiniS" -Properties DistinguishedName -Server "192.168.1.200" |
    Select-Object SamAccountName, DistinguishedName

$OURoot = "OU=Nexura,DC=homelab,DC=local"
$u = Get-ADUser -Identity "MartiniS" -Properties DistinguishedName -Server "192.168.1.200"
if ($u.DistinguishedName -like "*$OURoot") {
    Write-Host "OK: l'utente e' dentro OURoot" -ForegroundColor Green
} else {
    Write-Host "PROBLEMA: l'utente NON e' dentro OURoot '$OURoot'" -ForegroundColor Red
    Write-Host "DN reale utente: $($u.DistinguishedName)"
}

Get-ADUser -Filter "SamAccountName -eq 'MartiniS' -or UserPrincipalName -eq 'MartiniS' -or Name -eq 'MartiniS'" `
    -SearchBase $OURoot -Server "192.168.1.200"
