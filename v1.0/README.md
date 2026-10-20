# Dashboard AD v1.0

Applicazione desktop Windows composta da host .NET 8 WinForms/WebView2, interfaccia HTML/CSS/JavaScript e backend PowerShell per Active Directory.

## Struttura

- DesktopHost/: progetto C# e progetto .NET.
- UI/: interfaccia locale.
- Backend/: dispatcher e modulo PowerShell.
- Setup/Credential-Setup.ps1: inizializzazione delle credenziali.
- DashboardAD.config.json: configurazione di esempio.
- Gli script legacy sono in ../legacy e non vengono inclusi nella build.

## Requisiti

- Windows 10/11 o Windows Server supportato.
- .NET 8 SDK per compilazione da sorgente.
- Windows PowerShell 5.1 (powershell.exe), RSAT Active Directory PowerShell e, per le funzioni GPO, modulo GroupPolicy.
- Microsoft Edge WebView2 Runtime.
- Connettività al dominio e diritti AD appropriati per l'account configurato.

## Avvio in sviluppo

Dalla root del repository:

```powershell
dotnet restore .\v1.0\DesktopHost\DashboardAD.Desktop.csproj
dotnet build .\v1.0\DesktopHost\DashboardAD.Desktop.csproj -c Release --no-restore
dotnet run --project .\v1.0\DesktopHost\DashboardAD.Desktop.csproj
```

UI, backend, configurazione e script di setup restano come contenuti esterni necessari all'applicazione. L'eseguibile `DashboardAD.exe` incorpora il runtime .NET e le dipendenze gestite per ridurre i file nella cartella principale. La pubblicazione conserva solo le risorse di localizzazione inglese e italiana.

## Pubblicazione per PC tecnico

Per generare una cartella x64 autonoma rispetto al runtime .NET:

```powershell
dotnet publish .\v1.0\DesktopHost\DashboardAD.Desktop.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\artifacts\DashboardAD-win-x64
```

Copiare l'intera cartella artifacts\DashboardAD-win-x64 sul PC di destinazione, non soltanto l'EXE. WebView2 Runtime, Windows PowerShell 5.1 e i moduli RSAT richiesti restano prerequisiti. Per architetture diverse, pubblicare con il runtime appropriato.

## Credenziali e configurazione

1. Verificare DashboardAD.config.json. I nomi DNS dei DC sono preferiti; gli IP sono fallback opzionali. DNS/Kerberos restano preferibili quando disponibili.
2. Eseguire Setup\Credential-Setup.ps1 in PowerShell con lo stesso account Windows che avvierà l'applicazione.
3. Inserire l'account AD dedicato e con privilegi minimi necessari.
4. Il file CLIXML è protetto dal contesto DPAPI dell'utente Windows e dalla macchina; non copiarlo su altri PC o account.

Il percorso previsto è `C:\ProgramData\DashboardAD\admin-credential.xml`, esterno al repository. La configurazione `%ProgramData%\DashboardAD\Logs\DashboardAD.jsonl` definisce cartella e prefisso dei log: ogni sessione crea un file JSONL dedicato con nome `DashboardAD_<operatore>_<data-ora>.jsonl`, contenente accesso, operazioni e chiusura. I file precedenti restano consultabili nella sezione LOG. Proteggere credenziali e log con ACL appropriate.

## Stato e limiti

Il codice contiene funzionalità per consultazione e ricerca di utenti, gruppi e OU, gestione di utenti e gruppi, operazioni OU, dashboard, lettura GPO e attività pianificate. Le operazioni disponibili dipendono dai moduli installati e dai diritti AD assegnati.

La pubblicazione descritta è una procedura configurata nel progetto, non una build già verificata. Prima dell'uso operativo sono obbligatori una build pulita, test funzionali su oggetti di prova, test di fallback DC e revisione dei permessi. Non considerare v1.0 pronta per la produzione finché questi controlli non sono completati.
