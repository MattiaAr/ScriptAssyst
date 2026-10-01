# ScriptAssyst v1.0 — prototipo iniziale

La nuova versione è separata dallo script legacy presente nella root del repository.

## Fase 1 — Prototipo UI
- Interfaccia HTML/CSS/JavaScript con dashboard, navigazione e ricerca su dati fittizi.
- Selettore tra modalità Dashboard e Guidata.
- Nessuna modifica ad Active Directory.

## Fase 2 — Host desktop e backend locale
- Host Windows Forms .NET 8 con WebView2.
- Modulo PowerShell locale e dispatcher con allowlist `status` e `dashboard`.
- Il bridge accetta nomi operazione, non comandi PowerShell arbitrari.

## Avvio
Requisiti: Windows, .NET 8 SDK, PowerShell e Microsoft Edge WebView2 Runtime. Dalla cartella `v1.0/DesktopHost`, eseguire `dotnet restore` e `dotnet run`.

Il progetto è una base tecnica e non è pronto per la produzione. I dati della UI sono fittizi; il backend non si connette ad AD e non esegue scritture. Non sono ancora implementati autenticazione dedicata, audit persistente o profili autorizzativi. I permessi effettivi dovranno dipendere dai diritti Windows/Active Directory dell’operatore.
