# Deextend

**Version 0.1.0** · Native macOS-Menüleisten-App für Monitorpausen am USB-C-Hub.

Deextend trennt externe Bildschirme virtuell von deinem Mac. So kannst du am Monitor die Eingangsquelle wechseln und auf dem MacBook weiterarbeiten, während der Hub mit seinen anderen Geräten verbunden bleibt.

## Funktionen

- **Linksklick:** Externe Monitore gemeinsam pausieren oder pausierte Monitore wieder verbinden.
- **Rechtsklick:** Bedienmenü direkt am Menüleistensymbol öffnen und Monitore einzeln steuern.
- **Verbindungshinweis:** Eigener kleiner Popup mit „Wieder verbinden“, wenn ein pausierter Monitor erneut angeschlossen wird. Er erscheint auch, wenn der Monitor dabei virtuell getrennt bleibt, und blendet sich nach 20 Sekunden aus.
- **Deutsch und Englisch:** Automatisch nach macOS-Sprachpräferenz, mit Englisch als Rückfall.
- **Optionaler Autostart:** Unter „Bei Anmeldung starten“ im Bedienmenü.

Die Pausenbalken erscheinen innerhalb des Bildschirmsymbols. Das eingebaute Display wird nie deaktiviert; zum Trennen muss das MacBook geöffnet und sein Display aktiv sein. Beim normalen Beenden verbindet Deextend die selbst pausierten Monitore wieder.

## Voraussetzungen

- Mac mit Apple Silicon und macOS 13 oder neuer.
- Aktives eingebautes Display und mindestens ein externer Monitor.
- Zum Bauen: Xcode oder eine passende Swift-Toolchain; Python 3 für die Tests.

Deextend verwendet private macOS-Displayschnittstellen. Ein macOS-Update kann deren Verhalten ändern. Die App ist nicht notarisiert; der lokale Build wird mit einem auf deinem Mac verfügbaren Entwicklerzertifikat signiert.

## Bauen und starten

```sh
./scripts/build.sh
open build/Deextend.app
```

Das Build-Skript verwendet standardmäßig eine gültige **Apple Development**-Identität aus dem lokalen Schlüsselbund. Bei mehreren Identitäten oder für ein anderes Zertifikat:

```sh
CODE_SIGN_IDENTITY="Name oder SHA-1 deiner Codesigning-Identität" ./scripts/build.sh
```

Verfügbare Identitäten zeigt `security find-identity -v -p codesigning`. Fehlt das Zertifikat, bricht der Build ab; es gibt keinen automatischen Rückfall auf eine Ad-hoc-Signatur. Die Signatur wird vor dem Kopieren in den Projektordner geprüft.

Für den dauerhaften Einsatz die App nach `~/Applications` oder `/Applications` kopieren und nur diese Kopie starten. Eine laufende Version vor dem Ersetzen regulär beenden.

## Bedienung

1. MacBook geöffnet lassen und den externen Monitor anschließen.
2. Links auf das Menüleistensymbol klicken, um den externen Bildschirm virtuell zu trennen.
3. Am Monitor die Eingangsquelle wechseln.
4. Für die Rückkehr die Mac-Quelle wählen und erneut auf das Symbol oder im Hinweis-Popup auf **Wieder verbinden** klicken.

Die Monitorpause gilt pro Monitor, solange die App läuft. Erstmals angeschlossene andere Monitore werden nicht automatisch pausiert. Bei erneuter Aktivierung durch macOS versucht Deextend, pausierte Monitore wieder zu trennen. Nach drei Versuchen innerhalb einer Minute hält die Automatik an. Die Anschluss-Popups benötigen keine macOS-Mitteilungsrechte.

## Grenzen und Wiederherstellung

- Fenster können beim Trennen verschoben werden; ihre ursprünglichen Positionen werden nicht wiederhergestellt.
- Deextend wechselt keine Monitor-Eingangsquellen und schaltet keine anderen Hub-Geräte ab.
- AirPlay, DisplayLink und weitere spezielle Displayadapter sind bisher nicht verifiziert. Getestet wurde ein Apple M3 mit macOS 27.2 und Samsung LU28R55; der Popup nach physischem Abziehen und Einstecken wurde am realen Hub bestätigt. Ein vollständiger Schlaf-/Aufwachzyklus ist noch nicht bestätigt.
- Nach einem Absturz oder erzwungenen Beenden kann ein Monitor getrennt bleiben. Deextend wieder öffnen und **Verbinden** wählen; alternativ den Hub neu verbinden oder macOS neu starten.
- Bei identischen Monitoren ohne eindeutige Seriennummer kann die Zuordnung nach einem Portwechsel mehrdeutig sein.

Gerätenamen und Wiederherstellungsdaten werden lokal in der Preferences-Domäne `de.christianraudzis.deextend.display-cache` gespeichert. Deextend löst das Ziel vor jeder Änderung gegen die aktuelle Displayliste auf und sendet keine gespeicherte Display-ID ungeprüft an macOS.

## Entwicklung

```sh
./scripts/test.sh
```

Die Tests prüfen Display-Schutzregeln, Wiederverbinden, physische Anschlussereignisse bei weiterhin offline bleibenden Displays sowie Übersetzungen und Sprachrückfall. Sie ändern die tatsächliche Displaykonfiguration nicht.

Bei beendeter App sind außerdem Diagnose und ein optionaler Hardwaretest verfügbar:

```sh
# Nur lesen
build/Deextend.app/Contents/MacOS/Deextend --diagnose

# Trennt den ersten aktiven externen Monitor kurz und verbindet ihn wieder
build/Deextend.app/Contents/MacOS/Deextend --verify-toggle
```

Weitere Sprachen werden als `Resources/<Sprachcode>.lproj/Localizable.strings` ergänzt. Dazu die englische Datei kopieren, ihre Werte übersetzen und Schlüssel sowie Formatplatzhalter erhalten. Build und Tests berücksichtigen zusätzliche Sprachverzeichnisse automatisch.

Die Implementierung verwendet CoreGraphics-Konfigurationstransaktionen, dynamisch aufgelöste private SkyLight-Symbole und IOKit-Anschlussereignisse. Hintergrund zu den Schnittstellen: [Apple Display-Konfiguration](https://developer.apple.com/documentation/coregraphics/cgdisplayconfigref) und [MacDisplay](https://github.com/jjongkwann/MacDisplay). Die Implementierung ist eigenständig; fremder App-Quelltext wurde nicht übernommen.

## Lizenz und Änderungen

[MIT-Lizenz](LICENSE) · [Changelog](CHANGELOG.md)
