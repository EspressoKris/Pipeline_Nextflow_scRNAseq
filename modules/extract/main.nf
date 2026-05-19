process EXTRACT_RAW_DATA {
    tag "${library_id}"
    label 'basic'

    input:
    tuple val(library_id), val(tar_files), val(fastq_dir), val(libraries_dir), val(results_dir)

    output:
    tuple val(library_id), val(fastq_dir), emit: fastqs
    path("${library_id}_extract.log"), emit: log

    script:
    """
    mkdir -p ${fastq_dir}

    EXTRACTION_LOG="${fastq_dir}/.extraction_log"

    {
    echo "============================================"
    echo "  EXTRACT_RAW_DATA: ${library_id}"
    echo "  \$(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"

    # ── Check for successful previous extraction ─────────────────────────
    if [ -f "\$EXTRACTION_LOG" ] && grep -q "STATUS=SUCCESS" "\$EXTRACTION_LOG"; then
        PREV_DATE=\$(grep "DATE=" "\$EXTRACTION_LOG" | cut -d'=' -f2)
        PREV_COUNT=\$(grep "FASTQ_COUNT=" "\$EXTRACTION_LOG" | cut -d'=' -f2)
        echo "[SKIP] Previous successful extraction found"
        echo "  Date       : \$PREV_DATE"
        echo "  Fastq count: \$PREV_COUNT"
        echo ""
        echo "[INFO] Current files in ${fastq_dir}:"
        ls -lh ${fastq_dir}/*.fastq.gz 2>/dev/null || echo "  (none)"
        echo "============================================"
        exit 0
    fi

    if [ -f "\$EXTRACTION_LOG" ]; then
        echo "[WARNING] Previous extraction was not successful"
        echo "[INFO] Re-extracting..."
        echo ""
    fi

    echo "[INFO] No successful extraction log found — proceeding with extraction"

    # ── Invalidate downstream logs since we're re-extracting ─────────────
    echo "[INFO] Invalidating downstream logs for ${library_id}..."
    rm -f "${libraries_dir}/.libraries_log_${library_id}"
    rm -f "${results_dir}/.cellranger_count_log_${library_id}"
    echo "[INFO] Downstream logs cleared"
    echo ""

    IFS=';' read -ra TARS <<< "${tar_files}"
    TOTAL=\${#TARS[@]}
    CURRENT=0
    TOTAL_EXTRACTED=0
    TOTAL_PASSED=0
    TOTAL_FAILED=0
    ALL_OK=true

    echo "[INFO] ${library_id} has \${TOTAL} tar file(s) to process"
    echo ""

    for TAR in "\${TARS[@]}"; do
        TAR=\$(echo "\$TAR" | xargs)
        [ -z "\$TAR" ] && continue
        CURRENT=\$((CURRENT + 1))

        echo "--------------------------------------------"
        echo "[TAR \${CURRENT}/\${TOTAL}] \$TAR"

        if [ ! -f "\$TAR" ]; then
            echo "[ERROR] File not found: \$TAR"
            ALL_OK=false
            continue
        fi

        TMPDIR_EXTRACT=\$(mktemp -d)
        tar -xf \$TAR -C \${TMPDIR_EXTRACT}

        SAMPLE_DIR=\$(find \${TMPDIR_EXTRACT} -type d -name "${library_id}" | head -1)

        if [ -z "\$SAMPLE_DIR" ]; then
            echo "[WARNING] No folder named '${library_id}' found in this tar"
            rm -rf \${TMPDIR_EXTRACT}
            continue
        fi

        MD5_FILE=""
        if [ -f "\${SAMPLE_DIR}/MD5.txt" ]; then
            MD5_FILE="\${SAMPLE_DIR}/MD5.txt"
        else
            SEARCH_DIR=\$(dirname \$SAMPLE_DIR)
            while [ "\$SEARCH_DIR" != "\${TMPDIR_EXTRACT}" ] && [ "\$SEARCH_DIR" != "/" ]; do
                if [ -f "\${SEARCH_DIR}/MD5.txt" ]; then
                    MD5_FILE="\${SEARCH_DIR}/MD5.txt"
                    break
                fi
                SEARCH_DIR=\$(dirname \$SEARCH_DIR)
            done
            if [ -z "\$MD5_FILE" ] && [ -f "\${TMPDIR_EXTRACT}/MD5.txt" ]; then
                MD5_FILE="\${TMPDIR_EXTRACT}/MD5.txt"
            fi
        fi

        if [ -n "\$MD5_FILE" ]; then
            echo "[INFO] Found MD5 file: \$MD5_FILE"
        else
            echo "[WARNING] No MD5.txt found — skipping checksum verification"
        fi

        FASTQS_IN_TAR=\$(find \$SAMPLE_DIR -type f -name "*.fastq.gz")
        FASTQ_COUNT=\$(echo "\$FASTQS_IN_TAR" | grep -c . || true)
        NEW=0

        for FQ in \$FASTQS_IN_TAR; do
            BASENAME=\$(basename \$FQ)
            mv \$FQ ${fastq_dir}/
            NEW=\$((NEW + 1))

            if [ -n "\$MD5_FILE" ]; then
                EXPECTED_MD5=\$(grep "\$BASENAME" "\$MD5_FILE" | awk '{print \$1}' | head -1)
                if [ -n "\$EXPECTED_MD5" ]; then
                    ACTUAL_MD5=\$(md5sum ${fastq_dir}/\$BASENAME | awk '{print \$1}')
                    if [ "\$EXPECTED_MD5" = "\$ACTUAL_MD5" ]; then
                        echo "  [OK]   \$BASENAME (md5: \$ACTUAL_MD5)"
                        TOTAL_PASSED=\$((TOTAL_PASSED + 1))
                    else
                        echo "  [FAIL] \$BASENAME"
                        echo "         Expected: \$EXPECTED_MD5"
                        echo "         Got:      \$ACTUAL_MD5"
                        TOTAL_FAILED=\$((TOTAL_FAILED + 1))
                        ALL_OK=false
                    fi
                else
                    echo "  [WARN] \$BASENAME — no MD5 entry found in MD5.txt"
                fi
            else
                echo "  [NEW]  \$BASENAME (no MD5 check)"
            fi
        done

        echo "[TAR \${CURRENT}/\${TOTAL}] Done: \$NEW files extracted"
        TOTAL_EXTRACTED=\$((TOTAL_EXTRACTED + NEW))

        rm -rf \${TMPDIR_EXTRACT}
    done

    echo ""
    echo "============================================"
    echo "  SUMMARY: ${library_id}"
    echo "============================================"
    FINAL_COUNT=\$(find ${fastq_dir} -name "*.fastq.gz" | wc -l)
    echo "  Tar files processed  : \${TOTAL}"
    echo "  Files extracted      : \${TOTAL_EXTRACTED}"
    echo "  MD5 passed           : \${TOTAL_PASSED}"
    echo "  MD5 failed           : \${TOTAL_FAILED}"
    echo "  Total fastqs in dir  : \${FINAL_COUNT}"
    echo "  Output directory     : ${fastq_dir}"

    if [ "\$ALL_OK" = true ] && [ "\$TOTAL_EXTRACTED" -gt 0 ]; then
        echo ""
        echo "  *** ALL MD5 CHECKS PASSED ***"
        echo "============================================"

        cat > "\$EXTRACTION_LOG" <<EOF
STATUS=SUCCESS
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
FASTQ_COUNT=\${FINAL_COUNT}
MD5_PASSED=\${TOTAL_PASSED}
MD5_FAILED=0
TAR_FILES=${tar_files}
OUTPUT_DIR=${fastq_dir}
EOF
        echo "[INFO] Extraction log written to \$EXTRACTION_LOG"
    else
        echo ""
        if [ "\$TOTAL_FAILED" -gt 0 ]; then
            echo "  *** MD5 VERIFICATION FAILED ***"
        fi
        echo "============================================"

        cat > "\$EXTRACTION_LOG" <<EOF
STATUS=FAILED
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
FASTQ_COUNT=\${FINAL_COUNT}
MD5_PASSED=\${TOTAL_PASSED}
MD5_FAILED=\${TOTAL_FAILED}
TAR_FILES=${tar_files}
OUTPUT_DIR=${fastq_dir}
EOF
        echo "[ERROR] Extraction log written to \$EXTRACTION_LOG"
        exit 1
    fi

    echo ""
    echo "Final contents:"
    ls -lh ${fastq_dir}/*.fastq.gz 2>/dev/null || echo "  (no fastq.gz files)"

    } 2>&1 | tee ${library_id}_extract.log
    """
}

process MERGE_EXTRACT_LOGS {
    label 'basic'

    input:
    path(logs)
    val(logs_dir)

    output:
    path("01_Extract_raw_data.log")

    publishDir "${logs_dir}", mode: 'copy', overwrite: true

    script:
    """
    echo "================================================================" > 01_Extract_raw_data.log
    echo "  EXTRACTION REPORT" >> 01_Extract_raw_data.log
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')" >> 01_Extract_raw_data.log
    echo "  Samples processed: \$(ls -1 EGO_*_extract.log 2>/dev/null | wc -l)" >> 01_Extract_raw_data.log
    echo "================================================================" >> 01_Extract_raw_data.log
    echo "" >> 01_Extract_raw_data.log

    for LOG in \$(ls -1 EGO_*_extract.log 2>/dev/null | sort); do
        cat \$LOG >> 01_Extract_raw_data.log
        echo "" >> 01_Extract_raw_data.log
        echo "" >> 01_Extract_raw_data.log
    done
    """
}
