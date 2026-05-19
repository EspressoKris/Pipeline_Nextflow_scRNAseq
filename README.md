# Pipeline_Nextflow_scRNAseq

Nextflow DSL2 pipeline for scRNA-seq processing on Slurm. It supports
optional fastq extraction, CellRanger count, Souporcell demultiplexing,
CellBender ambient RNA removal, and Seurat object creation.

## Workflow overview
1. Extract fastqs from raw tar files (optional) - e.g. what provided by Novogene
2. Build CellRanger libraries CSV (auto-detects fastq prefixes)
3. Run CellRanger count
4. Run Souporcell (only when `souporcell_k > 1`)
5. Run CellBender (GPU)
6. Create Seurat object (RNA + RNA_cellbender assays, Souporcell metadata)

Subworkflows are in `subworkflows/`:
- `extraction.nf`
- `cellranger_libraries.nf`
- `cellranger_count.nf`
- `souporcell.nf`
- `cellbender.nf`
- `create_seurat_object.nf`

## Requirements
- Nextflow (module `nextflow/25.04.7` used in `start_pipeline.sh`)
- Slurm executor
- CellRanger module `cellranger/9.0.0`
- Apptainer/Singularity for containerized Souporcell and CellBender
- R module `R-base/4.4.1` with Seurat + scCustomize available
- CellRanger reference (`params.transcriptome`)
- Reference fasta (`params.ref_fasta`)
- Common variants VCF at `resources/common_variants_grch38.fixed.vcf`

## Inputs
### Sample sheet
Default: `data/sample_sheet.csv`

Required columns:
- `library_id`: Unique ID for each library (also the folder name inside tars)
- `fastq_dir`: Output directory for fastqs (or existing fastq dir)

Optional columns:
- `Raw_Data`: Semicolon-separated tar paths for raw data extraction. If empty,
  the pipeline assumes fastqs already exist in `fastq_dir`.
- `souporcell_k`: Integer. Souporcell runs only when `> 1`.

Other columns (e.g., `experiment`, `batch_10x`) are carried through for
bookkeeping but not used directly in `main.nf`.

## Configuration
Edit [nextflow.config](nextflow.config) to set paths and resources:
- `params.samplesheet`
- `params.cellranger_libraries`, `params.cellranger_results`
- `params.souporcell_results`, `params.cellbender_results`,
  `params.seurat_results`
- `params.transcriptome`, `params.ref_fasta`
- `params.logs_dir`

The pipeline is configured for Slurm with labels for `basic`, `build`, `long`,
and `gpu`. Reports are written to `reports/` under the launch directory.

## Run
Typical Slurm submission uses the wrapper:

```bash
sbatch start_pipeline.sh
```

This wrapper runs:

```bash
nextflow run /project/ANGEL/shared/Pipeline/main.nf -resume -w /project/ANGEL/shared/Pipeline/work
```

The wrapper runs Nextflow from a local scratch directory
`/tmp/${USER}/nf_run_${SLURM_JOB_ID}` and copies `.nextflow.log` back to the
pipeline folder after completion.

## Outputs
- Fastqs are extracted to `fastq_dir` from the sample sheet.
- CellRanger outputs are published to `params.cellranger_results/<library_id>/outs`.
- Souporcell outputs are published to `params.souporcell_results/<library_id>/`.
- CellBender outputs are published to `params.cellbender_results/<library_id>/`.
- Seurat object is written to `params.seurat_results/<library_id>/<library_id>_seurat.rds`.

## Notes on pipeline behavior
- Extraction verifies MD5s when `MD5.txt` is available and writes an
    `.extraction_log` in `fastq_dir`.
- Libraries CSV creation detects sample prefixes from fastq filenames and
    writes `.libraries_log_<library_id>` into the libraries folder.
- CellRanger, Souporcell, and CellBender skip work when outputs already exist
    and create `.cellranger_count_log_*`, `.souporcell_log_*`,
    `.cellbender_log_*` files in their output directories.
- Seurat creation reads CellRanger filtered counts and CellBender filtered h5,
    adds Souporcell metadata when present, and sets metadata to NA when
    `souporcell_k` is 1 or missing.

## Logs and reports
- Nextflow logs: `.nextflow.log*`
- Slurm logs: `Report-*.out` and `Report-*.err`
- Reports: `reports/pipeline_report.html`, `reports/timeline.html`,
  `reports/trace.txt`

Merged step logs are written to `params.logs_dir`:
- `01_Extract_raw_data.log`
- `02_CellRanger_libraries.log`
- `03_CellRanger_count.log`
- `04_CellBender.log`
- `05_Souporcell.log`
- `create_seurat_object_merged.log`

Use `clean_nf_logs.sh` to remove old `.nextflow.log*` files.
