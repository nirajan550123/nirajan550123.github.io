###############################################################################
# 0.Load Libraries

packages <- c("tidyverse", "ggpubr", "broom", "car", "rstatix", "patchwork", "ggcorrplot", "emmeans", "multcompView", "FSA", "ggplotify", "ggfortify")
installed <- packages %in% rownames(installed.packages())
if(any(!installed)) install.packages(packages[!installed], dependencies = TRUE)
library(tidyverse)
library(ggpubr)
library(broom)
library(car)        # for Levene's test, Anova/diagnostics
library(rstatix)    # convenient stats wrappers
library(patchwork)  # combine ggplots
library(ggcorrplot) # correlation plots
library(emmeans)    # estimated marginal means / pairwise comparisons
library(dplyr)
library(multcompView)
library(FSA)
library(ggplotify)
library(ggfortify)

###############################################################################
# 1. Read data and clean
# Import the dataset, convert land cover codes to descriptive labels,
# and get a general overview of the data.

data_path <- "data/StratifiedPointsTable.csv"
out_dir <- "outputs"
df <- read_csv(data_path, show_col_types = FALSE)

# Map CID to LULC labels
lulc_map <- c("0" = "water", "1" = "builtup", "2" = "barren", "3" = "forest", "4" = "agriculture")
df <- df %>%
  mutate(
    CID = as.integer(CID),
    LULC = factor(lulc_map[as.character(CID)],
                  levels = c("water","builtup","barren","forest","agriculture")),
    NDVI = as.numeric(NDVI),
    LST  = as.numeric(LST)
  ) %>%
  mutate(
    NDVI = ifelse(NDVI == -9999, NA, NDVI),
    LST  = ifelse(LST == -9999, NA, LST)
  ) %>%
  filter(!is.na(NDVI) & !is.na(LST) & !is.na(LULC))

# Quick overview
glimpse(df)
summary(df)

###############################################################################
# 2. Descriptive statistics
# Purpose: summarize NDVI and LST by LULC
# Summary table: mean, sd, median, IQR, min, max, n

desc_table <- df %>%
  group_by(LULC) %>%
  summarise(
    n = n(),
    NDVI_mean = mean(NDVI, na.rm = TRUE),
    NDVI_sd   = sd(NDVI, na.rm = TRUE),
    NDVI_median = median(NDVI, na.rm = TRUE),
    NDVI_IQR = IQR(NDVI, na.rm = TRUE),
    NDVI_min = min(NDVI, na.rm = TRUE),
    NDVI_max = max(NDVI, na.rm = TRUE),
    LST_mean = mean(LST, na.rm = TRUE),
    LST_sd   = sd(LST, na.rm = TRUE),
    LST_median = median(LST, na.rm = TRUE),
    LST_IQR = IQR(LST, na.rm = TRUE),
    LST_min = min(LST, na.rm = TRUE),
    LST_max = max(LST, na.rm = TRUE)
  ) %>% ungroup()

write_csv(desc_table, file.path(out_dir, "descriptive_summary_by_LULC.csv"))

###############################################################################
# 3.Visualizations: Box + Violin plots

lulc_palette <- c(
  "water" = "#1f78b4",
  "builtup" = "#e31a1c",
  "barren" = "#b15928",
  "forest" = "#33a02c",
  "agriculture" = "#ff7f00"
)

# Violin plot function
plot_violin <- function(df, var, y_label, out_name){
  p <- ggplot(df, aes(x=LULC, y=.data[[var]], fill=LULC)) +
    geom_violin(trim=TRUE, alpha=0.5, color="gray30") +
    geom_jitter(width=0.12, alpha=0.4, size=0.7, color="gray40") +
    scale_fill_manual(values=lulc_palette) +
    labs(title=paste(var,"by LULC (Violin)"), y=y_label, x="Land Use/Land Cover") +
    theme_minimal(base_size=13) +
    theme(legend.position="none",
          plot.title=element_text(hjust=0.5, face="bold"))
  ggsave(file.path(out_dir, out_name), p, width=8, height=6, dpi=300)
}

# Box plot function
plot_box <- function(df, var, y_label, out_name){
  p <- ggplot(df, aes(x=LULC, y=.data[[var]], fill=LULC)) +
    geom_boxplot(width=0.5, outlier.shape=NA, color="black") +
    geom_jitter(width=0.12, alpha=0.4, size=0.7, color="gray40") +
    scale_fill_manual(values=lulc_palette) +
    labs(title=paste(var,"by LULC (Box)"), y=y_label, x="Land Use/Land Cover") +
    theme_minimal(base_size=13) +
    theme(legend.position="none",
          plot.title=element_text(hjust=0.5, face="bold"))
  ggsave(file.path(out_dir, out_name), p, width=8, height=6, dpi=300)
}

# Example usage
plot_violin(df, "NDVI", "NDVI", "NDVI_violin_by_LULC.jpg")
plot_box(df, "NDVI", "NDVI", "NDVI_box_by_LULC.jpg")

plot_violin(df, "LST", "LST (°C)", "LST_violin_by_LULC.jpg")
plot_box(df, "LST", "LST (°C)", "LST_box_by_LULC.jpg")

###############################################################################
# 4. Levene's Test for homogeneity

levene_ndvi <- leveneTest(NDVI ~ LULC, data = df)
levene_lst  <- leveneTest(LST  ~ LULC, data = df)
cat("\n--- Levene's Test ---\n"); print(levene_ndvi); print(levene_lst)

###############################################################################
# 5. Kruskal-Wallis + Dunn + CLD

kruskal_dunn_cld_plot <- function(df, response, out_dir, y_label, sig_offset_ratio = 0.05) {
  kw <- kruskal_test(as.formula(paste0(response, " ~ LULC")), data = df)
  kw_eff <- kruskal_effsize(as.formula(paste0(response, " ~ LULC")), data = df)
  pairwise <- df %>% dunn_test(as.formula(paste0(response, " ~ LULC")), p.adjust.method = "bonferroni")
  write_csv(pairwise, file.path(out_dir, paste0("KW_posthoc_", response, "_LULC.csv")))
  
  # CLD letters
  generate_cld <- function(dunn_result) {
    df_cld <- dunn_result %>% select(group1, group2, p.adj) %>%
      mutate(across(c(group1, group2), str_trim))
    groups <- unique(c(df_cld$group1, df_cld$group2))
    pmat <- matrix(1, nrow = length(groups), ncol = length(groups), dimnames = list(groups, groups))
    for(i in seq_len(nrow(df_cld))){
      g1 <- df_cld$group1[i]; g2 <- df_cld$group2[i]
      pmat[g1,g2] <- df_cld$p.adj[i]; pmat[g2,g1] <- df_cld$p.adj[i]
    }
    letters_df <- multcompLetters(pmat < 0.05, Letters = letters)
    tibble(LULC = names(letters_df$Letters), Letters = letters_df$Letters)
  }
  cld <- generate_cld(pairwise)
  
  max_val <- max(df[[response]], na.rm = TRUE)
  offset <- max_val * sig_offset_ratio
  
  p <- ggplot(df, aes(x = LULC, y = .data[[response]], fill = LULC)) +
    geom_violin(trim = TRUE, alpha = 0.5, color = "gray30") +
    geom_boxplot(width = 0.15, outlier.shape = NA, color = "black") +
    geom_jitter(width = 0.12, alpha = 0.4, size = 0.7, color = "gray40") +
    geom_text(data = cld,
              aes(x = LULC, y = max_val + offset, label = Letters),
              color = "black", size = 5, fontface = "bold") +
    scale_fill_manual(values = lulc_palette) +
    labs(title = paste(response, "by LULC with Significant Differences"),
         y = y_label, x = "Land Use/Land Cover") +
    theme_minimal(base_size = 13) +
    theme(legend.position = "none", plot.title = element_text(hjust = 0.5, face = "bold"))
  
  ggsave(file.path(out_dir, paste0(response, "_box_CLD.jpg")), p, width = 8, height = 6, dpi = 300)
  
  return(list(kw = kw, effsize = kw_eff, pairwise = pairwise, cld_plot = p))
}

lst_results <- kruskal_dunn_cld_plot(df, "LST", out_dir, y_label = "Land Surface Temperature (°C)", sig_offset_ratio = 0.05)
ndvi_results <- kruskal_dunn_cld_plot(df, "NDVI", out_dir, y_label = "NDVI", sig_offset_ratio = 0.05)

###############################################################################
# 6. Correlation analysis
cor_by_group <- df %>%
  group_by(LULC) %>%
  summarise(n=n(),
            pearson_cor = ifelse(n>=3, cor.test(NDVI,LST,method="pearson")$estimate, NA_real_),
            pearson_p   = ifelse(n>=3, cor.test(NDVI,LST,method="pearson")$p.value, NA_real_),
            spearman_cor= ifelse(n>=3, cor.test(NDVI,LST,method="spearman")$estimate, NA_real_),
            spearman_p  = ifelse(n>=3, cor.test(NDVI,LST,method="spearman")$p.value, NA_real_))
write_csv(cor_by_group, file.path(out_dir,"correlations_by_LULC.csv"))

# Scatterplots overall and per LULC
p_scatter_all <- ggplot(df, aes(x=NDVI, y=LST)) +
  geom_point(alpha=0.6, color="darkblue") +
  geom_smooth(method="lm", se=TRUE, color="red") +
  labs(title="LST vs NDVI (Overall)", x="NDVI", y="LST (°C)") +
  theme_minimal(base_size=13)
ggsave(file.path(out_dir,"LST_vs_NDVI_overall.jpg"), p_scatter_all, width=7, height=5, dpi=300)

p_scatter_by <- ggplot(df, aes(x=NDVI, y=LST, color=LULC)) +
  geom_point(alpha=0.6) +
  geom_smooth(method="lm", se=FALSE, aes(color=LULC)) +
  facet_wrap(~LULC, scales="free") +
  labs(title="LST vs NDVI by LULC (Linear Fits)", x="NDVI", y="LST (°C)") +
  theme_minimal(base_size=13)
ggsave(file.path(out_dir,"LST_vs_NDVI_by_LULC.jpg"), p_scatter_by, width=12, height=8, dpi=300)

########################################################################
# 7. Linear regression: Overall
lm_overall <- lm(LST ~ NDVI, data=df)
capture.output(summary(lm_overall), file=file.path(out_dir,"lm_LST_NDVI_summary.csv"))

# Per-LULC regressions
per_lulc_lm <- df %>%
  group_by(LULC) %>%
  group_modify(~{
    m <- lm(LST ~ NDVI, data=.x)
    tibble(intercept=coef(m)[1], slope=coef(m)[2], r2=summary(m)$r.squared, p_value=summary(m)$coefficients[2,4])
  })
write_csv(per_lulc_lm, file.path(out_dir,"LM_LST_NDVI_per_LULC.csv"))

################################################################
# 8. ANCOVA: LST ~ NDVI * LULC

# Fit ANCOVA with interaction
ancova_interaction <- lm(LST ~ NDVI * LULC, data = df)
interaction_anova <- car::Anova(ancova_interaction, type = "III")
print(interaction_anova)

# Extract slopes per LULC
emtrends_lulc <- emtrends(ancova_interaction, ~ LULC, var = "NDVI")
slopes_df <- as.data.frame(summary(emtrends_lulc))
write_csv(slopes_df, file.path(out_dir,"ANCOVA_NDVI_slopes_per_LULC.csv"))

# Get adjusted means at mean NDVI
mean_ndvi <- mean(df$NDVI, na.rm = TRUE)
emm <- emmeans(ancova_interaction, ~ LULC, at = list(NDVI = mean_ndvi))
adj_means <- as.data.frame(emm)  # contains emmean, lower.CL, upper.CL
adj_means$x <- mean_ndvi  # center NDVI for plotting

# Generate predicted regression lines per LULC
ndvi_range <- seq(min(df$NDVI, na.rm = TRUE),
                  max(df$NDVI, na.rm = TRUE),
                  length.out = 100)

reg_df <- slopes_df %>%
  select(LULC, NDVI.trend) %>%
  left_join(adj_means %>% select(LULC, emmean), by = "LULC") %>%
  tidyr::crossing(NDVI = ndvi_range) %>%
  mutate(LST = emmean + NDVI.trend * (NDVI - mean_ndvi))

# Plot ANCOVA results
ancova_plot <- ggplot() +
  # Raw points faded
  geom_point(data = df, aes(x = NDVI, y = LST, color = LULC), alpha = 0.3) +
  # Regression lines per LULC
  geom_line(data = reg_df, aes(x = NDVI, y = LST, color = LULC), size = 1.1) +
  # Adjusted means at mean NDVI
  geom_point(data = adj_means, aes(x = x, y = emmean, fill = LULC),
             shape = 21, size = 3, color = "black") +
  geom_errorbar(data = adj_means,
                aes(x = x, ymin = lower.CL, ymax = upper.CL),
                width = 0.02, color = "black") +
  scale_color_manual(values = lulc_palette) +
  scale_fill_manual(values = lulc_palette) +
  labs(title = "ANCOVA: LST ~ NDVI * LULC (Adjusted Means & Slopes)",
       x = "NDVI", y = "LST (°C)") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "right")

# Save plot
ggsave(file.path(out_dir,"ANCOVA_plot.jpg"), ancova_plot, width = 9, height = 6, dpi = 300)
