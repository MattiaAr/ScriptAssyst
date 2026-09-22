# Eseguire come Amministratore sul PC tecnico
$DCServer = "192.168.1.200"
Set-Item WSMan:\localhost\Client\TrustedHosts -Value $DCServer -Concatenate -Force
Get-Item WSMan:\localhost\Client\TrustedHosts
