# Anamnesebogen - Entwicklungsstand und Arbeitsregeln

Diese Datei haelt den aktuellen, vom Nutzer uebergebenen Stand fuer
`anamnesebogen.yaml` fest. Sie ist als verbindlicher Kontext fuer kuenftige
Codex-/Agenten-Laeufe gedacht.

## Projektkontext

- Der Code und die aktuelle Datei `anamnesebogen.yaml` liegen im Repository.
- Aktuell bestaetigter Stand der YAML-Datei: Version `2.2.4`.
- `anamnesebogen.yaml` ist die fachlich massgebliche Konfiguration fuer den
  editierbaren Anamnesebogen.
- Sprache und Schreibweise in der YAML bleiben bewusst ASCII-kompatibel
  (`ae`/`oe`/`ue`/`ss`), sofern nicht ausdruecklich anders gewuenscht.

## Sehr wichtige Arbeitsweise

1. Immer von der zuletzt vom Nutzer bestaetigten vollstaendigen Datei ausgehen.
   Keine Rekonstruktion aus Erinnerung, keine aeltere Version als Basis.
2. Keine Felder, IDs, `show_if`-Regeln oder Abschnitte entfernen, umsortieren
   oder aufraeumen, wenn das nicht ausdruecklich beauftragt wurde.
3. Aenderungen zuerst besprechen, dann umsetzen:
   - Was wird konkret ergaenzt/geaendert/entfernt?
   - Welche bestehenden IDs/Felder bleiben erhalten?
   - Welche `show_if`-Logik wird verwendet?
4. Erst nach ausdruecklichem "go", "bitte umsetzen" o. ae. die Datei aendern
   oder vollstaendig ausgeben.
5. Bei jeder Umsetzung immer die komplette Datei ausgeben, nicht nur Ausschnitte
   oder Diffs.
6. Changelog vollstaendig fortschreiben.
7. Versionsnummer im Kommentarblock und `meta.version` synchron erhoehen.
8. Keine eigenmaechtigen UX-Refactors, Umbenennungen, Typaenderungen,
   Umstrukturierungen oder scheinbar triviale Korrekturen.
9. Fruehere Fehler duerfen sich nicht wiederholen: "Angst vor Zahnarzt" sowie
   Hilfsmittel-Felder wurden versehentlich entfernt und muessen erhalten bleiben.

## Pruefung vor jeder Ausgabe

- YAML-Syntax validieren.
- Alle bestehenden IDs muessen weiterhin vorhanden sein, ausser ihre Entfernung
  wurde ausdruecklich beauftragt.
- `show_if` muss auf tatsaechlich vorhandene IDs verweisen.
- Bedingungswerte muessen zum Feldtyp passen.
- Changelog muss alle Versionen vollstaendig enthalten.
- Keine unbesprochenen Nebenaenderungen.

Empfohlener Ablauf:

1. Aktuelle Datei vollstaendig einlesen.
2. Nur die konkret bestaetigten Aenderungen anwenden.
3. Gegen die Ausgangsversion diffen.
4. Jede zusaetzliche Aenderung, Loeschung oder Typaenderung als Fehler behandeln.
5. YAML parsen/validieren.
6. `show_if` auf ID-Existenz, Feldtyp und Vergleichswert pruefen.
7. Erst danach komplette Datei mit neuer Version und vollstaendigem Changelog
   liefern.

## Technische Erkenntnisse zu `show_if`

- Ein Feld mit `type: yesno` liefert im Renderer offenbar Werte `"yes"` und
  `"no"`.
- Fuer Folgefelder eines `yesno`-Triggerfelds funktioniert:

```yaml
show_if:
  id: trigger_id
  equals: "yes"
```

- Checklist-Items sind kein geeigneter Trigger fuer `equals: "yes"`; sie
  verhalten sich anders als `yesno`-Felder.
- Der Blutverduenner-Block funktionierte erst, nachdem `blutverduenner` von
  einem Checklist-Item in ein eigenstaendiges `yesno`-Feld umgewandelt wurde.
- Beim Multiselect keine spekulativen Operatoren wie `in: [Marcumar]` fuer eine
  Abhaengigkeit verwenden, sofern nicht im Frontend nachgewiesen unterstuetzt.
- Aktueller robuster Ansatz: Alle Blutverduenner-Detailfelder klappen bei
  `blutverduenner = yes` auf, nicht abhaengig von einzelnen
  Multiselect-Auswahlen.

## Aktueller fachlicher Stand v2.2.4

### Allergien

- Optionen ergaenzt: `Insekten`, `Sonstiges`.
- `allergie_details`, `allergieausweis` und `allergischer_schock` erscheinen
  nur, wenn in `allergie_typen` mindestens etwas ausser
  `"Keine Allergie bekannt"` ausgewaehlt ist:

```yaml
any_selected_except: "Keine Allergie bekannt"
```

### Eigene Vorerkrankungen

- Zusaetzlich: `Krebserkrankung`.
- Urogenital/Gynaekologisch: `Transsexualitaet`.
- Psychisch/Neurodivers: `Autismus-Spektrum`.
- Sucht-Checklist: `Rauchen`, `Alkoholkrankheit`, `Drogensucht`.

### Operationen

- `op_keine`: "Bisher keine Operation".
- Zusaetzlich: `Brust-OP`.
- Der Freitext-Abschnitt heisst:
  "auch Details zu oben & weitere Infos (Art, Jahr)".

### Hilfsmittel

- Eingangsfrage: "Ich benutze Hilfsmittel (z. B. Brille)".
- Ergaenzte Auswahl: `Inkontinenzhilfsmittel`.
- Die bestehenden Felder muessen erhalten bleiben:
  - `hilfsmittel_ausreichend`
  - `hilfsmittel_notizen`

### Zaehne

- Die beiden bestehenden Felder fuer "Angst vor Zahnarzt" muessen erhalten
  bleiben:
  - `zaehne_angst_zahnarzt_schlecht`
  - `zaehne_angst_zahnarzt_sehr_schlecht`
- Sie duerfen nicht vorbefuellt werden.
- Eine derzeitige Vorauswahl "nein" ist wahrscheinlich Renderer-/Frontend-
  Verhalten und nicht durch `default` in YAML gesetzt.
- Keine Aenderung daran ohne ausdruecklichen Auftrag.

### Blut / Gerinnung

- Kein Checklist-Abschnitt mehr fuer diese beiden Triggerfelder:
  - `gerinnungsstoerung`: `type: yesno`
  - `blutverduenner`: `type: yesno`
- Bei `blutverduenner = yes` muessen alle folgenden Felder erscheinen:
  - `blutverduenner_praeparat` (`multiselect`)
  - `blutverduenner_komplikation` (`yesno`)
  - `blutverduenner_grund` (`multiselect`)
  - `blutverduenner_details` (mehrzeiliges Textfeld)
- Praeparate aktuell:
  - `Marcumar`
  - `ASS`
  - `Eliquis`
  - `Lixiana`
  - `Xarelto`
  - `Clopidogrel`
  - `Prasugrel`
  - `Sonstiges`
- Gruende aktuell:
  - `Herzrhythmusstoerung / Vorhofflimmern`
  - `kuenstliche Herzklappe`
  - `Thrombose`
  - `Schlaganfall`
  - `Verschlusskrankheit`
  - `Sonstiges`
- Details-Feld:
  - Label: "Details: Praeparat, Ziel-INR"
  - `type: text`
  - `multiline: true`

### Nikotin / Alkohol / Drogen

- Raucher:
  - `type: choice`
  - Optionen: `nein`, `ja`, `ex-raucher`
  - Alle Raucher-Folgefelder erscheinen bei `rauchen != nein`.
  - "Seit wie vielen Jahren" wurde ersetzt durch "Anzahl Jahre gesamt".
- Alkohol:
  - Optionen: `nein`, `gelegentlich`, `taeglich`, `frueher`
  - `alkohol_jahre_konsum` erscheint bei jedem Konsum:
    `alkohol != nein`
- Drogen:
  - Oberes Auswahlfeld `drogenkonsum`: "Substanzen (z. B. Drogen, Anabolika)".
  - Darunterliegendes Multiselect `drogen`: "Substanzen".
  - Optionen: `nein`, `gelegentlich`, `taeglich`, `frueher`.
  - `drogen_jahre_konsum` erscheint bei jedem Konsum:
    `drogenkonsum != nein`
  - Substanzliste enthaelt zusaetzlich: "Steroide / Anabolika".
  - Das fruehere Feld `drogen_frueher` wurde ausdruecklich entfernt und darf
    nicht ohne neuen Auftrag wieder ergaenzt werden.

## Ziel

Der Nutzer moechte einen medizinisch sinnvollen, schrittweise entwickelten
Anamnesebogen. Praezision, Bestandsschutz und nachvollziehbare Versionierung
sind wichtiger als eigenstaendige Optimierungen.
