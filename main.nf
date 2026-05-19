#!/usr/bin/env nextflow

nextflow.enable.dsl=2

// ─── Subworkflows ───────────────────────────────────────────────────────────
include { EXTRACTION }             from './subworkflows/extraction.nf'
include { CELLRANGER_LIBRARIES }   from './subworkflows/cellranger_libraries.nf'
include { CELLRANGER }             from './subworkflows/cellranger_count.nf'
include { CELLBENDER }             from './subworkflows/cellbender.nf'
include { SOUPORCELL }             from './subworkflows/souporcell.nf'
include { CREATE_SEURAT }          from './subworkflows/create_seurat_object.nf'

// ─── Parameters ─────────────────────────────────────────────────────────────
params.samplesheet = "${projectDir}/data/sample_sheet.csv"

log.info """
============================================
  ANGEL Pipeline
  Started : ${new java.util.Date()}
  Logs    : ${params.logs_dir}
============================================
""".stripIndent()

// ─── Functions ──────────────────────────────────────────────────────────────
def parse_samplesheet(samplesheet) {
    Channel
        .fromPath(samplesheet)
        .splitCsv(header: true, strip: true)
        .filter { row -> row.library_id?.trim() }
}

// ─── Workflow ───────────────────────────────────────────────────────────────
workflow {

    ch_all = parse_samplesheet(params.samplesheet)

    // ── Extraction: only samples with Raw_Data and fastq_dir ────────────
    ch_to_extract = ch_all
        .filter { row -> row.Raw_Data?.trim() && row.fastq_dir?.trim() }
        .map { row ->
            tuple(row.library_id, row.Raw_Data.trim(), row.fastq_dir.trim())
        }

    EXTRACTION(
        ch_to_extract,
        params.cellranger_libraries,
        params.cellranger_results,
        params.logs_dir
    )

    // ── Samples that already have fastqs (no extraction needed) ─────────
    ch_existing = ch_all
        .filter { row -> !row.Raw_Data?.trim() && row.fastq_dir?.trim() }
        .map { row ->
            tuple(row.library_id, row.fastq_dir.trim())
        }

    // ── Merge: combine extracted with existing ─────────────────────────
    ch_fastqs_ready = EXTRACTION.out.fastqs.mix(ch_existing)

    ch_fastqs_ready.view { library_id, fastq_dir ->
        "Ready: ${library_id} | ${fastq_dir}"
    }

    // ── Create CellRanger Libraries CSVs ────────────────────────────────
    CELLRANGER_LIBRARIES(
        ch_fastqs_ready,
        params.cellranger_libraries,
        params.cellranger_results,
        params.logs_dir
    )

    // ── CellRanger Count ────────────────────────────────────────────────
    ch_sampleinfo = ch_all
        .filter { row -> row.library_id?.trim() }
        .map { row ->
            tuple(row.library_id, params.transcriptome)
        }

    CELLRANGER(
        CELLRANGER_LIBRARIES.out.libraries_csv,
        ch_sampleinfo,
        params.cellranger_results,
        params.logs_dir
    )

    // ── Souporcell: genotype-based demultiplexing (skip k=1) ──────
    ch_souporcell_info = ch_all
        .filter { row -> row.souporcell_k?.trim() && row.souporcell_k.trim() as int > 1 }
        .map { row ->
            tuple(row.library_id, row.souporcell_k.trim() as int)
        }

    SOUPORCELL(
        CELLRANGER.out.outs,
        ch_souporcell_info,
        params.cellranger_results,
        params.ref_fasta,
        params.souporcell_results,
        params.logs_dir
    )

    // ── CellBender: ambient RNA removal ───────────────────────────────
    CELLBENDER(
        CELLRANGER.out.outs,
        params.cellranger_results,
        params.cellbender_results,
        params.logs_dir
    )

    // ── Create Seurat Object ──────────────────────────────────────────
    CREATE_SEURAT(
        CELLRANGER.out.outs,
        CELLBENDER.out.filtered_h5,
        SOUPORCELL.out.results,
        params.cellranger_results,
        params.cellbender_results,
        params.souporcell_results,
        params.seurat_results,
        params.logs_dir
    )
}
