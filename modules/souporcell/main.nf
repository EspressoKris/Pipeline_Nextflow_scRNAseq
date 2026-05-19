process BUILD_SOUPORCELL_SIF {

    label 'build'
    storeDir "${projectDir}/containers"

    output:
    path("souporcell_latest.sif"), emit: sif

    script:
    """
    export APPTAINER_CACHEDIR="${projectDir}/containers/.apptainer_cache"
    export APPTAINER_TMPDIR="${projectDir}/containers/.apptainer_tmp"
    mkdir -p \${APPTAINER_CACHEDIR} \${APPTAINER_TMPDIR}

    singularity pull souporcell_latest.sif shub://wheaton5/souporcell

    # Clean up cache after successful build
    rm -rf \${APPTAINER_CACHEDIR} \${APPTAINER_TMPDIR}
    """
}

process SOUPORCELL_DEMUX {

    tag "${library_id}"
    label 'long'

    input:
    tuple val(library_id), val(outs_dir), val(souporcell_dir), val(souporcell_k), val(ref_fasta), val(common_variants)
    path(sif)

    output:
    tuple val(library_id), path("${library_id}_souporcell/"), emit: results
    path("${library_id}_souporcell.log"),                     emit: log

    script:
    def output_dir  = "${souporcell_dir}/${library_id}"
    def bam         = "${outs_dir}/possorted_genome_bam.bam"
    def barcodes    = "${outs_dir}/filtered_feature_bc_matrix/barcodes.tsv.gz"
    """
    set -euo pipefail

    SC_LOG="${souporcell_dir}/.souporcell_log_${library_id}"

    # ── Skip ONLY if output already exists on disk ───────────────────────
    if [ -d "${output_dir}" ] && \
       [ -f "${output_dir}/clusters.tsv" ]; then

        EXISTING_DATE=\$(stat -c '%y' "${output_dir}/clusters.tsv" 2>/dev/null | cut -d' ' -f1)
        EXISTING_SIZE=\$(du -sh "${output_dir}" 2>/dev/null | cut -f1)

        echo "============================================" | tee ${library_id}_souporcell.log
        echo "  SOUPORCELL: ${library_id}" | tee -a ${library_id}_souporcell.log
        echo "  \$(date '+%Y-%m-%d %H:%M:%S')" | tee -a ${library_id}_souporcell.log
        echo "============================================" | tee -a ${library_id}_souporcell.log
        echo "" | tee -a ${library_id}_souporcell.log
        echo "[SKIP] Souporcell output already exists on disk" | tee -a ${library_id}_souporcell.log
        echo "  Path     : ${output_dir}" | tee -a ${library_id}_souporcell.log
        echo "  Date     : \${EXISTING_DATE}" | tee -a ${library_id}_souporcell.log
        echo "  Size     : \${EXISTING_SIZE}" | tee -a ${library_id}_souporcell.log
        echo "  Clusters : present" | tee -a ${library_id}_souporcell.log
        echo "============================================" | tee -a ${library_id}_souporcell.log

        # Create expected output for Nextflow
        ln -s ${output_dir} ${library_id}_souporcell

        # Ensure success log exists
        if [ ! -f "\$SC_LOG" ] || ! grep -q "STATUS=SUCCESS" "\$SC_LOG"; then
            cat > "\$SC_LOG" <<EOF
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
    if [ -f "\$SC_LOG" ] && grep -q "STATUS=SUCCESS" "\$SC_LOG"; then
        echo "[WARNING] Success log exists but output is missing — re-running" | tee ${library_id}_souporcell.log
        rm -f "\$SC_LOG"
    fi

    # ── Validate inputs ──────────────────────────────────────────────────
    if [ ! -f "${bam}" ]; then
        echo "[ERROR] BAM file not found: ${bam}" | tee ${library_id}_souporcell.log
        echo "[ERROR] CellRanger outs dir: ${outs_dir}" | tee -a ${library_id}_souporcell.log
        ls -la ${outs_dir}/ 2>&1 | tee -a ${library_id}_souporcell.log
        exit 1
    fi

    if [ ! -f "${barcodes}" ]; then
        echo "[ERROR] Barcodes file not found: ${barcodes}" | tee ${library_id}_souporcell.log
        exit 1
    fi

    # ── Full run ─────────────────────────────────────────────────────────
    {
    echo "============================================"
    echo "  SOUPORCELL: ${library_id}"
    echo "  \$(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""

    if [ -f "\$SC_LOG" ]; then
        echo "[WARNING] Previous Souporcell run was not successful"
        echo "[INFO] Re-running..."
        cat "\$SC_LOG"
        echo ""
    fi

    if [ -d "${output_dir}" ]; then
        EXISTING_DATE=\$(stat -c '%y' "${output_dir}" 2>/dev/null | cut -d' ' -f1)
        EXISTING_SIZE=\$(du -sh "${output_dir}" 2>/dev/null | cut -f1)
        echo "[WARNING] Existing Souporcell output found (incomplete):"
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
    echo "  -i (BAM)         : ${bam}"
    echo "  -b (barcodes)    : ${barcodes}"
    echo "  -f (ref fasta)   : ${ref_fasta}"
    echo "  -k (clusters)    : ${souporcell_k}"
    echo "  -t (threads)     : ${task.cpus}"
    echo "  -o (output)      : ${library_id}_souporcell"
    echo "  --common_variants: ${common_variants}"
    echo "  --skip_remap     : SKIP_REMAP"
    echo "  Container        : ${sif}"
    echo ""

    echo "[INFO] Starting Souporcell at \$(date)"
    echo "============================================"
    echo ""

    singularity exec --bind /ceph,/project,/ceph-fast/databank:/databank ${sif} souporcell_pipeline.py \\
        -i ${bam} \\
        -b ${barcodes} \\
        -f ${ref_fasta} \\
        -t ${task.cpus} \\
        -o ${library_id}_souporcell \\
        --common_variants ${common_variants} \\
        -k ${souporcell_k} \\
        --skip_remap SKIP_REMAP

    echo ""
    echo "============================================"
    echo "  SOUPORCELL COMPLETE: ${library_id}"
    echo "============================================"
    echo "[INFO] Finished at \$(date)"
    echo ""

    echo "[INFO] Output files:"
    ls -lh ${library_id}_souporcell/
    echo ""

    # Delete intermediate .bam and .bai to save space
    find ${library_id}_souporcell -type f \\( -name "*.bam" -o -name "*.bai" \\) -exec rm -f {} \\;
    echo "[INFO] Cleaned up intermediate BAM/BAI files"
    echo ""

    # Copy results to final output directory
    mkdir -p ${output_dir}
    cp -r ${library_id}_souporcell/* ${output_dir}/

    OUTPUT_SIZE=\$(du -sh ${output_dir} 2>/dev/null | cut -f1)

    echo "[INFO] Results published to: ${output_dir}"
    echo "[INFO] Total size: \${OUTPUT_SIZE}"

    cat > "\$SC_LOG" <<EOF
STATUS=SUCCESS
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
LIBRARY_ID=${library_id}
K=${souporcell_k}
INPUT_BAM=${bam}
INPUT_BARCODES=${barcodes}
REF_FASTA=${ref_fasta}
COMMON_VARIANTS=${common_variants}
OUTPUT_DIR=${output_dir}
OUTPUT_SIZE=\${OUTPUT_SIZE}
EOF

    echo "[INFO] Souporcell log written to \$SC_LOG"
    echo "============================================"

    } 2>&1 | tee ${library_id}_souporcell.log
    """
}

process MERGE_SOUPORCELL_LOGS {

    label 'basic'

    input:
    path(log_files)
    val(logs_dir)

    output:
    path("05_Souporcell.log")

    publishDir "${logs_dir}", mode: 'copy', overwrite: true

    script:
    """
    echo "================================================================" > 05_Souporcell.log
    echo "  SOUPORCELL REPORT" >> 05_Souporcell.log
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')" >> 05_Souporcell.log
    echo "  Samples processed: \$(ls -1 EGO_*_souporcell.log 2>/dev/null | wc -l)" >> 05_Souporcell.log
    echo "================================================================" >> 05_Souporcell.log
    echo "" >> 05_Souporcell.log

    for LOG in \$(ls -1 EGO_*_souporcell.log 2>/dev/null | sort); do
        cat \$LOG >> 05_Souporcell.log
        echo "" >> 05_Souporcell.log
        echo "" >> 05_Souporcell.log
    done
    """
}
