include { CELLRANGER_COUNT; MERGE_COUNT_LOGS } from "${projectDir}/modules/cellranger_count/main.nf"

workflow CELLRANGER {
    take:
    ch_libraries   // tuple: [library_id, libraries_csv]
    ch_sampleinfo  // tuple: [library_id, transcriptome]
    results_dir    // val: path to output results
    logs_dir       // val: path to logs directory

    main:
    ch_input = ch_libraries
        .join(ch_sampleinfo)
        .map { library_id, libraries_csv, transcriptome ->
            tuple(library_id, libraries_csv, transcriptome, results_dir)
        }

    CELLRANGER_COUNT(ch_input)

    MERGE_COUNT_LOGS(
        CELLRANGER_COUNT.out.log.collect(),
        logs_dir
    )

    emit:
    outs = CELLRANGER_COUNT.out.outs
}
