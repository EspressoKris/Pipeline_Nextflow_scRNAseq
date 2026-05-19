include { BUILD_CELLBENDER_SIF; CELLBENDER_REMOVE_BACKGROUND; MERGE_CELLBENDER_LOGS } from "${projectDir}/modules/cellbender/main.nf"

workflow CELLBENDER {
    take:
    ch_cellranger_outs  // tuple: [library_id, cellranger_outs_dir] (from Nextflow, may be work dir)
    results_dir         // val: path to published CellRanger results
    cellbender_dir      // val: path to CellBender output directory
    logs_dir            // val: path to logs directory

    main:
    // Build (or reuse cached) CellBender SIF
    BUILD_CELLBENDER_SIF()

    // Use the PUBLISHED results path, not the Nextflow work dir
    // The raw_feature_bc_matrix.h5 lives at: results_dir/library_id/outs/raw_feature_bc_matrix.h5
    ch_results_dir  = Channel.value(results_dir)
    ch_cellbender_dir = Channel.value(cellbender_dir)

    ch_input = ch_cellranger_outs
        .combine(ch_results_dir)
        .combine(ch_cellbender_dir)
        .map { library_id, outs_dir, res_dir, cb_dir ->
            tuple(library_id, "${res_dir}/${library_id}/outs", res_dir, cb_dir)
        }

    CELLBENDER_REMOVE_BACKGROUND(ch_input, BUILD_CELLBENDER_SIF.out.sif)

    MERGE_CELLBENDER_LOGS(
        CELLBENDER_REMOVE_BACKGROUND.out.log.collect(),
        logs_dir
    )

    emit:
    h5          = CELLBENDER_REMOVE_BACKGROUND.out.h5           // tuple: [library_id, output.h5]
    filtered_h5 = CELLBENDER_REMOVE_BACKGROUND.out.filtered_h5  // tuple: [library_id, output_filtered.h5]
}
