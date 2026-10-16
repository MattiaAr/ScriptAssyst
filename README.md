# Dashboard AD

Dashboard AD è un'applicazione desktop Windows per operazioni di amministrazione Active Directory, con interfaccia HTML/CSS/JavaScript ospitata da WebView2 e backend PowerShell.

## Versioni e struttura

- **Applicazione corrente:** [v1.0](v1.0/README.md). Sorgenti, host desktop, UI, backend e configurazione di esempio.
- **Legacy:** [legacy](legacy/README.md). Script della versione precedente conservati per consultazione; non fanno parte della build v1.0.

## Build e distribuzione

Segui le istruzioni in [v1.0/README.md](v1.0/README.md) per requisiti, build, pubblicazione e inizializzazione credenziali.

## Sicurezza

- Non inserire password, file credenziali esportati o segreti nel repository.
- Le credenziali runtime sono previste in C:\ProgramData\DashboardAD\admin-credential.xml, fuori dal repository.
- Le directory bin, obj, .vs, publish e artifacts sono output generati ed escluse dal versionamento.
- La configurazione contiene nomi/IP dei controller e percorsi locali, non password.
