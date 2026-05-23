#!/usr/bin/env Rscript
# raw 星位置の時系列可視化
# 各 iter の elapsed_sec を横軸に、x_norm / y_norm / dec_disp_norm を縦軸でプロット
# 使い方: Rscript PolarDriftData/R/star_position_timeseries.R [data_dir]
# data_dir 既定: スクリプトの親ディレクトリ (PolarDriftData)

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
script_path <- sub("--file=", "", grep("--file=", commandArgs(trailingOnly = FALSE), value = TRUE))[1]
default_dir <- if (!is.na(script_path) && nzchar(script_path)) {
  normalizePath(file.path(dirname(script_path), ".."))
} else {
  "."
}
data_dir <- if (length(args) >= 1) args[1] else default_dir

files <- list.files(data_dir, pattern = "polardrift_raw_.*\\.csv$",
                    recursive = TRUE, full.names = TRUE)

if (length(files) == 0) {
  cat("No raw CSV found under", data_dir, "\n"); quit(status = 0)
}

for (f in files) {
  df <- tryCatch(read.csv(f), error = function(e) NULL)
  if (is.null(df) || nrow(df) < 2) {
    cat("Skip (empty):", f, "\n"); next
  }

  long <- df |>
    select(phase, iteration, elapsed_sec, x_norm, y_norm, dec_disp_norm) |>
    pivot_longer(c(x_norm, y_norm, dec_disp_norm),
                 names_to = "axis", values_to = "value") |>
    mutate(axis = factor(axis, levels = c("x_norm", "y_norm", "dec_disp_norm")))

  sess_short <- substr(df$session_id[1], 1, 8)
  title <- sprintf("Position timeseries — %s  (%s)", sess_short, basename(f))

  p <- ggplot(long, aes(x = elapsed_sec, y = value,
                        color = factor(iteration), group = iteration)) +
    geom_line(linewidth = 0.4, alpha = 0.8) +
    facet_grid(axis ~ phase, scales = "free_y") +
    labs(title = title, color = "iter",
         x = "elapsed (sec)", y = "value (normalized)",
         caption = "x_norm/y_norm = image coords; dec_disp_norm = Dec-axis projection") +
    theme_minimal(base_size = 10) +
    theme(plot.title = element_text(size = 10),
          plot.caption = element_text(size = 8),
          strip.text = element_text(size = 9, face = "bold"))

  out <- sub("\\.csv$", "_timeseries.png", f)
  ggsave(out, p, width = 12, height = 8, dpi = 150)
  cat("Saved:", out, "\n")
}
