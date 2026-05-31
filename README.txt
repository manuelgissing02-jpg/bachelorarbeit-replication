Replikationsmaterial zur Bachelorarbeit
=========================================

Titel:        Prognostizierbarkeit der Aktien-Risikoprämie über den Konjunkturzyklus
Autor:        Manuel Gissing
Institution:  FH JOANNEUM, Studiengang Bank- und Versicherungsmanagement
Abgabe:       Mai 2026


Inhalt dieses Ordners
---------------------

slim_recession_prob.R
    R-Skript zur rekursiven Out-of-Sample-Schätzung der Probit-
    Rezessionswahrscheinlichkeiten für die Spezifikationen M1, M2 und M3
    jeweils auf den Horizonten h ∈ {1, 3, 6, 12} (Stufe 1 des
    Zwei-Stufen-Ansatzes nach Mönch und Stein 2021).

slim_input.xlsx
    Eingabedaten für das R-Skript. Monatliche Werte für das
    10-jährige Treasury-Yield, die 3-Monats-T-Bill-Rate und den
    NBER-Rezessionsindikator (Spalten: date, us10y, us3m, usrec).

recession_prob_slim.xlsx
    Output des R-Skripts. Enthält die zwölf Wahrscheinlichkeits-
    zeitreihen p̂ pro Spezifikation und Horizont sowie die in
    Kapitel 5.1 berichteten Stufe-1-Gütemaße (Estrella-Pseudo-R²
    und AUROC). Kann durch erneutes Ausführen des R-Skripts
    regeneriert werden.

ERP_Prediction_Main.xlsx
    Excel-Modell der Stufe-2-Vorhersage-Regression mit rekursiv
    expandierender OLS, Forecast-Spalten, Prevailing-Mean-Benchmark
    sowie Berechnung des Campbell-Thompson-R²_OS und der
    Clark-West-Teststatistik. Die Stufe-1-Wahrscheinlichkeiten aus
    recession_prob_slim.xlsx dienen als Input für die OLS.


Reproduktionsschritte
---------------------

1. R (ab Version 4.0) mit den Paketen readxl, dplyr, slider, pROC
   und writexl installieren.

2. Working Directory auf diesen Ordner setzen.

3. source("slim_recession_prob.R") ausführen.
   Laufzeit ca. 2 Minuten.

4. Die erzeugte Datei recession_prob_slim.xlsx enthält die
   Stufe-1-Wahrscheinlichkeiten. Diese sind bereits in
   ERP_Prediction_Main.xlsx eingespielt.

5. ERP_Prediction_Main.xlsx öffnen. Die Tabellenblätter zeigen
   pro Spezifikation und Horizont die rekursive OLS-Schätzung
   sowie die abgeleiteten Gütemaße.


Vollständige Methodik-Dokumentation siehe Kapitel 4 der Bachelorarbeit.
Beschreibung des KI-Einsatzes bei der Erstellung der Skripte siehe
Anhang A (insbesondere A.1 und A.2) der Bachelorarbeit.
