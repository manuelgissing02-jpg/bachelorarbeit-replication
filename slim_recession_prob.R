# ===============================================================
# slim_recession_prob.R — schlanke Standalone-Pipeline
# ---------------------------------------------------------------
# WAS DIESES SKRIPT TUT
#   Liest eine Excel mit Spalten {date, us10y, us3m, usrec}, baut
#   daraus den Term Spread und alle Probit-Prädiktoren, rechnet
#   für die 12 Modelle (M1/M2/M3 × h = 1, 3, 6, 12) eine rekursive
#   Out-of-Sample-Rezessionswahrscheinlichkeit aus und schreibt
#   das Ergebnis als Excel raus.
#   Zusätzlich berechnet es zwei Gütemaße (Abschnitt 4 und 5):
#     Estrella-Pseudo-R²: wie viel besser als die naive Basisrate?
#     AUROC: trennt das Modell Rezessions- von Nicht-Rezessionsmonaten?
#
# WAS DIESES SKRIPT NICHT TUT
#   Keine Stage-2-Predictive-Regression auf die Equity Premium,
#   keine weiteren Diagnostics.
#
# AUSFÜHRUNG: Working Directory auf den Projekt-Root setzen, dann
#   source("abgabe_supervisor/slim_recession_prob.R").
# Laufzeit: ~2 Minuten (12 Modelle + 4 Benchmark-Modelle x ~555 Monate).
# ===============================================================

library(readxl)
library(dplyr)
library(slider)
library(writexl)
library(pROC)      # für AUROC (Abschnitt 5)

INPUT      <- "slim_input.xlsx"       # Excel mit date/us10y/us3m/usrec
OUTPUT     <- "recession_prob_slim.xlsx"
OOS_START  <- as.Date("1965-01-31")   # erster relevanter Forecast-Monat für ERP Prognose
CUTOFF     <- 24L                     # NBER-Publikationsverzögerung in Monaten
EVAL_START <- as.Date("1980-01-31")   # Auswertungsfenster (M&S-Vergleich)
MS_END     <- as.Date("2019-12-31")   # Ende M&S-Vergleichsfenster


# ---------------------------------------------------------------
# 1) Excel einlesen und alle Modellvariablen in einer Pipe ableiten
# ---------------------------------------------------------------
# tms      : Term Spread = 10J - 3M, der Hauptprädiktor
# tms_lag6 : TMS vor 6 Monaten, fängt die jüngste Slope-Änderung ein (M2)
# tms_ma36 : 36-Monats-Rückwärts-MA des TMS, mittelfristiger Anker (M3)
# y_h*     : 1 wenn in den nächsten h Monaten mind. ein NBER-Rezessions-
#            monat liegt, sonst 0. lead(usrec, 1) verschiebt nach vorne,
#            damit Monat t selbst nicht in die Zielvariable einfließt.

dat <- read_excel(INPUT) |>
  mutate(date = as.Date(date)) |>
  arrange(date) |>
  mutate(
    tms      = us10y - us3m,
    tms_lag6 = lag(tms, 6),
    tms_ma36 = slide_dbl(tms, mean, .before = 35, .after = 0, .complete = TRUE),
    y_h1  = slide_dbl(lead(usrec, 1), max, .before = 0, .after = 0,  .complete = TRUE),
    y_h3  = slide_dbl(lead(usrec, 1), max, .before = 0, .after = 2,  .complete = TRUE),
    y_h6  = slide_dbl(lead(usrec, 1), max, .before = 0, .after = 5,  .complete = TRUE),
    y_h12 = slide_dbl(lead(usrec, 1), max, .before = 0, .after = 11, .complete = TRUE)
  )


# ---------------------------------------------------------------
# 2) Grid aller 12 Modelle definieren
# ---------------------------------------------------------------
# Eine Named List: Name = Spec, Wert = rechte Seite der glm-Formel.
# Damit lässt sich die Schleife unten ohne switch/case bauen.

specs    <- list(M1 = "tms", M2 = "tms + tms_lag6", M3 = "tms + tms_ma36")
horizons <- c(1, 3, 6, 12)


# ---------------------------------------------------------------
# 3) OOS-Schleife: für jedes (spec, h) eine eigene Wahrscheinlichkeits-Spalte
# ---------------------------------------------------------------
# Pro Forecast-Monat i wird das Probit komplett NEU geschätzt — nur mit
# Daten bis Zeile (i - 24). Der 24-Monats-Cutoff verhindert, dass die
# später revidierte NBER-Klassifizierung der jüngsten Monate ins Modell
# leakt (Look-Ahead-Bias). Die Prädiktoren x_t selbst bleiben ungelagged,
# weil Renditen und Zinsen sofort öffentlich verfügbar sind.

forecast_rows <- which(dat$date >= OOS_START)
result <- tibble(date = dat$date)

for (spec_name in names(specs)) {
  rhs <- specs[[spec_name]]
  for (h in horizons) {
    col  <- paste0("p_", spec_name, "_h", h)
    yvar <- paste0("y_h", h)
    form <- as.formula(paste0(yvar, " ~ ", rhs))
    prob <- rep(NA_real_, nrow(dat))
    for (i in forecast_rows) {
      train   <- dat[seq_len(i - CUTOFF), ]
      fit     <- glm(form, data = train, family = binomial(link = "probit"))
      prob[i] <- predict(fit, newdata = dat[i, ], type = "response")
    }
    result[[col]] <- prob
    cat("fertig:", col, "\n")
  }
}


# ---------------------------------------------------------------
# 4) M0-Benchmark: rekursive historische Basisrate
# ---------------------------------------------------------------
# Das Estrella-Pseudo-R² vergleicht das Modell mit einer Baseline p0.
# Als p0 nutzen wir einen Probit nur mit Intercept (keine Prädiktoren):
# Das entspricht dem historischen Rezessionsdurchschnitt bis t-24 —
# also dem, was ein Investor in Echtzeit als Basisrate kannte.
# Wichtig: p0 ist ebenfalls OOS, damit kein Hindsight eingeschleust wird.

bench <- tibble(date = dat$date)

for (h in horizons) {
  col  <- paste0("p_M0_h", h)
  yvar <- paste0("y_h", h)
  form <- as.formula(paste0(yvar, " ~ 1"))  # nur Intercept = histor. Mittelwert
  prob <- rep(NA_real_, nrow(dat))
  for (i in forecast_rows) {
    train   <- dat[seq_len(i - CUTOFF), ]
    fit     <- glm(form, data = train, family = binomial(link = "probit"))
    prob[i] <- predict(fit, newdata = dat[i, ], type = "response")
  }
  bench[[col]] <- prob
  cat("fertig: Benchmark h =", h, "\n")
}


# ---------------------------------------------------------------
# 5) Gütemaße: Estrella-Pseudo-R² und AUROC
# ---------------------------------------------------------------
# estrella_r2(y, p, p0):
#   Misst, wie viel besser das Modell (p) die Rezessionen erklärt
#   als die Basisrate (p0). Formel: 1 - (logL_voll/logL_0)^((-2/n)*logL_0).
#   Auf OLS-R²-Skala lesbar: 0 = kein Mehrwert, 1 = perfekt.
#
# auroc_val(y, p):
#   Wahrscheinlichkeit, dass das Modell einem zufällig gezogenen
#   Rezessionsmonat eine höhere p gibt als einem Nicht-Rezessionsmonat.
#   0.5 = Münzwurf, 1.0 = perfekte Trennung.

estrella_r2 <- function(y, p, p0) {
  ok <- complete.cases(y, p, p0)
  y <- y[ok]; p <- p[ok]; p0 <- p0[ok]; n <- length(y)
  ll_full <- sum(y * log(p)  + (1 - y) * log(1 - p))
  ll_0    <- sum(y * log(p0) + (1 - y) * log(1 - p0))
  1 - (ll_full / ll_0)^(-(2 / n) * ll_0)
}

auroc_val <- function(y, p) {
  ok <- complete.cases(y, p)
  as.numeric(auc(roc(y[ok], p[ok], levels = c(0, 1), direction = "<", quiet = TRUE)))
}

# Auswertungs-Frame: Wahrscheinlichkeiten + Benchmark + realisierte y-Werte
eval_df <- merge(result, bench, by = "date")
eval_df <- merge(eval_df, dat[, c("date", "y_h1", "y_h3", "y_h6", "y_h12")], by = "date")

# Beide Auswertungsfenster: M&S-Vergleich (1980-2019) und Erweiterung (1980-2026)
EXT_END <- max(result$date)

gutemasse <- do.call(rbind, lapply(names(specs), function(spec_name) {
  do.call(rbind, lapply(horizons, function(h) {
    pcol  <- paste0("p_", spec_name, "_h", h)
    p0col <- paste0("p_M0_h", h)
    ycol  <- paste0("y_h", h)
    df_ms  <- eval_df[eval_df$date >= EVAL_START & eval_df$date <= MS_END,  ]
    df_ext <- eval_df[eval_df$date >= EVAL_START & eval_df$date <= EXT_END, ]
    data.frame(
      Spez           = spec_name,
      h              = h,
      PseudoR2_8019  = round(estrella_r2(df_ms[[ycol]],  df_ms[[pcol]],  df_ms[[p0col]]),  3),
      AUROC_8019     = round(auroc_val(  df_ms[[ycol]],  df_ms[[pcol]]),                   3),
      PseudoR2_8026  = round(estrella_r2(df_ext[[ycol]], df_ext[[pcol]], df_ext[[p0col]]), 3),
      AUROC_8026     = round(auroc_val(  df_ext[[ycol]], df_ext[[pcol]]),                  3)
    )
  }))
}))

cat("\n--- Gütemaße (Stufe 1) ---\n")
print(gutemasse, row.names = FALSE)


# ---------------------------------------------------------------
# 6) Excel schreiben: Sheet 1 = Wahrscheinlichkeiten, Sheet 2 = Gütemaße
# ---------------------------------------------------------------

probs_out <- result[result$date >= OOS_START, ]

write_xlsx(
  list(Wahrscheinlichkeiten = probs_out, Gutemasse = gutemasse),
  OUTPUT
)

cat("\ngeschrieben:", OUTPUT,
    "\n  Sheet 1 'Wahrscheinlichkeiten':", nrow(probs_out), "Monate",
    "\n  Sheet 2 'Gutemasse':           ", nrow(gutemasse), "Zeilen\n")
