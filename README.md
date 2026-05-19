# Pipeline_Nextflow_scRNAseq

Nextflow DSL2 pipeline for scRNA-seq processing on Slurm. It supports
optional fastq extraction, CellRanger count, Souporcell demultiplexing,
CellBender ambient RNA removal, and Seurat object creation.

## Workflow overview
1. Extract fastqs from raw tar files (optional) - e.g. what provided by Novogene  
2. Build CellRanger libraries CSV
3. Run CellRanger count
4. Run Souporcell (only when `souporcell_k > 1`)
5. Run CellBender
6. Create Seurat object

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
- CellRanger reference (`params.transcriptome`)
- Reference fasta (`params.ref_fasta`)

## Inputs
### Sample sheet
Default: `data/sample_sheet.csv`

Required columns:
- `library_id`: Unique ID for each library
- `Raw_Data`: Optional; semicolon-separated tar paths for raw data extraction
- `fastq_dir`: Output directory for fastqs (or existing fastq dir)
- `souporcell_k`: Optional; integer. Souporcell runs only when `> 1`

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

## Logs and reports
- Nextflow logs: `.nextflow.log*`
- Slurm logs: `Report-*.out` and `Report-*.err`
- Reports: `reports/pipeline_report.html`, `reports/timeline.html`,
  `reports/trace.txt`

Use `clean_nf_logs.sh` to remove old `.nextflow.log*` files.
