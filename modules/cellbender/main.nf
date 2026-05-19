process BUILD_CELLBENDER_SIF {

    label 'build'
    storeDir "${projectDir}/containers"

    output:
    path("cellbender_latest.sif"), emit: sif

    script:
    """
    export APPTAINER_CACHEDIR="${projectDir}/containers/.apptainer_cache"
    export APPTAINER_TMPDIR="${projectDir}/containers/.apptainer_tmp"
    mkdir -p \${APPTAINER_CACHEDIR} \${APPTAINER_TMPDIR}

    apptainer pull cellbender_latest.sif docker://us.gcr.io/broad-dsde-methods/cellbender:latest

    # Clean up cache after successful build
    rm -rf \${APPTAINER_CACHEDIR} \${APPTAINER_TMPDIR}
    """
}

process CELLBENDER_REMOVE_BACKGROUND {

    tag "${library_id}"
    label 'gpu'

    input:
    tuple val(library_id), val(outs_dir), val(results_dir), val(cellbender_dir)
    path(sif)

    output:
    tuple val(library_id), path("${library_id}_cellbender_output.h5"),          emit: h5
    tuple val(library_id), path("${library_id}_cellbender_output_filtered.h5"), emit: filtered_h5
    path("${library_id}_cellbender.log"),                                       emit: log

    script:
    def output_dir = "${cellbender_dir}/${library_id}"
    def raw_h5     = "${outs_dir}/raw_feature_bc_matrix.h5"
    """
    set -euo pipefail

    CB_LOG="${cellbender_dir}/.cellbender_log_${library_id}"

    # ── Skip ONLY if output already exists on disk ───────────────────────
    if [ -d "${output_dir}" ] && \
       [ -f "${output_dir}/${library_id}_cellbender_output.h5" ] && \
       [ -f "${output_dir}/${library_id}_cellbender_output_filtered.h5" ]; then

        EXISTING_DATE=\$(stat -c '%y' "${output_dir}/${library_id}_cellbender_output.h5" 2>/dev/null | cut -d' ' -f1)
        EXISTING_SIZE=\$(du -sh "${output_dir}" 2>/dev/null | cut -f1)

        echo "============================================" | tee ${library_id}_cellbender.log
        echo "  CELLBENDER: ${library_id}" | tee -a ${library_id}_cellbender.log
        echo "  \$(date '+%Y-%m-%d %H:%M:%S')" | tee -a ${library_id}_cellbender.log
        echo "============================================" | tee -a ${library_id}_cellbender.log
        echo "" | tee -a ${library_id}_cellbender.log
        echo "[SKIP] CellBender output already exists on disk" | tee -a ${library_id}_cellbender.log
        echo "  Path     : ${output_dir}" | tee -a ${library_id}_cellbender.log
        echo "  Date     : \${EXISTING_DATE}" | tee -a ${library_id}_cellbender.log
        echo "  Size     : \${EXISTING_SIZE}" | tee -a ${library_id}_cellbender.log
        echo "  Output   : present" | tee -a ${library_id}_cellbender.log
        echo "  Filtered : present" | tee -a ${library_id}_cellbender.log
        echo "============================================" | tee -a ${library_id}_cellbender.log

        # Create expected output files for Nextflow
        ln -s ${output_dir}/${library_id}_cellbender_output.h5 ${library_id}_cellbender_output.h5
        ln -s ${output_dir}/${library_id}_cellbender_output_filtered.h5 ${library_id}_cellbender_output_filtered.h5

        # Ensure success log exists
        if [ ! -f "\$CB_LOG" ] || ! grep -q "STATUS=SUCCESS" "\$CB_LOG"; then
            cat > "\$CB_LOG" <<EOF
STATUS=SUCCESS
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
NOTE=Retroactively logged from existing output
OUTPUT_DIR=${output_dir}
EOF
        fi

        exit 0
    fi

    # ── If skip log exists but output is missing, invalidate it ──────────
    if [ -f "\$CB_LOG" ] && grep -q "STATUS=SUCCESS" "\$CB_LOG"; then
        echo "[WARNING] Success log exists but output is missing — re-running" | tee ${library_id}_cellbender.log
        rm -f "\$CB_LOG"
    fi

    # ── Validate input ───────────────────────────────────────────────────
    if [ ! -f "${raw_h5}" ]; then
        echo "[ERROR] Input file not found: ${raw_h5}" | tee ${library_id}_cellbender.log
        echo "[ERROR] CellRanger outs dir: ${outs_dir}" | tee -a ${library_id}_cellbender.log
        echo "[ERROR] Contents:" | tee -a ${library_id}_cellbender.log
        ls -la ${outs_dir}/ 2>&1 | tee -a ${library_id}_cellbender.log
        exit 1
    fi

    # ── Full run ─────────────────────────────────────────────────────────
    {
    echo "============================================"
    echo "  CELLBENDER: ${library_id}"
    echo "  \$(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""

    if [ -f "\$CB_LOG" ]; then
        echo "[WARNING] Previous CellBender run was not successful"
        echo "[INFO] Re-running..."
        cat "\$CB_LOG"
        echo ""
    fi

    if [ -d "${output_dir}" ]; then
        EXISTING_DATE=\$(stat -c '%y' "${output_dir}" 2>/dev/null | cut -d' ' -f1)
        EXISTING_SIZE=\$(du -sh "${output_dir}" 2>/dev/null | cut -f1)
        echo "[WARNING] Existing CellBender output found (incomplete):"
        echo "  Path : ${output_dir}"
        echo "  Date : \${EXISTING_DATE}"
        echo "  Size : \${EXISTING_SIZE}"
        echo ""
        echo "[INFO] This run will overwrite the existing output"
    else
        echo "[INFO] No existing output found at ${output_dir}"
    fi
    echo ""

    echo "[INFO] Run parameters:"
    echo "  --input          : ${raw_h5}"
    echo "  --output         : ${library_id}_cellbender_output.h5"
    echo "  --cuda           : true"
    echo "  Container        : ${sif}"
    echo ""

    echo "[INFO] Starting CellBender remove-background at \$(date)"
    echo "============================================"
    echo ""

    apptainer exec --nv --writable-tmpfs --bind /ceph,/project,/ceph-fast/databank:/databank ${sif} \\
        cellbender remove-background \\
            --cuda \\
            --input ${raw_h5} \\
            --output ${library_id}_cellbender_output.h5

    echo ""
    echo "============================================"
    echo "  CELLBENDER COMPLETE: ${library_id}"
    echo "============================================"
    echo "[INFO] Finished at \$(date)"
    echo ""

    echo "[INFO] Output files:"
    ls -lh ${library_id}_cellbender_output*.h5
    echo ""

    # Copy results to final output directory
    mkdir -p ${output_dir}
    cp ${library_id}_cellbender_output*.h5 ${output_dir}/

    OUTPUT_SIZE=\$(du -sh ${output_dir} 2>/dev/null | cut -f1)

    echo "[INFO] Results published to: ${output_dir}"
    echo "[INFO] Total size: \${OUTPUT_SIZE}"

    cat > "\$CB_LOG" <<EOF
STATUS=SUCCESS
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
INPUT=${raw_h5}
OUTPUT_DIR=${output_dir}
OUTPUT_SIZE=\${OUTPUT_SIZE}
EOF

    echo "[INFO] CellBender log written to \$CB_LOG"
    echo "============================================"

    } 2>&1 | tee ${library_id}_cellbender.log
    """
}

process MERGE_CELLBENDER_LOGS {

    label 'basic'

    input:
    path(log_files)
    val(logs_dir)

    output:
    path("04_CellBender.log")

    publishDir "${logs_dir}", mode: 'copy', overwrite: true

    script:
    """
    echo "================================================================" > 04_CellBender.log
    echo "  CELLBENDER REPORT" >> 04_CellBender.log
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')" >> 04_CellBender.log
    echo "  Samples processed: \$(ls -1 EGO_*_cellbender.log 2>/dev/null | wc -l)" >> 04_CellBender.log
    echo "================================================================" >> 04_CellBender.log
    echo "" >> 04_CellBender.log

    for LOG in \$(ls -1 EGO_*_cellbender.log 2>/dev/null | sort); do
        cat \$LOG >> 04_CellBender.log
        echo "" >> 04_CellBender.log
        echo "" >> 04_CellBender.log
    done
    """
}
