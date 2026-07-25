Release Wrap für Sphaira Connect: Versionierung, Release Notes, Tests, Wiki und Commit. Eine App, ein Repo, eine Plattform (macOS).

## Schritte

1. **Änderungen seit dem letzten Release identifizieren:**
   - `git log --oneline` und `git log --stat` seit dem letzten Release-Commit (Muster `chore: v…`) lesen.
   - `git status` und `git diff` für noch nicht committete Arbeit prüfen.
   - Alle Features, Fixes und Breaking Changes sammeln — jeweils mit der Datei, in der sie stehen.
   - Nichts aufnehmen, was nicht im Code oder im Commit belegt ist.

2. **Versions- und Build-Nummer prüfen:**
   - Aktuellen Stand lesen:
     `grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "Sphaira Connect.xcodeproj/project.pbxproj" | sort -u`
   - Bump entscheiden:
     - neue Funktionen → `MARKETING_VERSION` Minor anheben, `CURRENT_PROJECT_VERSION` zurück auf `1`
     - nur Fixes → `MARKETING_VERSION` unverändert, `CURRENT_PROJECT_VERSION` um 1 erhöhen
     - Breaking Change am USB-Protokoll oder Sitzungsablauf → Major anheben
   - Beide Werte **nur** in `Sphaira Connect.xcodeproj/project.pbxproj` ändern (Single Source of Truth)
     und dabei in **allen** Konfigurationen (Debug und Release) angleichen.
   - Prüfen, dass `MACOSX_DEPLOYMENT_TARGET` noch zu den Release Notes passt.

3. **Release Notes schreiben:**
   - Build-Datei: `release_notes/v{VERSION}/macos_build_{N}.md`
     ({VERSION} = `MARKETING_VERSION` auf drei Stellen normalisiert, {N} = `CURRENT_PROJECT_VERSION`).
   - Kopfdaten: Version, Build, Datum, minimales macOS, Commit-Kurz-Hash.
   - Darunter kurze Zusammenfassung, dann Tabelle mit den Spalten `Typ` (FEATURE/FIX/CHANGE) und `Beschreibung`, alles auf Deutsch.
   - Einträge zum USB-Protokoll oder Sitzungsablauf verweisen zusätzlich auf den Wiki-Artikel (z. B. `protocol/install-session-flow`).
   - `release_notes/v{VERSION}/README.md`: Builds-Tabelle (Build, Datum, Kurzbeschreibung) ergänzen bzw. neu anlegen.
   - `release_notes/README.md`: Versionsübersicht um eine Zeile ergänzen.

4. **Tests laufen lassen (beide Stufen, beide müssen grün sein):**
   - Kernlogik im SwiftPM-Paket:
     `cd SphairaCoreTests && swift test`
   - App-Build in beiden Konfigurationen:
     `xcodebuild -project "Sphaira Connect.xcodeproj" -scheme "Sphaira Connect" -configuration Debug build`
     `xcodebuild -project "Sphaira Connect.xcodeproj" -scheme "Sphaira Connect" -configuration Release build`
   - Bei Fehlern: erst reparieren, dann weiter — kein Wrap auf rotem Stand.

5. **Wiki-Update (PFLICHT — zu jedem Wrap gehört IMMER ein Wiki-Update):**
   - Betroffene Artikel unter `.wiki/articles/*` gegen den **aktuellen** Code aktualisieren: Inhalt, `code_refs`-Pfade, `updated:`-Datum.
   - `code_refs` vor dem Schreiben mit `ls` prüfen — sie müssen auf tatsächlich existierende Dateien zeigen.
   - Neue Features → neuen Artikel anlegen und in `related` beidseitig verlinken.
   - Geänderte oder entfernte Konzepte korrigieren, nicht als `status: current` veraltet stehen lassen.
   - Änderungen am Protokoll oder am Sitzungsablauf zusätzlich gegen `CONTRACT.md` abgleichen.
   - Bei größeren Releases: vollen Freshness-Sweep über alle Kategorien erwägen.

6. **Git Commit:**
   - `git add -A && git commit -m "chore: v{VERSION} (Build {N}) — {Zusammenfassung}"`
   - Nur committen, wenn es Änderungen gibt.
   - **Die Commit-Message enthält keinerlei Claude- oder Anthropic-Signatur:** kein `Co-Authored-By`-Trailer, kein „Generated with"-Hinweis, keine Erwähnung im Betreff oder Rumpf. Der Commit gehört allein dem Benutzer.
