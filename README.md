
Camar - pacchetto pronto per GitHub Actions (completo)

Istruzioni rapide:
1) Sul PC (una volta): crea il progetto flutter:
   flutter create controllo_8_rele
   cd controllo_8_rele
2) Sostituisci i files:
   - copia la cartella lib/ dal pacchetto e sovrascrivi
   - copia pubspec.yaml
   - copia .github/workflows/build_apk.yml
   - aggiungi assets/camar_icon.png in assets
   - assicurati che android/app/src/main/AndroidManifest.xml contenga i permessi indicati in AndroidManifest_snippet.txt
3) Commit & push su GitHub (branch main)
4) GitHub Actions compilerà l'APK automaticamente; scarica l'artifact app-release-apk

Funzionalità implementate:
- Multi-board (tabs) con IP configurabile
- 8 relè per scheda (0..7)
- Nomina relè personalizzabile
- Gruppi (più relè per gruppo)
- Timer per relè fino a 120s
- Log eventi persistenti ed esportabili
- Comandi vocali in foreground (premi microfono)
- Modalità Schermo Nero che mantiene l'app attiva (wakelock)
- Invio comandi HTTP: http://IP/leds.cgi?led=X&on  or &off

Note:
- Per wake-word o ascolto in background serve integrazione nativa/Assistente Android.
- Prima esecuzione potrebbe richiedere di concedere permessi (microfono, storage).
