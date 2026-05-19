#!/usr/bin/env Rscript

# ─── Create Seurat Object ───────────────────────────────────────────────────
# Builds a Seurat object with:
#   - RNA assay          : CellRanger filtered counts
#   - RNA_cellbender     : CellBender corrected counts (subset to CellRanger barcodes)
#   - Souporcell metadata: souporcell_status and souporcell_assignment from clusters.tsv

# ─── Set library path explicitly ────────────────────────────────────────────
.libPaths("/project/meadlab/shared/01__Resources/01__Singularity_Containers/RStudio/RStudio_v4.4.1/RStudio_v4.4.1.packages")
cat("R library paths:\n")
cat(paste(" ", .libPaths(), collapse = "\n"), "\n\n")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4) {
    stop("Usage: create_seurat.R <library_id> <cellranger_outs> <cellbender_dir> <souporcell_dir>")
}

library_id      <- args[1]
cellranger_outs <- args[2]
cellbender_dir  <- args[3]
souporcell_dir  <- args[4]

# Auto-discover CellBender filtered h5 file
cb_h5_candidates <- list.files(cellbender_dir, pattern = "filtered.*\\.h5$", full.names = TRUE)
if (length(cb_h5_candidates) == 0) {
    # Fallback: look for any h5 file
    cb_h5_candidates <- list.files(cellbender_dir, pattern = "\\.h5$", full.names = TRUE)
}
if (length(cb_h5_candidates) == 0) {
    stop("ERROR: No .h5 files found in CellBender directory: ", cellbender_dir,
         "\n  Contents: ", paste(list.files(cellbender_dir), collapse = ", "))
}
cellbender_h5 <- cb_h5_candidates[1]

cat("=== Creating Seurat object for:", library_id, "===\n")
cat("CellRanger outs :", cellranger_outs, "\n")
cat("CellBender dir  :", cellbender_dir, "\n")
cat("CellBender h5   :", cellbender_h5, "\n")
cat("Souporcell dir  :", souporcell_dir, "\n")

suppressPackageStartupMessages({
    library(Seurat)
    library(scCustomize)
})

# ─── 1. RNA assay from CellRanger filtered matrix ───────────────────────────
cat("\n[1/4] Loading CellRanger filtered matrix...\n")
cr_matrix <- Read10X(data.dir = file.path(cellranger_outs, "filtered_feature_bc_matrix"))
seurat_obj <- CreateSeuratObject(
    counts   = cr_matrix,
    project  = library_id,
    assay    = "RNA"
)
cat("  Barcodes:", ncol(seurat_obj), "| Features:", nrow(seurat_obj), "\n")

# Keep the CellRanger barcode set for subsetting CellBender
cr_barcodes <- colnames(seurat_obj)

# ─── 2. RNA_cellbender assay from CellBender output ─────────────────────────
cat("\n[2/4] Loading CellBender output...\n")
cb_matrix <- Read_CellBender_h5_Mat(file_name = cellbender_h5)

# Subset CellBender matrix to CellRanger barcodes only
shared_barcodes <- intersect(cr_barcodes, colnames(cb_matrix))
cat("  CellBender total barcodes:", ncol(cb_matrix), "\n")
cat("  Shared with CellRanger   :", length(shared_barcodes), "\n")

if (length(shared_barcodes) == 0) {
    stop("ERROR: No overlapping barcodes between CellRanger and CellBender outputs.")
}

cb_matrix <- cb_matrix[, shared_barcodes]

# Ensure feature order matches, fill missing features with zeros
shared_features <- intersect(rownames(seurat_obj), rownames(cb_matrix))
cat("  Shared features          :", length(shared_features), "\n")

# Subset both to shared features for the CellBender assay
cb_matrix_aligned <- cb_matrix[shared_features, cr_barcodes[cr_barcodes %in% shared_barcodes]]

# For barcodes in CellRanger but not in CellBender, fill with zeros
if (length(cr_barcodes) > length(shared_barcodes)) {
    missing_barcodes <- setdiff(cr_barcodes, shared_barcodes)
    cat("  Barcodes in CellRanger but not CellBender:", length(missing_barcodes), "(filled with zeros)\n")
    zero_mat <- Matrix::sparseMatrix(
        i      = integer(0),
        j      = integer(0),
        x      = numeric(0),
        dims   = c(length(shared_features), length(missing_barcodes)),
        dimnames = list(shared_features, missing_barcodes)
    )
    cb_matrix_aligned <- cbind(cb_matrix_aligned, zero_mat)
}

# Reorder to match Seurat object barcodes
cb_matrix_aligned <- cb_matrix_aligned[, cr_barcodes]

seurat_obj[["RNA_cellbender"]] <- CreateAssayObject(counts = cb_matrix_aligned)
cat("  RNA_cellbender assay added.\n")

# ─── 3. Souporcell metadata ─────────────────────────────────────────────────
cat("\n[3/4] Loading Souporcell clusters.tsv...\n")

if (souporcell_dir == "NONE") {
    cat("  Souporcell not run for this sample (k=1), setting metadata to NA.\n")
    seurat_obj$souporcell_status     <- NA_character_
    seurat_obj$souporcell_assignment <- NA_character_
} else {
    clusters_file <- file.path(souporcell_dir, "clusters.tsv")

    if (file.exists(clusters_file)) {
        sc_clusters <- read.delim(clusters_file, stringsAsFactors = FALSE)
        cat("  Souporcell barcodes:", nrow(sc_clusters), "\n")

        # Match barcodes
        rownames(sc_clusters) <- sc_clusters$barcode
        shared_sc <- intersect(cr_barcodes, rownames(sc_clusters))
        cat("  Shared with CellRanger:", length(shared_sc), "\n")

        # Add status and assignment as metadata columns
        souporcell_status     <- rep(NA_character_, length(cr_barcodes))
        souporcell_assignment <- rep(NA_character_, length(cr_barcodes))
        names(souporcell_status)     <- cr_barcodes
        names(souporcell_assignment) <- cr_barcodes

        souporcell_status[shared_sc]     <- sc_clusters[shared_sc, "status"]
        souporcell_assignment[shared_sc] <- sc_clusters[shared_sc, "assignment"]

        seurat_obj$souporcell_status     <- souporcell_status
        seurat_obj$souporcell_assignment <- souporcell_assignment

        cat("  Souporcell metadata added (souporcell_status, souporcell_assignment).\n")
    } else {
        warning("Souporcell clusters.tsv not found at: ", clusters_file)
        seurat_obj$souporcell_status     <- NA_character_
        seurat_obj$souporcell_assignment <- NA_character_
    }
}

# ─── 4. Save Seurat object ──────────────────────────────────────────────────
cat("\n[4/4] Saving Seurat object...\n")
output_file <- paste0(library_id, "_seurat.rds")
saveRDS(seurat_obj, file = output_file)
cat("  Saved to:", output_file, "\n")

# Summary
cat("\n=== Summary ===\n")
cat("Assays         :", paste(Assays(seurat_obj), collapse = ", "), "\n")
cat("Cells          :", ncol(seurat_obj), "\n")
cat("RNA features   :", nrow(seurat_obj[["RNA"]]), "\n")
cat("CB features    :", nrow(seurat_obj[["RNA_cellbender"]]), "\n")
cat("Metadata cols  :", paste(colnames(seurat_obj@meta.data), collapse = ", "), "\n")
cat("Done.\n")
