#!/usr/bin/env Rscript
# 星位置軌跡の可視化
# 使い方: Rscript PolarDriftData/R/star_trajectory.R [data_dir]
# data_dir 既定: スクリプトの親ディレクトリ (PolarDriftData)

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
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

  endpoints <- df |>
    group_by(phase, iteration) |>
    summarise(
      x_start = first(x_norm), y_start = first(y_norm),
      x_end   = last(x_norm),  y_end   = last(y_norm),
      .groups = "drop"
    )

  sess_short <- substr(df$session_id[1], 1, 8)
  title <- sprintf("Star trajectory — %s  (%s)", sess_short, basename(f))

  p <- ggplot(df, aes(x = x_norm, y = y_norm,
                      color = factor(iteration), group = iteration)) +
    geom_path(linewidth = 0.4, alpha = 0.8) +
    geom_point(data = endpoints, aes(x = x_start, y = y_start),
               shape = 16, size = 2) +
    geom_point(data = endpoints, aes(x = x_end, y = y_end),
               shape = 4, size = 2, stroke = 1) +
    facet_wrap(~ phase, scales = "free") +
    scale_y_reverse() +
    labs(title = title, color = "iter",
         x = "x (normalized)", y = "y (normalized)",
         caption = "● start / x end (image y-axis: top -> bottom)") +
    theme_minimal(base_size = 10) +
    theme(plot.title = element_text(size = 10),
          plot.caption = element_text(size = 8),
          aspect.ratio = 1)

  out <- sub("\\.csv$", "_trajectory.png", f)
  ggsave(out, p, width = 10, height = 6, dpi = 150)
  cat("Saved:", out, "\n")
}
