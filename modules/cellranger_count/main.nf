process CELLRANGER_COUNT {
    tag "${library_id}"
    label 'long'

    module 'cellranger/9.0.0'

    input:
    tuple val(library_id), path(libraries_csv), val(transcriptome), val(results_dir)

    output:
    tuple val(library_id), path("${library_id}/outs"), emit: outs
    path("${library_id}_count.log"), emit: log

    script:
    """
    mkdir -p ${results_dir}

    COUNT_LOG="${results_dir}/.cellranger_count_log_${library_id}"

    # ── Skip ONLY if outs directory actually exists on disk ───────────────
    if [ -d "${results_dir}/${library_id}/outs" ] && \
       [ -f "${results_dir}/${library_id}/outs/metrics_summary.csv" ]; then

        EXISTING_DATE=\$(stat -c '%y' "${results_dir}/${library_id}" 2>/dev/null | cut -d' ' -f1)
        EXISTING_SIZE=\$(du -sh "${results_dir}/${library_id}" 2>/dev/null | cut -f1)

        echo "============================================" | tee ${library_id}_count.log
        echo "  CELLRANGER_COUNT: ${library_id}" | tee -a ${library_id}_count.log
        echo "  \$(date '+%Y-%m-%d %H:%M:%S')" | tee -a ${library_id}_count.log
        echo "============================================" | tee -a ${library_id}_count.log
        echo "" | tee -a ${library_id}_count.log
        echo "[SKIP] CellRanger output already exists on disk" | tee -a ${library_id}_count.log
        echo "  Path    : ${results_dir}/${library_id}" | tee -a ${library_id}_count.log
        echo "  Date    : \${EXISTING_DATE}" | tee -a ${library_id}_count.log
        echo "  Size    : \${EXISTING_SIZE}" | tee -a ${library_id}_count.log
        echo "  Metrics : present" | tee -a ${library_id}_count.log
        echo "============================================" | tee -a ${library_id}_count.log

        # Create expected output structure for Nextflow
        mkdir -p ${library_id}
        ln -s ${results_dir}/${library_id}/outs ${library_id}/outs

        # Ensure success log exists
        if [ ! -f "\$COUNT_LOG" ] || ! grep -q "STATUS=SUCCESS" "\$COUNT_LOG"; then
            cat > "\$COUNT_LOG" <<EOF
STATUS=SUCCESS
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
NOTE=Retroactively logged from existing output
OUTPUT_DIR=${results_dir}/${library_id}
EOF
        fi

        exit 0
    fi

    # ── If skip log exists but outs dir is missing, invalidate it ────────
    if [ -f "\$COUNT_LOG" ] && grep -q "STATUS=SUCCESS" "\$COUNT_LOG"; then
        echo "[WARNING] Success log exists but outs directory is missing — re-running" | tee ${library_id}_count.log
        rm -f "\$COUNT_LOG"
    fi

    # ── Full run ─────────────────────────────────────────────────────────
    {
    echo "============================================"
    echo "  CELLRANGER_COUNT: ${library_id}"
    echo "  \$(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""

    if [ -f "\$COUNT_LOG" ]; then
        echo "[WARNING] Previous CellRanger count was not successful"
        echo "[INFO] Re-running..."
        cat "\$COUNT_LOG"
        echo ""
    fi

    if [ -d "${results_dir}/${library_id}" ]; then
        EXISTING_DATE=\$(stat -c '%y' "${results_dir}/${library_id}" 2>/dev/null | cut -d' ' -f1)
        EXISTING_SIZE=\$(du -sh "${results_dir}/${library_id}" 2>/dev/null | cut -f1)
        echo "[WARNING] Existing CellRanger output found (incomplete):"
        echo "  Path    : ${results_dir}/${library_id}"
        echo "  Date    : \${EXISTING_DATE}"
        echo "  Size    : \${EXISTING_SIZE}"
        echo ""
        echo "[INFO] This run will overwrite the existing output"
    else
        echo "[INFO] No existing output found at ${results_dir}/${library_id}"
    fi
    echo ""

    echo "[INFO] Libraries CSV contents:"
    echo "--------------------------------------------"
    cat ${libraries_csv}
    echo "--------------------------------------------"
    SAMPLE_COUNT=\$(tail -n +2 ${libraries_csv} | wc -l)
    echo "[INFO] \${SAMPLE_COUNT} sample prefix(es) to process"
    echo ""

    echo "[INFO] Run parameters:"
    echo "  --id             : ${library_id}"
    echo "  --libraries      : ${libraries_csv}"
    echo "  --transcriptome  : ${transcriptome}"
    echo "  --expect-cells   : 20000"
    echo "  --create-bam     : true"
    echo "  --localcores     : ${task.cpus}"
    echo "  --localmem       : \$((${task.memory.toGiga()} - 4)) (${task.memory.toGiga()}GB allocated, 4GB headroom)"
    echo ""

    if [ ! -d "${transcriptome}" ]; then
        echo "[ERROR] Transcriptome directory not found: ${transcriptome}"
        exit 1
    fi
    echo "[INFO] Transcriptome validated: ${transcriptome}"
    echo ""

    echo "[INFO] Starting CellRanger count at \$(date)"
    echo "============================================"
    echo ""

    cellranger count \\
        --id=${library_id} \\
        --libraries=${libraries_csv} \\
        --transcriptome=${transcriptome} \\
        --expect-cells=20000 \\
        --create-bam=true \\
        --localcores=${task.cpus} \\
        --localmem=\$((${task.memory.toGiga()} - 4))

    echo ""
    echo "============================================"
    echo "  CELLRANGER_COUNT COMPLETE: ${library_id}"
    echo "============================================"
    echo "[INFO] Finished at \$(date)"
    echo ""

    ESTIMATED_CELLS=""
    if [ -f "${library_id}/outs/metrics_summary.csv" ]; then
        echo "[INFO] Metrics summary:"
        head -2 ${library_id}/outs/metrics_summary.csv | column -t -s','
        ESTIMATED_CELLS=\$(head -2 ${library_id}/outs/metrics_summary.csv | tail -1 | cut -d',' -f1)
        echo ""
    fi

    echo "[INFO] Output contents:"
    ls -lh ${library_id}/outs/
    echo ""

    # ── Copy results to final output directory ───────────────────────────
    echo "[INFO] Publishing results to ${results_dir}/${library_id}..."
    mkdir -p ${results_dir}/${library_id}
    cp -r ${library_id}/outs ${results_dir}/${library_id}/
    echo "[INFO] Results published to: ${results_dir}/${library_id}"

    OUTPUT_SIZE=\$(du -sh ${library_id} 2>/dev/null | cut -f1)

    cat > "\$COUNT_LOG" <<EOF
STATUS=SUCCESS
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
TRANSCRIPTOME=${transcriptome}
EXPECT_CELLS=20000
LOCALCORES=${task.cpus}
LOCALMEM=${task.memory.toGiga()}
ESTIMATED_CELLS=\${ESTIMATED_CELLS}
OUTPUT_SIZE=\${OUTPUT_SIZE}
OUTPUT_DIR=${results_dir}/${library_id}
EOF

    echo "[INFO] Count log written to \$COUNT_LOG"
    echo "============================================"

    } 2>&1 | tee ${library_id}_count.log
    """
}

process MERGE_COUNT_LOGS {
    label 'basic'

    input:
    path(logs)
    val(logs_dir)

    output:
    path("03_CellRanger_count.log")

    publishDir "${logs_dir}", mode: 'copy', overwrite: true

    script:
    """
    echo "================================================================" > 03_CellRanger_count.log
    echo "  CELLRANGER COUNT REPORT" >> 03_CellRanger_count.log
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')" >> 03_CellRanger_count.log
    echo "  Samples processed: \$(ls -1 EGO_*_count.log 2>/dev/null | wc -l)" >> 03_CellRanger_count.log
    echo "================================================================" >> 03_CellRanger_count.log
    echo "" >> 03_CellRanger_count.log

    for LOG in \$(ls -1 EGO_*_count.log 2>/dev/null | sort); do
        cat \$LOG >> 03_CellRanger_count.log
        echo "" >> 03_CellRanger_count.log
        echo "" >> 03_CellRanger_count.log
    done
    """
}
