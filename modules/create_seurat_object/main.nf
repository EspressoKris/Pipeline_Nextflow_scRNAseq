// modules/create_seurat_object/main.nf

process CREATE_SEURAT_OBJECT {
    label 'build'
    tag "${library_id}"

    publishDir "${seurat_dir}/${library_id}", mode: 'copy', overwrite: true

    input:
    tuple val(library_id), val(cellranger_outs), val(cellbender_dir), val(souporcell_dir), val(seurat_dir)

    output:
    tuple val(library_id), path("${library_id}_seurat.rds"), emit: rds
    path("${library_id}_seurat.log"),                        emit: log

    shell:
    '''
    set -euo pipefail

    module load R-base/4.4.1

    export R_LIBS_USER="/project/meadlab/shared/01__Resources/01__Singularity_Containers/RStudio/RStudio_v4.4.1/RStudio_v4.4.1.packages"

    Rscript !{projectDir}/modules/create_seurat_object/create_seurat.R \
        "!{library_id}" \
        "!{cellranger_outs}" \
        "!{cellbender_dir}" \
        "!{souporcell_dir}" \
        2>&1 | tee !{library_id}_seurat.log
    '''
}


process MERGE_CREATE_SEURAT_LOGS {
    label 'basic'
    tag 'merge_create_seurat_logs'

    input:
    path(log_files)
    val(logs_dir)

    output:
    path("create_seurat_object_merged.log")

    publishDir "${logs_dir}", mode: 'copy', overwrite: true, saveAs: { "create_seurat_object_merged.log" }

    script:
    """
    cat ${log_files} > create_seurat_object_merged.log
    """
}
