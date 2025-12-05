
Camar - progetto pronto (istruzioni)

ATTENZIONE: per motivi di spazio questa cartella contiene il codice sorgente Flutter (lib/), pubspec.yaml, .github/workflows e assets.
Per ottenere un progetto Flutter completo eseguire sul tuo PC (una sola volta):

1) Apri terminale e crea un progetto Flutter nuovo:
   flutter create camar_project
   cd camar_project

2) Copia i file dal pacchetto estratto sovrascrivendo il contenuto del progetto:
   - sovrascrivi 'lib/' con la cartella lib/ del pacchetto
   - copia 'pubspec.yaml' (sovrascrivi)
   - copia '.github/workflows/build_apk.yml'
   - copia 'assets/camar_icon.png' in assets/

3) Esegui:
   flutter pub get
   flutter build apk --release

Oppure carica l'intero progetto su GitHub e GitHub Actions compilerà automaticamente l'APK (vedi .github/workflows/build_apk.yml).

Note:
- Prima esecuzione potrebbe chiedere permessi e dipendenze native.
- Se vuoi che io generi anche la cartella android/ pronta e completa, dimmelo (posso generare i file base, ma per sicurezza è meglio eseguire 'flutter create' sul PC).
