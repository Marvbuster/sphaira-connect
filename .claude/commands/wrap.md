Release wrap for Sphaira Connect: versioning, release notes, tests, wiki and commit. One app, one repo, one platform (macOS).

## Steps

1. **Identify the changes since the last release:**
   - Read `git log --oneline` and `git log --stat` since the last release commit (pattern `chore: v…`).
   - Check `git status` and `git diff` for work that has not been committed yet.
   - Collect all features, fixes and breaking changes — each one together with the file it lives in.
   - Include nothing that is not backed by the code or by a commit.

2. **Check the version and build number:**
   - Read the current state:
     `grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "Sphaira Connect.xcodeproj/project.pbxproj" | sort -u`
   - Decide on the bump:
     - new functionality → raise the `MARKETING_VERSION` minor, reset `CURRENT_PROJECT_VERSION` to `1`
     - fixes only → leave `MARKETING_VERSION` unchanged, increase `CURRENT_PROJECT_VERSION` by 1
     - breaking change to the USB protocol or the session flow → raise the major
   - Change both values **only** in `Sphaira Connect.xcodeproj/project.pbxproj` (single source of truth),
     keeping them in sync across **all** configurations (Debug and Release).
   - Verify that `MACOSX_DEPLOYMENT_TARGET` still matches the release notes.

3. **Write the release notes:**
   - Build file: `release_notes/v{VERSION}/macos_build_{N}.md`
     ({VERSION} = `MARKETING_VERSION` normalised to three components, {N} = `CURRENT_PROJECT_VERSION`).
   - Header data: version, build, date, minimum macOS, short commit hash.
   - Below that a short summary, then a table with the columns `Type` (FEATURE/FIX/CHANGE) and `Description`, all in English.
   - Entries about the USB protocol or the session flow additionally reference the wiki article (e.g. `protocol/install-session-flow`).
   - `release_notes/v{VERSION}/README.md`: extend the builds table (build, date, short description), or create it.
   - `release_notes/README.md`: add one line to the version overview.

4. **Run the tests (both stages, both must be green):**
   - Core logic in the SwiftPM package:
     `cd SphairaCoreTests && swift test`
   - App build in both configurations:
     `xcodebuild -project "Sphaira Connect.xcodeproj" -scheme "Sphaira Connect" -configuration Debug build`
     `xcodebuild -project "Sphaira Connect.xcodeproj" -scheme "Sphaira Connect" -configuration Release build`
   - On failure: fix first, then continue — never wrap on a red state.

5. **Wiki update (MANDATORY — every wrap ALWAYS includes a wiki update):**
   - Bring the affected articles under `.wiki/articles/*` in line with the **current** code: content, `code_refs` paths, `updated:` date.
   - Check `code_refs` with `ls` before writing them — they must point at files that actually exist.
   - New features → create a new article and cross-link it in `related` in both directions.
   - Correct changed or removed concepts; do not leave them stale as `status: current`.
   - Changes to the protocol or the session flow are additionally reconciled against `CONTRACT.md`.
   - For larger releases: consider a full freshness sweep across all categories.

6. **Git commit:**
   - `git add -A && git commit -m "chore: v{VERSION} (build {N}) — {summary}"`
   - Only commit if there are changes.
   - **Commit messages are written in ENGLISH.**
   - **The commit message contains no Claude or Anthropic signature whatsoever:** no `Co-Authored-By` trailer, no "Generated with" note, no mention in the subject or the body. The commit belongs to the user alone.

## status.txt (Pflicht bei jedem Wrap)

Bei JEDEM `/wrap` MUSS eine `status.txt` im Repo-Root geschrieben/überschrieben werden -
**gitignored** (falls nicht vorhanden, `status.txt` in `.gitignore` aufnehmen; **nie
committen**). Sie enthält immer den letzten Stand, damit die nächste Session/der nächste
Mensch ohne Git-Archäologie weitermachen kann:

- `Stand:` Datum + Version
- `Zuletzt gemacht:` was dieser Wrap abgeschlossen hat
- `Offen / Nächste Schritte:` was noch aussteht (TODOs, bewusst Ausgelassenes, WIP)

Bei jedem Wrap überschreiben (nicht anhängen), sodass die Datei stets den aktuellen
Zustand zeigt.
