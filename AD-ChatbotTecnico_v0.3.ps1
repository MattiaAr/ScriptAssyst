<#
.SYNOPSIS
    AD-Chatbot Tecnico - Script di automazione Active Directory per tecnici (via VPN, no RDP).

.DESCRIPTION
    Menu interattivo a scelte numeriche per operare su Active Directory:
    - Analisi/gestione utenti
    - Gestione OU
    - Gestione GPO
    - Gestione gruppi
    - Analisi/gestione task schedulati (sul DC)

    Ogni azione (lettura o modifica) viene tracciata in un log TXT narrativo di sessione,
    pensato per essere ricostruibile da chi non conosce il contesto originale.

.PARAMETER DCServer
    Nome o IP del Domain Controller su cui operare.

.PARAMETER OURoot
    DistinguishedName della OU radice: ogni ricerca è vincolata a questo ramo (SearchBase).

.PARAMETER TXTPath
    Cartella dove verranno scritti il file di log di sessione e gli export richiesti.

.PARAMETER CredentialFile
    Percorso di un file XML credenziali protetto (creato con Export-CliXml / DPAPI).
    Se omesso, le credenziali vengono richieste in modo interattivo (Get-Credential).

.NOTES
    Requisiti: modulo ActiveDirectory (RSAT) e modulo GroupPolicy disponibili sulla macchina
    da cui si esegue lo script (o sulla sessione verso il DC).
    Versione: v0.3 - gestione OU/GPO separata e spostamento OU protetto.

.VERSIONHISTORY
    v0.1 (2026-09-21) - Baseline: scheletro completo 5 macro-menu, log narrativo per sessione,
                         credenziali via file protetto o interattive, SearchBase su OURoot (Subtree).
                         Delega permessi OU non implementata (TODO: dsacls.exe).
    v0.2 (2026-09-21) - Menu Analisi Utente/OU/GPO ristrutturati: ricerca e creazione sono ora
                         voci di menu indipendenti (non serve piu' cercare per poter creare).
                         Aggiunta selezione OU assistita con albero indentato ovunque si richieda
                         una OU (creazione/spostamento utenti, OU, gruppi, link GPO): il tecnico
                         digita solo il nome, lo script risolve il DN e chiede conferma.
                         Cache albero OU con invalidazione automatica su crea/sposta OU.
                         Fix bug indentazione albero (ordinamento per profondita' DN).
                         Password non conforme ai criteri di complessita': richiesta in loop
                         senza perdere il contesto dell'operazione (niente piu' reset da capo).
                         Convenzione "0" per annullare disponibile in ogni prompt di testo libero.
                         Nuova funzione: visualizzazione GPO collegate a una OU scelta dall'albero.
    v0.3 (2026-09-22) - Conferme annullabili con 0/ANNULLA. Albero OU costruito dalla reale
                         relazione padre/figlio dei Distinguished Name. Menu OU e GPO separati
                         per analisi e operazioni. Spostamento OU con controlli su root,
                         discendenti e ProtectedFromAccidentalDeletion, con ripristino garantito.
                         Sessioni CIM verso indirizzi IP tramite DCOM con diagnostica dedicata.
#>

[CmdletBinding()]
param(
    #[Parameter(Mandatory = $true)]
    [string]$DCServer = "192.168.1.200",

    #[Parameter(Mandatory = $true)]
    [string]$OURoot ="OU=Nexura,DC=homelab,DC=local",

    #[Parameter(Mandatory = $true)]
    [string]$TXTPath = "C:\Users\MerrinoM\Desktop\SCRIPT_REMOTE_AD\AD-Chatbot\Logs",

    #[Parameter(Mandatory = $false)]
    [string]$CredentialFile = "C:\Users\MerrinoM\Desktop\SCRIPT_REMOTE_AD\cred_tecnico.xml"
)

#region ============================ INIZIALIZZAZIONE ============================

$ErrorActionPreference = 'Stop'

# --- Import moduli richiesti ---
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Host "[ERRORE FATALE] Modulo ActiveDirectory non disponibile su questa macchina. Installare RSAT-AD-PowerShell." -ForegroundColor Red
    exit 1
}

try {
    Import-Module GroupPolicy -ErrorAction Stop
    $script:GPOModuleAvailable = $true
}
catch {
    Write-Host "[AVVISO] Modulo GroupPolicy non disponibile: le funzioni GPO saranno disabilitate." -ForegroundColor Yellow
    $script:GPOModuleAvailable = $false
}

# --- Verifica esistenza cartella TXTPath ---
if (-not (Test-Path -Path $TXTPath)) {
    Write-Host "[INFO] La cartella TXTPath '$TXTPath' non esiste. Creazione in corso..." -ForegroundColor Yellow
    New-Item -Path $TXTPath -ItemType Directory -Force | Out-Null
}

# --- Verifica esistenza OURoot su AD ---
try {
    $null = Get-ADOrganizationalUnit -Identity $OURoot -Server $DCServer -ErrorAction Stop
}
catch {
    Write-Host "[ERRORE FATALE] La OU root '$OURoot' non esiste o non è raggiungibile sul DC '$DCServer'." -ForegroundColor Red
    Write-Host "Dettaglio errore: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Credenziali ---
if ($CredentialFile) {
    if (-not (Test-Path -Path $CredentialFile)) {
        Write-Host "[ERRORE FATALE] File credenziali '$CredentialFile' non trovato." -ForegroundColor Red
        exit 1
    }
    try {
        $script:ADCredential = Import-Clixml -Path $CredentialFile
    }
    catch {
        Write-Host "[ERRORE FATALE] Impossibile leggere il file credenziali. Deve essere generato con Export-Clixml dallo stesso utente/PC." -ForegroundColor Red
        exit 1
    }
}
else {
    $script:ADCredential = Get-Credential -Message "Inserire le credenziali dell'utenza tecnica AD"
}

# --- Nome tecnico (per log) ---
$script:TecnicoNome = $env:USERNAME
if ($script:ADCredential -and $script:ADCredential.UserName) {
    $script:TecnicoNome = ($script:ADCredential.UserName -split '\\')[-1]
}

# --- Motivazione iniziale (obbligatoria) ---
function Read-MotivazioneObbligatoria {
    param([string]$Prompt = "Inserire motivazione (es. numero ticket '#1640253' oppure descrizione tipo 'verifica utente c.michelini')")
    do {
        $val = Read-Host -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Host "  -> Campo obbligatorio: inserire del testo." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($val))
    return $val.Trim()
}

Write-Host "=== AD-Chatbot Tecnico ===" -ForegroundColor Cyan
Write-Host "DC target : $DCServer"
Write-Host "OU root   : $OURoot"
Write-Host "Tecnico   : $($script:TecnicoNome)"
Write-Host ""

$script:MotivazioneSessione = Read-MotivazioneObbligatoria -Prompt "Inserire motivazione della sessione (numero ticket o descrizione libera)"

# --- Costruzione nome file di log ---
# Sanitizzazione semplice per nome file (rimuove caratteri non validi su Windows)
function ConvertTo-SafeFileToken {
    param([string]$Text)
    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        if ($invalidChars -contains $ch -or $ch -eq ' ') {
            [void]$sb.Append('_')
        }
        else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}

$script:SessionTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeTecnico = ConvertTo-SafeFileToken -Text $script:TecnicoNome
$safeMotivazione = ConvertTo-SafeFileToken -Text $script:MotivazioneSessione

$script:LogFileName = "{0}_{1}_{2}.txt" -f $safeTecnico, $script:SessionTimestamp, $safeMotivazione
$script:LogFilePath = Join-Path -Path $TXTPath -ChildPath $script:LogFileName

#endregion

#region ============================ MOTORE DI LOGGING ============================

<#
    Filosofia di logging:
    - Il file di log è uno STORICO NARRATIVO: ogni scelta di menu, ogni input, ogni esito
      viene scritto in ordine cronologico, con separatori, così chi legge il file (anche
      senza conoscere il ticket originale) può ricostruire l'intera dinamica dell'intervento.
    - Le operazioni di sola LETTURA vengono tracciate con una riga sintetica.
    - Le operazioni di MODIFICA vengono tracciate per intero: scelta menu, input, stato
      PRIMA, stato DOPO, motivazione specifica, esito.
#>

function Write-SessionLog {
    param(
        [Parameter(Mandatory = $true)][string]$Testo,
        [switch]$Separatore
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($Separatore) {
        Add-Content -Path $script:LogFilePath -Value "----------------------------------------------------------------------"
    }
    Add-Content -Path $script:LogFilePath -Value "[$ts] $Testo"
}

function Write-LogHeader {
    Write-SessionLog -Testo "=== INIZIO SESSIONE ===" -Separatore
    Write-SessionLog -Testo "Tecnico esecutore : $($script:TecnicoNome)"
    Write-SessionLog -Testo "DC target         : $DCServer"
    Write-SessionLog -Testo "OU root           : $OURoot"
    Write-SessionLog -Testo "Motivazione sessione: $($script:MotivazioneSessione)"
    Write-SessionLog -Testo "========================" -Separatore
}

# Traccia una scelta di menu (sempre, sia per letture che modifiche)
function Write-LogScelta {
    param(
        [string]$Percorso,   # es. "1.3.1"
        [string]$Descrizione # es. "Sblocca utente"
    )
    Write-SessionLog -Testo "SCELTA MENU [$Percorso] -> $Descrizione" -Separatore
}

# Traccia un input libero fornito dal tecnico
function Write-LogInput {
    param(
        [string]$Etichetta,
        [string]$Valore
    )
    Write-SessionLog -Testo "INPUT: $Etichetta = '$Valore'"
}

# Traccia una operazione di sola visualizzazione (riga sintetica, NO dettaglio risultato)
function Write-LogVisualizzazione {
    param(
        [string]$Oggetto  # es. "utente", "gpo", "OU", "gruppo", "task"
    )
    Write-SessionLog -Testo "RICHIESTA VISUALIZZAZIONE ($Oggetto) da parte di $($script:TecnicoNome)"
}

# Traccia una operazione di MODIFICA per intero: stato prima/dopo, motivazione, esito
function Write-LogModifica {
    param(
        [string]$Azione,         # es. "Sblocco utente"
        [string]$Target,         # es. "SamAccountName: c.michelini"
        [string]$StatoPrima,
        [string]$StatoDopo,
        [string]$Motivazione,
        [string]$Esito           # "RIUSCITA" / "FALLITA"
    )
    Write-SessionLog -Testo "MODIFICA: $Azione"
    Write-SessionLog -Testo "  Target       : $Target"
    Write-SessionLog -Testo "  Stato PRIMA  : $StatoPrima"
    Write-SessionLog -Testo "  Stato DOPO   : $StatoDopo"
    Write-SessionLog -Testo "  Motivazione  : $Motivazione"
    Write-SessionLog -Testo "  ESITO        : $Esito"
}

function Write-LogErrore {
    param([string]$Contesto, [string]$Messaggio)
    Write-SessionLog -Testo "ERRORE in '$Contesto': $Messaggio"
}

#endregion

#region ============================ HELPER UI ============================

function Read-ConfermaSiNo {
    param([string]$Prompt = "Confermare l'operazione?")
    do {
        $val = Read-Host -Prompt "$Prompt (Y/N/0 per annullare)"
        $val = $val.Trim().ToUpper()
        if ($val -eq '0' -or $val -eq 'ANNULLA') { return $null }
    } while ($val -ne 'Y' -and $val -ne 'N')
    return ($val -eq 'Y')
}

function Read-InputObbligatorio {
    param([string]$Prompt)
    do {
        $val = Read-Host -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Host "  -> Campo obbligatorio, non può essere vuoto." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($val))
    return $val.Trim()
}

function Read-MotivazioneOperazione {
    return Read-InputObbligatorio -Prompt "Inserire motivazione per questa operazione (es. numero ticket o descrizione)"
}

function Show-Esito {
    param([bool]$Successo, [string]$MessaggioOk = "Operazione riuscita.", [string]$MessaggioKo = "Operazione fallita.")
    if ($Successo) {
        Write-Host "[OK] $MessaggioOk" -ForegroundColor Green
    }
    else {
        Write-Host "[ERRORE] $MessaggioKo" -ForegroundColor Red
    }
}

function Export-RisultatoTxt {
    param(
        [string]$Prefisso,
        [string[]]$Righe
    )
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = "{0}_{1}.txt" -f (ConvertTo-SafeFileToken -Text $Prefisso), $ts
    $filePath = Join-Path -Path $TXTPath -ChildPath $fileName
    try {
        $Righe | Out-File -FilePath $filePath -Encoding UTF8
        return $true, $filePath
    }
    catch {
        return $false, $_.Exception.Message
    }
}

function Read-ReturnPause {
    Write-Host ""
    Read-Host "Premere ENTER per tornare al menu precedente"
}

# --- Sentinella di annullamento universale ---
# Qualsiasi prompt di testo libero, se il tecnico digita "0" o "annulla", interrompe
# l'operazione corrente e fa risalire il controllo alla funzione chiamante.
function Test-Annulla {
    param([string]$Valore)
    return ($Valore.Trim() -eq '0' -or $Valore.Trim().ToUpper() -eq 'ANNULLA')
}

function Read-InputAnnullabile {
    param([string]$Prompt)
    do {
        $val = Read-Host -Prompt "$Prompt (0 per annullare)"
        if (Test-Annulla -Valore $val) { return $null }
        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Host "  -> Campo obbligatorio, non puo' essere vuoto." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($val))
    return $val.Trim()
}

# --- Password conforme ai criteri di dominio, richiesta in loop senza reset del contesto ---
function Read-PasswordConforme {
    param([string]$Prompt = "Inserire password")
    while ($true) {
        $pwd1 = Read-Host -Prompt "$Prompt (0 per annullare)" -AsSecureString
        $ptr = [IntPtr]::Zero
        try {
            $ptr = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($pwd1)
            $plainCheck = [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
            if (Test-Annulla -Valore $plainCheck) { return $null }
        }
        finally {
            if ($ptr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)
            }
        }
        return $pwd1
    }
}

function Invoke-PasswordConCriteriRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Azione,  # scriptblock che accetta $pwd e prova l'operazione, deve fare throw se fallisce
        [string]$Prompt = "Inserire password"
    )
    while ($true) {
        $pwd = Read-PasswordConforme -Prompt $Prompt
        if ($null -eq $pwd) { return $false }
        try {
            & $Azione $pwd
            return $true
        }
        catch {
            if ($_.Exception.Message -match 'password does not meet|complexity|length|history') {
                Write-Host "[ERRORE] La password non soddisfa i criteri di complessita'/lunghezza/storico del dominio." -ForegroundColor Red
                Write-Host "Riprovare con una password diversa." -ForegroundColor Yellow
                continue
            }
            else {
                throw
            }
        }
    }
}

# --- Albero OU con cache di sessione e invalidazione manuale ---
$script:OUTreeCache = $null

function Get-OUTree {
    param([switch]$ForceRefresh)
    if ($script:OUTreeCache -and -not $ForceRefresh) {
        return $script:OUTreeCache
    }
    try {
        $ous = Get-ADOrganizationalUnit -SearchBase $OURoot -Filter * -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop |
            Select-Object Name, DistinguishedName
    }
    catch {
        Write-Host "[ERRORE] Impossibile recuperare l'elenco OU: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
    # Include esplicitamente la root: permette di usarla come OU padre anche se SearchBase
    # non la restituisce tra i risultati della ricerca subtree.
    if (-not ($ous | Where-Object { $_.DistinguishedName -eq $OURoot })) {
        try {
            $rootOU = Get-ADOrganizationalUnit -Identity $OURoot -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop |
                Select-Object Name, DistinguishedName
            $ous = @($rootOU) + @($ous)
        }
        catch {
            Write-Host "[ERRORE] Impossibile recuperare la OU root: $($_.Exception.Message)" -ForegroundColor Red
            return @()
        }
    }
    $script:OUTreeCache = @($ous | Sort-Object DistinguishedName -Unique)
    return $script:OUTreeCache
}

function Reset-OUTreeCache {
    $script:OUTreeCache = $null
}

function Get-ParentDistinguishedName {
    param([string]$DistinguishedName)
    # Rimuove il primo RDN rispettando le virgole con escape nel Distinguished Name.
    return ($DistinguishedName -replace '^(?:\\.|[^,])+,' , '')
}

function Show-OUTree {
    param([switch]$ForceRefresh)
    $tree = Get-OUTree -ForceRefresh:$ForceRefresh
    if (-not $tree -or $tree.Count -eq 0) {
        Write-Host "(Nessuna OU trovata sotto $OURoot)" -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "Struttura OU disponibile:" -ForegroundColor Cyan

    $figliPerPadre = @{}
    foreach ($ou in $tree) {
        if ($ou.DistinguishedName -eq $OURoot) { continue }
        $padre = Get-ParentDistinguishedName -DistinguishedName $ou.DistinguishedName
        $chiavePadre = $padre.ToLowerInvariant()
        if (-not $figliPerPadre.ContainsKey($chiavePadre)) { $figliPerPadre[$chiavePadre] = @() }
        $figliPerPadre[$chiavePadre] += $ou
    }

    function Show-OUFiglie {
        param([string]$DNPadre, [int]$Livello)
        $chiavePadre = $DNPadre.ToLowerInvariant()
        if (-not $figliPerPadre.ContainsKey($chiavePadre)) { return }
        foreach ($figlia in ($figliPerPadre[$chiavePadre] | Sort-Object Name, DistinguishedName)) {
            $indent = '  ' * $Livello
            Write-Host "$indent- $($figlia.Name)"
            Show-OUFiglie -DNPadre $figlia.DistinguishedName -Livello ($Livello + 1)
        }
    }

    $rootVisualizzata = $tree | Where-Object { $_.DistinguishedName -eq $OURoot } | Select-Object -First 1
    if ($rootVisualizzata) { Write-Host "- $($rootVisualizzata.Name)" }
    else { Write-Host "- $OURoot" }
    Show-OUFiglie -DNPadre $OURoot -Livello 1
    Write-Host ""
}

# --- Selezione assistita di una OU: mostra l'albero, chiede il nome, risolve il DN, chiede conferma ---
function Select-OUByName {
    param(
        [string]$Prompt = "Selezionare la OU",
        [switch]$ForceRefresh
    )
    Show-OUTree -ForceRefresh:$ForceRefresh
    $tree = Get-OUTree
    $ouScelta = Select-CandidatoAssistito -Candidati $tree -Prompt $Prompt `
        -GetNome { param($ou) $ou.Name } `
        -GetDettaglio { param($ou) $ou.DistinguishedName }
    if ($null -eq $ouScelta) { return $null }
    return $ouScelta.DistinguishedName
}
#endregion

#region ============================ 1. GESTIONE UTENTI ============================

function Get-UtenteInfoDisplay {
    param($Utente)
    $lines = @()
    $lines += "DisplayName     : $($Utente.DisplayName)"
    $lines += "SamAccountName  : $($Utente.SamAccountName)"
    $lines += "DistinguishedName: $($Utente.DistinguishedName)"
    $lines += "Enabled         : $($Utente.Enabled)"
    $lines += "LockedOut       : $($Utente.LockedOut)"
    $lines += "PasswordLastSet : $($Utente.PasswordLastSet)"
    $lines += "LastBadPasswordAttempt : $($Utente.LastBadPasswordAttempt)"
    $lines += "BadLogonCount   : $($Utente.BadLogonCount)"
    $lines += "EmailAddress    : $($Utente.EmailAddress)"
    $lines += "LastLogonDate   : $($Utente.LastLogonDate)"
    $lines += "whenCreated     : $($Utente.whenCreated)"
    $lines += "whenChanged     : $($Utente.whenChanged)"
    return $lines
}

function Find-ADUserInRoot {
    param([string]$Identity)
    $props = 'DisplayName','SamAccountName','DistinguishedName','Enabled','LockedOut','PasswordLastSet',
             'LastBadPasswordAttempt','BadLogonCount','EmailAddress','LastLogonDate','whenCreated','whenChanged',
             'GivenName','Surname','UserPrincipalName'
    try {
        # Tenta ricerca per SamAccountName, poi per UserPrincipalName/Name generico
        $filter = "SamAccountName -eq '$Identity' -or UserPrincipalName -eq '$Identity' -or Name -eq '$Identity'"
        $u = Get-ADUser -Filter $filter -SearchBase $OURoot -Server $DCServer -Credential $script:ADCredential -Properties $props -ErrorAction Stop
        if ($u -is [array]) { return $u[0] }
        return $u
    }
    catch {
        Write-LogErrore -Contesto "Find-ADUserInRoot" -Messaggio $_.Exception.Message
        return $null
    }
}

function Show-MenuAnalisiUtente {
    Write-LogScelta -Percorso "1" -Descrizione "Analisi utente (menu)"

    $menuIniziale = @"
Cosa si desidera fare?
  1) Cercare utente esistente
  2) Creare nuovo utente
  0) Torna al menu principale
"@
    Write-Host $menuIniziale
    $sceltaIniziale = Read-Host "Selezionare un'opzione"

    switch ($sceltaIniziale) {
        '1' { Invoke-RicercaEAzioniUtente }
        '2' { Invoke-CreazioneUtente }
        '0' { return }
        default { Write-Host "Opzione non valida." -ForegroundColor Yellow; Read-ReturnPause }
    }
}

function Invoke-RicercaEAzioniUtente {
    Write-LogScelta -Percorso "1.1" -Descrizione "Ricerca utente esistente"
    $identity = Read-InputAnnullabile -Prompt "Inserire nome utente (ES: c.michelini oppure m.rossi@hyperleonet.it)"
    if ($null -eq $identity) { return }
    Write-LogInput -Etichetta "Nome utente ricercato" -Valore $identity

    $utente = Find-ADUserInRoot -Identity $identity
    if (-not $utente) {
        Write-Host "[NOT FOUND] Utente inesistente nella OU root indicata." -ForegroundColor Yellow
        Write-SessionLog -Testo "RISULTATO RICERCA UTENTE '$identity': NON TROVATO"
        Read-ReturnPause
        return
    }

    Write-LogVisualizzazione -Oggetto "utente ($($utente.SamAccountName))"
    Write-Host ""
    Get-UtenteInfoDisplay -Utente $utente | ForEach-Object { Write-Host $_ }
    Write-Host ""

    $menuAzioni = @"
Cosa si desidera fare?
  1) Sblocca utente
  2) Abilita utente e cambio password
  3) Disabilita utente
  4) Dismettere utente (disabilita + sposta OU)
  5) Modifica appartenenza gruppi
  6) Modifica dati utente (email, nome, displayname...)
  7) Sposta utente in altra OU
  0) Torna al menu principale
"@
    Write-Host $menuAzioni
    $scelta = Read-Host "Selezionare un'opzione"

    switch ($scelta) {
        '1' { Invoke-SbloccaUtente -Utente $utente }
        '2' { Invoke-AbilitaUtenteCambioPwd -Utente $utente }
        '3' { Invoke-DisabilitaUtente -Utente $utente }
        '4' { Invoke-DismettiUtente -Utente $utente }
        '5' { Invoke-ModificaGruppiUtente -Utente $utente }
        '6' { Invoke-ModificaDatiUtente -Utente $utente }
        '7' { Invoke-SpostaUtenteOU -Utente $utente }
        '0' { return }
        default { Write-Host "Opzione non valida." -ForegroundColor Yellow }
    }
    Read-ReturnPause
}

function Invoke-SbloccaUtente {
    param($Utente)
    Write-LogScelta -Percorso "1.3.1" -Descrizione "Sblocca utente"

    $fresh = Find-ADUserInRoot -Identity $Utente.SamAccountName
    if (-not $fresh.LockedOut) {
        Write-Host "[INFO] L'utente non risulta bloccato. Nessuna modifica eseguita." -ForegroundColor Yellow
        Write-SessionLog -Testo "VERIFICA: utente $($fresh.SamAccountName) NON risulta bloccato (LockedOut=False). Nessuna modifica eseguita."
        return
    }

    Write-Host "Stato attuale: LockedOut=$($fresh.LockedOut), BadLogonCount=$($fresh.BadLogonCount), LastBadPasswordAttempt=$($fresh.LastBadPasswordAttempt)"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare lo sblocco dell'utente $($fresh.SamAccountName)?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (sblocco utente $($fresh.SamAccountName))"
        return
    }

    try {
        Unlock-ADAccount -Identity $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Utente sbloccato correttamente."
        Write-LogModifica -Azione "Sblocco utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "LockedOut=True" -StatoDopo "LockedOut=False" -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore durante lo sblocco: $($_.Exception.Message)"
        Write-LogModifica -Azione "Sblocco utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "LockedOut=True" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-AbilitaUtenteCambioPwd {
    param($Utente)
    Write-LogScelta -Percorso "1.3.2" -Descrizione "Abilita utente + cambio password"

    $fresh = Find-ADUserInRoot -Identity $Utente.SamAccountName
    if ($fresh.Enabled) {
        Write-Host "[ERRORE] L'utente non è disabilitato. Nessuna modifica eseguita." -ForegroundColor Yellow
        Write-SessionLog -Testo "VERIFICA: utente $($fresh.SamAccountName) risulta già ABILITATO. Nessuna modifica eseguita."
        return
    }

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione
    Write-SessionLog -Testo "INPUT: Nuova password = '********' (non registrata per motivi di sicurezza)"

    if (-not (Read-ConfermaSiNo -Prompt "Confermare abilitazione e cambio password per $($fresh.SamAccountName)?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (abilitazione+cambio pwd utente $($fresh.SamAccountName))"
        return
    }

    $operazioneOk = Invoke-PasswordConCriteriRetry -Prompt "Inserire nuova password per $($fresh.SamAccountName)" -Azione {
        param($pwdTentativo)
        Set-ADAccountPassword -Identity $fresh.DistinguishedName -NewPassword $pwdTentativo -Reset -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
    }

    if (-not $operazioneOk) {
        Write-Host "[ANNULLATO] Operazione annullata dal tecnico." -ForegroundColor Yellow
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (password non fornita per $($fresh.SamAccountName))"
        return
    }

    try {
        Enable-ADAccount -Identity $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Utente abilitato e password aggiornata."
        Write-LogModifica -Azione "Abilitazione utente + reset password" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "Enabled=False" -StatoDopo "Enabled=True, password reimpostata (valore non loggato)" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Abilitazione utente + reset password" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "Enabled=False" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-DisabilitaUtente {
    param($Utente)
    Write-LogScelta -Percorso "1.3.3" -Descrizione "Disabilita utente"

    $fresh = Find-ADUserInRoot -Identity $Utente.SamAccountName
    if (-not $fresh.Enabled) {
        Write-Host "[ERRORE] L'utente non è abilitato. Nessuna modifica eseguita." -ForegroundColor Yellow
        Write-SessionLog -Testo "VERIFICA: utente $($fresh.SamAccountName) risulta già DISABILITATO. Nessuna modifica eseguita."
        return
    }

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la disabilitazione di $($fresh.SamAccountName)?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (disabilitazione utente $($fresh.SamAccountName))"
        return
    }

    try {
        Disable-ADAccount -Identity $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Utente disabilitato correttamente."
        Write-LogModifica -Azione "Disabilitazione utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "Enabled=True" -StatoDopo "Enabled=False" -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Disabilitazione utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "Enabled=True" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-DismettiUtente {
    param($Utente)
    Write-LogScelta -Percorso "1.3.4" -Descrizione "Dismissione utente (disabilita + sposta OU)"

    $fresh = Find-ADUserInRoot -Identity $Utente.SamAccountName
    $ouDestinazione = Select-OUByName -Prompt "Selezionare la OU di destinazione (es. Dismessi)"
    if ($null -eq $ouDestinazione) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (selezione OU dismissione utente $($fresh.SamAccountName))"
        return
    }
    Write-LogInput -Etichetta "OU destinazione" -Valore $ouDestinazione

    Write-Host ""
    Write-Host "RIEPILOGO OPERAZIONE:"
    Write-Host "  Utente          : $($fresh.SamAccountName)"
    Write-Host "  Stato attuale   : Enabled=$($fresh.Enabled)"
    Write-Host "  OU attuale      : $($fresh.DistinguishedName)"
    Write-Host "  OU destinazione : $ouDestinazione"
    Write-Host "  Azioni previste : disabilitazione + spostamento OU"
    Write-Host ""

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la dismissione dell'utente $($fresh.SamAccountName)?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (dismissione utente $($fresh.SamAccountName))"
        return
    }

    $stato_prima = "Enabled=$($fresh.Enabled), OU=$($fresh.DistinguishedName)"
    try {
        Disable-ADAccount -Identity $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Write-SessionLog -Testo "STEP: utente disabilitato con successo (parte 1/2 della dismissione)."
        Move-ADObject -Identity $fresh.DistinguishedName -TargetPath $ouDestinazione -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Write-SessionLog -Testo "STEP: utente spostato con successo nella OU '$ouDestinazione' (parte 2/2 della dismissione)."

        Show-Esito -Successo $true -MessaggioOk "Utente disabilitato e spostato correttamente."
        Write-LogModifica -Azione "Dismissione utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima $stato_prima -StatoDopo "Enabled=False, OU=$ouDestinazione" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore durante la dismissione: $($_.Exception.Message)"
        Write-LogModifica -Azione "Dismissione utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima $stato_prima -StatoDopo "N/D (errore parziale possibile)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-CreazioneUtente {
    Write-LogScelta -Percorso "1.2" -Descrizione "Creazione utente"

    Write-Host "Scegliere modalita' (0 per annullare):"
    Write-Host "  1) Creazione da zero"
    Write-Host "  2) Copia da utente esistente"
    $modo = Read-Host "Selezionare un'opzione"
    if (Test-Annulla -Valore $modo) { return }

    $samNew = Read-InputAnnullabile -Prompt "Inserire SamAccountName nuovo utente (ES: m.rossi)"
    if ($null -eq $samNew) { return }
    Write-LogInput -Etichetta "SamAccountName nuovo utente" -Valore $samNew

    $esistente = Find-ADUserInRoot -Identity $samNew
    if ($esistente) {
        Write-Host "[ERRORE] Utente già esistente. Creazione annullata." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: utente '$samNew' GIA' ESISTENTE. Creazione annullata."
        return
    }

    $givenName = Read-InputAnnullabile -Prompt "Nome (GivenName)"
    if ($null -eq $givenName) { return }
    $surname = Read-InputAnnullabile -Prompt "Cognome (Surname)"
    if ($null -eq $surname) { return }
    $displayName = "$givenName $surname"

    $gruppiDaAggiungere = @()
    $templateSam = $null
    $ouTarget = $null

    if ($modo -eq '2') {
        $templateSam = Read-InputAnnullabile -Prompt "Inserire SamAccountName utente modello"
        if ($null -eq $templateSam) { return }
        Write-LogInput -Etichetta "Utente modello" -Valore $templateSam
        $utenteModello = Find-ADUserInRoot -Identity $templateSam
        if (-not $utenteModello) {
            Write-Host "[ERRORE] Utente modello non trovato." -ForegroundColor Red
            Write-SessionLog -Testo "VERIFICA: utente modello '$templateSam' NON trovato. Creazione annullata."
            return
        }
        $gruppiDaAggiungere = Get-ADPrincipalGroupMembership -Identity $utenteModello.DistinguishedName -Server $DCServer -Credential $script:ADCredential |
            Where-Object { $_.Name -ne 'Domain Users' } | Select-Object -ExpandProperty DistinguishedName
        $ouTarget = $utenteModello.DistinguishedName -replace '^CN=[^,]+,', ''
        Write-Host "Dati copiati da $templateSam. Gruppi che verranno replicati: $($gruppiDaAggiungere.Count)"
        Write-Host "OU calcolata dall'utente modello: $ouTarget"
    }
    else {
        $ouTarget = Select-OUByName -Prompt "Selezionare la OU di destinazione per il nuovo utente"
        if ($null -eq $ouTarget) { return }
    }
    Write-LogInput -Etichetta "Given/Surname/OU" -Valore "$givenName / $surname / $ouTarget"

    Write-Host ""
    Write-Host "RIEPILOGO NUOVO UTENTE:"
    Write-Host "  SamAccountName : $samNew"
    Write-Host "  DisplayName    : $displayName"
    Write-Host "  OU             : $ouTarget"
    Write-Host "  Modalità       : $(if ($modo -eq '2') { "Copia da $templateSam" } else { 'Da zero' })"
    Write-Host ""

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la creazione dell'utente $samNew?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (creazione utente $samNew)"
        return
    }

    Write-SessionLog -Testo "INPUT: Password iniziale = '********' (non registrata per motivi di sicurezza)"

    $nuovoDN = $null
    $creazioneOk = Invoke-PasswordConCriteriRetry -Prompt "Inserire password iniziale per $samNew" -Azione {
        param($pwdTentativo)
        $upn = "$samNew@$((Get-ADDomain -Server $DCServer -Credential $script:ADCredential).DNSRoot)"
        New-ADUser -Name $displayName -SamAccountName $samNew -GivenName $givenName -Surname $surname `
            -DisplayName $displayName -UserPrincipalName $upn -Path $ouTarget `
            -AccountPassword $pwdTentativo -Enabled $true -ChangePasswordAtLogon $true `
            -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
    }

    if (-not $creazioneOk) {
        Write-Host "[ANNULLATO] Creazione utente annullata dal tecnico." -ForegroundColor Yellow
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (password iniziale non fornita per $samNew)"
        return
    }

    try {
        $nuovoDN = (Find-ADUserInRoot -Identity $samNew).DistinguishedName

        if ($gruppiDaAggiungere.Count -gt 0) {
            foreach ($g in $gruppiDaAggiungere) {
                Add-ADGroupMember -Identity $g -Members $nuovoDN -Server $DCServer -Credential $script:ADCredential -ErrorAction SilentlyContinue
            }
            Write-SessionLog -Testo "STEP: aggiunto a $($gruppiDaAggiungere.Count) gruppi copiati dal modello '$templateSam'."
        }

        Show-Esito -Successo $true -MessaggioOk "Utente creato. DistinguishedName: $nuovoDN"
        Write-LogModifica -Azione "Creazione utente" -Target "SamAccountName: $samNew" `
            -StatoPrima "N/A (non esisteva)" -StatoDopo "Creato in $ouTarget, DN=$nuovoDN" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore durante la creazione: $($_.Exception.Message)"
        Write-LogModifica -Azione "Creazione utente" -Target "SamAccountName: $samNew" `
            -StatoPrima "N/A" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-ModificaGruppiUtente {
    param($Utente)
    Write-LogScelta -Percorso "1.3.6" -Descrizione "Modifica appartenenza gruppi"

    $fresh = Find-ADUserInRoot -Identity $Utente.SamAccountName
    $gruppiAttuali = Get-ADPrincipalGroupMembership -Identity $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential |
        Select-Object -ExpandProperty Name
    Write-Host "Gruppi attuali: $($gruppiAttuali -join ', ')"

    Write-Host "1) Aggiungere gruppi   2) Rimuovere gruppi"
    $azione = Read-Host "Selezionare un'opzione"
    $gruppiInput = Read-InputObbligatorio -Prompt "Inserire nome/i gruppo (separati da virgola)"
    Write-LogInput -Etichetta "Gruppi indicati" -Valore $gruppiInput
    $listaGruppi = $gruppiInput -split ',' | ForEach-Object { $_.Trim() }

    $gruppiValidi = @()
    foreach ($g in $listaGruppi) {
        try {
            $gObj = Get-ADGroup -Identity $g -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
            $gruppiValidi += $gObj
        }
        catch {
            Write-Host "[AVVISO] Gruppo '$g' non trovato, verrà ignorato." -ForegroundColor Yellow
            Write-SessionLog -Testo "VERIFICA: gruppo '$g' NON trovato, escluso dall'operazione."
        }
    }

    if ($gruppiValidi.Count -eq 0) {
        Write-Host "[ERRORE] Nessun gruppo valido indicato." -ForegroundColor Red
        return
    }

    $azioneTesto = if ($azione -eq '1') { 'AGGIUNTA' } else { 'RIMOZIONE' }
    Write-Host ""
    Write-Host "Situazione attuale: $($gruppiAttuali -join ', ')"
    Write-Host "Operazione prevista: $azioneTesto di [$($gruppiValidi.Name -join ', ')]"
    Write-Host ""

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare $azioneTesto gruppi per $($fresh.SamAccountName)?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (modifica gruppi $($fresh.SamAccountName))"
        return
    }

    try {
        foreach ($gObj in $gruppiValidi) {
            if ($azione -eq '1') {
                Add-ADGroupMember -Identity $gObj.DistinguishedName -Members $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
            }
            else {
                Remove-ADGroupMember -Identity $gObj.DistinguishedName -Members $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential -Confirm:$false -ErrorAction Stop
            }
        }
        $gruppiDopo = Get-ADPrincipalGroupMembership -Identity $fresh.DistinguishedName -Server $DCServer -Credential $script:ADCredential | Select-Object -ExpandProperty Name
        Show-Esito -Successo $true -MessaggioOk "$azioneTesto completata."
        Write-LogModifica -Azione "$azioneTesto gruppi" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "Gruppi: $($gruppiAttuali -join ', ')" -StatoDopo "Gruppi: $($gruppiDopo -join ', ')" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "$azioneTesto gruppi" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima "Gruppi: $($gruppiAttuali -join ', ')" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-ModificaDatiUtente {
    param($Utente)
    Write-LogScelta -Percorso "1.3.7" -Descrizione "Modifica dati utente"

    $fresh = Find-ADUserInRoot -Identity $Utente.SamAccountName
    Write-Host "Dati attuali:"
    Write-Host "  DisplayName : $($fresh.DisplayName)"
    Write-Host "  GivenName   : $($fresh.GivenName)"
    Write-Host "  Surname     : $($fresh.Surname)"
    Write-Host "  EmailAddress: $($fresh.EmailAddress)"
    Write-Host ""

    $nuovoDisplayName = Read-Host "Nuovo DisplayName (ENTER per non modificare)"
    $nuovaEmail = Read-Host "Nuova EmailAddress (ENTER per non modificare)"
    Write-LogInput -Etichetta "Nuovo DisplayName / Email" -Valore "$nuovoDisplayName / $nuovaEmail"

    $params = @{}
    $statoPrima = "DisplayName=$($fresh.DisplayName), Email=$($fresh.EmailAddress)"
    if (-not [string]::IsNullOrWhiteSpace($nuovoDisplayName)) { $params['DisplayName'] = $nuovoDisplayName }
    if (-not [string]::IsNullOrWhiteSpace($nuovaEmail)) { $params['EmailAddress'] = $nuovaEmail }

    if ($params.Count -eq 0) {
        Write-Host "[INFO] Nessun dato modificato." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "RIEPILOGO: $statoPrima  -->  DisplayName=$nuovoDisplayName, Email=$nuovaEmail"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la modifica dati per $($fresh.SamAccountName)?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (modifica dati $($fresh.SamAccountName))"
        return
    }

    try {
        Set-ADUser -Identity $fresh.DistinguishedName @params -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Dati aggiornati."
        Write-LogModifica -Azione "Modifica dati utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima $statoPrima -StatoDopo "DisplayName=$nuovoDisplayName, Email=$nuovaEmail" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Modifica dati utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima $statoPrima -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-SpostaUtenteOU {
    param($Utente)
    Write-LogScelta -Percorso "1.3.8" -Descrizione "Sposta utente in OU"

    $fresh = Find-ADUserInRoot -Identity $Utente.SamAccountName
    Write-Host "OU attuale: $($fresh.DistinguishedName)"
    $ouDest = Select-OUByName -Prompt "Selezionare la OU di destinazione"
    if ($null -eq $ouDest) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (selezione OU spostamento utente $($fresh.SamAccountName))"
        return
    }
    Write-LogInput -Etichetta "OU destinazione" -Valore $ouDest

    Write-Host "OU attuale: $($fresh.DistinguishedName)"
    Write-Host "OU prevista: $ouDest"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare lo spostamento di $($fresh.SamAccountName)?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (spostamento OU $($fresh.SamAccountName))"
        return
    }

    $statoPrima = $fresh.DistinguishedName
    try {
        Move-ADObject -Identity $fresh.DistinguishedName -TargetPath $ouDest -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Utente spostato."
        Write-LogModifica -Azione "Spostamento OU utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima $statoPrima -StatoDopo $ouDest -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Spostamento OU utente" -Target "SamAccountName: $($fresh.SamAccountName)" `
            -StatoPrima $statoPrima -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

#endregion

#region ============================ 2. GESTIONE OU ============================

function Menu-OperaOU {
    Write-LogScelta -Percorso "2" -Descrizione "Operare su OU (menu)"

    $menuIniziale = @"
Cosa si desidera fare?
  1) Cercare/analizzare una OU esistente
  2) Creare una nuova OU
  3) Spostare una OU
  4) Collegare/rimuovere una GPO a/da una OU
  0) Torna al menu principale
"@
    Write-Host $menuIniziale
    $sceltaIniziale = Read-Host "Selezionare un'opzione"

    switch ($sceltaIniziale) {
        '1' { Invoke-AnalisiOU }
        '2' { Invoke-CreaOU }
        '3' { Invoke-SpostaOUStandalone }
        '4' { Invoke-LinkPolicyOU }
        '0' { return }
        default { Write-Host "Opzione non valida." -ForegroundColor Yellow; Read-ReturnPause }
    }
}

function Invoke-AnalisiOU {
    Write-LogScelta -Percorso "2.1" -Descrizione "Analisi OU esistente"

    $dnScelto = Select-OUByName -Prompt "Selezionare la OU da analizzare"
    if ($null -eq $dnScelto) { return }

    $ou = $null
    try {
        $ou = Get-ADOrganizationalUnit -Identity $dnScelto -Server $DCServer -Credential $script:ADCredential -Properties Description -ErrorAction Stop
    }
    catch { $ou = $null }

    if (-not $ou) {
        Write-Host "[NOT FOUND] OU inesistente." -ForegroundColor Yellow
        Write-SessionLog -Testo "RISULTATO RICERCA OU '$dnScelto': NON TROVATA"
        Read-ReturnPause
        return
    }

    Write-LogVisualizzazione -Oggetto "OU ($($ou.DistinguishedName))"
    $ouPadre = $ou.DistinguishedName -replace '^OU=[^,]+,', ''
    $oggettiContenuti = (Get-ADObject -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter * -Server $DCServer -Credential $script:ADCredential).Count
    $gpoLinks = $ou.LinkedGroupPolicyObjects

    Write-Host ""
    Write-Host "Nome              : $($ou.Name)"
    Write-Host "DistinguishedName : $($ou.DistinguishedName)"
    Write-Host "Descrizione       : $($ou.Description)"
    Write-Host "OU padre          : $ouPadre"
    Write-Host "Oggetti contenuti : $oggettiContenuti"
    Write-Host "GPO collegate     : $(if ($gpoLinks) { $gpoLinks.Count } else { 0 })"
    Write-Host ""

    Read-ReturnPause
}

function Invoke-SpostaOUStandalone {
    Write-LogScelta -Percorso "2.3" -Descrizione "Spostamento OU (standalone)"

    $dnOrigine = Select-OUByName -Prompt "Selezionare la OU da spostare"
    if ($null -eq $dnOrigine) { return }

    $ouOrigine = $null
    try { $ouOrigine = Get-ADOrganizationalUnit -Identity $dnOrigine -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop } catch { $ouOrigine = $null }
    if (-not $ouOrigine) {
        Write-Host "[NOT FOUND] OU inesistente." -ForegroundColor Yellow
        Read-ReturnPause
        return
    }

    Invoke-SpostaOU -OU $ouOrigine
    Read-ReturnPause
}

function Invoke-CreaOU {
    Write-LogScelta -Percorso "2.2" -Descrizione "Creazione nuova OU"

    $nomeNuova = Read-InputAnnullabile -Prompt "Nome nuova OU"
    if ($null -eq $nomeNuova) { return }

    $ouPadre = Select-OUByName -Prompt "Selezionare la OU padre (dove verra' creata la nuova OU)"
    if ($null -eq $ouPadre) { return }
    Write-LogInput -Etichetta "Nome nuova OU / OU padre" -Valore "$nomeNuova / $ouPadre"

    $dnPrevisto = "OU=$nomeNuova,$ouPadre"
    $esiste = $null
    try { $esiste = Get-ADOrganizationalUnit -Identity $dnPrevisto -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop } catch { $esiste = $null }

    if ($esiste) {
        Write-Host "[ERRORE] La OU esiste già." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: OU '$dnPrevisto' GIA' ESISTENTE. Creazione annullata."
        Read-ReturnPause
        return
    }

    Write-Host "Riepilogo: verrà creata '$dnPrevisto'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la creazione della OU '$nomeNuova'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (creazione OU $nomeNuova)"
        Read-ReturnPause
        return
    }

    try {
        New-ADOrganizationalUnit -Name $nomeNuova -Path $ouPadre -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Reset-OUTreeCache
        Show-Esito -Successo $true -MessaggioOk "OU creata: $dnPrevisto"
        Write-LogModifica -Azione "Creazione OU" -Target $dnPrevisto -StatoPrima "N/A" -StatoDopo "Creata" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Creazione OU" -Target $dnPrevisto -StatoPrima "N/A" -StatoDopo "N/D (errore)" `
            -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
    Read-ReturnPause
}

function Invoke-SpostaOU {
    param($OU)
    Write-LogScelta -Percorso "2.3" -Descrizione "Spostamento OU"

    $dnOrigine = $OU.DistinguishedName
    if ($dnOrigine -eq $OURoot) {
        Write-Host "[ERRORE] La OU root '$OURoot' non puo' essere spostata." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: tentativo di spostare la OU root '$OURoot' bloccato."
        return
    }

    Write-Host "OU da spostare: $dnOrigine"
    $destinazione = Select-OUByName -Prompt "Selezionare la OU padre di destinazione"
    if ($null -eq $destinazione) { return }
    Write-LogInput -Etichetta "OU destinazione" -Valore $destinazione

    if ($destinazione -eq $dnOrigine -or $destinazione.EndsWith(",$dnOrigine", [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "[ERRORE] Non e' possibile spostare una OU dentro se stessa o una sua discendente." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: destinazione '$destinazione' non valida per spostamento OU '$dnOrigine' (self/descendant)."
        return
    }

    try {
        $OU = Get-ADOrganizationalUnit -Identity $dnOrigine -Server $DCServer -Credential $script:ADCredential `
            -Properties ProtectedFromAccidentalDeletion -ErrorAction Stop
    }
    catch {
        Write-Host "[ERRORE] Impossibile rileggere la OU da spostare: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogErrore -Contesto "Spostamento OU - rilettura origine" -Messaggio $_.Exception.Message
        return
    }

    Write-Host "OU attuale: $dnOrigine"
    Write-Host "Destinazione: $destinazione"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare lo spostamento della OU?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (spostamento OU $($OU.Name))"
        return
    }

    $protezioneDisabilitata = $false
    $spostamentoRiuscito = $false
    $erroreSpostamento = $null
    $erroreRipristinoProtezione = $null
    $statoPrima = $dnOrigine
    try {
        if ($OU.ProtectedFromAccidentalDeletion) {
            Write-Host "[AVVISO] La OU e' protetta dall'eliminazione accidentale." -ForegroundColor Yellow
            if (-not (Read-ConfermaSiNo -Prompt "Disabilitare temporaneamente la protezione per eseguire lo spostamento?")) {
                Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (disabilitazione temporanea protezione OU $($OU.Name))"
                return
            }
            Set-ADOrganizationalUnit -Identity $dnOrigine -ProtectedFromAccidentalDeletion $false -Server $DCServer `
                -Credential $script:ADCredential -ErrorAction Stop
            $protezioneDisabilitata = $true
            Write-SessionLog -Testo "STEP: protezione da eliminazione accidentale disabilitata temporaneamente per OU '$dnOrigine'."
        }

        Move-ADObject -Identity $dnOrigine -TargetPath $destinazione -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        $spostamentoRiuscito = $true
    }
    catch {
        $erroreSpostamento = $_.Exception.Message
    }
    finally {
        if ($protezioneDisabilitata) {
            try {
                $dnDaProteggere = if ($spostamentoRiuscito) { "OU=$($OU.Name),$destinazione" } else { $dnOrigine }
                Set-ADOrganizationalUnit -Identity $dnDaProteggere -ProtectedFromAccidentalDeletion $true -Server $DCServer `
                    -Credential $script:ADCredential -ErrorAction Stop
                Write-SessionLog -Testo "STEP: protezione da eliminazione accidentale ripristinata per OU '$dnDaProteggere'."
            }
            catch {
                $erroreRipristinoProtezione = $_.Exception.Message
            }
        }
    }

    if (-not $spostamentoRiuscito) {
        Show-Esito -Successo $false -MessaggioKo "Errore durante lo spostamento: $erroreSpostamento"
        if ($erroreSpostamento -match 'access.*denied|accesso.*negato') {
            Write-Host "Nota: servono 'Delete Child' o 'Delete Object' sull'OU di origine e 'Create Child'" -ForegroundColor Yellow
            Write-Host "sulla OU di destinazione. Se la protezione era attiva, servono anche permessi per modificarla." -ForegroundColor Yellow
        }
        Write-LogModifica -Azione "Spostamento OU" -Target $OU.Name -StatoPrima $statoPrima `
            -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $erroreSpostamento"
        return
    }

    Reset-OUTreeCache
    if ($erroreRipristinoProtezione) {
        Show-Esito -Successo $false -MessaggioKo "OU spostata, ma la protezione non e' stata ripristinata: $erroreRipristinoProtezione"
        Write-LogModifica -Azione "Spostamento OU" -Target $OU.Name -StatoPrima $statoPrima `
            -StatoDopo "OU=$($OU.Name),$destinazione; protezione NON ripristinata" -Motivazione $motivazione `
            -Esito "RIUSCITA CON AVVISO: $erroreRipristinoProtezione"
        return
    }

    Show-Esito -Successo $true -MessaggioOk "OU spostata."
    Write-LogModifica -Azione "Spostamento OU" -Target $OU.Name -StatoPrima $statoPrima `
        -StatoDopo "OU=$($OU.Name),$destinazione" -Motivazione $motivazione -Esito "RIUSCITA"
}

function Invoke-LinkPolicyOU {
    Write-LogScelta -Percorso "2.4" -Descrizione "Collega/rimuovi policy su OU"

    if (-not $script:GPOModuleAvailable) {
        Write-Host "[ERRORE] Modulo GroupPolicy non disponibile." -ForegroundColor Red
        return
    }

    $dnOU = Select-OUByName -Prompt "Selezionare la OU su cui operare il collegamento"
    if ($null -eq $dnOU) { return }
    try {
        $OU = Get-ADOrganizationalUnit -Identity $dnOU -Server $DCServer -Credential $script:ADCredential `
            -Properties LinkedGroupPolicyObjects -ErrorAction Stop
    }
    catch {
        Write-Host "[ERRORE] OU inesistente o non raggiungibile: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Policy attualmente collegate: $(($OU.LinkedGroupPolicyObjects | Measure-Object).Count)"
    Write-Host "1) Collegare una GPO   2) Rimuovere una GPO"
    $azione = Read-Host "Selezionare un'opzione"
    if ($azione -ne '1' -and $azione -ne '2') {
        Write-Host "Opzione non valida." -ForegroundColor Yellow
        return
    }
    $nomeGPO = Read-InputObbligatorio -Prompt "Nome della GPO"
    Write-LogInput -Etichetta "Nome GPO" -Valore $nomeGPO

    try { $gpo = Get-GPO -Name $nomeGPO -Server $DCServer -ErrorAction Stop }
    catch {
        Write-Host "[ERRORE] GPO inesistente." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: GPO '$nomeGPO' NON esiste. Operazione interrotta."
        return
    }
    $gpo = Select-GPOByName -Prompt "Inserire nome GPO"
    if ($null -eq $gpo) { return }
    $nomeGPO = $gpo.DisplayName
    Write-LogInput -Etichetta "Nome GPO" -Valore $nomeGPO

    $azioneTesto = if ($azione -eq '1') { 'COLLEGAMENTO' } else { 'RIMOZIONE LINK' }
    Write-Host "Situazione prevista: $azioneTesto GPO '$nomeGPO' su OU '$($OU.DistinguishedName)'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare $azioneTesto?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico ($azioneTesto GPO $nomeGPO su OU $($OU.Name))"
        return
    }

    try {
        if ($azione -eq '1') {
            New-GPLink -Name $nomeGPO -Target $OU.DistinguishedName -Server $DCServer -ErrorAction Stop
        }
        else {
            Remove-GPLink -Name $nomeGPO -Target $OU.DistinguishedName -Server $DCServer -ErrorAction Stop
        }
        Show-Esito -Successo $true -MessaggioOk "$azioneTesto completato."
        Write-LogModifica -Azione "$azioneTesto GPO su OU" -Target "GPO=$nomeGPO, OU=$($OU.DistinguishedName)" `
            -StatoPrima "N/D" -StatoDopo "$azioneTesto eseguito" -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "$azioneTesto GPO su OU" -Target "GPO=$nomeGPO, OU=$($OU.DistinguishedName)" `
            -StatoPrima "N/D" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

#endregion

#region ============================ 3. GESTIONE GPO ============================

function Select-GPOByName {
    param([string]$Prompt = "Inserire nome GPO")
    try {
        $gpoDisponibili = @(Get-GPO -All -Server $DCServer -ErrorAction Stop)
    }
    catch {
        Write-Host "[ERRORE] Impossibile recuperare le GPO: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }

    return Select-CandidatoAssistito -Candidati $gpoDisponibili -Prompt $Prompt `
        -GetNome { param($gpo) $gpo.DisplayName } `
        -GetDettaglio { param($gpo) "ID: $($gpo.Id)" }
}

function Menu-OperaGPO {
    Write-LogScelta -Percorso "3" -Descrizione "Operare su policy (GPO) - menu"

    if (-not $script:GPOModuleAvailable) {
        Write-Host "[ERRORE] Modulo GroupPolicy non disponibile su questa macchina." -ForegroundColor Red
        Read-ReturnPause
        return
    }

    $menuIniziale = @"
Cosa si desidera fare?
  1) Cercare/analizzare una GPO esistente
  2) Creare una nuova GPO
  3) Link/Unlink GPO su OU
  4) Visualizzare le GPO collegate a una OU
  5) Modificare ordine applicazione GPO su una OU
  6) Eseguire backup GPO
  7) Forzare aggiornamento GPO (gpupdate remoto)
  0) Torna al menu principale
"@
    Write-Host $menuIniziale
    $sceltaIniziale = Read-Host "Selezionare un'opzione"

    switch ($sceltaIniziale) {
        '1' { Invoke-AnalisiGPO }
        '2' { Invoke-CreaGPO }
        '3' { Invoke-LinkUnlinkGPO }
        '4' { Invoke-VisualizzaGPOPerOU }
        '5' { Invoke-OrdineGPO }
        '6' { Invoke-BackupGPO }
        '7' { Invoke-ForzaGPUpdate }
        '0' { return }
        default { Write-Host "Opzione non valida." -ForegroundColor Yellow; Read-ReturnPause }
    }
}

function Invoke-AnalisiGPO {
    Write-LogScelta -Percorso "3.1" -Descrizione "Analisi GPO esistente"

    $gpo = Select-GPOByName -Prompt "Inserire nome GPO da analizzare"
    if ($null -eq $gpo) { return }
    $nomeGPO = $gpo.DisplayName
    Write-LogInput -Etichetta "Nome GPO ricercata" -Valore $nomeGPO

    if (-not $gpo) {
        Write-Host "[NOT FOUND] GPO inesistente." -ForegroundColor Yellow
        Write-SessionLog -Testo "RISULTATO RICERCA GPO '$nomeGPO': NON TROVATA"
        Read-ReturnPause
        return
    }

    Write-LogVisualizzazione -Oggetto "GPO ($($gpo.DisplayName))"
    Write-Host ""
    Write-Host "Nome        : $($gpo.DisplayName)"
    Write-Host "ID          : $($gpo.Id)"
    Write-Host "Descrizione : $($gpo.Description)"
    Write-Host "Stato       : $($gpo.GpoStatus)"
    Write-Host "Creata il   : $($gpo.CreationTime)"
    Write-Host "Modificata  : $($gpo.ModificationTime)"
    Write-Host ""

    Read-ReturnPause
}

function Invoke-VisualizzaGPOPerOU {
    Write-LogScelta -Percorso "3.3" -Descrizione "Visualizzazione GPO collegate a una OU"

    $dnOU = Select-OUByName -Prompt "Selezionare la OU di cui visualizzare le GPO collegate"
    if ($null -eq $dnOU) { return }

    try {
        $inheritance = Get-GPInheritance -Target $dnOU -Server $DCServer -ErrorAction Stop
    }
    catch {
        Write-Host "[ERRORE] Impossibile leggere le GPO collegate: $($_.Exception.Message)" -ForegroundColor Red
        Read-ReturnPause
        return
    }

    Write-LogVisualizzazione -Oggetto "GPO collegate a OU ($dnOU)"
    Write-Host ""
    Write-Host "GPO collegate a '$dnOU' (ordine di priorita', 1 = massima priorita'):"
    if (-not $inheritance.GpoLinks -or $inheritance.GpoLinks.Count -eq 0) {
        Write-Host "  (nessuna GPO collegata)" -ForegroundColor Yellow
    }
    else {
        $inheritance.GpoLinks | Sort-Object Order | ForEach-Object {
            Write-Host "  [$($_.Order)] $($_.DisplayName)  (Enabled: $($_.Enabled))"
        }
    }
    Write-Host ""
    Read-ReturnPause
}

function Invoke-CreaGPO {
    Write-LogScelta -Percorso "3.2" -Descrizione "Creazione GPO"

    $nome = Read-InputObbligatorio -Prompt "Nome nuova GPO"
    $descrizione = Read-Host "Descrizione (opzionale)"
    Write-LogInput -Etichetta "Nome/Descrizione GPO" -Valore "$nome / $descrizione"

    $esiste = $null
    try { $esiste = Get-GPO -Name $nome -Server $DCServer -ErrorAction Stop } catch { $esiste = $null }
    if ($esiste) {
        Write-Host "[ERRORE] GPO già esistente." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: GPO '$nome' GIA' ESISTENTE. Creazione annullata."
        return
    }

    Write-Host "Riepilogo: verrà creata GPO '$nome'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la creazione della GPO '$nome'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (creazione GPO $nome)"
        return
    }

    try {
        New-GPO -Name $nome -Comment $descrizione -Server $DCServer -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "GPO creata."
        Write-LogModifica -Azione "Creazione GPO" -Target $nome -StatoPrima "N/A" -StatoDopo "Creata" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Creazione GPO" -Target $nome -StatoPrima "N/A" -StatoDopo "N/D (errore)" `
            -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-LinkUnlinkGPO {
    param($GPO)
    Write-LogScelta -Percorso "3.3" -Descrizione "Link/Unlink GPO su OU"

    if ($null -eq $GPO) {
        $nomeGPO = Read-InputAnnullabile -Prompt "Inserire nome GPO"
        if ($null -eq $nomeGPO) { return }
        try { $GPO = Get-GPO -Name $nomeGPO -Server $DCServer -ErrorAction Stop }
        catch {
            Write-Host "[ERRORE] GPO inesistente." -ForegroundColor Red
            Write-SessionLog -Testo "VERIFICA: GPO '$nomeGPO' NON esiste. Operazione interrotta."
            return
        }
    }

    $ouTarget = Select-OUByName -Prompt "Selezionare la OU su cui operare il link"
    if ($null -eq $ouTarget) { return }
    Write-LogInput -Etichetta "OU target" -Valore $ouTarget

    Write-Host "1) Collegare   2) Rimuovere link"
    $azione = Read-Host "Selezionare un'opzione"
    if ($azione -ne '1' -and $azione -ne '2') {
        Write-Host "Opzione non valida." -ForegroundColor Yellow
        return
    }
    $azioneTesto = if ($azione -eq '1') { 'COLLEGAMENTO' } else { 'RIMOZIONE LINK' }

    Write-Host "Previsto: $azioneTesto GPO '$($GPO.DisplayName)' su OU '$ouTarget'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare $azioneTesto?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico ($azioneTesto GPO $($GPO.DisplayName))"
        return
    }

    try {
        if ($azione -eq '1') {
            New-GPLink -Name $GPO.DisplayName -Target $ouTarget -Server $DCServer -ErrorAction Stop
        }
        else {
            Remove-GPLink -Name $GPO.DisplayName -Target $ouTarget -Server $DCServer -ErrorAction Stop
        }
        Show-Esito -Successo $true -MessaggioOk "$azioneTesto completato."
        Write-LogModifica -Azione "$azioneTesto GPO" -Target "GPO=$($GPO.DisplayName), OU=$ouTarget" `
            -StatoPrima "N/D" -StatoDopo "$azioneTesto eseguito" -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "$azioneTesto GPO" -Target "GPO=$($GPO.DisplayName), OU=$ouTarget" `
            -StatoPrima "N/D" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-OrdineGPO {
    Write-LogScelta -Percorso "3.5" -Descrizione "Modifica ordine applicazione GPO"

    $ouTarget = Select-OUByName -Prompt "Selezionare la OU interessata"
    if ($null -eq $ouTarget) { return }
    Write-LogInput -Etichetta "OU target" -Valore $ouTarget

    try {
        $links = Get-GPInheritance -Target $ouTarget -Server $DCServer -ErrorAction Stop
    }
    catch {
        Write-Host "[ERRORE] OU non valida o nessun link presente." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: OU '$ouTarget' non valida per lettura ordine GPO."
        return
    }

    Write-Host "Ordine attuale (dal più prioritario al meno prioritario, Order=1 e' il piu' prioritario):"
    $links.GpoLinks | Sort-Object Order | ForEach-Object { Write-Host "  [$($_.Order)] $($_.DisplayName)" }

    $gpoDaRiordinare = Select-CandidatoAssistito -Candidati @($links.GpoLinks) -Prompt "Inserire nome GPO di cui cambiare l'ordine" `
        -GetNome { param($link) $link.DisplayName } `
        -GetDettaglio { param($link) "Order: $($link.Order)" }
    if ($null -eq $gpoDaRiordinare) { return }
    $nomeGPOSpost = $gpoDaRiordinare.DisplayName
    $nuovoOrdine = Read-InputObbligatorio -Prompt "Nuovo valore Order (numero intero, 1 = massima priorità)"
    Write-LogInput -Etichetta "GPO / Nuovo ordine" -Valore "$nomeGPOSpost / $nuovoOrdine"

    Write-Host "Riepilogo: GPO '$nomeGPOSpost' -> Order=$nuovoOrdine su OU '$ouTarget'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la modifica dell'ordine?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (modifica ordine GPO su $ouTarget)"
        return
    }

    try {
        Set-GPLink -Name $nomeGPOSpost -Target $ouTarget -Order ([int]$nuovoOrdine) -Server $DCServer -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Ordine aggiornato."
        Write-LogModifica -Azione "Modifica ordine GPO" -Target "GPO=$nomeGPOSpost, OU=$ouTarget" `
            -StatoPrima "Ordine precedente non fissato" -StatoDopo "Order=$nuovoOrdine" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Modifica ordine GPO" -Target "GPO=$nomeGPOSpost, OU=$ouTarget" `
            -StatoPrima "N/D" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-BackupGPO {
    param($GPO)
    Write-LogScelta -Percorso "3.6" -Descrizione "Backup GPO"

    if ($null -eq $GPO) {
        $nomeGPO = Read-InputAnnullabile -Prompt "Inserire nome GPO per il backup"
        if ($null -eq $nomeGPO) { return }
        try { $GPO = Get-GPO -Name $nomeGPO -Server $DCServer -ErrorAction Stop }
        catch {
            Write-Host "[ERRORE] GPO inesistente." -ForegroundColor Red
            Write-SessionLog -Testo "VERIFICA: GPO '$nomeGPO' NON esiste. Backup interrotto."
            return
        }
    }

    $percorso = Read-InputObbligatorio -Prompt "Percorso di destinazione per il backup"
    Write-LogInput -Etichetta "Percorso backup" -Valore $percorso

    if (-not (Test-Path -Path $percorso)) {
        Write-Host "[ERRORE] Percorso non valido/non raggiungibile." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: percorso backup '$percorso' NON valido. Operazione interrotta."
        return
    }

    Write-Host "Riepilogo: backup GPO '$($GPO.DisplayName)' verso '$percorso'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare il backup?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (backup GPO $($GPO.DisplayName))"
        return
    }

    try {
        $result = Backup-GPO -Name $GPO.DisplayName -Path $percorso -Server $DCServer -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Backup completato, ID: $($result.Id)"
        Write-LogModifica -Azione "Backup GPO" -Target $GPO.DisplayName -StatoPrima "N/A" `
            -StatoDopo "Backup creato in $percorso (ID: $($result.Id))" -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Backup GPO" -Target $GPO.DisplayName -StatoPrima "N/A" `
            -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-ForzaGPUpdate {
    Write-LogScelta -Percorso "3.7" -Descrizione "Forzare aggiornamento GPO"

    $computerTarget = Read-InputObbligatorio -Prompt "Nome computer o OU interessata"
    Write-LogInput -Etichetta "Target aggiornamento" -Valore $computerTarget

    Write-Host "Riepilogo: gpupdate forzato su '$computerTarget'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare il forzamento aggiornamento GPO?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (gpupdate forzato su $computerTarget)"
        return
    }

    try {
        Invoke-GPUpdate -Computer $computerTarget -Force -RandomDelayInMinutes 0 -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Aggiornamento GPO inviato a $computerTarget."
        Write-LogModifica -Azione "Forza aggiornamento GPO" -Target $computerTarget -StatoPrima "N/A" `
            -StatoDopo "gpupdate /force inviato" -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Forza aggiornamento GPO" -Target $computerTarget -StatoPrima "N/A" `
            -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

#endregion

#region ============================ 4. GESTIONE GRUPPI ============================

function Select-ADGroupByName {
    param([string]$Prompt = "Inserire nome gruppo")
    try {
        $gruppiDisponibili = @(Get-ADGroup -Filter * -SearchBase $OURoot -Server $DCServer -Credential $script:ADCredential `
            -Properties Description, GroupCategory, GroupScope, whenCreated, whenChanged -ErrorAction Stop)
    }
    catch {
        Write-Host "[ERRORE] Impossibile recuperare i gruppi: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }

    return Select-CandidatoAssistito -Candidati $gruppiDisponibili -Prompt $Prompt `
        -GetNome { param($gruppo) $gruppo.Name } `
        -GetDettaglio { param($gruppo) $gruppo.DistinguishedName }
}

function Menu-OperaGruppi {
    Write-LogScelta -Percorso "4" -Descrizione "Operare su gruppi"

    $menu = @"
Cosa si desidera fare?
  1) Analizzare uno o più gruppi
  2) Creare un nuovo gruppo
  3) Modificare i dati del gruppo
  4) Modificare gli utenti del gruppo
  5) Spostare il gruppo di OU
  6) Eliminare un gruppo
  0) Torna al menu principale
"@
    Write-Host $menu
    $scelta = Read-Host "Selezionare un'opzione"

    switch ($scelta) {
        '1' { Invoke-AnalizzaGruppi }
        '2' { Invoke-CreaGruppo }
        '3' { Invoke-ModificaGruppo }
        '4' { Invoke-ModificaMembriGruppo }
        '5' { Invoke-SpostaGruppo }
        '6' { Invoke-EliminaGruppo }
        '0' { return }
        default { Write-Host "Opzione non valida." -ForegroundColor Yellow }
    }
    Read-ReturnPause
}

function Invoke-AnalizzaGruppi {
    Write-LogScelta -Percorso "4.1" -Descrizione "Analisi di uno o più gruppi"

    $input_gruppi = Read-InputObbligatorio -Prompt "Specificare nome/nomi gruppo (separati da virgola)"
    Write-LogInput -Etichetta "Gruppi richiesti" -Valore $input_gruppi
    $nomi = $input_gruppi -split ',' | ForEach-Object { $_.Trim() }

    $trovati = @()
    $nonTrovati = @()
    foreach ($n in $nomi) {
        $g = Select-ADGroupByName -Prompt "Cercare gruppo '$n'"
        if ($g) { $trovati += $g } else { $nonTrovati += $n }
    }

    if ($trovati.Count -eq 0) {
        Write-Host "[NOT FOUND] Nessun gruppo trovato." -ForegroundColor Yellow
        Write-SessionLog -Testo "RISULTATO RICERCA GRUPPI '$input_gruppi': NESSUNO TROVATO"
        return
    }

    Write-LogVisualizzazione -Oggetto "gruppi ($($trovati.Name -join ', '))"
    if ($nonTrovati.Count -gt 0) {
        Write-Host "[AVVISO] Non trovati: $($nonTrovati -join ', ')" -ForegroundColor Yellow
        Write-SessionLog -Testo "AVVISO: gruppi non trovati: $($nonTrovati -join ', ')"
    }

    $righeExport = @()
    foreach ($g in $trovati) {
        $membri = (Get-ADGroupMember -Identity $g.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction SilentlyContinue).Name -join ', '
        $memberOf = (Get-ADPrincipalGroupMembership -Identity $g.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction SilentlyContinue).Name -join ', '
        $blocco = @(
            "Name             : $($g.Name)",
            "DistinguishedName: $($g.DistinguishedName)",
            "Members          : $membri",
            "MemberOf         : $memberOf",
            "Description      : $($g.Description)",
            "whenCreated      : $($g.whenCreated)",
            "whenChanged      : $($g.whenChanged)",
            ""
        )
        $blocco | ForEach-Object { Write-Host $_ }
        $righeExport += $blocco
    }

    if (Read-ConfermaSiNo -Prompt "Si desidera esportare in TXT il risultato di questa ricerca?") {
        $ok, $path = Export-RisultatoTxt -Prefisso "AnalisiGruppi" -Righe $righeExport
        if ($ok) {
            Write-Host "[OK] Esportato in: $path" -ForegroundColor Green
            Write-SessionLog -Testo "EXPORT: risultato analisi gruppi esportato in '$path'"
        }
        else {
            Write-Host "[ERRORE] Esportazione fallita: $path" -ForegroundColor Red
            Write-SessionLog -Testo "EXPORT: FALLITO - $path"
        }
    }
}

function Invoke-CreaGruppo {
    Write-LogScelta -Percorso "4.2" -Descrizione "Creazione nuovo gruppo"

    $nome = Read-InputAnnullabile -Prompt "Nome del gruppo"
    if ($null -eq $nome) { return }
    $descrizione = Read-Host "Descrizione del gruppo (opzionale)"
    $ouDest = Select-OUByName -Prompt "Selezionare la OU di destinazione per il nuovo gruppo"
    if ($null -eq $ouDest) { return }
    Write-LogInput -Etichetta "Nome/Descrizione/OU" -Valore "$nome / $descrizione / $ouDest"

    $esiste = $null
    try { $esiste = Get-ADGroup -Filter "Name -eq '$nome'" -SearchBase $OURoot -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop } catch { $esiste = $null }

    if ($esiste) {
        Write-Host "[ERRORE] Gruppo già esistente." -ForegroundColor Red
        Write-SessionLog -Testo "VERIFICA: gruppo '$nome' GIA' ESISTENTE. Creazione annullata."
        return
    }

    Write-Host "Riepilogo: gruppo '$nome' in '$ouDest'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la creazione del gruppo '$nome'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (creazione gruppo $nome)"
        return
    }

    try {
        New-ADGroup -Name $nome -SamAccountName $nome -GroupCategory Security -GroupScope Global `
            -Path $ouDest -Description $descrizione -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Gruppo creato."
        Write-LogModifica -Azione "Creazione gruppo" -Target $nome -StatoPrima "N/A" -StatoDopo "Creato in $ouDest" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Creazione gruppo" -Target $nome -StatoPrima "N/A" -StatoDopo "N/D (errore)" `
            -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-ModificaGruppo {
    Write-LogScelta -Percorso "4.3" -Descrizione "Modifica dati gruppo"

    $g = Select-ADGroupByName -Prompt "Inserire nome del gruppo"
    if ($null -eq $g) { return }
    $nome = $g.Name
    Write-LogInput -Etichetta "Nome gruppo" -Valore $nome

    Write-Host "Dati attuali: Description=$($g.Description), Scope=$($g.GroupScope), Category=$($g.GroupCategory)"
    $nuovaDescrizione = Read-Host "Nuova descrizione (ENTER per non modificare)"
    Write-LogInput -Etichetta "Nuova descrizione" -Valore $nuovaDescrizione

    if ([string]::IsNullOrWhiteSpace($nuovaDescrizione)) {
        Write-Host "[INFO] Nessuna modifica indicata." -ForegroundColor Yellow
        return
    }

    Write-Host "Riepilogo: Description '$($g.Description)' -> '$nuovaDescrizione'"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la modifica del gruppo '$nome'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (modifica gruppo $nome)"
        return
    }

    try {
        Set-ADGroup -Identity $g.DistinguishedName -Description $nuovaDescrizione -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Gruppo aggiornato."
        Write-LogModifica -Azione "Modifica dati gruppo" -Target $nome -StatoPrima "Description=$($g.Description)" `
            -StatoDopo "Description=$nuovaDescrizione" -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Modifica dati gruppo" -Target $nome -StatoPrima "Description=$($g.Description)" `
            -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-ModificaMembriGruppo {
    Write-LogScelta -Percorso "4.4" -Descrizione "Modifica membri gruppo"

    $g = Select-ADGroupByName -Prompt "Inserire nome del gruppo"
    if ($null -eq $g) { return }
    $nome = $g.Name
    Write-LogInput -Etichetta "Nome gruppo" -Valore $nome

    $membriAttuali = (Get-ADGroupMember -Identity $g.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction SilentlyContinue).Name
    Write-Host "Membri attuali: $($membriAttuali -join ', ')"

    Write-Host "1) Aggiungere utenti   2) Rimuovere utenti"
    $azione = Read-Host "Selezionare un'opzione"
    $inputUtenti = Read-InputObbligatorio -Prompt "Nome/i utente (separati da virgola)"
    Write-LogInput -Etichetta "Utenti indicati" -Valore $inputUtenti
    $listaUtenti = $inputUtenti -split ',' | ForEach-Object { $_.Trim() }

    $utentiValidi = @()
    foreach ($u in $listaUtenti) {
        $uObj = Find-ADUserInRoot -Identity $u
        if ($uObj) { $utentiValidi += $uObj }
        else {
            Write-Host "[AVVISO] Utente '$u' non trovato, verrà ignorato." -ForegroundColor Yellow
            Write-SessionLog -Testo "VERIFICA: utente '$u' NON trovato, escluso dall'operazione."
        }
    }

    if ($utentiValidi.Count -eq 0) {
        Write-Host "[ERRORE] Nessun utente valido." -ForegroundColor Red
        return
    }

    $azioneTesto = if ($azione -eq '1') { 'AGGIUNTA' } else { 'RIMOZIONE' }
    Write-Host "Situazione attuale: $($membriAttuali -join ', ')"
    Write-Host "Operazione prevista: $azioneTesto di [$($utentiValidi.SamAccountName -join ', ')]"

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare $azioneTesto membri del gruppo '$nome'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico ($azioneTesto membri gruppo $nome)"
        return
    }

    try {
        foreach ($uObj in $utentiValidi) {
            if ($azione -eq '1') {
                Add-ADGroupMember -Identity $g.DistinguishedName -Members $uObj.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
            }
            else {
                Remove-ADGroupMember -Identity $g.DistinguishedName -Members $uObj.DistinguishedName -Server $DCServer -Credential $script:ADCredential -Confirm:$false -ErrorAction Stop
            }
        }
        $membriDopo = (Get-ADGroupMember -Identity $g.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction SilentlyContinue).Name
        Show-Esito -Successo $true -MessaggioOk "$azioneTesto completata."
        Write-LogModifica -Azione "$azioneTesto membri gruppo" -Target $nome `
            -StatoPrima "Membri: $($membriAttuali -join ', ')" -StatoDopo "Membri: $($membriDopo -join ', ')" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "$azioneTesto membri gruppo" -Target $nome `
            -StatoPrima "Membri: $($membriAttuali -join ', ')" -StatoDopo "N/D (errore)" `
            -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-SpostaGruppo {
    Write-LogScelta -Percorso "4.5" -Descrizione "Spostamento gruppo di OU"

    $g = Select-ADGroupByName -Prompt "Inserire nome del gruppo"
    if ($null -eq $g) { return }
    $nome = $g.Name
    Write-LogInput -Etichetta "Nome gruppo" -Valore $nome

    Write-Host "OU attuale: $($g.DistinguishedName)"
    $ouDest = Select-OUByName -Prompt "Selezionare la OU di destinazione"
    if ($null -eq $ouDest) { return }
    Write-LogInput -Etichetta "OU destinazione" -Valore $ouDest

    Write-Host "OU attuale: $($g.DistinguishedName)"
    Write-Host "OU prevista: $ouDest"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare lo spostamento del gruppo '$nome'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (spostamento gruppo $nome)"
        return
    }

    $statoPrima = $g.DistinguishedName
    try {
        Move-ADObject -Identity $g.DistinguishedName -TargetPath $ouDest -Server $DCServer -Credential $script:ADCredential -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Gruppo spostato."
        Write-LogModifica -Azione "Spostamento gruppo" -Target $nome -StatoPrima $statoPrima -StatoDopo $ouDest `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Spostamento gruppo" -Target $nome -StatoPrima $statoPrima `
            -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

function Invoke-EliminaGruppo {
    Write-LogScelta -Percorso "4.6" -Descrizione "Eliminazione gruppo"

    $g = Select-ADGroupByName -Prompt "Inserire nome del gruppo"
    if ($null -eq $g) { return }
    $nome = $g.Name
    Write-LogInput -Etichetta "Nome gruppo" -Valore $nome

    $membri = (Get-ADGroupMember -Identity $g.DistinguishedName -Server $DCServer -Credential $script:ADCredential -ErrorAction SilentlyContinue).Name
    Write-Host "ATTENZIONE: eliminazione del gruppo '$nome'"
    Write-Host "DistinguishedName: $($g.DistinguishedName)"
    Write-Host "Descrizione: $($g.Description)"
    Write-Host "Membri attuali: $($membri -join ', ')"

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "CONFERMA ESPLICITA: eliminare definitivamente il gruppo '$nome'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (eliminazione gruppo $nome)"
        return
    }

    try {
        Remove-ADGroup -Identity $g.DistinguishedName -Server $DCServer -Credential $script:ADCredential -Confirm:$false -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Gruppo eliminato."
        Write-LogModifica -Azione "Eliminazione gruppo" -Target $nome `
            -StatoPrima "Esistente (Membri: $($membri -join ', '))" -StatoDopo "Eliminato" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Eliminazione gruppo" -Target $nome `
            -StatoPrima "Esistente" -StatoDopo "N/D (errore)" -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
}

#endregion

#region ============================ 5. TASK SCHEDULATI (SUL DC) ============================

function Menu-TaskSchedulati {
    Write-LogScelta -Percorso "5" -Descrizione "Analisi task schedulati"

    $menu = @"
Cosa si desidera fare?
  1) Visualizzare stato di tutti i task schedulati
  2) Visualizzare dettagli di un task specifico
  3) Abilitare un task
  4) Disabilitare un task
  5) Avviare manualmente un task
  0) Torna al menu principale
"@
    Write-Host $menu
    $scelta = Read-Host "Selezionare un'opzione"

    switch ($scelta) {
        '1' { Invoke-VisualizzaTuttiTask }
        '2' { Invoke-VisualizzaDettaglioTask }
        '3' { Invoke-AbilitaTask }
        '4' { Invoke-DisabilitaTask }
        '5' { Invoke-AvviaTask }
        '0' { return }
        default { Write-Host "Opzione non valida." -ForegroundColor Yellow }
    }
    Read-ReturnPause
}

function Get-TaskCimSession {
    $isIndirizzoIP = $false
    $indirizzoIP = $null
    $isIndirizzoIP = [System.Net.IPAddress]::TryParse($DCServer, [ref]$indirizzoIP)

    try {
        if ($isIndirizzoIP) {
            # WinRM verso un IP richiede TrustedHosts; DCOM evita tale dipendenza.
            $opzioni = New-CimSessionOption -Protocol Dcom
            return New-CimSession -ComputerName $DCServer -Credential $script:ADCredential -SessionOption $opzioni -ErrorAction Stop
        }
        return New-CimSession -ComputerName $DCServer -Credential $script:ADCredential -ErrorAction Stop
    }
    catch {
        Write-Host "[ERRORE] Impossibile stabilire sessione CIM verso $DCServer: $($_.Exception.Message)" -ForegroundColor Red
        if ($isIndirizzoIP) {
            Write-Host "Per un indirizzo IP lo script usa DCOM: verificare RPC/DCOM, firewall e autorizzazioni" -ForegroundColor Yellow
            Write-Host "dell'utenza tecnica sul Domain Controller. In alternativa usare il nome DNS del DC con WinRM configurato." -ForegroundColor Yellow
        }
        else {
            Write-Host "Verificare che WinRM sia abilitato sul DC e che il nome DNS sia risolvibile." -ForegroundColor Yellow
            Write-Host "Se si usa un IP con WinRM, aggiungerlo a TrustedHosts oppure usare il nome DNS del DC." -ForegroundColor Yellow
        }
        return $null
    }
}

function Invoke-VisualizzaTuttiTask {
    Write-LogScelta -Percorso "5.1" -Descrizione "Visualizza stato di tutti i task schedulati"

    $session = Get-TaskCimSession
    if (-not $session) { return }

    try {
        $tasks = Get-ScheduledTask -CimSession $session -ErrorAction Stop
    }
    catch {
        Write-Host "[ERRORE] $($_.Exception.Message)" -ForegroundColor Red
        Remove-CimSession $session
        return
    }

    Write-LogVisualizzazione -Oggetto "elenco task schedulati sul DC ($DCServer)"

    $righeExport = @()
    foreach ($t in $tasks) {
        $info = $t | Get-ScheduledTaskInfo -CimSession $session -ErrorAction SilentlyContinue
        $evidenzia = ""
        if ($t.State -eq 'Disabled') { $evidenzia = " [DISABILITATO]" }
        elseif ($info.LastTaskResult -ne 0) { $evidenzia = " [ULTIMA ESECUZIONE FALLITA]" }
        elseif (-not $info.LastRunTime) { $evidenzia = " [MAI ESEGUITO]" }

        $riga = "Nome: $($t.TaskName) | Stato: $($t.State) | UltimaEsec: $($info.LastRunTime) | ProssimaEsec: $($info.NextRunTime) | RisultatoUltimaEsec: $($info.LastTaskResult) | Account: $($t.Principal.UserId)$evidenzia"
        Write-Host $riga
        $righeExport += $riga
    }
    Remove-CimSession $session

    if (Read-ConfermaSiNo -Prompt "Si desidera esportare in TXT il risultato?") {
        $ok, $path = Export-RisultatoTxt -Prefisso "ElencoTask" -Righe $righeExport
        if ($ok) { Write-Host "[OK] Esportato in: $path" -ForegroundColor Green; Write-SessionLog -Testo "EXPORT: elenco task esportato in '$path'" }
        else { Write-Host "[ERRORE] Esportazione fallita." -ForegroundColor Red; Write-SessionLog -Testo "EXPORT: FALLITO - $path" }
    }
}

function Find-TaskByName {
    param([string]$Nome, $Session)
    try { return Get-ScheduledTask -CimSession $Session -TaskName $Nome -ErrorAction Stop }
    catch { return $null }
}

function Select-TaskByName {
    param($Session, [string]$Prompt = "Inserire nome del task")
    try {
        $taskDisponibili = @(Get-ScheduledTask -CimSession $Session -ErrorAction Stop)
    }
    catch {
        Write-Host "[ERRORE] Impossibile recuperare i task: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }

    return Select-CandidatoAssistito -Candidati $taskDisponibili -Prompt $Prompt `
        -GetNome { param($task) $task.TaskName } `
        -GetDettaglio { param($task) $task.TaskPath }
}

function Invoke-VisualizzaDettaglioTask {
    Write-LogScelta -Percorso "5.2" -Descrizione "Visualizza dettaglio task"

    $session = Get-TaskCimSession
    if (-not $session) { return }
    $task = Select-TaskByName -Session $session
    if ($task) { $nomeTask = $task.TaskName; Write-LogInput -Etichetta "Nome task" -Valore $nomeTask }
    if (-not $task) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA o non eseguibile (selezione task dettaglio)."
        Remove-CimSession $session
        return
    }

    Write-LogVisualizzazione -Oggetto "task ($($task.TaskName))"
    $info = $task | Get-ScheduledTaskInfo -CimSession $session

    $righe = @(
        "Nome            : $($task.TaskName)",
        "Percorso        : $($task.TaskPath)",
        "Stato           : $($task.State)",
        "Account esec.   : $($task.Principal.UserId)",
        "Ultima esecuz.  : $($info.LastRunTime)",
        "Prossima esecuz.: $($info.NextRunTime)",
        "Risultato ultima: $($info.LastTaskResult)",
        "Trigger         : $($task.Triggers | Out-String)",
        "Azioni          : $($task.Actions | Out-String)"
    )
    $righe | ForEach-Object { Write-Host $_ }
    Remove-CimSession $session

    if (Read-ConfermaSiNo -Prompt "Si desidera esportare in TXT il risultato?") {
        $ok, $path = Export-RisultatoTxt -Prefisso "DettaglioTask_$nomeTask" -Righe $righe
        if ($ok) { Write-Host "[OK] Esportato in: $path" -ForegroundColor Green; Write-SessionLog -Testo "EXPORT: dettaglio task '$nomeTask' esportato in '$path'" }
        else { Write-Host "[ERRORE] Esportazione fallita." -ForegroundColor Red; Write-SessionLog -Testo "EXPORT: FALLITO - $path" }
    }
}

function Invoke-AbilitaTask {
    Write-LogScelta -Percorso "5.3" -Descrizione "Abilita task"

    $session = Get-TaskCimSession
    if (-not $session) { return }
    $task = Select-TaskByName -Session $session
    if ($task) { $nomeTask = $task.TaskName; Write-LogInput -Etichetta "Nome task" -Valore $nomeTask }
    if (-not $task) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA o non eseguibile (selezione task abilitazione)."
        Remove-CimSession $session
        return
    }

    if ($task.State -ne 'Disabled') {
        Write-Host "[INFO] Task già abilitato." -ForegroundColor Yellow
        Write-SessionLog -Testo "VERIFICA: task '$nomeTask' risulta GIA' ABILITATO. Nessuna modifica eseguita."
        Remove-CimSession $session
        return
    }

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare l'abilitazione del task '$nomeTask'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (abilitazione task $nomeTask)"
        Remove-CimSession $session
        return
    }

    try {
        Enable-ScheduledTask -CimSession $session -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Task abilitato."
        Write-LogModifica -Azione "Abilitazione task" -Target $nomeTask -StatoPrima "Disabled" -StatoDopo "Ready/Enabled" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Abilitazione task" -Target $nomeTask -StatoPrima "Disabled" -StatoDopo "N/D (errore)" `
            -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
    Remove-CimSession $session
}

function Invoke-DisabilitaTask {
    Write-LogScelta -Percorso "5.4" -Descrizione "Disabilita task"

    $session = Get-TaskCimSession
    if (-not $session) { return }
    $task = Select-TaskByName -Session $session
    if ($task) { $nomeTask = $task.TaskName; Write-LogInput -Etichetta "Nome task" -Valore $nomeTask }
    if (-not $task) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA o non eseguibile (selezione task disabilitazione)."
        Remove-CimSession $session
        return
    }

    if ($task.State -eq 'Disabled') {
        Write-Host "[INFO] Task già disabilitato." -ForegroundColor Yellow
        Write-SessionLog -Testo "VERIFICA: task '$nomeTask' risulta GIA' DISABILITATO. Nessuna modifica eseguita."
        Remove-CimSession $session
        return
    }

    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare la disabilitazione del task '$nomeTask'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (disabilitazione task $nomeTask)"
        Remove-CimSession $session
        return
    }

    try {
        Disable-ScheduledTask -CimSession $session -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Task disabilitato."
        Write-LogModifica -Azione "Disabilitazione task" -Target $nomeTask -StatoPrima "Enabled" -StatoDopo "Disabled" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Disabilitazione task" -Target $nomeTask -StatoPrima "Enabled" -StatoDopo "N/D (errore)" `
            -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
    Remove-CimSession $session
}

function Invoke-AvviaTask {
    Write-LogScelta -Percorso "5.5" -Descrizione "Avvia manualmente task"

    $session = Get-TaskCimSession
    if (-not $session) { return }
    $task = Select-TaskByName -Session $session
    if ($task) { $nomeTask = $task.TaskName; Write-LogInput -Etichetta "Nome task" -Valore $nomeTask }
    if (-not $task) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA o non eseguibile (selezione task avvio)."
        Remove-CimSession $session
        return
    }

    Write-Host "Task trovato: $($task.TaskName) | Stato: $($task.State) | Percorso: $($task.TaskPath)"
    $motivazione = Read-MotivazioneOperazione
    Write-LogInput -Etichetta "Motivazione" -Valore $motivazione

    if (-not (Read-ConfermaSiNo -Prompt "Confermare l'avvio manuale del task '$nomeTask'?")) {
        Write-SessionLog -Testo "OPERAZIONE ANNULLATA dal tecnico (avvio manuale task $nomeTask)"
        Remove-CimSession $session
        return
    }

    try {
        Start-ScheduledTask -CimSession $session -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
        Show-Esito -Successo $true -MessaggioOk "Task avviato manualmente."
        Write-LogModifica -Azione "Avvio manuale task" -Target $nomeTask -StatoPrima "N/A" -StatoDopo "Avvio richiesto manualmente" `
            -Motivazione $motivazione -Esito "RIUSCITA"
    }
    catch {
        Show-Esito -Successo $false -MessaggioKo "Errore: $($_.Exception.Message)"
        Write-LogModifica -Azione "Avvio manuale task" -Target $nomeTask -StatoPrima "N/A" -StatoDopo "N/D (errore)" `
            -Motivazione $motivazione -Esito "FALLITA: $($_.Exception.Message)"
    }
    Remove-CimSession $session
}

#endregion

#region ============================ MENU PRINCIPALE ============================

Write-LogHeader

function Show-MenuPrincipale {
    Clear-Host
    Write-Host "=== AD-Chatbot Tecnico ===" -ForegroundColor Cyan
    Write-Host "Tecnico: $($script:TecnicoNome)  |  DC: $DCServer  |  Motivazione sessione: $($script:MotivazioneSessione)"
    Write-Host ""
    $menu = @"
Cosa si desidera fare?
  1) Analisi utente
  2) Operare su OU
  3) Operare su group policy (GPO)
  4) Analisi/gestione membri di un gruppo
  5) Analisi/gestione task schedulati
  0) Esci
"@
    Write-Host $menu
    return Read-Host "Selezionare un'opzione"
}
 
$continua = $true
while ($continua) {
    $scelta = Show-MenuPrincipale
    switch ($scelta) {
        '1' { Show-MenuAnalisiUtente }
        '2' { Menu-OperaOU }
        '3' { Menu-OperaGPO }
        '4' { Menu-OperaGruppi }
        '5' { Menu-TaskSchedulati }
        '0' { $continua = $false }
        default { Write-Host "Opzione non valida." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}

Write-SessionLog -Testo "=== FINE SESSIONE ===" -Separatore
Write-Host ""
Write-Host "Sessione terminata. Log salvato in: $($script:LogFilePath)" -ForegroundColor Cyan
