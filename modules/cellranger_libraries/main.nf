process CREATE_CELLRANGER_LIBRARIES {
    tag "${library_id}"
    label 'basic'

    input:
    tuple val(library_id), val(fastq_dir), val(libraries_dir), val(results_dir)

    output:
    tuple val(library_id), path("${library_id}.csv"), emit: libraries_csv
    path("${library_id}_libraries.log"), emit: log

    publishDir "${libraries_dir}", mode: 'copy', overwrite: true, pattern: "*.csv"

    script:
    """
    mkdir -p ${libraries_dir}

    LIBRARIES_LOG="${libraries_dir}/.libraries_log_${library_id}"

    {
    echo "============================================"
    echo "  CREATE_CELLRANGER_LIBRARIES: ${library_id}"
    echo "  \$(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"

    # ── Check for successful previous run ────────────────────────────────
    if [ -f "\$LIBRARIES_LOG" ] && grep -q "STATUS=SUCCESS" "\$LIBRARIES_LOG"; then
        PREV_DATE=\$(grep "DATE=" "\$LIBRARIES_LOG" | cut -d'=' -f2)
        PREV_CSV=\$(grep "CSV_FILE=" "\$LIBRARIES_LOG" | cut -d'=' -f2)
        PREV_PREFIXES=\$(grep "PREFIX_COUNT=" "\$LIBRARIES_LOG" | cut -d'=' -f2)
        echo "[SKIP] Previous successful libraries CSV found"
        echo "  Date       : \$PREV_DATE"
        echo "  CSV        : \$PREV_CSV"
        echo "  Prefixes   : \$PREV_PREFIXES"
        echo ""
        if [ -f "${libraries_dir}/${library_id}.csv" ]; then
            echo "[INFO] Existing CSV contents:"
            echo "--------------------------------------------"
            cat "${libraries_dir}/${library_id}.csv"
            echo "--------------------------------------------"
            cp "${libraries_dir}/${library_id}.csv" ${library_id}.csv
        fi
        echo "============================================"
        exit 0
    fi

    if [ -f "\$LIBRARIES_LOG" ]; then
        echo "[WARNING] Previous libraries CSV creation was not successful"
        echo "[INFO] Re-creating..."
        echo ""
    fi

    # ── Invalidate downstream logs since we're re-creating ───────────────
    echo "[INFO] Invalidating downstream logs for ${library_id}..."
    rm -f "${results_dir}/.cellranger_count_log_${library_id}"
    echo "[INFO] Downstream logs cleared"
    echo ""

    if [ ! -d "${fastq_dir}" ]; then
        echo "[ERROR] Fastq directory does not exist: ${fastq_dir}"
        exit 1
    fi

    FASTQ_COUNT=\$(find ${fastq_dir} -name "*.fastq.gz" 2>/dev/null | wc -l)
    if [ "\$FASTQ_COUNT" -eq 0 ]; then
        echo "[ERROR] No fastq.gz files found in ${fastq_dir}"
        exit 1
    fi

    echo "[INFO] Found \$FASTQ_COUNT fastq.gz files in ${fastq_dir}"
    echo ""

    echo "[INFO] Detecting sample prefixes from fastq filenames..."
    PREFIXES=\$(ls ${fastq_dir}/*.fastq.gz 2>/dev/null | xargs -n1 basename | sed 's/_S[0-9]*_L[0-9]*_[RI][0-9]*_001\\.fastq\\.gz//' | sort -u)
    PREFIX_COUNT=\$(echo "\$PREFIXES" | grep -c . || true)

    echo "[INFO] Found \${PREFIX_COUNT} unique sample prefix(es):"
    for P in \$PREFIXES; do
        FILE_COUNT=\$(ls ${fastq_dir}/\${P}_S*_L*_*.fastq.gz 2>/dev/null | wc -l)
        echo "  - \${P} (\${FILE_COUNT} files)"
    done
    echo ""

    if [ -f "${libraries_dir}/${library_id}.csv" ]; then
        echo "[INFO] Existing CSV found at ${libraries_dir}/${library_id}.csv"
        echo "[INFO] Will be overwritten"
        echo ""
    fi

    echo "fastqs,sample,library_type" > ${library_id}.csv
    for PREFIX in \$PREFIXES; do
        echo "${fastq_dir},\${PREFIX},Gene Expression" >> ${library_id}.csv
    done

    echo "[INFO] Generated ${library_id}.csv:"
    echo "--------------------------------------------"
    cat ${library_id}.csv
    echo "--------------------------------------------"
    echo ""
    echo "[INFO] CSV will be published to: ${libraries_dir}/${library_id}.csv"

    cat > "\$LIBRARIES_LOG" <<EOF
STATUS=SUCCESS
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
CSV_FILE=${libraries_dir}/${library_id}.csv
FASTQ_DIR=${fastq_dir}
FASTQ_COUNT=\${FASTQ_COUNT}
PREFIX_COUNT=\${PREFIX_COUNT}
PREFIXES=\$(echo \$PREFIXES | tr '\\n' ',')
EOF

    echo "[INFO] Libraries log written to \$LIBRARIES_LOG"
    echo "============================================"

    } 2>&1 | tee ${library_id}_libraries.log
    """
}

process MERGE_LIBRARIES_LOGS {
    label 'basic'

    input:
    path(logs)
    val(logs_dir)

    output:
    path("02_CellRanger_libraries.log")

    publishDir "${logs_dir}", mode: 'copy', overwrite: true

    script:
    """
    echo "================================================================" > 02_CellRanger_libraries.log
    echo "  CELLRANGER LIBRARIES REPORT" >> 02_CellRanger_libraries.log
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')" >> 02_CellRanger_libraries.log
    echo "  Samples processed: \$(ls -1 EGO_*_libraries.log 2>/dev/null | wc -l)" >> 02_CellRanger_libraries.log
    echo "================================================================" >> 02_CellRanger_libraries.log
    echo "" >> 02_CellRanger_libraries.log

    for LOG in \$(ls -1 EGO_*_libraries.log 2>/dev/null | sort); do
        cat \$LOG >> 02_CellRanger_libraries.log
        echo "" >> 02_CellRanger_libraries.log
        echo "" >> 02_CellRanger_libraries.log
    done
    """
}
