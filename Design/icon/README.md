# Icon-Assets

Ebenen für **Icon Composer** (`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`).

| Datei | Inhalt |
|---|---|
| `sphere.svg` | Kugel, radialer Verlauf, Licht nach links oben versetzt |
| `arrow.svg` | Pfeil nach unten, schwacher senkrechter Verlauf |

Beide sind 1024 × 1024, freistehend auf transparentem Grund und teilen dasselbe
Koordinatensystem — übereinandergelegt sitzt der Pfeil mittig auf der Kugel.

**Bewusst nicht enthalten:** Glanzlichter, Schlagschatten, Deckkraft und
Kantenrundung des Symbols. Das legt Icon Composer selbst darüber; wer es hier
schon einbackt, bekommt es doppelt.

## Maße

- Kugel: Mittelpunkt 512/512, Radius 340
- Pfeil: waagerecht mittig, y von 210 bis 830, Schaft 180 breit, Spitze 380 breit

## Umfärben

Jeweils nur die `stop-color`-Werte im `<defs>`-Block ändern. Die Kugel hat vier
Stufen (hell → dunkel), der Pfeil zwei.
